/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Combine
import Defaults
import Foundation
import NaturalLanguage

/// Finds synced lyrics for the current song and prepares them for the notch.
///
/// Asks the enabled sources (LRCLIB, NetEase Cloud Music, QQ Music) at the same time
/// and keeps the best: word timing (NetEase) first, then line timing from LRCLIB,
/// NetEase, QQ. Lyrics are kept in memory only, never written to disk.
@MainActor
final class LyricsManager: ObservableObject {
    static let shared = LyricsManager()

    /// Lines of the current song, ready to show; empty when there are none.
    @Published private(set) var lines: [LyricsLine] = []
    @Published private(set) var isWordTimed = false
    /// Where the lyrics came from ("LRCLIB", "NetEase", "QQ Music"), empty when none.
    @Published private(set) var source = ""
    /// Language code of the current lyrics, when known.
    @Published private(set) var languageCode: String?
    /// True between just before the first line and the end of the last one. The
    /// closed notch only shows the lyric row then, not during the intro or after
    /// the last line (the song's ending), where it would be an empty strip.
    @Published private(set) var isWithinLyrics = false

    @Published private(set) var translationRequest: LyricsTranslationRequest?
    @Published private(set) var translationStatus: LyricsTranslationStatus = .idle

    private let music = MusicManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var fetchTask: Task<Void, Never>?
    private var currentQuery: LyricsQuery?
    /// The lyrics as fetched, before the display settings are applied.
    private var fetched: LyricsResult?
    /// Apple translations of the current song: target language → source text → translation.
    private var translations: [String: [String: String]] = [:]

    /// Recently played songs, so going back to one doesn't fetch again. Memory only.
    private var memoryCache: [String: LyricsResult] = [:]
    private var memoryCacheOrder: [String] = []
    private let memoryCacheLimit = 40

    private init() {
        // Cheap: returns at once when nothing is playing or there are no lyrics.
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.updateWithinLyrics() }
            .store(in: &cancellables)

