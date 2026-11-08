/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 * Based on Atoll, Copyright (C) 2024-2026 Atoll Contributors
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

#if canImport(AppKit)
import AppKit
#endif

struct MinimalisticMusicPlayerView: View {
    @EnvironmentObject var vm: NooriViewModel
    let albumArtNamespace: Namespace.ID
    @Default(.showShuffleAndRepeat) private var showCustomControls
    @Default(.musicControlSlots) private var slotConfig
    @Default(.showMediaOutputControl) private var showMediaOutputControl
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @ObservedObject private var coordinator = NooriViewCoordinator.shared
    @State private var hudValue: Double = 0
    @State private var hudDragging: Bool = false
    @State private var hudLastDragged: Date = .distantPast
    private let seekInterval: TimeInterval = 10
    private let skipMagnitude: CGFloat = 8

    var body: some View {
        if !musicManager.hasActiveSession {
            // Nothing playing state
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    Image(systemName: "music.note.slash")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(.gray)
                    Text("Nothing Playing")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }

                Spacer(minLength: 0)

            }
            .padding(.horizontal, shouldUseNooriMode(for: vm.screen) ? -4 : 12)
            .padding(.vertical, shouldUseNooriMode(for: vm.screen) ? 14 : 0)
            .frame(maxWidth: .infinity)
            .frame(height: calculateDynamicHeight())
            .fadesWithNotchContent()
        } else {
            VStack(spacing: 0) {
                if shouldUseNooriMode(for: vm.screen) {
                    // ── Battery ON / DI mode: original flat layout (unchanged) ──
                    GeometryReader { headerGeo in
                        let albumArtWidth: CGFloat = 50
                        let spacing: CGFloat = 10
                        // The right-side time label in the progress bar below is 42pt wide,
                        // trailing-aligned, so its center sits 21pt from the right edge.
                        // We use the same 42pt block for the visualizer so the candles
                        // are perfectly centred above the "-00:00" text.
                        let vizBlockWidth: CGFloat = useMusicVisualizer ? 42 : 0
                        let visualizerBarWidth: CGFloat = useMusicVisualizer ? 24 : 0
                        // Leave an extra 8pt gap between the title text and the visualizer.
                        let textWidth = max(0, headerGeo.size.width - albumArtWidth - spacing - (useMusicVisualizer ? (vizBlockWidth + spacing) : 0))
                        HStack(alignment: .center, spacing: spacing) {
                            MinimalisticAlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                                .frame(width: albumArtWidth, height: albumArtWidth)

                            VStack(alignment: .leading, spacing: 1) {
                                if !musicManager.songTitle.isEmpty {
                                    MusicTitleMarqueeView(
                                        text: musicManager.songTitle,
                                        isExplicit: musicManager.isCurrentTrackExplicit,
                                        font: .system(size: 12, weight: .semibold),
                                        nsFont: .subheadline,
                                        textColor: .white,
                                        frameWidth: textWidth,
                                        badgeHeight: 13
                                    )
                                }

                                artistLine(width: textWidth)

                            }
                            .frame(width: textWidth, alignment: .leading)
                            .fadesWithNotchContent()

                            if useMusicVisualizer {
                                // 48-pt block matches the trailing time-label width so the
                                // candle centre lines up with the centre of "-00:00".
                                ZStack {
                                    visualizer
                                        .frame(width: visualizerBarWidth)
                                }
                                .frame(width: vizBlockWidth)
                            }
                        }
                    }
                    .frame(height: 50)
                } else {
                    // ── Battery OFF (notch mode): U-shaped notch-hugging layout ──
                    notchHuggingHeader
                }

                // Compact progress bar
                progressBar
                    .padding(.top, batteryOffNotchMode ? 4 : 6)
                    .fadesWithNotchContent()
                
                // Compact playback controls
                if shouldShowControlHUDRow {
                    controlHUDRow
                        .padding(.top, 4)
                        .fadesWithNotchContent()
                } else {
                    playbackControls
                        .padding(.top, 4)
                        .fadesWithNotchContent()
                }

            }
            .padding(.horizontal, shouldUseNooriMode(for: vm.screen) ? -4 : 12)
            .padding(.top, shouldUseNooriMode(for: vm.screen) ? 14 : (batteryOffNotchMode ? 10 : 6))
            .padding(.bottom, shouldUseNooriMode(for: vm.screen) ? 14 : (batteryOffNotchMode ? 10 : minimalisticBaselineBottomPadding))
            .frame(maxWidth: .infinity)
            .frame(height: calculateDynamicHeight(), alignment: .top)
        }
    }






    private var brandAccentColor: Color {
        musicManager.brandAccentColor
    }




    /// True when the battery indicator is hidden and we are in notch mode (not DI).
    private var batteryOffNotchMode: Bool {
        !shouldUseNooriMode(for: vm.screen)
    }

    private func calculateDynamicHeight() -> CGFloat {
        let isNoori = shouldUseNooriMode(for: vm.screen)

        if !batteryOffNotchMode {
            // ── Battery ON / DI: use the exact original height formula ──
            var height: CGFloat = 50 // header
            height += 6 + 4          // progress bar top padding + bar
            height += 54 + 2         // controls + top padding

            height += isNoori ? 14 : 15 // top padding
            height += isNoori ? 14 : minimalisticBaselineBottomPadding
            return height
        }

        // ── Battery OFF (notch mode): tighter height for U-shaped layout ──
        // The album art is pulled UP into the notch header area, so the
        // visible header in-flow is only the title + artist text (~26pt).
        var height: CGFloat = 26 // reduced header (text only; art overlaps upward)
        height += 4 + 4          // progress bar top padding + bar
        height += 54 + 2         // controls + top padding

        height += 10 // top padding
        height += 10 // bottom padding
        return height
    }

    /// The artist name; scrolls on its own when it's too long to fit, like the title.
    private func artistLine(width: CGFloat) -> some View {
        MusicTitleMarqueeView(
            text: musicManager.artistName,
            isExplicit: false,
            font: .system(size: 11, weight: .medium),
            nsFont: .subheadline,
            textColor: Defaults[.playerColorTinting]
                ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                : .gray,
            frameWidth: width
        )
    }

    // MARK: - U-Shaped Notch-Hugging Header

    /// Layout that wraps content around the physical notch cutout.
    /// Album art sits to the left of the notch, the visualizer to the right,
    /// and the song title + artist are centered below the notch — producing a
    /// "U" shape.
    private var notchHuggingHeader: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let albumArtSize: CGFloat = 50
            let visualizerWidth: CGFloat = useMusicVisualizer ? 24 : 0
            // How far to pull the album art and waveform up alongside the notch.
            let notchHeight = vm.effectiveClosedNotchHeight
            let pullUp = max(notchHeight - 4, 20)
            
            ZStack(alignment: .top) {
                // ── Left: Album art ──
                HStack {
                    MinimalisticAlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                        .frame(width: albumArtSize, height: albumArtSize)
                    Spacer()
                }
                .offset(y: -pullUp)
                .frame(width: totalWidth)

                // ── Right: Waveform ──
                if useMusicVisualizer {
                    HStack {
                        Spacer()
                        visualizer
                            .frame(width: visualizerWidth)
                        Spacer()
                            .frame(width: 12)
                    }
                    .offset(y: -pullUp + (albumArtSize - 16) / 2)
                    .frame(width: totalWidth)
                }

                // ── Center: Title + Artist (below the notch) ──
                // The visualizer sits beside the text and has a 12-pt right spacer;
                // title and artist both stop before it.
                let textAreaWidth = max(0, totalWidth - albumArtSize - 10 - (useMusicVisualizer ? (visualizerWidth + 12 + 10) : 0))
                VStack(alignment: .leading, spacing: 1) {
                    if !musicManager.songTitle.isEmpty {
                        MusicTitleMarqueeView(
                            text: musicManager.songTitle,
                            isExplicit: musicManager.isCurrentTrackExplicit,
                            font: .system(size: 12, weight: .semibold),
                            nsFont: .subheadline,
                            textColor: .white,
                            frameWidth: textAreaWidth,
                            badgeHeight: 13
                        )
                    }

                    artistLine(width: textAreaWidth)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fadesWithNotchContent()
                .padding(.leading, albumArtSize + 10)
                // Position so the bottom of the artist text aligns with the
                // bottom of the album art (which was pulled up by pullUp).
                .offset(y: albumArtSize - pullUp - 28)
            }
        }
        .frame(height: 26) // Only the text portion is in-flow; album art overlaps upward
    }


    private func displayFont(size: CGFloat) -> Font {
        .custom("SF Pro Display", size: size)
    }



    



    // MARK: - Visualizer
    
    @Default(.useMusicVisualizer) var useMusicVisualizer
    
    private var visualizer: some View {
        let width = CGFloat(Defaults[.visualizerBarCount]) * 4
        return Rectangle()
            .fill((Defaults[.coloredSpectrogram] ? Color(nsColor: MusicManager.shared.avgColor) : Color.gray).spectrogramGradient())
            .mask {
                AudioVisualizerView(isPlaying: .constant(MusicManager.shared.isPlaying))
                    .frame(width: width, height: 16)
            }
            .frame(width: width, height: 16)
            // Glides from the closed notch's visualizer, like the album art.
            .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
    }
    
    // MARK: - Progress Bar (Full Width)
    
    @ObservedObject var musicManager = MusicManager.shared
    @State private var sliderValue: Double = MusicManager.shared.estimatedPlaybackPosition()
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    
    /// Whether the progress timeline should be paused (no ticks).
    private var isProgressTimelinePaused: Bool {
        !musicManager.isPlaying || musicManager.isLiveStream || musicManager.playbackRate <= 0
    }

    private var progressBar: some View {
        // 4 updates a second is visually smooth for a song progress bar;
        // `.animation` redrew it every display frame (up to 120 times a second).
        TimelineView(
            ProgressTimelineSchedule(interval: 0.25, paused: isProgressTimelinePaused)
        ) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: Binding(
                    get: { musicManager.songDuration },
                    set: { musicManager.songDuration = $0 }
                ),
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                isLiveStream: musicManager.isLiveStream,
                onValueChange: { newValue in
                    musicManager.seek(to: newValue)
                },
                labelLayout: .inline,
                trailingLabel: .remaining,
                restingTrackHeight: 7,
                draggingTrackHeight: 11
            )
        }
        .onAppear {
            sliderValue = musicManager.elapsedTime
        }
        .onChange(of: musicManager.isLiveStream) { _, isLive in
            if isLive {
                dragging = false
                sliderValue = 0
            }
        }
    }

    // MARK: - Playback Controls (Larger)
    
    private var playbackControls: some View {
        HStack(spacing: 10) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    private var shouldShowControlHUDRow: Bool {
        guard vm.notchState == .open else { return false }
        guard coordinator.sneakPeek.show else { return false }
        guard Defaults[.enableSystemHUD] else { return false }

        switch coordinator.sneakPeek.type {
        case .volume:
            return Defaults[.enableVolumeHUD]
        case .brightness:
            return Defaults[.enableBrightnessHUD]
        case .backlight:
            return Defaults[.enableKeyboardBacklightHUD]
        default:
            return false
        }
    }

    private var controlHUDRow: some View {
        HStack(alignment: .center, spacing: 10) {
            if !controlLeftIconName.isEmpty {
                Image(systemName: controlLeftIconName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22, height: 22, alignment: .center)
            }

            controlHUDSlider

            if !controlRightIconName.isEmpty {
                Image(systemName: controlRightIconName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22, height: 22, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: 60, alignment: .center)
        .onAppear { syncHUDValueIfNeeded(force: true) }
        .onChange(of: coordinator.sneakPeek.value) { _, _ in
            syncHUDValueIfNeeded(force: false)
        }
    }

    private var controlHUDSlider: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            CustomSlider(
                value: Binding(
                    get: { hudValue },
                    set: { newValue in
                        hudValue = newValue
                        updateControlHUDValue(newValue)
                    }
                ),
                range: 0...1,
                color: .white,
                dragging: $hudDragging,
                lastDragged: $hudLastDragged,
                onValueChange: { newValue in
                    updateControlHUDValue(newValue)
                },
                thumbSize: 10,
                restingTrackHeight: 4,
                draggingTrackHeight: 7
            )
            .frame(height: 7)
            Spacer(minLength: 0)
        }
        .frame(height: 22)
    }

    private func syncHUDValueIfNeeded(force: Bool) {
        guard shouldShowControlHUDRow else { return }
        guard force || !hudDragging else { return }
        hudValue = Double(coordinator.sneakPeek.value)
    }

    private func updateControlHUDValue(_ newValue: Double) {
        let clamped = max(0, min(1, newValue))
        switch coordinator.sneakPeek.type {
        case .volume:
            SystemVolumeController.shared.setVolume(Float(clamped))
        case .brightness:
            SystemBrightnessController.shared.setBrightness(Float(clamped))
        case .backlight:
            SystemKeyboardBacklightController.shared.setLevel(Float(clamped))
        default:
            break
        }
    }

    private var controlLeftIconName: String {
        switch coordinator.sneakPeek.type {
        case .volume:
            return SystemVolumeController.shared.isMuted ? "speaker.slash" : "speaker.wave.1"
        case .brightness:
            return "sun.min.fill"
        case .backlight:
            return "light.min"
        default:
            return ""
        }
    }

    private var controlRightIconName: String {
        switch coordinator.sneakPeek.type {
        case .volume:
            return SystemVolumeController.shared.isMuted ? "" : "speaker.wave.3"
        case .brightness:
            return "sun.max.fill"
        case .backlight:
            return "light.max"
        default:
            return ""
        }
    }
    
    private var playPauseButton: some View {
        MinimalisticSquircircleButton(
            icon: musicManager.isPlaying ? (musicManager.isLiveStream ? "stop.fill" : "pause.fill") : "play.fill",
            fontSize: 26,
            fontWeight: .semibold,
            frameSize: CGSize(width: 54, height: 54),
            cornerRadius: 22,
            foregroundColor: .white,
            pressEffect: .none,
            symbolEffectStyle: .replace,
            action: {
                musicManager.togglePlay()
            }
        )
    }
    
    private struct SkipTrigger {
        let token: Int
        let pressEffect: MinimalisticSquircircleButton.PressEffect
    }

    private func controlButton(
        icon: String,
        size: CGFloat = 18,
        isActive: Bool = false,
        activeColor: Color? = nil,
        pressEffect: MinimalisticSquircircleButton.PressEffect = .none,
        symbolEffect: MinimalisticSquircircleButton.SymbolEffectStyle = .none,
        trigger: SkipTrigger? = nil,
        isSecondary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let resolvedActiveColor = activeColor ?? brandAccentColor
        // Extra buttons (shuffle, repeat, …) are grey so the main three stand out.
        let restingColor: Color = isSecondary ? .gray : .white.opacity(0.85)
        return MinimalisticSquircircleButton(
            icon: icon,
            fontSize: size,
            fontWeight: .medium,
            frameSize: CGSize(width: 36, height: 36),
            cornerRadius: 14,
            foregroundColor: isActive ? resolvedActiveColor : restingColor,
            pressEffect: pressEffect,
            symbolEffectStyle: symbolEffect,
            externalTriggerToken: trigger?.token,
            externalTriggerEffect: trigger?.pressEffect,
            action: action
        )
    }

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    private var displayedSlots: [MusicControlButton] {
        if showCustomControls {
            let normalized = slotConfig.normalized(allowingMediaOutput: showMediaOutputControl, isAppleMusicActive: isAppleMusicActive)
            return normalized.contains(where: { $0 != .none }) ? normalized : MusicControlButton.defaultLayout
        }

        switch musicSkipBehavior {
        case .track:
            return MusicControlButton.minimalLayout
        case .tenSecond:
            return [.none, .seekBackward, .playPause, .seekForward, .none]
        }
    }

    @ViewBuilder
    private func slotView(for control: MusicControlButton) -> some View {
        switch control {
        case .none:
            Spacer(minLength: 0)
        case .playPause:
            playPauseButton
        case .trackBackward:
            controlButton(
                icon: "backward.fill",
                size: 18,
                pressEffect: .nudge(-skipMagnitude),
                symbolEffect: .replace,
                trigger: skipGestureTrigger(for: .trackBackward),
                action: { musicManager.previousTrack() }
            )
        case .trackForward:
            controlButton(
                icon: "forward.fill",
                size: 18,
                pressEffect: .nudge(skipMagnitude),
                symbolEffect: .replace,
                trigger: skipGestureTrigger(for: .trackForward),
                action: { musicManager.nextTrack() }
            )
        case .seekBackward:
            controlButton(
                icon: "gobackward.10",
                size: 18,
                pressEffect: .wiggle(.counterClockwise),
                symbolEffect: .wiggle,
                trigger: skipGestureTrigger(for: .seekBackward),
                action: { musicManager.seek(by: -seekInterval) }
            )
        case .seekForward:
            controlButton(
                icon: "goforward.10",
                size: 18,
                pressEffect: .wiggle(.clockwise),
                symbolEffect: .wiggle,
                trigger: skipGestureTrigger(for: .seekForward),
                action: { musicManager.seek(by: seekInterval) }
            )
        case .shuffle:
            controlButton(icon: "shuffle", isActive: musicManager.isShuffled, isSecondary: true) {
                musicManager.toggleShuffle()
            }
        case .repeatMode:
            controlButton(icon: repeatIcon, isActive: musicManager.repeatMode != .off, symbolEffect: .replace, isSecondary: true) {
                musicManager.toggleRepeat()
            }
        case .mediaOutput:
            MinimalisticMediaOutputButton()
        case .airPlay:
            MinimalisticAirPlayButton()
        case .lyrics:
            // Placeholder: the lyrics feature was removed; the button is kept for a future version.
            controlButton(icon: "quote.bubble", isActive: false, isSecondary: true) {}
        }
    }

    private func skipGestureTrigger(for control: MusicControlButton) -> SkipTrigger? {
        guard let pulse = musicManager.skipGesturePulse else { return nil }

        switch control {
        case .trackBackward where pulse.behavior == .track && pulse.direction == .backward:
            return SkipTrigger(token: pulse.token, pressEffect: .nudge(-skipMagnitude))
        case .trackForward where pulse.behavior == .track && pulse.direction == .forward:
            return SkipTrigger(token: pulse.token, pressEffect: .nudge(skipMagnitude))
        case .seekBackward where pulse.behavior == .tenSecond && pulse.direction == .backward:
            return SkipTrigger(token: pulse.token, pressEffect: .wiggle(.counterClockwise))
        case .seekForward where pulse.behavior == .tenSecond && pulse.direction == .forward:
            return SkipTrigger(token: pulse.token, pressEffect: .wiggle(.clockwise))
        default:
            return nil
        }
    }
    private struct MinimalisticMediaOutputButton: View {
        @ObservedObject private var routeManager = AudioRouteManager.shared
        @StateObject private var volumeModel = MediaOutputVolumeViewModel()
        @EnvironmentObject private var vm: NooriViewModel
        @State private var isPopoverPresented = false
        @State private var isHoveringPopover = false

        var body: some View {
            MinimalisticSquircircleButton(
                icon: routeManager.activeDevice?.iconName ?? "speaker.wave.2",
                fontSize: 18,
                fontWeight: .medium,
                frameSize: CGSize(width: 36, height: 36),
                cornerRadius: 14,
                foregroundColor: .gray,
                symbolEffectStyle: .replace
            ) {
                isPopoverPresented.toggle()
                if isPopoverPresented {
                    routeManager.refreshDevices()
                }
            }
            .accessibilityLabel("Media output")
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                MediaOutputSelectorPopover(
                    routeManager: routeManager,
                    volumeModel: volumeModel,
                    onHoverChanged: { hovering in
                        isHoveringPopover = hovering
                        updateActivity()
                    }
                ) {
                    isPopoverPresented = false
                    isHoveringPopover = false
                    updateActivity()
                }
            }
            .onChange(of: isPopoverPresented) { _, presented in
                if !presented {
                    isHoveringPopover = false
                }
                updateActivity()
            }
            .onAppear {
                routeManager.refreshDevices()
            }
            .onDisappear {
                vm.isMediaOutputPopoverActive = false
            }
        }

        private func updateActivity() {
            vm.isMediaOutputPopoverActive = isPopoverPresented && isHoveringPopover
        }
    }

    private struct MinimalisticAirPlayButton: View {
        @ObservedObject private var musicManager = MusicManager.shared
        @ObservedObject private var airPlayManager = AppleMusicAirPlayManager.shared
        @EnvironmentObject private var vm: NooriViewModel
        @State private var isPopoverPresented = false
        @State private var isHoveringPopover = false

        private var isAppleMusicActive: Bool {
            musicManager.bundleIdentifier == "com.apple.Music"
        }

        var body: some View {
            MinimalisticSquircircleButton(
                icon: "airplayaudio",
                fontSize: 18,
                fontWeight: .medium,
                frameSize: CGSize(width: 36, height: 36),
                cornerRadius: 14,
                foregroundColor: .gray,
                symbolEffectStyle: .replace
            ) {
                isPopoverPresented.toggle()
                if isPopoverPresented {
                    Task { await airPlayManager.refreshDevices() }
                }
            }
            .accessibilityLabel("AirPlay")
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                AirPlaySelectorPopover(
                    airPlayManager: airPlayManager,
                    onHoverChanged: { hovering in
                        isHoveringPopover = hovering
                        updateActivity()
                    }
                ) {
                    isPopoverPresented = false
                    isHoveringPopover = false
                    updateActivity()
                }
            }
            .onChange(of: isPopoverPresented) { _, presented in
                if !presented { isHoveringPopover = false }
                updateActivity()
            }
            .onAppear {
                if isAppleMusicActive {
                    Task { await airPlayManager.refreshDevices() }
                }
            }
            .onChange(of: musicManager.bundleIdentifier) { _, newBundle in
                if newBundle == "com.apple.Music" {
                    Task { await airPlayManager.refreshDevices() }
                }
            }
            .onDisappear {
                vm.isMediaOutputPopoverActive = false
            }
        }

        private func updateActivity() {
            vm.isMediaOutputPopoverActive = isPopoverPresented && isHoveringPopover
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

// MARK: - Minimalistic Album Art

struct MinimalisticAlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: NooriViewModel
    let albumArtNamespace: Namespace.ID

    private var albumArtCornerRadius: CGFloat {
        musicManager.albumArt.size.width / musicManager.albumArt.size.height > 1.0 ? 4 : 12
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            albumArtButton
        }
    }
    
    private var albumArtButton: some View {
        Button {
            musicManager.openMusicApp()
        } label: {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .background(
                        NooriArtworkSourceView(
                            cornerRadius: albumArtCornerRadius,
                            contentMode: .fit
                        )
                    )
                    .clipped()
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                    .albumArtFlip(angle: musicManager.flipAngle)
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(musicManager.isPlaying ? 1 : 0.4)
        .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
    }
}

