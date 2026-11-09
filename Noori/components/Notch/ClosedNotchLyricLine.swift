/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import SwiftUI

/// Height of the lyric row under the closed notch.
let closedNotchLyricRowHeight: CGFloat = 22

/// The line being sung, under the closed notch. With word timing, the words
/// fill in as they're sung.
struct ClosedNotchLyricLine: View {
    let width: CGFloat

    @ObservedObject private var lyrics = LyricsManager.shared
    @ObservedObject private var music = MusicManager.shared

    /// Show a line slightly early so it doesn't trail the singer.
    private let leadMs = 150
    private static let fontSize: CGFloat = 12
    private static let minimumFontSize: CGFloat = 10

    var body: some View {
        TimelineView(.animation(minimumInterval: lyrics.isWordTimed ? 1.0 / 30.0 : 0.2, paused: !music.isPlaying)) { context in
            let ms = Int(music.estimatedPlaybackPosition(at: context.date) * 1000) + leadMs
            let index = lyrics.lineIndex(at: ms)
            let line = index.map { lyrics.lines[$0] }

            ZStack {
                if let line, !line.text.isEmpty {
                    lineView(line, ms: ms)
                        .id(index)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 6)),
                            removal: .opacity.combined(with: .offset(y: -6))
                        ))
                } else {
                    // Before the first line and in instrumental parts.
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .transition(.opacity)
                }
            }
            .frame(width: width, height: closedNotchLyricRowHeight)
            .animation(NooriMotion.change, value: index)
        }
        .clipped()
    }

    @ViewBuilder
    private func lineView(_ line: LyricsLine, ms: Int) -> some View {
        let fontSize = Self.fittingFontSize(for: line.text, width: width)
        let font = Font.system(size: fontSize, weight: .semibold)

        if let words = line.words {
            let fullWidth = Self.textWidth(line.text, size: fontSize)
            let sungWidth = Self.textWidth(Self.sungText(words, ms: ms), size: fontSize)
            let fraction = fullWidth > 0 ? min(1, sungWidth / fullWidth) : 0

            Text(line.text)
                .font(font)
                .foregroundStyle(.white.opacity(0.4))
                .overlay(alignment: .leading) {
                    Text(line.text)
                        .font(font)
                        .foregroundStyle(.white)
                        .mask(alignment: .leading) {
                            GeometryReader { geo in
                                Rectangle().frame(width: geo.size.width * fraction)
                            }
                        }
                }
                .lineLimit(1)
                .fixedSize()
                .frame(width: width)
        } else {
            Text(line.text)
                .font(font)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: width)
        }
    }

    /// The part of the line sung by `ms`: whole words, plus the share of the current word.
    private static func sungText(_ words: [LyricWord], ms: Int) -> String {
        var sung = ""
        for word in words {
            if ms >= word.startMs + word.durationMs {
                sung += word.text
            } else if ms > word.startMs, word.durationMs > 0 {
                let progress = Double(ms - word.startMs) / Double(word.durationMs)
                let characters = Array(word.text)
                sung += String(characters.prefix(Int((Double(characters.count) * progress).rounded())))
                break
            } else {
                break
            }
        }
        return sung.trimmingCharacters(in: .whitespaces).isEmpty ? "" : sung
    }

    /// The font size that fits the line in `width`, down to the minimum.
    private static func fittingFontSize(for text: String, width: CGFloat) -> CGFloat {
        let natural = textWidth(text, size: fontSize)
        guard natural > width, natural > 0 else { return fontSize }
        return max(minimumFontSize, (fontSize * width / natural).rounded(.down))
    }

    private static func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
