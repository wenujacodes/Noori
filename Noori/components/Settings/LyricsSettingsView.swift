/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 *
 * The lyrics settings follow Lyrimuse's (https://github.com/Yudaotor/lyrimuse),
 * GPL-3.0, limited to the lyrics under the notch. See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Combine
import Defaults
import SwiftUI

/// Settings › Lyrics.
struct LyricsSettingsView: View {
    @ObservedObject private var lyrics = LyricsManager.shared
    /// Whether something is playing; watching the whole MusicManager redrew this
    /// page on every playback update.
    @State private var hasActiveSession = MusicManager.shared.hasActiveSession

    @Default(.showLyrics) private var showLyrics
    @Default(.lyricsSecondaryLine) private var secondaryLine
    @Default(.lyricsTranslationLanguage) private var translationLanguage
    @Default(.lyricsChineseScript) private var chineseScript
    @Default(.lyricsOffsetMs) private var offsetMs
    @Default(.lyricsAlignment) private var alignment
    @Default(.lyricsColorStyle) private var colorStyle
    @Default(.lyricsFontSize) private var fontSize
    @Default(.lyricsFontWeight) private var fontWeight

    private func highlightID(_ title: String) -> String { "lyrics-\(title)" }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showLyrics) {
                    Text("Show lyrics under the notch")
                }
                .settingsHighlight(id: highlightID("Show lyrics under the notch"))
                if showLyrics {
                    HStack {
                        Text("Now playing")
                        Spacer()
                        Text(currentStatus)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if hasActiveSession {
                            Button("Search again") { lyrics.reload() }
                        }
                    }
                }
            } footer: {
                Text("While a song plays, the line being sung shows under the closed notch. The lyrics button in the player turns this on and off. Lyrics aren't saved on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .lyricsUseLRCLIB) { Text("LRCLIB") }
                Defaults.Toggle(key: .lyricsUseNetEase) { Text("NetEase Cloud Music") }
                Defaults.Toggle(key: .lyricsUseQQ) { Text("QQ Music") }
            } header: {
                Text("Sources")
            } footer: {
                Text("All enabled sources are searched at the same time, and word-by-word timing is used when one has it (NetEase Cloud Music has it for many songs). Only the song's title, artist, album and length are sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsHighlight(id: highlightID("Sources"))

            Section {
                Picker("Second line", selection: $secondaryLine) {
                    ForEach(LyricsSecondaryLine.allCases) { Text($0.title).tag($0) }
                }
                .settingsHighlight(id: highlightID("Second line"))

                Picker("Translate to", selection: $translationLanguage) {
                    Text("Automatic (\(LyricsTranslationLanguages.name(for: systemTarget)))").tag("")
                    Divider()
                    ForEach(LyricsTranslationLanguages.codes, id: \.self) { code in
                        Text(LyricsTranslationLanguages.name(for: code)).tag(code)
                    }
                }
                .settingsHighlight(id: highlightID("Translate to"))

                Defaults.Toggle(key: .lyricsAutoTranslate) {
                    Text("Translate on this Mac when there's no translation")
                }
                .disabled(!onDeviceTranslationAvailable)
                .settingsHighlight(id: highlightID("Translate on this Mac"))

                if secondaryLine == .translation {
                    translationStatusRow
                }

                Picker("Chinese characters", selection: $chineseScript) {
                    ForEach(LyricsChineseScript.allCases) { Text($0.title).tag($0) }
                }
                .settingsHighlight(id: highlightID("Chinese characters"))
            } header: {
                Text("Translation and pronunciation")
            } footer: {
                Text(onDeviceTranslationAvailable
                     ? "NetEase Cloud Music has Chinese translations for many songs. Other languages use Apple's translation on this Mac; nothing is sent online. Pronunciation shows romaji for Japanese, pinyin for Chinese and Latin letters for Korean and other scripts."
                     : "NetEase Cloud Music has Chinese translations for many songs. Translating into other languages needs macOS 15 or later. Pronunciation shows romaji for Japanese, pinyin for Chinese and Latin letters for Korean and other scripts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $offsetMs, in: -3000...3000, step: 100) {
                    HStack {
                        Text("Timing offset")
                        Spacer()
                        Text(offsetLabel)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Timing offset"))
                if offsetMs != 0 {
                    Button("Reset offset") { offsetMs = 0 }
                }
            } header: {
                Text("Timing")
            } footer: {
                Text("A positive offset shows lyrics earlier, a negative one later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .lyricsKaraoke) {
                    Text("Fill in words as they're sung")
                }
                .settingsHighlight(id: highlightID("Fill in words as they're sung"))

                Picker("Alignment", selection: $alignment) {
                    ForEach(LyricsAlignment.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Color", selection: $colorStyle) {
                    ForEach(LyricsColorStyle.allCases) { Text($0.title).tag($0) }
                }
                .settingsHighlight(id: highlightID("Color"))

                Picker("Weight", selection: $fontWeight) {
                    ForEach(LyricsFontWeight.allCases) { Text($0.title).tag($0) }
                }

                HStack {
                    Text("Text size")
                    Slider(value: $fontSize, in: 10...16, step: 1)
                    Text("\(Int(fontSize)) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                .settingsHighlight(id: highlightID("Text size"))
            } header: {
                Text("Look")
            } footer: {
                Text("Words fill in only when the lyrics have word-by-word timing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .lyricsHideWhenPaused) {
                    Text("Hide when paused")
                }
                .settingsHighlight(id: highlightID("Hide when paused"))
            } header: {
                Text("Behavior")
            }
        }
        .navigationTitle("Lyrics")
        .onReceive(
            Publishers.CombineLatest3(MusicManager.shared.$songTitle, MusicManager.shared.$artistName, MusicManager.shared.$isPlaying)
                .map { _ in () }
                .receive(on: RunLoop.main)
        ) { _ in
            let active = MusicManager.shared.hasActiveSession
            if hasActiveSession != active { hasActiveSession = active }
        }
    }

    // MARK: - Helpers

    /// The system language, shown for "Automatic".
    private var systemTarget: String {
        let system = Locale.current.language
        if system.languageCode?.identifier == "zh" {
            return system.script?.identifier == "Hant" ? "zh-Hant" : "zh-Hans"
        }
        return system.languageCode?.identifier ?? "en"
    }

    private var onDeviceTranslationAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    private var offsetLabel: String {
        let seconds = Double(offsetMs) / 1000
        return offsetMs == 0 ? "0 s" : String(format: "%+.1f s", seconds)
    }

    private var currentStatus: String {
        guard hasActiveSession else { return String(localized: "Nothing playing") }
        guard !lyrics.lines.isEmpty else { return String(localized: "No lyrics found") }
        let timing = lyrics.isWordTimed ? String(localized: "word by word") : String(localized: "line by line")
        return "\(lyrics.source) · \(timing)"
    }

    @ViewBuilder
    private var translationStatusRow: some View {
        switch lyrics.translationStatus {
        case .needsDownload:
            HStack {
                Text("The languages for this song aren't downloaded yet.")
                    .foregroundStyle(.secondary)
                Spacer()
                if #available(macOS 15.0, *) {
                    LyricsTranslationDownloadButton(
                        source: lyrics.languageCode,
                        target: LyricsTranslationLanguages.resolvedTarget,
                        onFinish: { lyrics.retryTranslation() }
                    )
                }
            }
        case .unsupported:
            Text("Apple's translation doesn't support this song's language.")
                .foregroundStyle(.secondary)
        case .translating:
            HStack {
                Text("Translating…")
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView().controlSize(.small)
            }
        case .idle, .done, .unavailable:
            EmptyView()
        }
    }
}
