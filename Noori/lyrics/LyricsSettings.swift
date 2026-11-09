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

import AppKit
import Defaults
import SwiftUI

/// What the smaller second line under the lyric shows.
enum LyricsSecondaryLine: String, CaseIterable, Identifiable, Defaults.Serializable {
    case none
    case translation
    case pronunciation
    case nextLine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return String(localized: "None")
        case .translation: return String(localized: "Translation")
        case .pronunciation: return String(localized: "Pronunciation")
        case .nextLine: return String(localized: "Next line")
        }
    }
}

/// How Chinese characters are written.
enum LyricsChineseScript: String, CaseIterable, Identifiable, Defaults.Serializable {
    case original
    case simplified
    case traditional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return String(localized: "As written")
        case .simplified: return String(localized: "Simplified")
        case .traditional: return String(localized: "Traditional")
        }
    }
}

enum LyricsAlignment: String, CaseIterable, Identifiable, Defaults.Serializable {
    case center
    case leading

    var id: String { rawValue }

    var title: String {
        switch self {
        case .center: return String(localized: "Center")
        case .leading: return String(localized: "Left")
        }
    }
}

enum LyricsColorStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case white
    case albumArt
    case accent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .white: return String(localized: "White")
        case .albumArt: return String(localized: "Album art color")
        case .accent: return String(localized: "Accent color")
        }
    }
}

enum LyricsFontWeight: String, CaseIterable, Identifiable, Defaults.Serializable {
    case regular
    case medium
    case semibold
    case bold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: return String(localized: "Regular")
        case .medium: return String(localized: "Medium")
        case .semibold: return String(localized: "Semibold")
        case .bold: return String(localized: "Bold")
        }
    }

    var fontWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    var nsFontWeight: NSFont.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

/// Languages offered for translation (Apple's on-device translation covers these).
enum LyricsTranslationLanguages {
    static let codes = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es", "fr", "de", "it", "pt-BR", "ru", "uk", "pl", "nl", "tr", "ar", "hi", "th", "vi", "id"]

    static func name(for code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    /// The chosen language, or the system language when "Automatic".
    static var resolvedTarget: String {
        let chosen = Defaults[.lyricsTranslationLanguage]
        if !chosen.isEmpty { return chosen }
        let system = Locale.current.language
        if system.languageCode?.identifier == "zh" {
            return system.script?.identifier == "Hant" ? "zh-Hant" : "zh-Hans"
        }
        return system.languageCode?.identifier ?? "en"
    }
}
