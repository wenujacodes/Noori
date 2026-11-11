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

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

/// Shown until the first song's artwork arrives: empty, so nothing odd
/// (like a placeholder icon) flashes before the real cover.
let defaultImage: NSImage = .init(size: NSSize(width: 1, height: 1))

private struct ITunesExplicitnessSearchResponse: Decodable {
    let results: [ITunesExplicitnessTrack]
}

private struct ITunesExplicitnessTrack: Decodable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let trackExplicitness: String?
}

private actor MusicExplicitnessResolver {
    struct LookupKey: Hashable, Sendable {
        let title: String
        let artist: String
        let album: String

        init(title: String, artist: String, album: String) {
            self.title = MusicExplicitnessResolver.normalize(title)
            self.artist = MusicExplicitnessResolver.normalize(artist)
            self.album = MusicExplicitnessResolver.normalize(album)
        }

        var canResolve: Bool {
            !title.isEmpty && !artist.isEmpty
        }
    }

    static let shared = MusicExplicitnessResolver()

    private let session = URLSession(configuration: .ephemeral)
    private static let cacheLimit = 300
    private var cache: [LookupKey: Bool] = [:]
    private var cacheOrder: [LookupKey] = []
    private var inFlightTasks: [LookupKey: Task<Bool, Never>] = [:]

    private func store(_ value: Bool, for key: LookupKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
            while cacheOrder.count > Self.cacheLimit {
                let evicted = cacheOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        }
        cache[key] = value
    }

    func resolve(title: String, artist: String, album: String) async -> Bool {
        let key = LookupKey(title: title, artist: artist, album: album)
        guard key.canResolve else { return false }

        if let cached = cache[key] {
            return cached
        }

        if let inFlightTask = inFlightTasks[key] {
            return await inFlightTask.value
        }

        let task = Task<Bool, Never> { [session] in
            await Self.fetchExplicitness(for: key, using: session)
        }

        inFlightTasks[key] = task
        let result = await task.value
        store(result, for: key)
        inFlightTasks[key] = nil
        return result
    }

    private static func fetchExplicitness(for key: LookupKey, using session: URLSession) async -> Bool {
        let query = "\(key.title) \(key.artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(
                string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=15")
        else {
            return false
        }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(ITunesExplicitnessSearchResponse.self, from: data)

            let bestMatch = response.results
                .map { track in (track, matchScore(for: track, key: key)) }
                .max { lhs, rhs in lhs.1 < rhs.1 }

            guard let bestMatch,
                  bestMatch.1 >= 8
            else {
                return false
            }

            return bestMatch.0.trackExplicitness?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == "explicit"
        } catch {
            return false
        }
    }

    private static func matchScore(for track: ITunesExplicitnessTrack, key: LookupKey) -> Int {
        let trackTitle = canonicalTitle(track.trackName ?? "")
        guard !trackTitle.isEmpty else { return Int.min }

        let keyTitle = canonicalTitle(key.title)
        let trackArtist = normalize(track.artistName ?? "")
        let trackAlbum = normalize(track.collectionName ?? "")

        var score = 0

        if trackTitle == keyTitle {
            score += 6
        } else if trackTitle.contains(keyTitle) || keyTitle.contains(trackTitle) {
            score += 4
        } else {
            return Int.min
        }

        if !key.artist.isEmpty {
            if trackArtist == key.artist {
                score += 4
            } else if trackArtist.contains(key.artist) || key.artist.contains(trackArtist) {
                score += 2
            }
        }

        if !key.album.isEmpty {
            if trackAlbum == key.album {
                score += 2
            } else if !trackAlbum.isEmpty && (trackAlbum.contains(key.album) || key.album.contains(trackAlbum)) {
                score += 1
            }
        }

        return score
    }

    private static func canonicalTitle(_ value: String) -> String {
        var title = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        title = title.replacingOccurrences(
            of: #"\([^)]*\)|\[[^\]]*\]"#,
            with: " ",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: #"\s-\s(?:\d{4}\s)?(?:remaster(?:ed)?|live|edit|mix|version|mono|stereo).*$"#,
            with: " ",
            options: .regularExpression
        )
        return normalize(title)
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let stripped = folded.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: " ",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private actor SpotifyExplicitnessResolver {
    struct LookupKey: Hashable, Sendable {
        let trackID: String

        init?(contentIdentifier: String?, contentURL: String?) {
            guard let trackID = SpotifyExplicitnessResolver.extractTrackID(from: contentIdentifier)
                ?? SpotifyExplicitnessResolver.extractTrackID(from: contentURL)
            else {
                return nil
            }

            self.trackID = trackID
        }
    }

    static let shared = SpotifyExplicitnessResolver()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0",
            "Accept-Language": "en-US,en;q=0.9"
        ]
        return URLSession(configuration: configuration)
    }()

    private static let cacheLimit = 300
    private var cache: [LookupKey: Bool] = [:]
    private var cacheOrder: [LookupKey] = []
    private var inFlightTasks: [LookupKey: Task<Bool?, Never>] = [:]

    private func store(_ value: Bool, for key: LookupKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
            while cacheOrder.count > Self.cacheLimit {
                let evicted = cacheOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        }
        cache[key] = value
    }

    func resolve(key: LookupKey) async -> Bool? {
        if let cached = cache[key] {
            return cached
        }

        if let inFlightTask = inFlightTasks[key] {
            return await inFlightTask.value
        }

        let task = Task<Bool?, Never> { [session] in
            await Self.fetchExplicitness(for: key, using: session)
        }

        inFlightTasks[key] = task
        let result = await task.value
        if let result {
            store(result, for: key)
        }
        inFlightTasks[key] = nil
        return result
    }

    private static func fetchExplicitness(for key: LookupKey, using session: URLSession) async -> Bool? {
        guard let url = URL(string: "https://open.spotify.com/embed/track/\(key.trackID)") else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8)
            else {
                return nil
            }

            if let isExplicit = parseIsExplicitDirectly(from: html) {
                return isExplicit
            }

            if let nextDataJSON = extractNextDataJSON(from: html),
               let isExplicit = parseIsExplicit(from: nextDataJSON) {
                return isExplicit
            }

            return nil
        } catch {
            return nil
        }
    }

    private static func extractNextDataJSON(from html: String) -> String? {
        let pattern = #"<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > 1,
              let jsonRange = Range(match.range(at: 1), in: html)
        else {
            return nil
        }

        return String(html[jsonRange])
    }

    private static func parseIsExplicitDirectly(from html: String) -> Bool? {
        if let value = captureFirstMatch(
            in: html,
            pattern: #""isExplicit"\s*:\s*(true|false)"#
        ) {
            return value == "true"
        }

        if let label = captureFirstMatch(
            in: html,
            pattern: #""label"\s*:\s*"([A-Z_]+)""#
        ) {
            switch label {
            case "EXPLICIT":
                return true
            case "NON_EXPLICIT":
                return false
            default:
                break
            }
        }

        return nil
    }

    private static func captureFirstMatch(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }

        return String(source[valueRange]).lowercased()
    }

    private static func parseIsExplicit(from nextDataJSON: String) -> Bool? {
        guard let data = nextDataJSON.data(using: .utf8),
              let rootObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = rootObject["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let state = pageProps["state"] as? [String: Any],
              let dataObject = state["data"] as? [String: Any],
              let entity = dataObject["entity"] as? [String: Any]
        else {
            return nil
        }

        if let isExplicit = entity["isExplicit"] as? Bool {
            return isExplicit
        }

        if let contentRating = entity["contentRating"] as? [String: Any],
           let label = contentRating["label"] as? String {
            return label.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "EXPLICIT"
        }

        return nil
    }

    private static func extractTrackID(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("spotify:track:") {
            return validatedTrackID(String(trimmed.split(separator: ":").last ?? ""))
        }

        if let url = URL(string: trimmed) {
            let pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if let trackIndex = pathComponents.firstIndex(of: "track"),
               trackIndex + 1 < pathComponents.count {
                return validatedTrackID(pathComponents[trackIndex + 1])
            }
        }

        return validatedTrackID(trimmed)
    }

    private static func validatedTrackID<S: StringProtocol>(_ candidate: S) -> String? {
        let value = String(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[A-Za-z0-9]{22}$"#, options: .regularExpression) != nil else {
            return nil
        }

        return value
    }
}

