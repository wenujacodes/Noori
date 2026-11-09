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
import Defaults
import SwiftUI

/// The line being sung, under the closed notch, with an optional smaller second
/// line (translation, pronunciation or the next line). With word timing, the
/// words fill in as they're sung.
struct ClosedNotchLyricLine: View {
    let width: CGFloat

    @ObservedObject private var lyrics = LyricsManager.shared
    @ObservedObject private var music = MusicManager.shared
    @Default(.lyricsSecondaryLine) private var secondaryLine
    @Default(.lyricsKaraoke) private var karaoke
    @Default(.lyricsAlignment) private var alignment
    @Default(.lyricsColorStyle) private var colorStyle
    @Default(.lyricsFontSize) private var fontSize
    @Default(.lyricsFontWeight) private var fontWeight
    @Default(.lyricsOffsetMs) private var offsetMs

    /// Show a line slightly early so it doesn't trail the singer.
    private let leadMs = 150

    private var primaryHeight: CGFloat { (fontSize + 10).rounded() }
    private var secondaryFontSize: CGFloat { max(9, fontSize - 2) }
    private var secondaryHeight: CGFloat { secondaryLine == .none ? 0 : (secondaryFontSize + 5).rounded() }

    var body: some View {
        let fillsWords = karaoke && lyrics.isWordTimed
        TimelineView(.animation(minimumInterval: fillsWords ? 1.0 / 30.0 : 0.2, paused: !music.isPlaying)) { context in
            let ms = Int(music.estimatedPlaybackPosition(at: context.date) * 1000) + leadMs + offsetMs
            let index = lyrics.lineIndex(at: ms)
            let line = index.map { lyrics.lines[$0] }

            ZStack {
                if let index, let line, !line.text.isEmpty {
                    VStack(spacing: 0) {
                        primaryLine(line, ms: ms, fillsWords: fillsWords)
                            .frame(width: width, height: primaryHeight, alignment: frameAlignment)
                        if secondaryLine != .none {
                            secondaryText(for: line, at: index)
                                .frame(width: width, height: secondaryHeight, alignment: frameAlignment)
                        }
                    }
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
                        .frame(width: width, alignment: frameAlignment)
                        .transition(.opacity)
                }
            }
            .frame(width: width, height: primaryHeight + secondaryHeight)
            .animation(NooriMotion.change, value: index)
        }
        .clipped()
    }

    private var frameAlignment: Alignment { alignment == .center ? .center : .leading }

    private var sungColor: Color {
        switch colorStyle {
        case .white: return .white
        case .albumArt: return Color(nsColor: music.avgColor).ensureMinimumBrightness(factor: 0.7)
        case .accent: return .accentColor
        }
    }

    @ViewBuilder
    private func primaryLine(_ line: LyricsLine, ms: Int, fillsWords: Bool) -> some View {
        let size = fittingFontSize(for: line.text)
        let font = Font.system(size: size, weight: fontWeight.fontWeight)

        if fillsWords, let words = line.words {
            let fullWidth = textWidth(line.text, size: size)
            let sungWidth = textWidth(Self.sungText(words, ms: ms), size: size)
            let fraction = fullWidth > 0 ? min(1, sungWidth / fullWidth) : 0

            Text(line.text)
                .font(font)
                .foregroundStyle(sungColor.opacity(0.4))
                .overlay(alignment: .leading) {
                    Text(line.text)
                        .font(font)
                        .foregroundStyle(sungColor)
                        .mask(alignment: .leading) {
                            GeometryReader { geo in
                                Rectangle().frame(width: geo.size.width * fraction)
                            }
                        }
                }
                .lineLimit(1)
                .fixedSize()
        } else {
            Text(line.text)
                .font(font)
                .foregroundStyle(sungColor.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func secondaryText(for line: LyricsLine, at index: Int) -> some View {
        let text: String? = {
            switch secondaryLine {
            case .none: return nil
            case .translation: return line.translation
            case .pronunciation: return line.pronunciation
            case .nextLine:
                return lyrics.lines[(index + 1)...].first { !$0.text.isEmpty }?.text
            }
        }()
        if let text, !text.isEmpty {
            Text(text)
                .font(.system(size: secondaryFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
        } else {
            Color.clear
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

    /// The font size that fits the line in `width`, down to 80% of the chosen size.
    private func fittingFontSize(for text: String) -> CGFloat {
        let natural = textWidth(text, size: fontSize)
        guard natural > width, natural > 0 else { return fontSize }
        return max((fontSize * 0.8).rounded(), (fontSize * width / natural).rounded(.down))
    }

    private func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: size, weight: fontWeight.nsFontWeight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
