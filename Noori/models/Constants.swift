/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 * Based on Atoll, Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll, and then for Noori
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Defaults
import Foundation

let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16


enum ThirdPartyDDCProvider: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case betterDisplay
    case lunar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .betterDisplay:
            return "BetterDisplay"
        case .lunar:
            return "Lunar"
        }
    }
    
    /// Bundle identifiers to try when looking up the app icon.
    var bundleIdentifiers: [String] {
        switch self {
        case .betterDisplay: return ["pro.betterdisplay.BetterDisplay"]
        case .lunar: return ["fyi.lunar.Lunar"]
        }
    }
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "Youtube Music"
    case amazonMusic = "Amazon Music"
    case cider = "Cider"
    
    var id: String { self.rawValue }
    
    var localizedName: String {
        switch self {
        case .nowPlaying: return String(localized: "Now Playing")
        case .appleMusic: return String(localized: "Apple Music")
        case .spotify: return String(localized: "Spotify")
        case .youtubeMusic: return String(localized: "Youtube Music")
        case .amazonMusic: return String(localized: "Amazon Music")
        case .cider: return String(localized: "Cider")
        }
    }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard = "Default"
    case inline = "Inline"
    
    var id: String { self.rawValue }
    
    var localizedName: String {
        switch self {
        case .standard: return String(localized: "Default")
        case .inline: return String(localized: "Inline")
        }
    }
}

enum LogLevel: Int, CaseIterable, Identifiable, Defaults.Serializable {
    case none = 0
    case error = 1
    case warning = 2
    case info = 3
    case debug = 4
    
    var id: Int { self.rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "No Logging"
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Info"
        case .debug: return "Debug"
        }
    }
}

enum CapsLockIndicatorTintMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case green
    case accent
    case white

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .green:
            return String(localized: "Green")
        case .accent:
            return String(localized: "Accent")
        case .white:
            return String(localized: "White")
        }
    }

    var color: Color {
        switch self {
        case .green:
            return .green
        case .accent:
            return .accentColor
        case .white:
            return .white
        }
    }
}

enum ProgressBarStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case hierarchical = "Hierarchical"
    case gradient = "Gradient"
    case segmented = "Segmented"
    
    var id: String { self.rawValue }
}

enum BatteryNotificationStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return String(localized: "Standard")
        case .compact:
            return String(localized: "Compact")
        }
    }
}

enum MusicAuxiliaryControl: String, CaseIterable, Identifiable, Defaults.Serializable {
    case shuffle
    case repeatMode
    case mediaOutput
    case lyrics

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shuffle:
            return "Shuffle"
        case .repeatMode:
            return "Repeat"
        case .mediaOutput:
            return "Media Output"
        case .lyrics:
            return "Lyrics"
        }
    }

    var symbolName: String {
        switch self {
        case .shuffle:
            return "shuffle"
        case .repeatMode:
            return "repeat"
        case .mediaOutput:
            return "laptopcomputer"
        case .lyrics:
            return "quote.bubble"
        }
    }

    static func alternative(
        excluding control: MusicAuxiliaryControl,
        preferring candidate: MusicAuxiliaryControl? = nil
    ) -> MusicAuxiliaryControl {
        if let candidate, candidate != control {
            return candidate
        }

        return allCases.first { $0 != control } ?? .shuffle
    }
}

enum MusicSkipBehavior: String, CaseIterable, Identifiable, Defaults.Serializable {
    case track
    case tenSecond

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .track:
            return String(localized: "Track Skip")
        case .tenSecond:
            return String(localized: "±10 Seconds")
        }
    }

    var description: String {
        switch self {
        case .track:
            return String(localized: "Standard previous/next track controls")
        case .tenSecond:
            return String(localized: "Skip forward or backward by ten seconds")
        }
    }
}



enum FocusMonitoringMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case withoutDevTools = "withoutDevTools"
    case useDevTools = "useDevTools"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .withoutDevTools:
            return "Standard"
        case .useDevTools:
            return "Faster, via system logs (needs Developer Tools permission)"
        }
    }
}