class MusicManager: ObservableObject {
    enum SkipDirection: Equatable {
        case backward
        case forward
    }

    struct SkipGesturePulse: Equatable {
        let token: Int
        let direction: SkipDirection
        let behavior: MusicSkipBehavior
    }

    static let skipGestureSeekInterval: TimeInterval = 10

    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?
    @MainActor private var pendingOptimisticPlayState: Bool?

    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Pear Desktop auto-detection
    private static let pearDesktopBundleID = YouTubeMusicConfiguration.default.bundleIdentifier
    private var isPearDesktopAutoSwitched: Bool = false

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true
    @Published var isCurrentTrackExplicit: Bool = false

    /// Whether there is an active music session with real metadata.
    /// Returns `false` only when the metadata is still placeholder/fallback defaults
    /// (i.e. nothing has been played since app launch, or the controller returned
    /// unknown/not-playing placeholders). Paused music with real metadata is still
    /// considered an active session.
    private static let placeholderTitles: Set<String> = [
        "i'm handsome", "unknown", "not playing"
    ]
    private static let placeholderArtists: Set<String> = [
        "me", "unknown"
    ]

    var hasActiveSession: Bool {
        if isPlaying { return true }
        let trimmedTitle = songTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedArtist = artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasRealTitle = !trimmedTitle.isEmpty && !Self.placeholderTitles.contains(trimmedTitle)
        let hasRealArtist = !trimmedArtist.isEmpty && !Self.placeholderArtists.contains(trimmedArtist)
        return hasRealTitle || hasRealArtist
    }

