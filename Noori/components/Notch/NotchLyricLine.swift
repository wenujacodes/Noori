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

/// The line being sung (under the closed notch, and under the controls in the open
/// notch), with an optional smaller second
/// line (translation, pronunciation or the next line). With word timing, the
/// words fill in as they're sung.
struct NotchLyricLine: View {
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

    /// Height of the row with the current settings.
    static var rowHeight: CGFloat {
        let size = CGFloat(Defaults[.lyricsFontSize])
        let secondary: CGFloat = Defaults[.lyricsSecondaryLine] == .none ? 0 : (max(9, size - 2) + 5).rounded()
        return (size + 10).rounded() + secondary
    }

    var body: some View {
        let fillsWords = karaoke && lyrics.isWordTimed
        TimelineView(.animation(minimumInterval: fillsWords ? 1.0 / 60.0 : 0.1, paused: !music.isPlaying)) { context in
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
                    // Like Apple Music: the old line drifts up and blurs out, the new one rises in.
                    .transition(.asymmetric(
                        insertion: .modifier(
                            active: LyricLineMotion(offset: 9, blur: 5, opacity: 0, scale: 0.97),
                            identity: LyricLineMotion(offset: 0, blur: 0, opacity: 1, scale: 1)
                        ),
                        removal: .modifier(
                            active: LyricLineMotion(offset: -9, blur: 5, opacity: 0, scale: 0.97),
                            identity: LyricLineMotion(offset: 0, blur: 0, opacity: 1, scale: 1)
                        )
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
            .animation(.spring(response: 0.55, dampingFraction: 0.9), value: index)
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
            // Each word lights up on its own, Apple Music style.
            HStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    SungWord(word: word, ms: ms, font: font, color: sungColor)
                }
            }
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

/// One word of a word-timed line. Unsung words are dim; as a word is sung, a soft
/// edge sweeps across it, it rises a little, and long held words glow.
private struct SungWord: View {
    let word: LyricWord
    let ms: Int
    let font: Font
    let color: Color

    private var progress: CGFloat {
        guard word.durationMs > 0 else { return ms >= word.startMs ? 1 : 0 }
        return min(1, max(0, CGFloat(ms - word.startMs) / CGFloat(word.durationMs)))
    }

    var body: some View {
        let p = progress
        // Ease out, so the rise settles instead of stopping hard.
        let lift = 1 - (1 - p) * (1 - p)
        // Held notes (a second or more) glow while they're sung.
        let glow = word.durationMs >= 1000 && p > 0 && p < 1 ? sin(.pi * p) : 0

        Text(word.text)
            .font(font)
            .foregroundStyle(color.opacity(0.35))
            .overlay {
                Text(word.text)
                    .font(font)
                    .foregroundStyle(color)
                    .mask {
                        // A soft edge 30% of the word wide, moving from left to right.
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: p * 1.3 - 0.3),
                                .init(color: .clear, location: p * 1.3),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                    .shadow(color: color.opacity(0.7 * glow), radius: 5)
            }
            .offset(y: -1.5 * lift)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Offset, blur, fade and scale for a lyric line coming in or going out.
private struct LyricLineMotion: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(y: offset)
            .blur(radius: blur)
            .opacity(opacity)
    }
}