// AI Model types for screen assistant



extension Defaults.Keys {
        // MARK: General
    static let logLevel = Key<LogLevel>("logLevel", default: .none)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let hideNooriFromScreenCapture = Key<Bool>("hideNooriFromScreenCapture", default: false)
    
        // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.2)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let externalDisplayStyle = Key<ExternalDisplayStyle>(
        "externalDisplayStyle",
        default: .notch
    )
    static let hideNonNotchUntilHover = Key<Bool>("hideNonNotchUntilHover", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    static let openNotchWidth = Key<CGFloat>("openNotchWidth", default: 640)
    static let closedNotchWidth = Key<CGFloat>("closedNotchWidth", default: 150)
    static let customizePhysicalNotchWidth = Key<Bool>("customizePhysicalNotchWidth", default: false)
    
        // MARK: Appearance
    static let showEmojis = Key<Bool>("showEmojis", default: false)
    static let accentColor = Key<Color>("accentColor", default: Color.blue)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    static let useMusicVisualizer = Key<Bool>("useMusicVisualizer", default: true)
    static let visualizerBarCount = Key<Int>("visualizerBarCount", default: 5)
    
        // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    static let enableHorizontalMusicGestures = Key<Bool>("enableHorizontalMusicGestures", default: true)
    static let musicGestureBehavior = Key<MusicSkipBehavior>("musicGestureBehavior", default: .track)
    static let reverseSwipeGestures = Key<Bool>("reverseSwipeGestures", default: false)
    static let reverseScrollGestures = Key<Bool>("reverseScrollGestures", default: false)
    
        // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: true)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .inline)
    static let showSneakPeekOnTrackChange = Key<Bool>("showSneakPeekOnTrackChange", default: true)
    static let enableFullscreenMediaDetection = Key<Bool>("enableFullscreenMediaDetection", default: true)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: true)
    static let showMediaOutputControl = Key<Bool>("showMediaOutputControl", default: true)
    static let musicAuxLeftControl = Key<MusicAuxiliaryControl>("musicAuxLeftControl", default: .shuffle)
    static let musicAuxRightControl = Key<MusicAuxiliaryControl>("musicAuxRightControl", default: .repeatMode)
    static let didMigrateMusicAuxControls = Key<Bool>("didMigrateMusicAuxControls", default: false)
    static let musicControlSlots = Key<[MusicControlButton]>("musicControlSlots", default: MusicControlButton.defaultLayout)
    static let didMigrateMusicControlSlots = Key<Bool>("didMigrateMusicControlSlots", default: false)
    static let musicSkipBehavior = Key<MusicSkipBehavior>("musicSkipBehavior", default: .track)
    static let showStandardMediaControls = Key<Bool>("showStandardMediaControls", default: true)
    static let autoHideInactiveNotchMediaPlayer = Key<Bool>("autoHideInactiveNotchMediaPlayer", default: true)
    static let cachedMusicLiveActivityPreference = Key<Bool?>("cachedMusicLiveActivityPreference", default: nil)
    // Enable lock screen media widget (shows the standalone panel when screen is locked)
    
    
        // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let playLowBatteryAlertSound = Key<Bool>("playLowBatteryAlertSound", default: true)
    static let showChargingBatteryHUD = Key<Bool>("showChargingBatteryHUD", default: true)
    static let showLowBatteryHUD = Key<Bool>("showLowBatteryHUD", default: true)
    static let showFullBatteryHUD = Key<Bool>("showFullBatteryHUD", default: true)
    static let chargingBatteryHUDDuration = Key<Int>("chargingBatteryHUDDuration", default: 3)
    static let lowBatteryHUDDuration = Key<Int>("lowBatteryHUDDuration", default: 3)
    static let fullBatteryHUDDuration = Key<Int>("fullBatteryHUDDuration", default: 3)
    static let lowBatteryHUDThreshold = Key<Int>("lowBatteryHUDThreshold", default: 20)
    static let fullBatteryHUDThreshold = Key<Int>("fullBatteryHUDThreshold", default: 100)
    static let lowBatteryHUDStyle = Key<BatteryNotificationStyle>("lowBatteryHUDStyle", default: .standard)
    static let fullBatteryHUDStyle = Key<BatteryNotificationStyle>("fullBatteryHUDStyle", default: .standard)

    
        // MARK: Downloads
    
        // MARK: HUD
    static let inlineHUD = Key<Bool>("inlineHUD", default: true)
    static let progressBarStyle = Key<ProgressBarStyle>("progressBarStyle", default: .hierarchical)
    // Legacy support - keeping for backward compatibility
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    /// Volume bars green, brightness bars yellow (instead of white or the accent color).
    static let colorCodedHUDSliders = Key<Bool>("colorCodedHUDSliders", default: true)
    static let showProgressPercentages = Key<Bool>("showProgressPercentages", default: true)
    
    
    
        // MARK: Fullscreen Media Detection
    
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
    // MARK: Wobble Animation
    
    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)
    
    // MARK: Bluetooth Audio Devices
    static let showBluetoothDeviceConnections = Key<Bool>("showBluetoothDeviceConnections", default: true)
    static let showWiFiChanges = Key<Bool>("showWiFiChanges", default: true)
    static let showMenuBarIcon = Key<Bool>("showMenuBarIcon", default: false)
    static let showAirDropChanges = Key<Bool>("showAirDropChanges", default: true)
    static let useColorCodedBatteryDisplay = Key<Bool>("useColorCodedBatteryDisplay", default: true)
    static let useSmoothColorGradient = Key<Bool>("useSmoothColorGradient", default: true)
    static let useCircularBluetoothBatteryIndicator = Key<Bool>("useCircularBluetoothBatteryIndicator", default: true)
    static let showBluetoothBatteryPercentageText = Key<Bool>("showBluetoothBatteryPercentageText", default: true)
    static let showBluetoothDeviceNameMarquee = Key<Bool>("showBluetoothDeviceNameMarquee", default: true)
    static let showAirPodsListeningModeChanges = Key<Bool>("showAirPodsListeningModeChanges", default: true)
    
    
    
    
    
    
    
    

    
    // MARK: Keyboard Shortcuts
    static let enableShortcuts = Key<Bool>("enableShortcuts", default: false)
    
    // MARK: System HUD Feature
    static let enableSystemHUD = Key<Bool>("enableSystemHUD", default: true)
    static let enableVolumeHUD = Key<Bool>("enableVolumeHUD", default: true)
    static let enableBrightnessHUD = Key<Bool>("enableBrightnessHUD", default: true)
    static let enableKeyboardBacklightHUD = Key<Bool>("enableKeyboardBacklightHUD", default: true)
    static let systemHUDSensitivity = Key<Int>("systemHUDSensitivity", default: 5)

    // Step sizes for hardware media keys (percent of full range, 1-25)
    static let volumeStepPercent = Key<Int>("volumeStepPercent", default: 6)
    static let volumeFineStepPercent = Key<Int>("volumeFineStepPercent", default: 2)
    static let brightnessStepPercent = Key<Int>("brightnessStepPercent", default: 6)
    static let brightnessFineStepPercent = Key<Int>("brightnessFineStepPercent", default: 2)
    
