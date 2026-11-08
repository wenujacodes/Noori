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

import Combine
import Foundation
import SwiftUI

class SpotifyController: MediaControllerProtocol {
    static let bundleIdentifier = "com.spotify.client"

    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: SpotifyController.bundleIdentifier
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var isWorking: Bool {
        true
    }

    private var notificationTask: Task<Void, Never>?

    // Constant for time between command and update
    private let commandUpdateDelay: Duration = .milliseconds(25)

    private var lastArtworkURL: String?
    private var artworkFetchTask: Task<Void, Never>?
    private let trackMetadataResolver = SpotifyTrackMetadataResolver()
    private var artistMetadataFetchTask: Task<Void, Never>?
    private var currentArtistTrackURI: String?

    init() {
        setupPlaybackStateChangeObserver()
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }

    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.spotify.client.PlaybackStateChanged")
            )

            for await _ in notifications {
                await self?.updatePlaybackInfo()
            }
        }
    }

    deinit {
        notificationTask?.cancel()
        artworkFetchTask?.cancel()
        artistMetadataFetchTask?.cancel()
    }

    // MARK: - Protocol Implementation
    func play() async { await executeCommand("play") }
    func pause() async { await executeCommand("pause") }
    func togglePlay() async { await executeCommand("playpause") }
    func nextTrack() async { await executeCommand("next track") }

    func previousTrack() async {
        await executeAndRefresh("previous track")
    }

    func seek(to time: Double) async {
        await executeAndRefresh("set player position to \(time)")
    }

    func toggleShuffle() async {
        await executeAndRefresh("set shuffling to not shuffling")
    }

    func toggleRepeat() async {
        await executeAndRefresh("set repeating to not repeating")
    }

    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == playbackState.bundleIdentifier }
    }

    func updatePlaybackInfo() async {
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard descriptor.numberOfItems >= 11 else { return }

        let isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        let currentTrack = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        let currentTrackArtist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        let currentTrackAlbum = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        let currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        let duration = (descriptor.atIndex(6)?.doubleValue ?? 0) / 1000
        let isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let isRepeating = descriptor.atIndex(8)?.booleanValue ?? false
        let artworkURL = descriptor.atIndex(9)?.stringValue ?? ""
        let trackIdentifier = descriptor.atIndex(10)?.stringValue ?? ""
        let spotifyURLString = descriptor.atIndex(11)?.stringValue ?? ""
        let trackURI = Self.canonicalTrackURI(from: trackIdentifier, spotifyURLString: spotifyURLString)
        let cachedArtistResult = await trackMetadataResolver.cachedArtistResult(for: trackURI)
        let displayArtist = cachedArtistResult?.displayName ?? currentTrackArtist

        var state = PlaybackState(
            bundleIdentifier: Self.bundleIdentifier,
            isPlaying: isPlaying,
            title: currentTrack,
            artist: displayArtist,
            album: currentTrackAlbum,
            currentTime: currentTime,
            duration: duration,
            playbackRate: 1,
            isShuffled: isShuffled,
            repeatMode: isRepeating ? .all : .off,
            lastUpdated: Date()
        )
        state.contentIdentifier = trackIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : trackIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        state.contentURL = spotifyURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : spotifyURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        if artworkURL == lastArtworkURL, let existingArtwork = self.playbackState.artwork {
            state.artwork = existingArtwork
        }

        let isSameArtistTrack = trackURI == currentArtistTrackURI

        if !isSameArtistTrack {
            currentArtistTrackURI = trackURI.isEmpty ? nil : trackURI
            artistMetadataFetchTask?.cancel()
            artistMetadataFetchTask = nil
        }

        playbackState = state

        if !trackURI.isEmpty {
            if cachedArtistResult == nil {
                scheduleArtistMetadataFetchIfNeeded(for: trackURI)
            }
        }

        if !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            guard artworkURL != lastArtworkURL || state.artwork == nil else { return }
            artworkFetchTask?.cancel()

            let currentState = state
            let expectedTrackURI = trackURI

            artworkFetchTask = Task {
                do {
                    let data = try await ImageService.shared.fetchImageData(from: url)

                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        guard expectedTrackURI.isEmpty || self.currentArtistTrackURI == expectedTrackURI else {
                            self.artworkFetchTask = nil
                            return
                        }
                        var updatedState = currentState
                        updatedState.artwork = data
                        updatedState.artist = self.playbackState.artist
                        self.playbackState = updatedState
                        self.lastArtworkURL = artworkURL
                        self.artworkFetchTask = nil
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.artworkFetchTask = nil
                    }
                }
            }
        }
    }

    private func scheduleArtistMetadataFetchIfNeeded(for trackURI: String) {
        guard !trackURI.isEmpty else { return }
        guard artistMetadataFetchTask == nil else { return }

        artistMetadataFetchTask = Task { [weak self] in
            guard let self else { return }

            let displayName = await self.trackMetadataResolver.artistDisplayName(for: trackURI)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.currentArtistTrackURI == trackURI else {
                    self.artistMetadataFetchTask = nil
                    return
                }

                if let displayName, self.playbackState.artist != displayName {
                    var updatedState = self.playbackState
                    updatedState.artist = displayName
                    self.playbackState = updatedState
                }

                self.artistMetadataFetchTask = nil
            }
        }
    }

    private func executeCommand(_ command: String) async {
        let script = "tell application \"Spotify\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }

    private func executeAndRefresh(_ command: String) async {
        await executeCommand(command)
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }

    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "Spotify"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set shuffleState to shuffling
                set repeatState to repeating
                set artworkURL to artwork url of current track
                set trackID to id of current track
                set spotifyURL to spotify url of current track
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatState, artworkURL, trackID, spotifyURL}
            on error
                return {false, "Unknown", "Unknown", "Unknown", 0, 0, false, false, "", "", ""}
            end try
        end tell
        """

        return try await AppleScriptHelper.execute(script)
    }

    private static func canonicalTrackURI(from trackIdentifier: String, spotifyURLString: String) -> String {
        let trimmedIdentifier = trackIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedIdentifier.hasPrefix("spotify:track:") {
            return trimmedIdentifier
        }

        if isLikelySpotifyTrackID(trimmedIdentifier) {
            return "spotify:track:\(trimmedIdentifier)"
        }

        if let trackID = extractTrackID(from: spotifyURLString) {
            return "spotify:track:\(trackID)"
        }

        return ""
    }

    private static func extractTrackID(from spotifyURLString: String) -> String? {
        guard let url = URL(string: spotifyURLString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        let pathComponents = components.path.split(separator: "/")
        guard let trackIndex = pathComponents.firstIndex(of: "track"),
              trackIndex + 1 < pathComponents.count
        else { return nil }

        let identifier = String(pathComponents[trackIndex + 1])
        return isLikelySpotifyTrackID(identifier) ? identifier : nil
    }

    private static func isLikelySpotifyTrackID(_ value: String) -> Bool {
        value.count == 22 && value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
    }
}

private actor SpotifyTrackMetadataResolver {
    private struct CacheEntry {
        let displayName: String?
        let expiresAt: Date
    }

    private var cache: [String: CacheEntry] = [:]

    func cachedArtistResult(for trackURI: String) -> SpotifyArtistCacheResult? {
        guard !trackURI.isEmpty,
              let entry = cache[trackURI],
              entry.expiresAt > Date()
        else {
            return nil
        }

        return SpotifyArtistCacheResult(displayName: entry.displayName)
    }

    func artistDisplayName(for trackURI: String) async -> String? {
        if let cached = cachedArtistResult(for: trackURI) {
            return cached.displayName
        }

        let displayName = await fetchArtistDisplayName(for: trackURI)
        let cacheLifetime: TimeInterval = displayName == nil ? 300 : 3600
        cache[trackURI] = CacheEntry(displayName: displayName, expiresAt: Date().addingTimeInterval(cacheLifetime))
        return displayName
    }

    /// All artist names for the track, from Spotify's public embed page.
    private func fetchArtistDisplayName(for trackURI: String) async -> String? {
        guard let trackID = Self.trackID(from: trackURI) else {
            return nil
        }
        return await fetchPublicEmbedArtistDisplayName(for: trackID)
    }

    private func fetchPublicEmbedArtistDisplayName(for trackID: String) async -> String? {
        guard let url = URL(string: "https://open.spotify.com/embed/track/\(trackID)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8)
            else {
                return nil
            }

            return Self.artistDisplayNameFromEmbedHTML(html)
        } catch {
            return nil
        }
    }

    static func artistDisplayNameFromEmbedHTML(_ html: String) -> String? {
        guard let scriptStart = html.range(of: #"<script id="__NEXT_DATA__""#),
              let openingTagEnd = html[scriptStart.upperBound...].range(of: ">"),
              let scriptEnd = html[openingTagEnd.upperBound...].range(of: "</script>")
        else {
            return nil
        }

        let jsonString = String(html[openingTagEnd.upperBound..<scriptEnd.lowerBound])
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = root["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let state = pageProps["state"] as? [String: Any],
              let stateData = state["data"] as? [String: Any],
              let entity = stateData["entity"] as? [String: Any],
              let artists = entity["artists"] as? [[String: Any]]
        else {
            return nil
        }

        let artistNames = artists
            .compactMap { $0["name"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !artistNames.isEmpty else {
            return nil
        }

        return artistNames.joined(separator: ", ")
    }

    private static func trackID(from trackURI: String) -> String? {
        let components = trackURI.split(separator: ":")
        guard components.count == 3,
              components[0] == "spotify",
              components[1] == "track"
        else {
            return nil
        }

        let identifier = String(components[2])
        return identifier.isEmpty ? nil : identifier
    }
}

private struct SpotifyArtistCacheResult: Sendable {
    let displayName: String?
}