    @Published var animations: NooriAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var secondaryColor: NSColor = .gray
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var isLiveStream: Bool = false
    @ObservedObject var coordinator = NooriViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published private(set) var skipGesturePulse: SkipGesturePulse?

    private var explicitLookupTask: Task<Void, Never>?
    private var explicitLookupKey: String?

    private(set) var artworkData: Data? = nil


    private var liveStreamUnknownDurationCount: Int = 0
    private var liveStreamEdgeObservationCount: Int = 0
    private var liveStreamCompletionObservationCount: Int = 0
    private var liveStreamCompletionReleaseCount: Int = 0

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil
    private var lastArtworkContentIdentifier: String? = nil
    private var lastArtworkContentURL: String? = nil

    @Published var flipAngle: Double = 0
    /// A Spotify ad is playing (its track id starts with "spotify:ad:").
    @Published private(set) var isAdvertisement = false
    @Published var lastFlipDirection: SkipDirection = .forward
    private let flipAnimationDuration: TimeInterval = 0.75
    private var flipCooldownActive: Bool = false

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?
    private var skipGestureToken: Int = 0

    // MARK: - Initialization
    init() {
        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.isPearDesktopAutoSwitched = false
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        // Re-pick the album art colors when the color style changes.
        Defaults.publisher(.colorExtractionMode, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.calculateAverageColor() }
            .store(in: &cancellables)

        // Observe Pear Desktop launch/terminate for auto-detection
        setupPearDesktopAutoDetection()

        // Initialize deprecation check asynchronously
        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
            // Check if Pear Desktop is already running at startup
            let pearDesktopRunning = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == Self.pearDesktopBundleID
            }
            
