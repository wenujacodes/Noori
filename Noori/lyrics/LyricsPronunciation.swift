/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation
import NaturalLanguage

/// Readings in Latin letters, worked out on this Mac: romaji for Japanese, pinyin
/// for Chinese, and the standard romanization for Korean, Cyrillic, Greek, Thai and others.
enum LyricsPronunciation {
    /// The main language of a song's lyrics.
    static func dominantLanguage(of lines: [LyricsLine]) -> NLLanguage? {
        let sample = lines.prefix(60).map(\.text).joined(separator: "\n")
        guard !sample.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return recognizer.dominantLanguage
    }

    /// The reading of a line, or nil when it's already in Latin letters.
    static func romanize(_ text: String, language: NLLanguage?) -> String? {
        guard hasNonLatinLetters(text) else { return nil }
        let result: String?
        if language == .japanese || hasKana(text) {
            result = japaneseRomaji(text)
        } else if language == .simplifiedChinese || language == .traditionalChinese {
            result = text.applyingTransform(.mandarinToLatin, reverse: false)
        } else if language == .russian || language == .ukrainian {
            // The everyday style ("Ya lyublyu"), not ISO 9 ("Â lûblû").
            let id = language == .ukrainian ? "Ukrainian-Latin/BGN" : "Russian-Latin/BGN"
            result = text.applyingTransform(StringTransform(rawValue: id), reverse: false)
                ?? text.applyingTransform(.toLatin, reverse: false)
        } else {
            result = text.applyingTransform(.toLatin, reverse: false)
        }
        let trimmed = result?.trimmingCharacters(in: .whitespaces)
        return (trimmed?.isEmpty ?? true) || trimmed == text ? nil : trimmed
    }

    /// Japanese with kanji needs a dictionary reading; the system tokenizer has one.
    private static func japaneseRomaji(_ text: String) -> String? {
        let cfText = text as CFString
        guard let tokenizer = CFStringTokenizerCreate(
            nil, cfText, CFRange(location: 0, length: CFStringGetLength(cfText)),
            kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale
        ) else { return nil }
        let ns = text as NSString
        var parts: [String] = []
        var lastEnd = 0
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            // Keep punctuation and Latin text between tokens as is.
            if range.location > lastEnd {
                let between = ns.substring(with: NSRange(location: lastEnd, length: range.location - lastEnd)).trimmingCharacters(in: .whitespaces)
                if !between.isEmpty { parts.append(between) }
            }
            let token = ns.substring(with: NSRange(location: range.location, length: range.length))
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                parts.append(latin)
            } else {
                parts.append(token)
            }
            lastEnd = range.location + range.length
        }
        if lastEnd < ns.length {
            let rest = ns.substring(from: lastEnd).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { parts.append(rest) }
        }
        // The small っ comes out as "~tsu": double the next consonant ("yoka~tsu ta" → "yokatta").
        var joined = parts.joined(separator: " ")
        joined = joined.replacingOccurrences(of: #"\s*~tsu\s*([bcdfghjkmpqrstvwxz])"#, with: "$1$1", options: .regularExpression)
        return joined.replacingOccurrences(of: "~", with: "")
    }

    private static func hasNonLatinLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar) && !(scalar.properties.isASCIIHexDigit || isLatin(scalar))
        }
    }

    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0041...0x024F, 0x1E00...0x1EFF: return true
        default: return false
        }
    }

    private static func hasKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
    }
}
