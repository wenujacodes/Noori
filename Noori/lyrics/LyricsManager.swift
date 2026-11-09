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
import CryptoKit
import Defaults
import Foundation

/// Finds synced lyrics for the current song and says which line is being sung.
///
/// Asks LRCLIB, NetEase Cloud Music and QQ Music at the same time and keeps the best:
/// word timing (NetEase) first, then line timing from LRCLIB, NetEase, QQ.
/// Results (including "no lyrics") are cached on disk.
@MainActor
final class LyricsManager: ObservableObject {
    static let shared = LyricsManager()

    /// Lines of the current song; empty when there are none (or lyrics are off).
    @Published private(set) var lines: [LyricsLine] = []
    @Published private(set) var isWordTimed = false

    private let music = MusicManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var fetchTask: Task<Void, Never>?
    private var currentQuery: LyricsQuery?
    private var memoryCache: [String: LyricsResult] = [:]

    /// "No lyrics" is trusted for a day, then asked again.
    private let notFoundRetryInterval: TimeInterval = 24 * 60 * 60

    private init() {
        Publishers.CombineLatest4(music.$songTitle, music.$artistName, music.$album, music.$songDuration)
            .combineLatest(Defaults.publisher(.showLyrics).map(\.newValue))
            // Title, artist and length arrive one by one on a track change.
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.trackChanged() }
            .store(in: &cancellables)
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

    // MARK: - Track changes

    private func trackChanged() {
        guard Defaults[.showLyrics], music.hasActiveSession, !music.isLiveStream,
              !music.songTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
            currentQuery = nil
            fetchTask?.cancel()
            show(nil)
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
        if let cached = memoryCache[key] ?? readDiskCache(key: key) {
            memoryCache[key] = cached
            show(cached)
            return
        }

        show(nil)
        fetchTask = Task { [weak self] in
            let result = await Self.fetch(query)
            guard !Task.isCancelled, let self, self.currentQuery == query else { return }
            let stored = result ?? LyricsResult(lines: [], source: "")
            self.memoryCache[key] = stored
            self.writeDiskCache(stored, key: key)
            self.show(stored)
        }
    }

    private func show(_ result: LyricsResult?) {
        let newLines = result?.lines ?? []
        if lines != newLines { lines = newLines }
        let wordTimed = result?.isWordTimed ?? false
        if isWordTimed != wordTimed { isWordTimed = wordTimed }
    }

    // MARK: - Fetching

    nonisolated private static func fetch(_ query: LyricsQuery) async -> LyricsResult? {
        async let lrclib = LyricsSources.lrclib(query)
        async let netEase = LyricsSources.netEase(query)
        async let qq = LyricsSources.qq(query)
        let (lrclibOutcome, netEaseOutcome, qqOutcome) = await (lrclib, netEase, qq)

        for outcome in [netEaseOutcome.word, lrclibOutcome, netEaseOutcome.line, qqOutcome] {
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

    // MARK: - Cache

    private func cacheKey(for query: LyricsQuery) -> String {
        let raw = "\(LyricsMatching.normalize(query.artist))|\(LyricsMatching.normalize(query.title))|\(Int((query.duration / 5).rounded()))"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private lazy var cacheDirectory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Noori", isDirectory: true)
            .appendingPathComponent("Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    private func readDiskCache(key: String) -> LyricsResult? {
        guard let file = cacheDirectory?.appendingPathComponent("\(key).json"),
              let data = try? Data(contentsOf: file),
              let result = try? JSONDecoder().decode(LyricsResult.self, from: data) else { return nil }
        if result.lines.isEmpty,
           let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           Date().timeIntervalSince(modified) > notFoundRetryInterval {
            return nil
        }
        return result
    }

    private func writeDiskCache(_ result: LyricsResult, key: String) {
        guard let file = cacheDirectory?.appendingPathComponent("\(key).json"),
              let data = try? JSONEncoder().encode(result) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