            if pearDesktopRunning {
                print("[MusicManager] Pear Desktop detected at startup, auto-switching to YouTubeMusicController")
                self.isPearDesktopAutoSwitched = true
                if let controller = self.createController(for: .youtubeMusic) {
                    self.setActiveController(controller)
                }
            } else {
                // Initialize the active controller after deprecation check
                self.setActiveControllerBasedOnPreference()
            }
        }
    }

    // MARK: - Pear Desktop Auto-Detection
    private func setupPearDesktopAutoDetection() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] notification in
                guard let self = self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.pearDesktopBundleID else { return }

                print("[MusicManager] Pear Desktop launched, auto-switching to YouTubeMusicController")
                self.isPearDesktopAutoSwitched = true
                if let controller = self.createController(for: .youtubeMusic) {
                    self.setActiveController(controller)
                }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] notification in
                guard let self = self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.pearDesktopBundleID else { return }

                print("[MusicManager] Pear Desktop terminated, reverting to preferred controller")
                if self.isPearDesktopAutoSwitched {
                    self.isPearDesktopAutoSwitched = false
                    self.setActiveControllerBasedOnPreference()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        explicitLookupTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        transitionWorkItem?.cancel()

        // Release active controller
        activeController = nil
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        // Cleanup previous controller
        if activeController != nil {
            controllerCancellables.removeAll()
            activeController = nil
        }

        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        case .youtubeMusic:
            newController = YouTubeMusicController()
        case .amazonMusic:
            newController = AmazonMusicController()
        case .cider:
            newController = CiderController()
        }

        // Set up state observation for the new controller
        if let controller = newController {
            controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self,
                          self.activeController === controller else { return }
                    self.updateFromPlaybackState(state)
                }
                .store(in: &controllerCancellables)
        }

        return newController
    }

    private func setActiveControllerBasedOnPreference() {
        let preferredType = Defaults[.mediaController]
        print("Preferred Media Controller: \(preferredType)")

        // If NowPlaying is deprecated but that's the preference, use Apple Music instead
        let controllerType = (self.isNowPlayingDeprecated && preferredType == .nowPlaying)
            ? .appleMusic
            : preferredType

        if let controller = createController(for: controllerType) {
            setActiveController(controller)
        } else if controllerType != .appleMusic, let fallbackController = createController(for: .appleMusic) {
            // Fallback to Apple Music if preferred controller couldn't be created
            setActiveController(fallbackController)
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        // Set new active controller
        activeController = controller

        // Get current state from active controller
        forceUpdate()
    }

    @MainActor
    private func applyPlayState(_ state: Bool, animation: Animation?) {
        if let animation {
            var transaction = Transaction()
            transaction.animation = animation
            withTransaction(transaction) {
                self.isPlaying = state
            }
        } else {
            self.isPlaying = state
        }

        self.updateIdleState(state: state)
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Check for playback state changes (playing/paused)
        let eventIsPlaying = state.isPlaying
        let expectedState = pendingOptimisticPlayState
        pendingOptimisticPlayState = nil

        if eventIsPlaying != self.isPlaying {
            let animation: Animation? = (expectedState == eventIsPlaying) ? .smooth(duration: 0.18) : .smooth
            applyPlayState(eventIsPlaying, animation: animation)

            if eventIsPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                self.updateSneakPeek()
            }
        } else {
            self.updateIdleState(state: eventIsPlaying)
        }

        // Spotify ads: the AppleScript track id starts with "spotify:ad:". Through
        // macOS Now Playing there's no such id, but ads come from the artist
        // "Spotify" (no real song is credited to just "Spotify").
        let isSpotify = state.bundleIdentifier == "com.spotify.client"
        let isAd = (state.contentIdentifier?.contains("spotify:ad:") ?? false)
            || (isSpotify && state.artist.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Spotify") == .orderedSame)
            || (isSpotify && state.artist.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Advertisement") == .orderedSame)
        if isAd != self.isAdvertisement { self.isAdvertisement = isAd }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier
        let contentIdentifierChanged = state.contentIdentifier != self.lastArtworkContentIdentifier
        let contentURLChanged = state.contentURL != self.lastArtworkContentURL

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData

        let hasContentChange =
            titleChanged
            || artistChanged
            || albumChanged
            || artworkChanged
            || bundleChanged
            || contentIdentifierChanged
            || contentURLChanged
        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        // Handle artwork and visual transitions for changed content
        let shouldAutoPeekOnTrackChange = Defaults[.showSneakPeekOnTrackChange]

        if hasContentChange {
            // No flip for the very first cover after launch; it just appears.
            if self.albumArt !== defaultImage {
                self.triggerFlipAnimation()
            }

            if artworkChanged, let artwork = state.artwork {
                self.updateArtwork(artwork, bundleIdentifier: state.bundleIdentifier)
            } else if state.artwork == nil {
                // No artwork: a music app shows its icon, anything else (a
                // browser, say) a plain music-note cover. Wait a bit first: the
                // artwork often arrives in a separate update right after, and
                // that cancels this, so the stand-in doesn't flash first.
                if NowPlayingArtwork.isMusicApp(state.bundleIdentifier),
                   let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                    self.updateAlbumArt(newAlbumArt: appIconImage, isAppIcon: true, delay: 1.0)
                } else {
                    self.updateAlbumArt(newAlbumArt: NowPlayingArtwork.placeholder, isAppIcon: true, delay: 1.0)
                }
            }
            self.artworkData = state.artwork

            // Update last artwork change values
            self.lastArtworkTitle = state.title
            self.lastArtworkArtist = state.artist
            self.lastArtworkAlbum = state.album
            self.lastArtworkBundleIdentifier = state.bundleIdentifier
            self.lastArtworkContentIdentifier = state.contentIdentifier
            self.lastArtworkContentURL = state.contentURL

            self.refreshExplicitFlag(for: state)


            // Only update sneak peek if there's actual content and something changed
            if shouldAutoPeekOnTrackChange && !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }
        } else if state.isExplicit != nil {
            self.refreshExplicitFlag(for: state)
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode

        if timeChanged {
            self.elapsedTime = state.currentTime
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        
        updateLiveStreamState(with: state)
        self.timestampDate = state.lastUpdated
    }

    @MainActor
    private func refreshExplicitFlag(for state: PlaybackState) {
        if let explicitValue = state.isExplicit {
            explicitLookupTask?.cancel()
            explicitLookupTask = nil
            explicitLookupKey = nil

            if isCurrentTrackExplicit != explicitValue {
                isCurrentTrackExplicit = explicitValue
            }
            return
        }

        if state.bundleIdentifier == SpotifyController.bundleIdentifier,
           let spotifyLookupKey = SpotifyExplicitnessResolver.LookupKey(
               contentIdentifier: state.contentIdentifier,
               contentURL: state.contentURL
           ) {
            let lookupIdentifier = "spotify|\(spotifyLookupKey.trackID)"
            let fallbackTitle = state.title
            let fallbackArtist = state.artist
            let fallbackAlbum = state.album
            guard explicitLookupKey != lookupIdentifier else { return }

            explicitLookupTask?.cancel()
            explicitLookupKey = lookupIdentifier

            if isCurrentTrackExplicit {
                isCurrentTrackExplicit = false
            }

            explicitLookupTask = Task { [weak self] in
                let isExplicit = await SpotifyExplicitnessResolver.shared.resolve(key: spotifyLookupKey)

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self,
                          self.explicitLookupKey == lookupIdentifier
                    else {
                        return
                    }

                    self.explicitLookupTask = nil

                    if let isExplicit {
                        self.isCurrentTrackExplicit = isExplicit
                    } else {
                        self.explicitLookupKey = nil
                        self.refreshGenericExplicitFlag(
                            title: fallbackTitle,
                            artist: fallbackArtist,
                            album: fallbackAlbum
                        )
                    }
                }
            }
            return
        }

        refreshGenericExplicitFlag(title: state.title, artist: state.artist, album: state.album)
    }

    @MainActor
    private func refreshGenericExplicitFlag(title: String, artist: String, album: String) {
        let lookupKey = MusicExplicitnessResolver.LookupKey(
            title: title,
            artist: artist,
            album: album
        )
        let lookupIdentifier = "generic|\(lookupKey.title)|\(lookupKey.artist)|\(lookupKey.album)"

        guard lookupKey.canResolve,
              !Self.placeholderTitles.contains(lookupKey.title),
              !Self.placeholderArtists.contains(lookupKey.artist)
        else {
            explicitLookupTask?.cancel()
            explicitLookupTask = nil
            explicitLookupKey = nil
            if isCurrentTrackExplicit {
                isCurrentTrackExplicit = false
            }
            return
        }

        guard explicitLookupKey != lookupIdentifier else { return }

        explicitLookupTask?.cancel()
        explicitLookupKey = lookupIdentifier

        if isCurrentTrackExplicit {
            isCurrentTrackExplicit = false
        }

        explicitLookupTask = Task { [weak self] in
            let isExplicit = await MusicExplicitnessResolver.shared.resolve(
                title: title,
                artist: artist,
                album: album
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self,
                      self.explicitLookupKey == lookupIdentifier
                else {
                    return
                }

                self.isCurrentTrackExplicit = isExplicit
                self.explicitLookupTask = nil
            }
        }
    }

    private func triggerFlipAnimation() {
        // Debounce: rapid metadata updates (title, artwork, bundle arriving
        // separately for one track change) should only produce a single flip.
        guard !flipCooldownActive else { return }
        flipCooldownActive = true

        // Direction: positive rotation = next (page turn forward),
        //            negative rotation = previous (page turn backward).
        let delta: Double = lastFlipDirection == .forward ? 180 : -180
        withAnimation(.smooth(duration: flipAnimationDuration)) {
            flipAngle += delta
        }

        // Reset cooldown after the animation completes so the next
        // genuine track change can flip again.
        DispatchQueue.main.asyncAfter(deadline: .now() + flipAnimationDuration + 0.15) { [weak self] in
            self?.flipCooldownActive = false
        }
    }

    private func updateLiveStreamState(with state: PlaybackState) {
        let duration = state.duration
        let current = max(state.currentTime, elapsedTime)
        let hasKnownDuration = duration.isFinite && duration > 0
        let isPlaying = state.isPlaying

        if hasKnownDuration {
            liveStreamUnknownDurationCount = 0

            let remaining = duration - current
            let clampedDuration = max(duration, 0)
            let clampedCurrent = clampedDuration > 0
                ? max(0, min(current, clampedDuration))
                : max(0, current)
            let progress = clampedDuration > 0 ? clampedCurrent / clampedDuration : 0
            let sliderAppearsComplete = isPlaying && clampedDuration > 0 && progress >= 0.999
            let nearDurationEdge = isPlaying && remaining.isFinite && remaining <= 1.0 && clampedCurrent >= 10

            if sliderAppearsComplete {
                liveStreamCompletionObservationCount = min(liveStreamCompletionObservationCount + 1, 8)
                liveStreamCompletionReleaseCount = 0
            } else {
                liveStreamCompletionReleaseCount = min(liveStreamCompletionReleaseCount + 1, 8)
                if liveStreamCompletionObservationCount > 0 {
                    liveStreamCompletionObservationCount = max(liveStreamCompletionObservationCount - 1, 0)
                }
            }

            if nearDurationEdge || sliderAppearsComplete {
                liveStreamEdgeObservationCount = min(liveStreamEdgeObservationCount + 1, 12)
            } else if liveStreamEdgeObservationCount > 0 {
                liveStreamEdgeObservationCount = max(liveStreamEdgeObservationCount - 1, 0)
            }

            if !isLiveStream {
                if liveStreamCompletionObservationCount >= 3 || liveStreamEdgeObservationCount >= 5 {
                    isLiveStream = true
                }
            } else {
                let shouldClearForKnownDuration =
                    (duration > 10 && remaining > 5)
                    || (liveStreamCompletionObservationCount == 0
                        && liveStreamEdgeObservationCount == 0
                        && liveStreamCompletionReleaseCount >= 4)

                if shouldClearForKnownDuration {
                    isLiveStream = false
                }
            }
        } else if isPlaying {
            liveStreamEdgeObservationCount = max(liveStreamEdgeObservationCount - 1, 0)
            liveStreamCompletionObservationCount = max(liveStreamCompletionObservationCount - 1, 0)
            liveStreamCompletionReleaseCount = 0

            liveStreamUnknownDurationCount = min(liveStreamUnknownDurationCount + 1, 8)
            if liveStreamUnknownDurationCount >= 3 && !isLiveStream {
                isLiveStream = true
            }
        } else {
            liveStreamUnknownDurationCount = 0
            liveStreamEdgeObservationCount = 0
            liveStreamCompletionObservationCount = 0
            liveStreamCompletionReleaseCount = 0
        }
    }

    private func updateArtwork(_ artworkData: Data, bundleIdentifier: String?) {
        let isMusicApp = NowPlayingArtwork.isMusicApp(bundleIdentifier)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let decoded = NSImage(data: artworkData) {
                // Browsers pass on whatever the site offers, often just its logo
                // (Facebook's "f"): show the music-note cover instead.
                let artworkImage = !isMusicApp && NowPlayingArtwork.looksLikeLogo(decoded)
                    ? NowPlayingArtwork.placeholder
                    : decoded
                DispatchQueue.main.async { [weak self] in
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage, isAppIcon: Bool = false, delay: TimeInterval = 0.4) {
        workItem?.cancel()
        // The first cover after launch shows right away, without the delay.
        let isFirstCover = albumArt === defaultImage && !isAppIcon
        workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.usingAppIconForArtwork = isAppIcon
            withAnimation(isFirstCover ? nil : .smooth) {
                self.albumArt = newAlbumArt
                if Defaults[.coloredSpectrogram] {
                    self.calculateAverageColor()
                }
            }
        }
        if isFirstCover {
            workItem?.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem!)
        }
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.prominentOpposingColors { [weak self] primary, secondary in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = primary
                    self?.secondaryColor = secondary
                }
            }
        }
    }

    private func updateSneakPeek() {

        if isPlaying && Defaults[.enableSneakPeek] {
            if Defaults[.sneakPeekStyles] == .standard {
                coordinator.toggleSneakPeek(status: true, type: .music)
            } else {
                coordinator.toggleExpandingView(status: true, type: .music)
            }
        }
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        guard let controller = activeController else { return }
        let targetState = !isPlaying

        Task {
            await MainActor.run {
                pendingOptimisticPlayState = targetState
                applyPlayState(targetState, animation: .smooth(duration: 0.18))
            }

            if targetState {
                await controller.play()
            } else {
                await controller.pause()
            }
        }
    }

    func nextTrack() {
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        Task {
            await activeController?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        // Move our own position right away: some players (like Spotify through Now
        // Playing) don't report a seek until play/pause, so lyrics kept going from
        // the old spot. Then ask the player for its exact position.
        let target = songDuration > 0 ? min(max(0, position), songDuration) : max(0, position)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.elapsedTime = target
            self.timestampDate = Date()
            await self.activeController?.seek(to: target)
            try? await Task.sleep(for: .milliseconds(400))
            self.forceUpdate()
        }
    }

    func seek(by offset: TimeInterval) {
        guard !isLiveStream else { return }
        let duration = songDuration
        guard duration > 0 else { return }

        let current = estimatedPlaybackPosition()
        let magnitude = abs(offset)

        if offset < 0, current <= magnitude {
            previousTrack()
            return
        }

        if offset > 0, (duration - current) <= magnitude {
            nextTrack()
            return
        }

        let target = min(max(0, current + offset), duration)
        seek(to: target)
    }

    @MainActor
    func handleSkipGesture(direction: SkipDirection) {
        guard Defaults[.enableHorizontalMusicGestures] else { return }
        guard !isPlayerIdle || bundleIdentifier != nil else { return }

        let behavior = Defaults[.musicGestureBehavior]

        switch behavior {
        case .track:
            if direction == .forward {
                lastFlipDirection = .forward
                nextTrack()
            } else {
                lastFlipDirection = .backward
                previousTrack()
            }
        case .tenSecond:
            let interval = Self.skipGestureSeekInterval
            let offset = direction == .forward ? interval : -interval
            seek(by: offset)
        }

        skipGestureToken = skipGestureToken &+ 1
        skipGesturePulse = SkipGesturePulse(
            token: skipGestureToken,
            direction: direction,
            behavior: behavior
        )
    }

    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                if let youtubeController = self?.activeController as? YouTubeMusicController {
                    await youtubeController.pollPlaybackState()
                } else {
                    await self?.activeController?.updatePlaybackInfo()
                }
            }
        }
    }

}