// "left" or "right"
    
    

    // MARK: Third-Party DDC Integration
    static let enableThirdPartyDDCIntegration = Key<Bool>("enableThirdPartyDDCIntegration", default: false)
    static let thirdPartyDDCProvider = Key<ThirdPartyDDCProvider>("thirdPartyDDCProvider", default: .betterDisplay)
    static let enableExternalVolumeControlListener = Key<Bool>("enableExternalVolumeControlListener", default: false)
    static let didMigrateThirdPartyDDCIntegration = Key<Bool>("didMigrateThirdPartyDDCIntegration", default: false)

    // Legacy keys retained for migration/backward compatibility
    static let enableBetterDisplayIntegration = Key<Bool>("enableBetterDisplayIntegration", default: false)
    static let enableLunarIntegration = Key<Bool>("enableLunarIntegration", default: false)
    
    
    // MARK: Screen Recording Detection Feature
    static let enableScreenRecordingDetection = Key<Bool>("enableScreenRecordingDetection", default: true)
    static let showRecordingIndicator = Key<Bool>("showRecordingIndicator", default: true)
    // Polling removed - now uses event-driven private API detection (CGSIsScreenWatcherPresent)

    // MARK: Call Live Activity
    static let showCallLiveActivity = Key<Bool>("showCallLiveActivity", default: true)

    // MARK: Focus / Do Not Disturb Detection
    static let enableDoNotDisturbDetection = Key<Bool>("enableDoNotDisturbDetection", default: true)
    static let focusMonitoringMode = Key<FocusMonitoringMode>("focusMonitoringMode", default: .withoutDevTools)
    static let showDoNotDisturbIndicator = Key<Bool>("showDoNotDisturbIndicator", default: true)
    static let showDoNotDisturbLabel = Key<Bool>("showDoNotDisturbLabel", default: true)
    static let focusIndicatorNonPersistent = Key<Bool>("focusIndicatorNonPersistent", default: false)
    
    // MARK: Privacy Indicators (Camera & Microphone Detection)
    static let enableCameraDetection = Key<Bool>("enableCameraDetection", default: true)
    static let enableMicrophoneDetection = Key<Bool>("enableMicrophoneDetection", default: true)
    
    // MARK: Lock Screen Features
    
    // MARK: Caps Lock Indicator
    static let enableCapsLockIndicator = Key<Bool>("enableCapsLockIndicator", default: true)
    static let capsLockIndicatorTintMode = Key<CapsLockIndicatorTintMode>("capsLockIndicatorTintMode", default: .green)
    static let didMigrateCapsLockTintModeToGreen = Key<Bool>("didMigrateCapsLockTintModeToGreen", default: false)
    static let showCapsLockLabel = Key<Bool>("showCapsLockLabel", default: false)
    
    // MARK: Message notifications
    /// Off by default: reading new messages needs Full Disk Access.
    static let showMessageNotifications = Key<Bool>("showMessageNotifications", default: false)
    static let messageNotificationsQuickReply = Key<Bool>("messageNotificationsQuickReply", default: true)
    /// ROWID of the newest message already seen in chat.db (the only thing kept on disk).
    static let messagesLastSeenRowID = Key<Int>("messagesLastSeenRowID", default: 0)

    // MARK: ImageService
    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCacheV1", default: false)
    
    
    // MARK: Live Canvas
    
    
    // Default media controller for new installs.
    static var defaultMediaController: MediaControllerType {
        .nowPlaying
    }
    
    // Migration helper to convert from legacy enableGradient Boolean to new ProgressBarStyle enum
    static func migrateProgressBarStyle() {
        // Check if migration is needed by seeing if the old Boolean was set to gradient
        let wasGradientEnabled = Defaults[.enableGradient]
        
        // Only migrate if we're still using the default hierarchical value but gradient was enabled
        if wasGradientEnabled && Defaults[.progressBarStyle] == .hierarchical {
            Defaults[.progressBarStyle] = .gradient
        }
    }

    static func migrateMusicAuxControls() {
        // Atoll moved its old output button here; Noori never had that setting,
        // so new installs keep the default controls.
        if Defaults[.didMigrateMusicAuxControls] == false {
            Defaults[.didMigrateMusicAuxControls] = true
        }

        normalizeMusicAuxControls()
    }

    /// Green is the default Caps Lock color. Earlier builds saved White for every user on
    /// first launch, so switch a saved White to Green once; later choices are kept.
    static func migrateCapsLockTintMode() {
        guard Defaults[.didMigrateCapsLockTintModeToGreen] == false else { return }

        if Defaults[.capsLockIndicatorTintMode] == .white {
            Defaults[.capsLockIndicatorTintMode] = .green
        }
        Defaults[.didMigrateCapsLockTintModeToGreen] = true
    }

    static func migrateMusicControlSlots() {
        // Atoll built the slots from its older two-button settings. Noori never
        // had those, so new installs keep the default layout (lyrics on the right).
        guard Defaults[.didMigrateMusicControlSlots] == false else { return }
        Defaults[.didMigrateMusicControlSlots] = true
    }

    static func migrateThirdPartyDDCIntegration() {
        if Defaults[.didMigrateThirdPartyDDCIntegration] == false {
            let legacyBetterDisplayEnabled = Defaults[.enableBetterDisplayIntegration]
            let legacyLunarEnabled = Defaults[.enableLunarIntegration]

            if legacyBetterDisplayEnabled || legacyLunarEnabled {
                Defaults[.enableThirdPartyDDCIntegration] = true
                Defaults[.thirdPartyDDCProvider] = (legacyLunarEnabled && !legacyBetterDisplayEnabled) ? .lunar : .betterDisplay
            }

            Defaults[.didMigrateThirdPartyDDCIntegration] = true
        }

        syncLegacyThirdPartyDDCKeys()
    }

    static func syncLegacyThirdPartyDDCKeys() {
        let isIntegrationEnabled = Defaults[.enableThirdPartyDDCIntegration]
        let selectedProvider = Defaults[.thirdPartyDDCProvider]
        Defaults[.enableBetterDisplayIntegration] = isIntegrationEnabled && selectedProvider == .betterDisplay
        Defaults[.enableLunarIntegration] = isIntegrationEnabled && selectedProvider == .lunar
    }

    private static func normalizeMusicAuxControls() {
        guard Defaults[.musicAuxLeftControl] == Defaults[.musicAuxRightControl] else { return }

        let current = Defaults[.musicAuxLeftControl]
        let fallback = MusicAuxiliaryControl.alternative(excluding: current)
        Defaults[.musicAuxRightControl] = fallback
    }
    static let showSongMetadataInClosedNotch = Key<Bool>("showSongMetadataInClosedNotch", default: false)
    /// Synced lyrics under the closed notch while music plays.
    static let showLyrics = Key<Bool>("showLyrics", default: false)
    // Lyrics: sources
    static let lyricsUseLRCLIB = Key<Bool>("lyricsUseLRCLIB", default: true)
    static let lyricsUseNetEase = Key<Bool>("lyricsUseNetEase", default: true)
    static let lyricsUseQQ = Key<Bool>("lyricsUseQQ", default: true)
    // Lyrics: translation and pronunciation
    static let lyricsSecondaryLine = Key<LyricsSecondaryLine>("lyricsSecondaryLine", default: .none)
    /// Language code to translate into; empty = the system language.
    static let lyricsTranslationLanguage = Key<String>("lyricsTranslationLanguage", default: "")
    static let lyricsAutoTranslate = Key<Bool>("lyricsAutoTranslate", default: true)
    static let lyricsChineseScript = Key<LyricsChineseScript>("lyricsChineseScript", default: .original)
    // Lyrics: timing
    /// Positive shows lyrics earlier, negative later.
    static let lyricsOffsetMs = Key<Int>("lyricsOffsetMs", default: 0)
    // Lyrics: look
    static let lyricsKaraoke = Key<Bool>("lyricsKaraoke", default: true)
    static let lyricsAlignment = Key<LyricsAlignment>("lyricsAlignment", default: .center)
    static let lyricsColorStyle = Key<LyricsColorStyle>("lyricsColorStyle", default: .white)
    static let lyricsFontSize = Key<Double>("lyricsFontSize", default: 12)
    static let lyricsFontWeight = Key<LyricsFontWeight>("lyricsFontWeight", default: .semibold)
    // Lyrics: behavior
    static let lyricsHideWhenPaused = Key<Bool>("lyricsHideWhenPaused", default: true)
}