// MARK: - Hover-highlighted control button

private struct MinimalisticSquircircleButton: View {
    let icon: String
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let frameSize: CGSize
    let cornerRadius: CGFloat
    let foregroundColor: Color
    let pressEffect: PressEffect
    let symbolEffectStyle: SymbolEffectStyle
    let externalTriggerToken: Int?
    let externalTriggerEffect: PressEffect?
    let action: () -> Void

    @State private var isHovering = false
    @State private var pressOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    @State private var wiggleToken: Int = 0
    @State private var lastExternalTriggerToken: Int?

    init(
        icon: String,
        fontSize: CGFloat,
        fontWeight: Font.Weight,
        frameSize: CGSize,
        cornerRadius: CGFloat,
        foregroundColor: Color,
        pressEffect: PressEffect = .none,
        symbolEffectStyle: SymbolEffectStyle = .none,
        externalTriggerToken: Int? = nil,
        externalTriggerEffect: PressEffect? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.frameSize = frameSize
        self.cornerRadius = cornerRadius
        self.foregroundColor = foregroundColor
        self.pressEffect = pressEffect
        self.symbolEffectStyle = symbolEffectStyle
        self.externalTriggerToken = externalTriggerToken
        self.externalTriggerEffect = externalTriggerEffect
        self.action = action
    }