        Publishers.CombineLatest4(music.$songTitle, music.$artistName, music.$album, music.$songDuration)
            .combineLatest(Defaults.publisher(.showLyrics).map(\.newValue))
            // Title, artist and length arrive one by one on a track change.
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.trackChanged() }
            .store(in: &cancellables)

        // Different sources can give different lyrics: fetch again.
        Publishers.CombineLatest3(
            Defaults.publisher(.lyricsUseLRCLIB).map(\.newValue),
            Defaults.publisher(.lyricsUseNetEase).map(\.newValue),
            Defaults.publisher(.lyricsUseQQ).map(\.newValue)
        )
        .dropFirst()
        .removeDuplicates { $0 == $1 }
        .sink { [weak self] _ in
            self?.memoryCache.removeAll()
            self?.memoryCacheOrder.removeAll()
            self?.currentQuery = nil
            self?.trackChanged()
        }
        .store(in: &cancellables)

        // Display settings only change how the same lyrics look.
        Publishers.CombineLatest4(
            Defaults.publisher(.lyricsSecondaryLine).map(\.newValue),
            Defaults.publisher(.lyricsTranslationLanguage).map(\.newValue),
            Defaults.publisher(.lyricsAutoTranslate).map(\.newValue),
            Defaults.publisher(.lyricsChineseScript).map(\.newValue)
        )
        .dropFirst()
        .sink { [weak self] _ in
            Task { @MainActor in self?.prepareForDisplay() }
        }
        .store(in: &cancellables)
    }

    /// Whether the open notch shows the lyric row: whenever the song has lyrics
    /// (pausing doesn't hide it there, so the open notch doesn't jump in size).
    private func updateWithinLyrics() {
        let within: Bool = {
            guard let first = lines.firstIndex(where: { !$0.text.isEmpty }),
                  let last = lines.lastIndex(where: { !$0.text.isEmpty }) else { return false }
            let ms = Int(music.estimatedPlaybackPosition() * 1000) + 150 + Defaults[.lyricsOffsetMs]
            // Show the row a moment before the first line, so it's there when it starts.
            let start = lines[first].timeMs - 1000
            // The last line ends at the pause after it, its last sung word, or after 6 s.
            let end: Int = {
                if last + 1 < lines.count { return lines[last + 1].timeMs }
                if let lastWord = lines[last].words?.last { return lastWord.startMs + lastWord.durationMs + 1500 }
                return lines[last].timeMs + 6000
            }()
            return ms >= start && ms < end
        }()
        if isWithinLyrics != within { isWithinLyrics = within }
    }

    var showsInOpenNotch: Bool {
        Defaults[.showLyrics] && !lines.isEmpty && music.hasActiveSession
    }

    /// The index of the line at `ms` into the song, or nil before the first line.
    func lineIndex(at ms: Int) -> Int? {
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].timeMs <= ms {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// Fetch the current song's lyrics again, ignoring what's in memory.
    func reload() {
        if let query = currentQuery {
            let key = cacheKey(for: query)
            memoryCache.removeValue(forKey: key)
            memoryCacheOrder.removeAll { $0 == key }
        }
        currentQuery = nil
        trackChanged()
    }

    // MARK: - Track changes

    private func trackChanged() {
        guard Defaults[.showLyrics], music.hasActiveSession, !music.isLiveStream,
              !music.songTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
            currentQuery = nil
            fetchTask?.cancel()
            setFetched(nil)
            return
        }

        let query = LyricsQuery(
            title: music.songTitle,
            artist: music.artistName,
            album: music.album,
            duration: music.songDuration
        )
        // Same song, only the length arrived or changed slightly: keep what we have.
        if let current = currentQuery, current.title == query.title, current.artist == query.artist,
           abs(current.duration - query.duration) < 2 || query.duration == 0 {
            return
        }
        currentQuery = query
        fetchTask?.cancel()

        let key = cacheKey(for: query)
        if let cached = memoryCache[key] {
            setFetched(cached)
            return
        }

        setFetched(nil)
        let sources = (lrclib: Defaults[.lyricsUseLRCLIB], netEase: Defaults[.lyricsUseNetEase], qq: Defaults[.lyricsUseQQ])
        fetchTask = Task { [weak self] in
            let result = await Self.fetch(query, sources: sources)
            guard !Task.isCancelled, let self, self.currentQuery == query else { return }
            let stored = result ?? LyricsResult(lines: [], source: "")
            self.remember(stored, key: key)
            self.setFetched(stored)
        }
    }

    private func setFetched(_ result: LyricsResult?) {
        fetched = result
        translations.removeAll()
        let detected = result.flatMap { LyricsPronunciation.dominantLanguage(of: $0.lines) }
        languageCode = detected.map(\.rawValue)
        prepareForDisplay()
    }

    // MARK: - Display

    /// Applies the display settings (Chinese script, pronunciation, translation) to the fetched lyrics.
    private func prepareForDisplay() {
        guard let fetched, !fetched.lines.isEmpty else {
            publish([], wordTimed: false, source: "")
            translationRequest = nil
            translationStatus = .idle
            return
        }

        let script = Defaults[.lyricsChineseScript]
        let secondary = Defaults[.lyricsSecondaryLine]
        let language = languageCode.map(NLLanguage.init(rawValue:))
        let target = LyricsTranslationLanguages.resolvedTarget
        let sourceTranslationFits = target.hasPrefix("zh")

        var prepared = fetched.lines.map { line -> LyricsLine in
            var line = line
            line.text = Self.convert(line.text, to: script)
            line.words = line.words?.map { word in
                var word = word
                word.text = Self.convert(word.text, to: script)
                return word
            }
            // NetEase's translations are Chinese; use them only when Chinese is wanted.
            if sourceTranslationFits, let translation = line.translation {
                line.translation = Self.convert(translation, to: target == "zh-Hant" ? .traditional : .simplified)
            } else {
                line.translation = nil
            }
            if secondary == .pronunciation, line.pronunciation == nil, !line.text.isEmpty {
                line.pronunciation = LyricsPronunciation.romanize(line.text, language: language)
            }
            return line
        }

        if secondary == .translation {
            prepared = applyAppleTranslations(to: prepared, target: target, language: language)
        } else {
            translationRequest = nil
            translationStatus = .idle
        }
        publish(prepared, wordTimed: fetched.isWordTimed, source: fetched.source)
    }

    /// Fills in Apple translations already done, and asks for the rest.
    private func applyAppleTranslations(to lines: [LyricsLine], target: String, language: NLLanguage?) -> [LyricsLine] {
        // Already in the wanted language: nothing to translate.
        if let language, Self.sameLanguage(language.rawValue, target) {
            translationRequest = nil
            translationStatus = .done
            return lines
        }
        let known = translations[target] ?? [:]
        let result = lines.map { line -> LyricsLine in
            guard line.translation == nil, let translated = known[line.text] else { return line }
            var line = line
            line.translation = translated
            return line
        }
        let missing = Array(Set(result.filter { $0.translation == nil && !$0.text.isEmpty }.map(\.text)))
        guard Defaults[.lyricsAutoTranslate], !missing.isEmpty else {
            translationRequest = nil
            translationStatus = missing.isEmpty ? .done : .idle
            return result
        }
        guard #available(macOS 15.0, *) else {
            translationStatus = .unavailable
            return result
        }
        if translationRequest?.target != target || Set(translationRequest?.texts ?? []) != Set(missing) {
            translationRequest = LyricsTranslationRequest(source: languageCode, target: target, texts: missing)
            translationStatus = .translating
        }
        return result
    }

    /// Called by `LyricsTranslationHost` when Apple's translation finishes.
    func applyTranslations(_ translated: [String: String], for request: LyricsTranslationRequest) {
        guard request == translationRequest else { return }
        translations[request.target, default: [:]].merge(translated) { _, new in new }
        translationRequest = nil
        translationStatus = .done
        prepareForDisplay()
    }

    func translationFailed(for request: LyricsTranslationRequest, status: LyricsTranslationStatus) {
        guard request == translationRequest else { return }
        translationStatus = status
    }

    /// Try the translation again (after the languages were downloaded).
    func retryTranslation() {
        translationRequest = nil
        prepareForDisplay()
    }

    private func publish(_ newLines: [LyricsLine], wordTimed: Bool, source newSource: String) {
        if lines != newLines { lines = newLines }
        if isWordTimed != wordTimed { isWordTimed = wordTimed }
        if source != newSource { source = newSource }
    }

    private static func convert(_ text: String, to script: LyricsChineseScript) -> String {
        switch script {
        case .original:
            return text
        case .simplified:
            return text.applyingTransform(StringTransform(rawValue: "Traditional-Simplified"), reverse: false) ?? text
        case .traditional:
            return text.applyingTransform(StringTransform(rawValue: "Simplified-Traditional"), reverse: false) ?? text
        }
    }

    private static func sameLanguage(_ a: String, _ b: String) -> Bool {
        let base: (String) -> String = { String($0.split(separator: "-").first ?? Substring($0)) }
        // Simplified and traditional Chinese count as different targets.
        if base(a) == "zh" || base(b) == "zh" { return a == b }
        return base(a) == base(b)
    }

    // MARK: - Fetching

    nonisolated private static func fetch(_ query: LyricsQuery, sources: (lrclib: Bool, netEase: Bool, qq: Bool)) async -> LyricsResult? {
        async let lrclib = sources.lrclib ? LyricsSources.lrclib(query) : .none
        async let netEase = sources.netEase ? LyricsSources.netEase(query) : (LyricsSources.Outcome.none, LyricsSources.Outcome.none)
        async let qq = sources.qq ? LyricsSources.qq(query) : .none
        let (lrclibOutcome, netEaseOutcome, qqOutcome) = await (lrclib, netEase, qq)

        for outcome in [netEaseOutcome.0, lrclibOutcome, netEaseOutcome.1, qqOutcome] {
            if case .lyrics(let result) = outcome {
                let lines = LyricsParsing.cleaned(result.lines, title: query.title, artist: query.artist)
                // A couple of lines is usually just credits or a "no lyrics" notice.
                if lines.filter({ !$0.text.isEmpty }).count >= 3 {
                    return LyricsResult(lines: lines, source: result.source)
                }
            }
        }
        return nil
    }

    // MARK: - Memory cache

    private func cacheKey(for query: LyricsQuery) -> String {
        "\(LyricsMatching.normalize(query.artist))|\(LyricsMatching.normalize(query.title))|\(Int((query.duration / 5).rounded()))"
    }

    private func remember(_ result: LyricsResult, key: String) {
        memoryCache[key] = result
        memoryCacheOrder.removeAll { $0 == key }
        memoryCacheOrder.append(key)
        while memoryCacheOrder.count > memoryCacheLimit {
            memoryCache.removeValue(forKey: memoryCacheOrder.removeFirst())
        }
    }
}
