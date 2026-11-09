/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 *
 * The LRC and NetEase word-timed (YRC) parsers are adapted from Lyrimuse
 * (https://github.com/Yudaotor/lyrimuse), licensed under the GPL-3.0.
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

/// One sung word (or syllable) with its own timing.
struct LyricWord: Equatable {
    let startMs: Int
    let durationMs: Int
    var text: String
}

/// One lyric line. `words` is set when the source has word-by-word timing.
/// An empty `text` marks a gap (instrumental part) starting at `timeMs`.
struct LyricsLine: Equatable {
    let timeMs: Int
    var text: String
    var words: [LyricWord]?
    /// From the lyrics source or Apple's on-device translation.
    var translation: String? = nil
    /// Reading in Latin letters (romaji, pinyin…), from the source or worked out on this Mac.
    var pronunciation: String? = nil
}

enum LyricsParsing {
    // MARK: - LRC (line timing)

    private static let tagRegex = try! NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
    private static let bracketRegex = try! NSRegularExpression(pattern: #"\[[^\]]*\]"#)
    private static let wordTimeTagRegex = try! NSRegularExpression(pattern: #"<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>"#)
    private static let doubleBracketRegex = try! NSRegularExpression(pattern: #"\s*(?:\[\[[^\[\]]*\]\]\s*)+"#)
    private static let offsetRegex = try! NSRegularExpression(pattern: #"\[offset:\s*([+-]?\d+)\s*\]"#)

    /// Parses LRC text. A line can carry several timestamps (a repeated chorus); each
    /// becomes its own line. Timestamp-only lines are kept as gaps. `[offset:±ms]`
    /// is applied (positive = lyrics earlier, as in the LRC spec).
    static func parseLRC(_ text: String) -> [LyricsLine] {
        let offset = lrcOffsetMs(text)
        var out: [LyricsLine] = []
        // CRLF is one Character in Swift, so split on "\n" would see the whole file as one line.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            let matches = tagRegex.matches(in: line, range: fullRange)
            if matches.isEmpty { continue }
            let unbracketed = doubleBracketRegex.stringByReplacingMatches(in: line, range: fullRange, withTemplate: " ")
            let unwrapped = wordTimeTagRegex.stringByReplacingMatches(
                in: unbracketed, range: NSRange(location: 0, length: (unbracketed as NSString).length), withTemplate: "")
            let stripped = bracketRegex
                .stringByReplacingMatches(in: unwrapped, range: NSRange(location: 0, length: (unwrapped as NSString).length), withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            for m in leadingTags(matches, in: nsLine) {
                let minutes = Int(nsLine.substring(with: m.range(at: 1))) ?? 0
                let seconds = Int(nsLine.substring(with: m.range(at: 2))) ?? 0
                var fracMs = 0
                let fracRange = m.range(at: 3)
                if fracRange.location != NSNotFound {
                    // .5, .50 and .500 all mean 500 ms.
                    fracMs = Int(String((nsLine.substring(with: fracRange) + "00").prefix(3))) ?? 0
                }
                let time = max(0, (minutes * 60 + seconds) * 1000 + fracMs - offset)
                out.append(LyricsLine(timeMs: time, text: stripped, words: nil))
            }
        }
        return out.sorted { $0.timeMs < $1.timeMs }
    }

    /// `[offset:±ms]`, ignored when it's implausibly large.
    private static func lrcOffsetMs(_ text: String) -> Int {
        let ns = text as NSString
        guard let m = offsetRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let value = Int(ns.substring(with: m.range(at: 1))),
              abs(value) <= 10_000 else { return 0 }
        return value
    }

    /// The timestamps at the start of a line; ones in the middle are word timing, not new lines.
    private static func leadingTags(_ matches: [NSTextCheckingResult], in line: NSString) -> [NSTextCheckingResult] {
        var leading: [NSTextCheckingResult] = []
        var cursor = 0
        for m in matches {
            let gap = line.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            guard gap.trimmingCharacters(in: .whitespaces).isEmpty else { break }
            leading.append(m)
            cursor = m.range.location + m.range.length
        }
        return leading.isEmpty ? Array(matches.prefix(1)) : leading
    }

    // MARK: - YRC (NetEase word timing)

    private static let yrcHeadRegex = try! NSRegularExpression(pattern: #"^\[(\d+),(\d+)\]"#)
    // A word's text may contain a literal "(" (like "(oh)"); only "(" followed by a
    // timing tuple starts a new word.
    private static let yrcWordRegex = try! NSRegularExpression(pattern: #"\((\d+),(\d+),\d+\)((?:[^(]|\((?!\d+,\d+,\d+\)))*)"#)
    // Some data has two-part tuples like "(18040,2255)"; drop them so the digits don't show.
    private static let yrcMalformedTupleRegex = try! NSRegularExpression(pattern: #"\(\d+,\d+\)"#)

    /// Parses NetEase's word-timed lyrics: each line is `[startMs,durationMs]` followed by
    /// `(wordStartMs,wordDurationMs,0)word` pieces. Lines without words are skipped.
    static func parseYRC(_ text: String) -> [LyricsLine] {
        var out: [LyricsLine] = []
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let rawLineString = String(rawLine)
            let rawNsLine = rawLineString as NSString
            let headRange = NSRange(location: 0, length: rawNsLine.length)
            guard let head = yrcHeadRegex.firstMatch(in: rawLineString, range: headRange) else { continue }
            let lineTimeMs = Int(rawNsLine.substring(with: head.range(at: 1))) ?? 0
            let lineDurationMs = Int(rawNsLine.substring(with: head.range(at: 2))) ?? 0
            let line = yrcMalformedTupleRegex.stringByReplacingMatches(in: rawLineString, range: headRange, withTemplate: "")
            let nsLine = line as NSString
            let matches = yrcWordRegex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            // Text between the line head and the first word's timing belongs to the first word.
            let headEnd = head.range.location + head.range.length
            var leading = ""
            if let first = matches.first, first.range.location > headEnd {
                leading = nsLine.substring(with: NSRange(location: headEnd, length: first.range.location - headEnd))
                if leading.trimmingCharacters(in: .whitespaces).isEmpty { leading = "" }
            }
            var words: [LyricWord] = []
            for m in matches {
                let wordText = nsLine.substring(with: m.range(at: 3))
                if wordText.isEmpty { continue }
                let start = Int(nsLine.substring(with: m.range(at: 1))) ?? 0
                let duration = Int(nsLine.substring(with: m.range(at: 2))) ?? 0
                if words.isEmpty, !leading.isEmpty {
                    let begin = min(lineTimeMs, start)
                    words.append(LyricWord(startMs: begin, durationMs: start + duration - begin, text: leading + wordText))
                    continue
                }
                words.append(LyricWord(startMs: start, durationMs: duration, text: wordText))
            }
            let text = words.map(\.text).joined().trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            out.append(LyricsLine(timeMs: lineTimeMs, text: text, words: words))
            // A gap after the line, so its text doesn't stay up through a long instrumental.
            if lineDurationMs > 0 {
                out.append(LyricsLine(timeMs: lineTimeMs + lineDurationMs + 1500, text: "", words: nil))
            }
        }
        out.sort { $0.timeMs < $1.timeMs }
        // A gap that lands after the next line has started isn't a gap.
        var cleaned: [LyricsLine] = []
        for (index, line) in out.enumerated() {
            if line.text.isEmpty, index + 1 < out.count, out[index + 1].timeMs <= line.timeMs { continue }
            cleaned.append(line)
        }
        return cleaned
    }

    // MARK: - Cleanup

    private static let creditRegex = try! NSRegularExpression(
        pattern: #"^\s*(作词|作詞|作曲|编曲|編曲|词|詞|曲|制作人|製作人|监制|監製|混音|母带|母帶|和声|和聲|合声|合聲|演唱|原唱|配唱|人声|人聲|伴唱|录音|錄音|出品|发行|發行|统筹|統籌|策划|策劃|吉他|贝斯|貝斯|鼓|弦乐|弦樂|键盘|鍵盤|OP|SP|Lyricist|Lyrics by|Lyrics|Composer|Composed by|Written by|Arranger|Arranged by|Producer|Produced by|Mixed by|Mastered by)[^:：\n]{0,4}\s*[:：]"#,
        options: [.caseInsensitive]
    )

    /// Drops credit lines ("作词 : …", "Composer: …") and a "Title - Artist" header line.
    static func cleaned(_ lines: [LyricsLine], title: String, artist: String) -> [LyricsLine] {
        let normalizedTitle = LyricsMatching.normalize(LyricsMatching.baseTitle(title))
        let normalizedArtist = LyricsMatching.normalize(LyricsMatching.primaryArtist(artist))
        var result = lines.filter { line in
            let text = line.text
            guard !text.isEmpty else { return true }
            let ns = text as NSString
            if creditRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil {
                return false
            }
            // "Song - Artist (Name)" near the start (QQ adds one).
            if line.timeMs < 15_000, text.contains("-"), !normalizedTitle.isEmpty, !normalizedArtist.isEmpty {
                let compact = LyricsMatching.normalize(text)
                if compact.contains(normalizedTitle), compact.contains(normalizedArtist) {
                    return false
                }
            }
            return true
        }
        // Leading gaps only delay the first line's appearance; drop them.
        while let first = result.first, first.text.isEmpty { result.removeFirst() }
        return result
    }

    /// Puts each extra line's text (a translation or pronunciation, timed like the
    /// lyrics) on the lyric line it belongs to: the one starting closest, within a second.
    static func attach(_ extras: [LyricsLine], to lines: [LyricsLine], as keyPath: WritableKeyPath<LyricsLine, String?>) -> [LyricsLine] {
        let extras = extras.filter { !$0.text.isEmpty && $0.text != "//" }
        guard !extras.isEmpty else { return lines }
        return lines.map { line in
            guard !line.text.isEmpty else { return line }
            let nearest = extras.min { abs($0.timeMs - line.timeMs) < abs($1.timeMs - line.timeMs) }
            guard let nearest, abs(nearest.timeMs - line.timeMs) <= 1000,
                  nearest.text != line.text else { return line }
            var updated = line
            updated[keyPath: keyPath] = nearest.text
            return updated
        }
    }

    /// QQ returns some characters as HTML entities.
    static func decodeHTMLEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let entities = ["&apos;": "'", "&#39;": "'", "&quot;": "\"", "&#34;": "\"", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#32;": " ", "&#10;": "\n", "&#13;": "", "&#40;": "(", "&#41;": ")", "&#45;": "-", "&#46;": ".", "&#58;": ":", "&amp;": "&"]
        for (entity, value) in entities {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }
}
