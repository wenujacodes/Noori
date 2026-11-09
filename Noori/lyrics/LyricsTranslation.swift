/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI
@_weakLinked import Translation

/// Lines to translate with Apple's on-device translation.
struct LyricsTranslationRequest: Equatable {
    let id = UUID()
    /// Language code of the lyrics; nil when unknown.
    let source: String?
    let target: String
    let texts: [String]
}

/// Whether on-device translation can run for the current song.
enum LyricsTranslationStatus: Equatable {
    case idle
    case translating
    case done
    /// The language pair is supported but its languages aren't downloaded yet.
    case needsDownload
    case unsupported
    /// macOS 14: no on-device translation.
    case unavailable
}

/// Invisible view in the notch that runs translation requests from `LyricsManager`.
/// Apple's translation sessions only come from a SwiftUI view.
struct LyricsTranslationHost: View {
    var body: some View {
        if #available(macOS 15.0, *) {
            TranslationRunner()
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

@available(macOS 15.0, *)
private struct TranslationRunner: View {
    @ObservedObject private var lyrics = LyricsManager.shared
    @State private var configuration: TranslationSession.Configuration?
    @State private var activeRequest: LyricsTranslationRequest?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { start(lyrics.translationRequest) }
            .onChange(of: lyrics.translationRequest) { _, request in start(request) }
            .translationTask(configuration) { session in
                guard let request = activeRequest else { return }
                let requests = request.texts.enumerated().map {
                    TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
                }
                do {
                    let responses = try await session.translations(from: requests)
                    var translated: [String: String] = [:]
                    for response in responses { translated[response.sourceText] = response.targetText }
                    lyrics.applyTranslations(translated, for: request)
                } catch {
                    lyrics.translationFailed(for: request, status: .unsupported)
                }
            }
    }

    private func start(_ request: LyricsTranslationRequest?) {
        guard let request, request != activeRequest else { return }
        Task {
            let target = Locale.Language(identifier: request.target)
            let source = request.source.map { Locale.Language(identifier: $0) }
            let availability = LanguageAvailability()
            let status: LanguageAvailability.Status
            if let source {
                status = await availability.status(from: source, to: target)
            } else if let sample = request.texts.first,
                      let detected = try? await availability.status(for: sample, to: target) {
                status = detected
            } else {
                status = .unsupported
            }
            // Never start a download from the notch; Settings has a button for that.
            guard status == .installed else {
                lyrics.translationFailed(for: request, status: status == .supported ? .needsDownload : .unsupported)
                return
            }
            activeRequest = request
            let newConfiguration = TranslationSession.Configuration(source: source, target: target)
            if configuration?.source == newConfiguration.source, configuration?.target == newConfiguration.target {
                configuration?.invalidate()
            } else {
                configuration = newConfiguration
            }
        }
    }
}

/// "Download languages" in Settings: asks macOS to download the language pair.
@available(macOS 15.0, *)
struct LyricsTranslationDownloadButton: View {
    let source: String?
    let target: String
    var onFinish: () -> Void

    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Button(String(localized: "Download languages…")) {
            let newConfiguration = TranslationSession.Configuration(
                source: source.map { Locale.Language(identifier: $0) },
                target: Locale.Language(identifier: target)
            )
            if configuration?.source == newConfiguration.source, configuration?.target == newConfiguration.target {
                configuration?.invalidate()
            } else {
                configuration = newConfiguration
            }
        }
        .translationTask(configuration) { session in
            try? await session.prepareTranslation()
            onFinish()
        }
    }
}
