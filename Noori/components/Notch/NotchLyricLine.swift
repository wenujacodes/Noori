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

            if secondaryLine == .nextLine {
                nextLineRows(current: index, ms: ms, fillsWords: fillsWords)
            } else {
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
                    // The finished line slides up and out as the next one slides up from below.
                    .transition(.asymmetric(
                        insertion: .modifier(
                            active: LyricLineMotion(offset: primaryHeight + secondaryHeight, opacity: 0.4),
                            identity: LyricLineMotion(offset: 0, opacity: 1)
                        ),
                        removal: .modifier(
                            active: LyricLineMotion(offset: -(primaryHeight + secondaryHeight), opacity: 0.4),
                            identity: LyricLineMotion(offset: 0, opacity: 1)
                        )
                    ))
                } else {
                    // Before the first line and in instrumental parts: a music note,
                    // and the line that comes next, dimmed.
                    pauseView(upcoming: nextLyricIndex(after: index).map { lyrics.lines[$0].text })
                        .transition(.opacity)
                }
            }
            .frame(width: width, height: primaryHeight + secondaryHeight)
            // A smooth slide up, without bounce.
            .animation(.spring(response: 0.5, dampingFraction: 1), value: index)
            }
        }
        .clipped()
    }

    /// "Next line" mode: the current line and the next one are separate rows, keyed
    /// by line, so when a line is done it slides out on its own and the next line
    /// moves up and grows into its place.
    private func nextLineRows(current index: Int?, ms: Int, fillsWords: Bool) -> some View {
        // In a pause (or before the first line) the upcoming line takes the top row,
        // dimmed with a music note; when it's sung, the same row lights up in place.
        let isPause = index.map { lyrics.lines[$0].text.isEmpty } ?? true
        let topRow: Int? = isPause ? nextLyricIndex(after: index) : index
        let rows = [topRow, topRow.flatMap { nextLyricIndex(after: $0) }].compactMap { $0 }
        let smallScale = secondaryFontSize / max(fontSize, 1)
        let anchor: UnitPoint = alignment == .center ? .center : .leading

        return VStack(spacing: 0) {
            ForEach(rows, id: \.self) { row in
                let isTop = row == topRow
                let line = lyrics.lines[row]
                // Word-timed lines are already dim until they're sung.
                let dimmed: Double = fillsWords && line.words != nil ? 1 : 0.5
                // Every row is the same line view, drawn at full size: moving up only
                // changes its scale and brightness, so it never disappears on the way.
                HStack(spacing: 6) {
                    if isTop && isPause {
                        Image(systemName: "music.note")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    primaryLine(line, ms: ms, fillsWords: fillsWords)
                }
                .scaleEffect(isTop ? 1 : smallScale, anchor: anchor)
                .opacity(isTop && !isPause ? 1 : dimmed)
                .frame(width: width, height: isTop ? primaryHeight : secondaryHeight, alignment: frameAlignment)
                .transition(.asymmetric(
                    insertion: .modifier(
                        active: LyricLineMotion(offset: secondaryHeight, opacity: 0),
                        identity: LyricLineMotion(offset: 0, opacity: 1)
                    ),
                    removal: .modifier(
                        active: LyricLineMotion(offset: -primaryHeight, opacity: 0),
                        identity: LyricLineMotion(offset: 0, opacity: 1)
                    )
                ))
            }
        }
        .frame(width: width, height: primaryHeight + secondaryHeight, alignment: .top)
        .animation(.spring(response: 0.5, dampingFraction: 1), value: index)
    }

    /// A pause (or before the first line): the line that comes next, dimmed, in the
    /// main row with a music note, so the notch isn't an empty band.
    private func pauseView(upcoming: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            if let upcoming {
                Text(upcoming)
                    .font(.system(size: fittingFontSize(for: upcoming) * 0.92, weight: fontWeight.fontWeight))
                    .foregroundStyle(sungColor.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: width, height: primaryHeight, alignment: frameAlignment)
        .frame(height: primaryHeight + secondaryHeight, alignment: .top)
    }

    /// The first line with words after `index` (or the first line of the song).
    private func nextLyricIndex(after index: Int?) -> Int? {
        let start = (index ?? -1) + 1
        guard start < lyrics.lines.count else { return nil }
        return lyrics.lines[start...].firstIndex { !$0.text.isEmpty }
    }

    private var frameAlignment: Alignment { alignment == .center ? .center : .leading }

    private var sungColor: Color {
        switch colorStyle {
        case .white: return .white
        case .albumArt: return Color(nsColor: music.avgColor).ensureMinimumBrightness(factor: 0.7)
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
        LyricTextWidths.width(of: text, size: size, weight: fontWeight.nsFontWeight)
    }
}

/// Measured line widths. The row redraws up to 60 times a second; measuring the
/// same line with AppKit every frame made the notch's animations stutter.
@MainActor
private enum LyricTextWidths {
    private static var cache: [String: CGFloat] = [:]

    static func width(of text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let key = "\(size)|\(weight.rawValue)|\(text)"
        if let cached = cache[key] { return cached }
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        if cache.count > 500 { cache.removeAll() }
        cache[key] = width
        return width
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
                    // Only held notes glow; no shadow to draw for the rest.
                    .shadow(color: color.opacity(0.7 * glow), radius: glow > 0 ? 5 : 0)
            }
            .offset(y: -1.5 * lift)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Position and fade for a lyric line sliding in or out.
private struct LyricLineMotion: ViewModifier {
    let offset: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .opacity(opacity)
    }
}