    var body: some View {
        Button {
            triggerPressEffect()
            action()
        } label: {
            iconView()
                .frame(width: frameSize.width, height: frameSize.height)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isHovering ? Color.white.opacity(0.18) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: pressOffset)
        .rotationEffect(.degrees(rotationAngle))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                isHovering = hovering
            }
        }
        .onChange(of: externalTriggerToken) { _, newToken in
            guard let newToken, newToken != lastExternalTriggerToken else { return }
            lastExternalTriggerToken = newToken
            triggerPressEffect(override: externalTriggerEffect)
        }
    }

    private func triggerPressEffect(override: PressEffect? = nil) {
        let effect = override ?? pressEffect

        switch effect {
        case .none:
            return
        case .nudge(let amount):
            withAnimation(.spring(response: 0.16, dampingFraction: 0.72)) {
                pressOffset = amount
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                    pressOffset = 0
                }
            }
        case .wiggle(let direction):
            guard #available(macOS 14.0, *) else { return }
            wiggleToken += 1
            let angle: Double = direction == .clockwise ? 11 : -11

            withAnimation(.spring(response: 0.18, dampingFraction: 0.52)) {
                rotationAngle = angle
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                    rotationAngle = 0
                }
            }
        }
    }

    @ViewBuilder
    private func iconView() -> some View {
        let image = Image(systemName: icon)
            .font(.system(size: fontSize, weight: fontWeight))
            .foregroundColor(foregroundColor)

        switch symbolEffectStyle {
        case .none:
            image
        case .replace:
            if #available(macOS 14.0, *) {
                image.contentTransition(.symbolEffect(.replace))
            } else {
                image
            }
        case .bounce:
            if #available(macOS 14.0, *) {
                image.symbolEffect(.bounce, value: icon)
            } else {
                image
            }
        case .replaceAndBounce:
            if #available(macOS 14.0, *) {
                image
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: icon)
            } else {
                image
            }
        case .wiggle:
            if #available(macOS 15.0, *) {
                image.symbolEffect(
                    .wiggle.byLayer,
                    options: .nonRepeating,
                    value: wiggleToken
                )
            } else {
                image
            }
        }
    }

    enum PressEffect {
        case none
        case nudge(CGFloat)
        case wiggle(WiggleDirection)
    }

    enum SymbolEffectStyle {
        case none
        case replace
        case bounce
        case replaceAndBounce
        case wiggle
    }

    enum WiggleDirection {
        case clockwise
        case counterClockwise
    }
}

/// Timeline that ticks at a fixed interval, or once when paused.
private struct ProgressTimelineSchedule: TimelineSchedule {
    let interval: TimeInterval
    let paused: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next: Date? = startDate
        let step = interval
        let isPaused = paused
        return AnyIterator {
            guard let current = next else { return nil }
            next = isPaused ? nil : current.addingTimeInterval(step)
            return current
        }
    }
}