// MARK: - Media Branding

extension MusicManager {
    var brandAccentColor: Color {
        Self.brandAccentColor(for: Defaults[.mediaController], bundleIdentifier: bundleIdentifier)
    }

    private static func brandAccentColor(for controller: MediaControllerType, bundleIdentifier: String?) -> Color {
        switch controller {
        case .appleMusic:
            return appleMusicPink
        case .spotify:
            return spotifyGreen
        case .amazonMusic:
            return amazonOrange
        case .cider:
            return .accentColor
        case .nowPlaying:
            if let bundleIdentifier,
               let bundleColor = brandAccentColor(forBundleIdentifier: bundleIdentifier) {
                return bundleColor
            }
            fallthrough
        case .youtubeMusic:
            return .accentColor
        }
    }

    private static func brandAccentColor(forBundleIdentifier bundleIdentifier: String) -> Color? {
        switch bundleIdentifier {
        case "com.apple.Music":
            return appleMusicPink
        case "com.spotify.client":
            return spotifyGreen
        case AmazonMusicController.bundleIdentifier:
            return amazonOrange
        case CiderController.bundleIdentifier:
            return .accentColor
        default:
            return nil
        }
    }

    private static let appleMusicPink = Color(red: 0.999, green: 0.171, blue: 0.331)
    private static let spotifyGreen = Color(red: 0.0, green: 0.857, blue: 0.302)
    private static let amazonOrange = Color(red: 1.0, green: 0.6, blue: 0.0)
}

// MARK: - Album Art Flip Helper

/// The cover turning over on a track change. A flat flip: the cover narrows to
/// an edge and widens again (with a little blur at the edge), which reads as a
/// page turn at this size. It used to be a real 3D rotation, but a 3D layer
/// inside the notch made macOS drop the notch's rounded clip for the moment of
/// the flip, showing the notch as a square-cornered black rectangle.
private struct AlbumArtFlipModifier: ViewModifier, Animatable {
    var angle: Double
    /// Blur at the middle of the flip (edge-on); none when the cover faces front.
    private let maxBlur: CGFloat = 6

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let radians = angle * .pi / 180
        content
            .blur(radius: abs(sin(radians)) * maxBlur)
            // Width follows the cosine of the turn; never mirrored.
            .scaleEffect(x: max(0.001, abs(cos(radians))), y: 1, anchor: .center)
    }
}

extension View {
    func albumArtFlip(angle: Double) -> some View {
        modifier(AlbumArtFlipModifier(angle: angle))
    }
}
