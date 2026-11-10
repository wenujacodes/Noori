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

import AVFoundation
import Combine
import Defaults
import Foundation
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: NooriViewModel

    @ObservedObject var coordinator = NooriViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject private var lyricsManager = LyricsManager.shared
    @Default(.showLyrics) private var showLyrics
    @Default(.lyricsHideWhenPaused) private var lyricsHideWhenPaused
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @ObservedObject var privacyManager = PrivacyIndicatorManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @ObservedObject var lockScreenManager = LockScreenManager.shared
    @ObservedObject var capsLockManager = CapsLockManager.shared
    @ObservedObject var callManager = CallActivityManager.shared
    @Default(.showCallLiveActivity) var showCallLiveActivity
    
    @Default(.enableHorizontalMusicGestures) var enableHorizontalMusicGestures
    @Default(.showCapsLockLabel) var showCapsLockLabel
    @Default(.capsLockIndicatorTintMode) var capsLockTintMode
    @Default(.enableDoNotDisturbDetection) var enableDoNotDisturbDetection
    @Default(.showDoNotDisturbIndicator) var showDoNotDisturbIndicator
    @Default(.enableScreenRecordingDetection) var enableScreenRecordingDetection
    @Default(.enableCapsLockIndicator) var enableCapsLockIndicator
    @Default(.albumArtNotchBackground) private var albumArtNotchBackground
    @Default(.albumArtClosedLyricsBackground) private var albumArtClosedLyricsBackground
    @Default(.showStandardMediaControls) var showStandardMediaControls
    @Default(.externalDisplayStyle) var externalDisplayStyle
    @Default(.hideNonNotchUntilHover) var hideNonNotchUntilHover
    
    // Battery settings reactivity
    @Default(.showPowerStatusNotifications) var showPowerStatusNotifications
    @Default(.showChargingBatteryHUD) var showChargingBatteryHUD
    @Default(.showLowBatteryHUD) var showLowBatteryHUD
    @Default(.showFullBatteryHUD) var showFullBatteryHUD
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.lowBatteryHUDStyle) var lowBatteryHUDStyle
    @Default(.fullBatteryHUDStyle) var fullBatteryHUDStyle
    
    // Dynamic sizing based on view type and graph count with smooth transitions
    var dynamicNotchSize: CGSize {
        let baseSize = minimalisticOpenNotchSize(isNooriMode: isNooriMode)
        
        // When inline sneak peek is active in closed notch, use the wider inline width
        // so the outer maxWidth frame doesn't clip the expanded content
        let airPodsListeningModeSneakActive = vm.notchState == .closed
            && coordinator.sneakPeek.show
            && coordinator.sneakPeek.type == .bluetoothAudio
            && coordinator.sneakPeek.value < 0
            && AirPodsListeningMode.fromHUDSymbol(coordinator.sneakPeek.icon) != nil
        let inlineSneakPeekActive = vm.notchState == .closed
            && (
                coordinator.expandingView.show
                    && coordinator.expandingView.type == .music
                    && Defaults[.sneakPeekStyles] == .inline
                || airPodsListeningModeSneakActive
            )
            && Defaults[.enableSneakPeek]
        if inlineSneakPeekActive {
            let inlineWidth: CGFloat = airPodsListeningModeSneakActive
                ? InlineHUD.airPodsListeningModeWidth(
                    closedNotchWidth: vm.closedNotchSize.width,
                    gestureProgress: gestureProgress,
                    minimalistic: true
                ) + notchHorizontalPadding * 2
                : 460
            return CGSize(width: max(baseSize.width, inlineWidth), height: baseSize.height)
        }
        
        // Long lyric lines widen the closed notch past the open notch's width.
        if vm.notchState == .closed, closedLyricRowVisible {
            let lyricsWidth = lyricsManager.closedWindowWidth
            if lyricsWidth > baseSize.width {
                return CGSize(width: lyricsWidth, height: baseSize.height)
            }
        }

        // Handle battery HUD expansion sizing
        if vm.notchState == .closed && 
           coordinator.expandingView.show && 
           coordinator.expandingView.type == .battery &&
           isBatteryHUDVisibleOnCurrentScreen {
            
            if let kind = batteryModel.activeTemporaryHUDKind {
                let style: BatteryNotificationStyle = {
                    switch kind {
                    case .charging: return .compact
                    case .lowBattery: return Defaults[.lowBatteryHUDStyle]
                    case .fullBattery: return Defaults[.fullBatteryHUDStyle]
                    }
                }()
                
                var width = vm.closedNotchSize.width
                var height = vm.effectiveClosedNotchHeight
                
                switch (kind, style) {
                case (.charging, _), (.lowBattery, .compact), (.fullBattery, .compact):
                    width += 180
                case (.lowBattery, .standard):
                    width += 100
                    height += 75
                case (.fullBattery, .standard):
                    width += 80
                    height += 70
                }
                
                return CGSize(width: width, height: height)
            }
        }
        
        return baseSize
    }
    

    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    /// Counts notch openings; each change plays the open bounce once.
    @State private var notchOpenCount: Int = 0
    /// Measured height of the notch body (see `keepWindowTallEnough`).
    @State private var measuredNotchHeight: CGFloat = 0
    @State private var lastHapticTime: Date = Date()
    @State private var hoverClickMonitor: Any?
    @State private var hoverClickLocalMonitor: Any?
    @State private var hiddenEdgeHoverPollingTask: Task<Void, Never>?
    @State private var isHoveringClosedMusicWaveformControl: Bool = false

    @State private var gestureProgress: CGFloat = .zero
    @State private var skipGestureActiveDirection: MusicManager.SkipDirection?

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    private func runAfter(_ delay: TimeInterval, _ action: @escaping @Sendable @MainActor () -> Void) {
        guard delay >= 0 else { return }
        Task { @MainActor in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            action()
        }
    }

    private var dynamicNotchResizeAnimation: Animation? {
        nil
    }
    
    private let zeroHeightHoverPadding: CGFloat = 10
    private let expandedRowHeight: CGFloat = 132

    
    


    private var isMusicHUDDeferredAfterUnlock: Bool {
        lockScreenManager.shouldDelayPostUnlockMusicHUD
    }

    private var interactionsEnabled: Bool {
        !lockScreenManager.isLocked
    }

    private var isIslandMode: Bool {
        isNooriMode
    }

    private var notchHorizontalPadding: CGFloat {
        guard vm.notchState == .open else {
            return activeCornerRadiusInsets.closed.bottom
        }
        return activeCornerRadiusInsets.opened.top - 5
    }

    private var bodyHoverAreaPadding: CGFloat {
        vm.effectiveClosedNotchHeight == 0 ? zeroHeightHoverPadding : 0
    }

    private var notchBottomPadding: CGFloat {
        currentShadowPadding + bodyHoverAreaPadding
    }

    private var pillTopOffset: CGFloat {
        isIslandMode ? nooriTopOffset : 0
    }

    private func closedMusicPairingEligible(hasActiveMusicSnapshot: Bool) -> Bool {
        vm.notchState == .closed
            && hasActiveMusicSnapshot
            && coordinator.musicLiveActivityEnabled
            && !vm.hideOnClosed
            && !lockScreenManager.isLocked
            && !isMusicHUDDeferredAfterUnlock
    }

    private var closedLiveActivitySwapTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.965, anchor: .center))
                .animation(.spring(response: 0.34, dampingFraction: 0.88)),
            removal: .opacity
                .combined(with: .scale(scale: 0.92, anchor: .center))
                .animation(.smooth(duration: 0.22))
        )
    }
    
    // Use minimalistic corner radius ONLY when opened, keep normal when closed
    private var activeCornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) {
        // Normal closed corner radius, minimalistic radius when opened
        return (opened: minimalisticCornerRadiusInsets.opened, closed: cornerRadiusInsets.closed)
    }
    
    private var currentShadowPadding: CGFloat {
        notchShadowPaddingValue(isMinimalistic: true)
    }

    private var currentNotchShape: NotchShape {
        let topRadius = vm.notchState == .open
            ? activeCornerRadiusInsets.opened.top
            : activeCornerRadiusInsets.closed.top
        let bottomRadius = vm.notchState == .open
            ? activeCornerRadiusInsets.opened.bottom
            : activeCornerRadiusInsets.closed.bottom
        return NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
    }

    /// Whether the current screen should render as a Noori pill
    /// rather than the standard notch shape. Always false on physical notch screens.
    private var isNooriMode: Bool {
        shouldUseNooriMode(for: currentScreenName)
    }

    private var currentScreenName: String {
        vm.screen ?? coordinator.selectedScreen
    }

    /// Whether the current screen lacks a physical notch.
    private var isNonNotchScreen: Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return true
        }
        return screen.safeAreaInsets.top <= 0
    }

    /// Whether the global sneak peek is visible on this specific screen.
    private var isSneakPeekVisibleOnCurrentScreen: Bool {
        guard coordinator.sneakPeek.show else { return false }
        guard Defaults[.showOnAllDisplays] else { return true }
        guard let targetScreenName = coordinator.sneakPeek.targetScreenName else { return true }
        return currentScreenName == targetScreenName
    }

    /// Whether the notch/island should hide off-screen when closed on a non-notch display.
    /// Temporarily reveals the notch when a sneakPeek HUD (volume, brightness, music, etc.) is active.
    private var shouldHideUntilHover: Bool {
        hideNonNotchUntilHover && isNonNotchScreen && vm.notchState == .closed && !isSneakPeekVisibleOnCurrentScreen
    }

    /// Whether the fallback top-edge hover detector should run.
    /// This is only needed when the notch is fully hidden off-screen and
    /// regular `.onHover` hit-testing may not trigger reliably.
    private var shouldUseHiddenEdgeHoverPolling: Bool {
        shouldHideUntilHover && !lockScreenManager.isLocked
    }
    
    

    /// Pill shape for Noori mode with animated corner radius transitions.
    private var currentPillShape: NooriPillShape {
        let radius: CGFloat
        if vm.notchState == .open {
            radius = minimalisticCornerRadiusInsets.opened.top
        } else {
            // Use half the closed height for a true capsule shape
            radius = max(vm.closedNotchSize.height / 2, nooriPillCornerRadiusInsets.closed.standard)
        }
        return NooriPillShape(cornerRadius: radius)
    }

    private var isBatteryHUDVisibleOnCurrentScreen: Bool {
        guard coordinator.expandingView.show, coordinator.expandingView.type == .battery else { return false }
        guard showPowerStatusNotifications else { return false }
        guard batteryModel.activeTemporaryHUDKind != nil else { return false }
        if showOnAllDisplays { return true }
        guard let targetScreenName = batteryModel.activeTemporaryHUDTargetScreenName else { return true }
        return currentScreenName == targetScreenName
    }

    private var isCurrentScreenExpansionVisible: Bool {
        guard coordinator.expandingView.show else { return false }
        if coordinator.expandingView.type == .battery {
            return isBatteryHUDVisibleOnCurrentScreen
        }
        return true
    }

    private var currentScreenExpansionType: SneakContentType? {
        isCurrentScreenExpansionVisible ? coordinator.expandingView.type : nil
    }

    private var displayedBatteryHUDLevel: Int {
        let resolvedLevel = batteryModel.activeTemporaryHUDLevelOverride
            ?? Int(batteryModel.levelBattery.rounded())
        return min(max(resolvedLevel, 0), 100)
    }

    private var displayedBatteryHUDUsesLowPowerMode: Bool {
        batteryModel.activeTemporaryHUDLowPowerModeOverride ?? batteryModel.isInLowPowerMode
    }


    private var activeClosedBatterySurfaceShape: AnyShape? {
        guard vm.notchState == .closed else { return nil }
        guard isBatteryHUDVisibleOnCurrentScreen else { return nil }
        guard let kind = batteryModel.activeTemporaryHUDKind else { return nil }

        if isNooriMode {
            let radius = nooriPillCornerRadiusInsets.opened
            return AnyShape(NooriPillShape(cornerRadius: radius))
        } else {
            let topRadius = activeCornerRadiusInsets.closed.top
            let bottomRadius: CGFloat = {
                switch resolvedBatteryNotificationStyle(for: kind) {
                case .compact:
                    return activeCornerRadiusInsets.closed.bottom
                case .standard:
                    return kind == .fullBattery ? 36 : 40
                }
            }()
            return AnyShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
        }
    }

    private func resolvedBatteryNotificationStyle(for kind: BatteryTemporaryHUDKind) -> BatteryNotificationStyle {
        switch kind {
        case .charging:
            return .compact
        case .lowBattery:
            return lowBatteryHUDStyle
        case .fullBattery:
            return fullBatteryHUDStyle
        }
    }


    /// Resolves the clip/content shape per-screen: pill on non-notch screens
    /// when Noori pill mode is active, standard notch shape otherwise.
    private var resolvedClipShape: AnyShape {
        if let activeClosedBatterySurfaceShape {
            return activeClosedBatterySurfaceShape
        }
        if isNooriMode {
            return AnyShape(currentPillShape)
        }
        return AnyShape(currentNotchShape)
    }

    var body: some View {
        installRootLifecycleHandlers(on: rootBodyView)
    }

    private var mainLayoutBase: some View {
        NotchLayout()
            .frame(alignment: .top)
            .padding(.horizontal, notchHorizontalPadding)
            .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
            .background { notchBackground }
            .clipShape(resolvedClipShape)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                measuredNotchHeight = height
                keepWindowTallEnough()
            }
            // The bounces are extra black shapes behind the notch, drawn only while
            // a bounce plays, so the content inside never moves or stretches and
            // the notch at rest renders exactly as a plain clipped black shape.
            .background {
                let isOpen = vm.notchState == .open
                resolvedClipShape
                    .fill(.black)
                    .keyframeAnimator(initialValue: CGFloat(0), trigger: notchOpenCount) { shape, swell in
                        // Only while open, so a close mid-bounce isn't stretched.
                        let amount = isOpen ? swell : 0
                        shape
                            .scaleEffect(
                                x: 1 + (NooriMotion.notchOpenBounce.width - 1) * amount,
                                y: 1 + (NooriMotion.notchOpenBounce.height - 1) * amount,
                                anchor: .top
                            )
                            .opacity(amount > 0.001 ? 1 : 0)
                    } keyframes: { _ in
                        // One smooth swell: waits while the notch grows fast, peaks
                        // as it reaches full size, then settles back softly.
                        CubicKeyframe(0, duration: NooriMotion.notchBounceWait)
                        CubicKeyframe(1, duration: NooriMotion.notchBounceRise)
                        SpringKeyframe(0, duration: NooriMotion.notchBounceFall, spring: .smooth)
                    }
            }
            .compositingGroup()
            // The open notch grows and shrinks with the lyric row.
            .animation(NooriMotion.notchOpen, value: lyricsManager.showsInOpenNotch)
            .shadow(
                color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                    ? .black.opacity(0.6)
                    : .clear,
                radius: 10
            )
            // Extra horizontal inset for Noori mode so the shadow
            // is not clipped by the outer frame constraint
            .padding(.horizontal, isIslandMode ? nooriShadowInset : 0)
            .padding(.bottom, isIslandMode ? nooriShadowInset : 0)
            .padding(.top, pillTopOffset)
            .accessibilityIdentifier("NooriNotch")
    }

    private var configuredMainLayout: some View {
        mainLayoutBase
            .animation(NooriMotion.hover, value: isHovering)
            .animation(NooriMotion.notch(opening: vm.notchState == .open), value: vm.notchState)
            .animation(NooriMotion.gesture, value: gestureProgress)
            // After unlock the music pill comes back once the lock pill has
            // closed; animate the notch body with it so it grows instead of jumping.
            .animation(NooriMotion.notchOpen, value: lockScreenManager.shouldDelayPostUnlockMusicHUD)
            .conditionalModifier(interactionsEnabled) { view in
                view
                    .contentShape(resolvedClipShape)
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        if handleClosedCallTapIfNeeded() {
                            return
                        }
                        if handleClosedMusicWaveformTapIfNeeded() {
                            return
                        }
                        if vm.notchState == .closed && Defaults[.enableHaptics] {
                            triggerHapticIfAllowed()
                        }
                        openNotch()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                            .panGesture(direction: .left) { translation, phase in
                                handleSkipGesture(direction: .forward, translation: translation, phase: phase)
                            }
                            .panGesture(direction: .right) { translation, phase in
                                handleSkipGesture(direction: .backward, translation: translation, phase: phase)
                            }
                    }
            }
            .conditionalModifier((Defaults[.closeGestureEnabled] || Defaults[.reverseScrollGestures]) && Defaults[.enableGestures] && interactionsEnabled) { view in
                view
                    .panGesture(direction: .up) { translation, phase in
                        handleUpGesture(translation: translation, phase: phase)
                    }
            }
            // Shadow bottom padding and hide-until-hover offset applied AFTER
            // interaction modifiers so .contentShape / .onHover only covers
            // the actual notch content, not the shadow clearance below it.
            .padding(.bottom, notchBottomPadding)
            .offset(y: shouldHideUntilHover && !isHovering
                ? -(vm.closedNotchSize.height + pillTopOffset + currentShadowPadding + 10)
                : 0
            )
            .onChange(of: vm.notchState) { _, newState in
                // Reset hover state when notch state changes
                if newState == .closed && isHovering {
                    withAnimation {
                        isHovering = false
                    }
                }
                if newState != .closed {
                    isHoveringClosedMusicWaveformControl = false
                }
            }
            .onChange(of: vm.shouldRecheckHover) { _, _ in
                // Recheck hover state when popovers are closed
                runAfter(0.1) {
                    if vm.notchState == .open && !shouldPreventAutoClose() && !isHovering {
                        vm.close()
                    }
                }
            }
            .onChange(of: coordinator.sneakPeek.show) { _, sneakPeekShowing in
                // When sneak peek finishes, check if user is still hovering and open notch if needed
                if !sneakPeekShowing {
                    runAfter(0.2) {
                        if isHovering && vm.notchState == .closed && !coordinator.isHoverOpenSuppressed {
                            openNotch()
                        }
                    }
                }
            }
            .sensoryFeedback(.alignment, trigger: haptics)
            .contextMenu {
                Button("Settings") {
                    SettingsWindowController.shared.showWindow()
                }
                Divider()
                Button("Restart Noori") {
                    restartNoori()
                }
                Button("Quit Noori") {
                    NSApplication.shared.terminate(nil)
                }
            }
    }

    private var rootBodyView: some View {
        ZStack(alignment: .top) {
            configuredMainLayout
            // Runs Apple's on-device translation for the lyrics (invisible).
            LyricsTranslationHost()
        }
        .onChange(of: vm.notchState) { _, newState in
            if newState == .open { notchOpenCount &+= 1 }
        }
        .frame(
            maxWidth: (dynamicNotchSize.width + (vm.notchState == .open ? 24 : 0) + (isNooriMode ? nooriShadowInset * 2 : 0)).rounded(),
            maxHeight: (dynamicNotchSize.height + (vm.notchState == .open ? 12 : 0) + (isNooriMode ? nooriTopOffset + nooriShadowInset * 2 : currentShadowPadding)).rounded(),
            alignment: .top
        )
        // Pinned to the top of the window. When the content is briefly taller than
        // the window (lyrics just loaded, window not resized yet), SwiftUI would
        // center it, pushing the art and controls up under the camera notch; with a
        // fixed top it only runs past the bottom (the shadow area) until the window
        // catches up.
        .modifier(PinnedToWindowTop())
        .environmentObject(privacyManager)
        .environmentObject(vm)
    }

    private var showsAlbumArtBackground: Bool {
        albumArtNotchBackground && vm.notchState == .open && musicManager.hasActiveSession
    }

    private var showsClosedLyricsArtBackground: Bool {
        albumArtClosedLyricsBackground && vm.notchState == .closed && closedLyricRowVisible
            && !vm.hideOnClosed && !lockScreenManager.isLocked
    }

    /// Black, or the album art when that's turned on (open notch, or behind the
    /// closed notch's lyrics).
    private var notchBackground: some View {
        ZStack {
            Color.black
            if showsAlbumArtBackground {
                AlbumArtNotchBackground(style: .open, topBlack: max(24, vm.effectiveClosedNotchHeight))
                    .transition(.opacity)
            } else if showsClosedLyricsArtBackground {
                AlbumArtNotchBackground(style: .closedLyrics, topBlack: vm.effectiveClosedNotchHeight)
                    .transition(.opacity)
            }
        }
        // In with the notch's content, out a little faster as it closes.
        .animation(
            showsAlbumArtBackground ? .easeOut(duration: 0.3) : .easeIn(duration: 0.18),
            value: showsAlbumArtBackground
        )
        .animation(.easeInOut(duration: 0.3), value: showsClosedLyricsArtBackground)
    }

    /// Grows the window when the open notch is taller than the window, which
    /// would cut off its rounded bottom corners.
    private func keepWindowTallEnough() {
        guard vm.notchState == .open, measuredNotchHeight > 0,
              let delegate = AppDelegate.shared else { return }
        // The same room below the notch that the root frame leaves.
        let below = isNooriMode ? nooriTopOffset + nooriShadowInset * 2 : currentShadowPadding
        let needed = (measuredNotchHeight + below).rounded(.up)
        delegate.openNotchHeightFloor = needed
        // Resize after this layout pass, never during it (resizing the window
        // mid-layout can make SwiftUI lay out again and again). It only grows
        // windows that are actually shorter, so it settles at once.
        DispatchQueue.main.async {
            guard vm.notchState == .open else { return }
            delegate.ensureOpenWindowHeight(needed)
        }
    }

    private func installRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        view
            .onAppear {
                if shouldUseHiddenEdgeHoverPolling {
                    startHiddenEdgeHoverPolling()
                }
                // Deterministic teardown for borderless panels (`.onDisappear` is
                // unreliable); the window-cleanup path calls this before closing.
                vm.onViewTeardown = { performViewTeardown() }
            }
            .onDisappear {
                performViewTeardown()
            }
            // Only poll while the notch is hidden off-screen; otherwise the loop
            // would wake the CPU 20 times a second for nothing.
            .onChange(of: shouldUseHiddenEdgeHoverPolling) { _, shouldPoll in
                if shouldPoll {
                    startHiddenEdgeHoverPolling()
                } else {
                    stopHiddenEdgeHoverPolling()
                }
            }
    }

    @ViewBuilder
      func NotchLayout() -> some View {
          VStack(alignment: .leading) {
              VStack(alignment: .leading) {
                        let hasMusicMetadata = !musicManager.songTitle.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                            || !musicManager.artistName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                      let hasActiveMusicSnapshot: Bool = {
                          if musicManager.isPlaying { return true }
                          return !musicManager.isPlayerIdle && hasMusicMetadata
                      }()
                      let musicPairingEligible = closedMusicPairingEligible(hasActiveMusicSnapshot: hasActiveMusicSnapshot)
                      let musicSecondary = resolveMusicSecondaryLiveActivity(isMusicPairingEligible: musicPairingEligible)
                      let activeSneakPeekStyle = resolvedSneakPeekStyle()
                      let expansionMatchesSecondary: Bool = {
                          guard let musicSecondary else { return false }
                          switch musicSecondary {
                          case .recording:
                              return currentScreenExpansionType == .recording
                          case .focus:
                              return currentScreenExpansionType == .doNotDisturb
                          case .capsLock:
                              return false
                          }
                      }()
                      let canShowMusicDuringExpansion = !isCurrentScreenExpansionVisible
                          || currentScreenExpansionType == .music
                          || expansionMatchesSecondary
                      let isAirPodsListeningModeSneak = coordinator.sneakPeek.type == .bluetoothAudio
                          && coordinator.sneakPeek.value < 0
                          && AirPodsListeningMode.fromHUDSymbol(coordinator.sneakPeek.icon) != nil

                      if currentScreenExpansionType == .battery
                            && isBatteryHUDVisibleOnCurrentScreen
                            && vm.notchState == .closed
                            && Defaults[.showPowerStatusNotifications]
                            && batteryModel.activeTemporaryHUDKind != nil {
                        BatteryTemporaryActivityView(
                            kind: batteryModel.activeTemporaryHUDKind ?? .charging,
                            batteryLevel: displayedBatteryHUDLevel,
                            isLowPowerMode: displayedBatteryHUDUsesLowPowerMode,
                            closedNotchWidth: vm.closedNotchSize.width + (isHovering ? 8 : 0),
                            baseHeight: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0),
                            isNooriMode: isNooriMode,
                            topCornerRadius: activeCornerRadiusInsets.closed.top,
                            styleOverride: batteryModel.activeTemporaryHUDKind.map { resolvedBatteryNotificationStyle(for: $0) }
                        )
                        .id(batteryModel.activeTemporaryHUDToken)
                      } else if isSneakPeekVisibleOnCurrentScreen && !controlHUDUnderLyrics && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && (coordinator.sneakPeek.type != .capsLock || vm.notchState == .closed) && ((coordinator.sneakPeek.type != .volume && coordinator.sneakPeek.type != .brightness && coordinator.sneakPeek.type != .backlight) || vm.notchState == .closed) {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(
                                  coordinator.sneakPeek.type == .capsLock
                                      ? AnyTransition.move(edge: .trailing).combined(with: .opacity)
                                      : AnyTransition.opacity
                              )
                      } else if vm.notchState == .closed && capsLockManager.isCapsLockActive && Defaults[.enableCapsLockIndicator] && !vm.hideOnClosed && !lockScreenManager.isLocked {
                          InlineHUD(type: .constant(.capsLock), value: .constant(1.0), icon: .constant(""), hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
                      } else if showsClosedCallActivity {
                          CallLiveActivity(isHovering: isHovering, gestureProgress: gestureProgress)
                              .id("closed-call-live-activity")
                              .transition(closedLiveActivitySwapTransition)
                      } else if canShowMusicDuringExpansion && musicPairingEligible {
                          MusicLiveActivity(secondary: musicSecondary)
                              .id("closed-music-live-activity")
                              .transition(closedLiveActivitySwapTransition)
                      } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .recording) && vm.notchState == .closed && (recordingManager.isRecording || !recordingManager.isRecorderIdle) && Defaults[.enableScreenRecordingDetection] && !vm.hideOnClosed && !musicPairingEligible {
                          RecordingLiveActivity()
                      } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .doNotDisturb) && vm.notchState == .closed && Defaults[.enableDoNotDisturbDetection] && Defaults[.showDoNotDisturbIndicator] && (doNotDisturbManager.isDoNotDisturbActive || doNotDisturbManager.isFocusToastDismissing) && !vm.hideOnClosed && !lockScreenManager.isLocked {
                          DoNotDisturbLiveActivity()
                    } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .privacy) && vm.notchState == .closed && privacyManager.hasAnyIndicator && (Defaults[.enableCameraDetection] || Defaults[.enableMicrophoneDetection]) && !vm.hideOnClosed {
                        PrivacyLiveActivity()
                      } else if vm.notchState == .open {
                          NooriHeader()
                              .frame(height: isNooriMode ? nil : max(24, vm.effectiveClosedNotchHeight))
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }
                      
                      if isSneakPeekVisibleOnCurrentScreen {
                          // HUDs are always inline (above); this is the music sneak peek.
                          if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && activeSneakPeekStyle == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName), font: .system(size: 11, weight: .medium), nsFont: .subheadline, textColor: .gray, minDuration: 1, frameWidth: geo.size.width, onScrollPass: { coordinator.holdSneakPeek(for: $0) })
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
              }
              .conditionalModifier(shouldFixSizeForSneakPeek()) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
              
              ZStack {
                  if vm.notchState == .open {
                      Group {
                          switch coordinator.currentView {
                              case .home:
                                  NotchHomeView(albumArtNamespace: albumArtNamespace)
                          }
                      }
                      .id(coordinator.currentView)
                      .transition(NooriMotion.notchContentFade)
                  }
              }
              .zIndex(1)
              .allowsHitTesting(vm.notchState == .open)
              .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
              .opacity(abs(gestureProgress) > 0.3 ? min(abs(gestureProgress * 2), 0.8) : 1)
              .animation(NooriMotion.appear, value: coordinator.currentView)
          }
      }



    @ViewBuilder
    private func MusicLiveActivity(secondary preResolvedSecondary: MusicSecondaryLiveActivity? = nil) -> some View {
        let secondary = preResolvedSecondary ?? resolveMusicSecondaryLiveActivity()
        let notchContentHeight = max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
        let wingBaseWidth = max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2)
        let rawCenterBaseWidth = vm.closedNotchSize.width + (isHovering ? 8 : 0)
        let centerBaseWidth = max(rawCenterBaseWidth, 96)
        let inlineSneakPeekActive = (
            coordinator.expandingView.show &&
            coordinator.expandingView.type == .music &&
            Defaults[.enableSneakPeek] &&
            Defaults[.sneakPeekStyles] == .inline
        )
        let rightWingWidth = resolvedRightWingWidth(
            for: secondary,
            baseWidth: wingBaseWidth,
            centerBaseWidth: centerBaseWidth,
            notchHeight: notchContentHeight
        )
        // Lyrics: a row under the notch for the line being sung, with the notch a bit
        // wider so lines fit.
        let showLyricRow = closedLyricRowVisible
        let showsControlHUD = controlHUDUnderLyrics
        let effectiveCenterWidth = inlineSneakPeekActive ? 380 : (showLyricRow ? max(centerBaseWidth, lyricsManager.closedCenterWidth) : centerBaseWidth)
        let notchWidth = wingBaseWidth + effectiveCenterWidth + rightWingWidth
        let badgeBaseSize = max(13, notchContentHeight * 0.36)
        let badgeDisplaySize = badgeDisplaySize(for: secondary, baseSize: badgeBaseSize)
        let badgeOffset = badgeOverlayOffset(for: secondary, badgeSize: badgeDisplaySize)

        VStack(spacing: 0) {
        HStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .background(
                        Image(nsImage: musicManager.albumArt)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: musicManager.albumArt.size.width/musicManager.albumArt.size.height > 1.0 ? MusicPlayerImageSizes.cornerRadiusInset.closed/3.0 : MusicPlayerImageSizes.cornerRadiusInset.closed))
                    )
                    .clipped()
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                    .albumArtFlip(angle: musicManager.flipAngle)
                albumArtBadge(for: secondary, badgeSize: badgeDisplaySize)
                    .offset(x: badgeOffset.width, y: badgeOffset.height)
                    .id(secondary?.id ?? "music-badge")
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: wingBaseWidth, height: notchContentHeight)

            Rectangle()
                .fill(.black)
                .frame(width: effectiveCenterWidth, height: notchContentHeight)
                .overlay(
                    HStack(alignment: .top) {
                        if(coordinator.expandingView.show && coordinator.expandingView.type == .music) {
                            MusicTitleMarqueeView(
                                text: musicManager.songTitle,
                                isExplicit: musicManager.isCurrentTrackExplicit,
                                font: .system(size: 11, weight: .medium),
                                nsFont: .subheadline,
                                textColor: Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: max(0, (effectiveCenterWidth - vm.closedNotchSize.width) / 2 - 12),
                                badgeHeight: 13,
                                onScrollPass: { coordinator.holdExpandingView(for: $0) }
                            )
                            .padding(.leading, 8)
                            .opacity((coordinator.expandingView.show && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Scrolls like the title when it's too long; right-aligned when it fits.
                            MusicTitleMarqueeView(
                                text: musicManager.artistName,
                                isExplicit: false,
                                font: .system(size: 11, weight: .medium),
                                nsFont: .subheadline,
                                textColor: Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: max(0, (effectiveCenterWidth - vm.closedNotchSize.width) / 2 - 12),
                                alignment: .trailing,
                                onScrollPass: { coordinator.holdExpandingView(for: $0) }
                            )
                            .padding(.trailing, 8)
                                .opacity((coordinator.expandingView.show && coordinator.expandingView.type == .music && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                        } else if Defaults[.showSongMetadataInClosedNotch] && isNonNotchScreen && !musicManager.songTitle.isEmpty {
                            MarqueeText(
                                .constant("\(musicManager.songTitle) • \(musicManager.artistName)"),
                                font: .system(size: 11, weight: .medium),
                                nsFont: .subheadline,
                                textColor: Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 3,
                                frameWidth: max(0, effectiveCenterWidth - 16)
                            )
                            .padding(.horizontal, 8)
                        }
                    }
                    .clipped()
                )

            musicRightWing(for: secondary, notchHeight: notchContentHeight, trailingWidth: rightWingWidth)
                .frame(width: rightWingWidth, height: notchContentHeight, alignment: .center)
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard shouldShowClosedMusicWaveformPlayPauseOverlay(for: secondary) else {
                        if isHoveringClosedMusicWaveformControl {
                            isHoveringClosedMusicWaveformControl = false
                        }
                        return
                    }
                    withAnimation(NooriMotion.change) {
                        isHoveringClosedMusicWaveformControl = hovering
                    }
                }
                .id(secondary?.id ?? "music-spectrum")
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: notchWidth, height: notchContentHeight)
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)

            if showLyricRow {
                NotchLyricLine(width: max(0, notchWidth - 16))
                    .padding(.bottom, showsControlHUD ? 2 : 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                if showsControlHUD {
                    // Volume / brightness under the lyrics for a moment; the lyrics stay.
                    NotchLyricHUDRow(
                        type: coordinator.sneakPeek.type,
                        value: coordinator.sneakPeek.value,
                        width: max(0, notchWidth - 16)
                    )
                    .frame(height: 22)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(NooriMotion.appear, value: secondary?.id)
        .animation(NooriMotion.change, value: showLyricRow)
        .animation(NooriMotion.change, value: showsControlHUD)
    }

    /// The lyric row under the closed notch is showing.
    private var closedLyricRowVisible: Bool {
        showLyrics && !lyricsManager.lines.isEmpty && lyricsManager.isWithinLyrics
            && (musicManager.isPlaying || (!lyricsHideWhenPaused && musicManager.hasActiveSession))
    }

    /// A volume, brightness or keyboard backlight change while lyrics show under the
    /// closed notch: it shows as a bar under the lyrics instead of the wide inline HUD.
    private var controlHUDUnderLyrics: Bool {
        guard vm.notchState == .closed, isSneakPeekVisibleOnCurrentScreen, closedLyricRowVisible else { return false }
        switch coordinator.sneakPeek.type {
        case .volume, .brightness, .backlight: return true
        default: return false
        }
    }

    private func resolveMusicSecondaryLiveActivity(isMusicPairingEligible: Bool = true) -> MusicSecondaryLiveActivity? {
        if enableScreenRecordingDetection && (recordingManager.isRecording || !recordingManager.isRecorderIdle) {
            return .recording
        }

        if enableDoNotDisturbDetection && showDoNotDisturbIndicator && doNotDisturbManager.isDoNotDisturbActive {
            let mode = FocusModeType.resolve(identifier: doNotDisturbManager.currentFocusModeIdentifier, name: doNotDisturbManager.currentFocusModeName)
            return .focus(mode)
        }

        if enableCapsLockIndicator && capsLockManager.isCapsLockActive {
            return .capsLock(showLabel: showCapsLockLabel)
        }

        return nil
    }

    private func resolvedRightWingWidth(for secondary: MusicSecondaryLiveActivity?, baseWidth: CGFloat, centerBaseWidth: CGFloat, notchHeight: CGFloat) -> CGFloat {
        guard let secondary else { return baseWidth }

        switch secondary {
        case .capsLock(let showLabel):
            return showLabel ? scaledWingWidth(baseWidth: baseWidth, centerBaseWidth: centerBaseWidth, factor: 0.4, extra: 12) : baseWidth
        case .focus:
            return focusRightWingWidth(baseWidth: baseWidth)
        case .recording:
            return recordingRightWingWidth(baseWidth: baseWidth)
        }
    }




    private func focusRightWingWidth(baseWidth: CGFloat) -> CGFloat {
        // Focus pairings now mirror the default music spectrum width to keep the notch compact.
        return baseWidth
    }

    private func recordingRightWingWidth(baseWidth: CGFloat) -> CGFloat {
        // Keep recording pairings compact by reducing the width relative to the notch height.
        let absoluteMin: CGFloat = 38
        let preferredWidth = max(baseWidth * 0.6, 0)
        let maxWidth = min(baseWidth - 6, 52)
        let clampedPreferred = min(preferredWidth, maxWidth)
        return min(baseWidth, max(absoluteMin, clampedPreferred))
    }

    private func scaledWingWidth(baseWidth: CGFloat, centerBaseWidth: CGFloat, factor: CGFloat, extra: CGFloat) -> CGFloat {
        max(baseWidth, max(centerBaseWidth * factor, baseWidth + extra))
    }

    @ViewBuilder
    private func albumArtBadge(for secondary: MusicSecondaryLiveActivity?, badgeSize: CGFloat) -> some View {
        if let secondary, badgeSize > 0 {
            ZStack {
                Circle()
                    .fill(Color.black)

                switch secondary {
                case .focus(let mode):
                    mode.resolvedActiveIcon(usePrivateSymbol: true)
                        .renderingMode(.template)
                        .font(.system(size: badgeSize * 0.5, weight: .semibold))
                        .foregroundStyle(mode.accentColor)
                case .recording:
                    Circle()
                        .fill(Color.red)
                        .frame(width: badgeSize * 0.45, height: badgeSize * 0.45)
                        .modifier(PulsingModifier())
                case .capsLock:
                    Image(systemName: "capslock.fill")
                        .font(.system(size: badgeSize * 0.5, weight: .semibold))
                        .foregroundStyle(capsLockTintMode.color)
                }
            }
            .frame(width: badgeSize, height: badgeSize)
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            .transition(.opacity.combined(with: .scale))
        } else {
            EmptyView()
        }
    }

    private func badgeDisplaySize(for secondary: MusicSecondaryLiveActivity?, baseSize: CGFloat) -> CGFloat {
        guard let secondary else { return baseSize }
        switch secondary {
        default:
            return baseSize
        }
    }

    private func badgeOverlayOffset(for secondary: MusicSecondaryLiveActivity?, badgeSize: CGFloat) -> CGSize {
        guard let secondary else { return CGSize(width: badgeSize * 0.2, height: badgeSize * 0.25) }
        switch secondary {
        default:
            return CGSize(width: badgeSize * 0.2, height: badgeSize * 0.25)
        }
    }

    @ViewBuilder
    private func musicRightWing(for secondary: MusicSecondaryLiveActivity?, notchHeight: CGFloat, trailingWidth: CGFloat) -> some View {
        switch secondary {
        case .capsLock(let showLabel):
            if showLabel {
                MusicCapsLockLabelView(color: capsLockTintMode.color)
            } else {
                spectrumView(forceSpectrum: true)
            }
        case .focus:
            spectrumView(forceSpectrum: true)
        case .recording:
            spectrumView(forceSpectrum: true, trailingInset: 6)
        case .none:
            spectrumView(
                forceSpectrum: false,
                enableClosedPlayPauseOverlay: shouldShowClosedMusicWaveformPlayPauseOverlay(for: secondary)
            )
        }
    }

    @ViewBuilder
    private func SpectrumVisualizer(
        useMusicVisualizer: Bool,
        forceSpectrum: Bool
    ) -> some View {
        let width = CGFloat(Defaults[.visualizerBarCount]) * 4
        if useMusicVisualizer || forceSpectrum {
            // Sized to just the visible bars, so it can glide to the open
            // player's visualizer (same id) without jumping.
            Rectangle()
                .fill((Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray).spectrogramGradient())
                .frame(width: min(width, 50), height: 12)
                .mask {
                    AudioVisualizerView(isPlaying: $musicManager.isPlaying)
                        .frame(width: width, height: 12)
                }
                .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                .frame(width: 50)
                .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func spectrumView(
        forceSpectrum: Bool,
        trailingInset: CGFloat = 0,
        enableClosedPlayPauseOverlay: Bool = false
    ) -> some View {
        if useMusicVisualizer || forceSpectrum {
            SpectrumVisualizer(useMusicVisualizer: useMusicVisualizer, forceSpectrum: forceSpectrum)
                .blur(radius: (enableClosedPlayPauseOverlay && isHoveringClosedMusicWaveformControl) ? 2.4 : 0)
                .overlay {
                    if enableClosedPlayPauseOverlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(isHoveringClosedMusicWaveformControl ? 0.24 : 0.02))

                            Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(isHoveringClosedMusicWaveformControl ? 0.98 : 0.0))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.trailing, trailingInset)
                .animation(NooriMotion.change, value: isHoveringClosedMusicWaveformControl)
                .animation(NooriMotion.change, value: musicManager.isPlaying)
        }
    }








    

    // MARK: - Private Methods
    private func openNotch() {
        withAnimation(NooriMotion.notchOpen) {
            vm.open()
        }
    }

    private func shouldShowClosedMusicWaveformPlayPauseOverlay(for secondary: MusicSecondaryLiveActivity?) -> Bool {
        guard secondary == nil else { return false }
        return isClosedMusicGestureContext && !Defaults[.openNotchOnHover]
    }

    private var isClosedMusicGestureContext: Bool {
        vm.notchState == .closed
            && coordinator.musicLiveActivityEnabled
            && !vm.hideOnClosed
            && !lockScreenManager.isLocked
            && !isMusicHUDDeferredAfterUnlock
            && !isCurrentScreenExpansionVisible
            && (!musicManager.isPlayerIdle || musicManager.bundleIdentifier != nil)
            && !coordinator.firstLaunch
    }

    /// The call pill shows in the closed notch (it takes priority over music).
    private var showsClosedCallActivity: Bool {
        vm.notchState == .closed
            && showCallLiveActivity
            && callManager.isCallActive
            && !vm.hideOnClosed
            && !lockScreenManager.isLocked
            && (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .music)
    }

    /// A click on the call pill brings the calling app to the front instead of opening the notch.
    private func handleClosedCallTapIfNeeded() -> Bool {
        guard showsClosedCallActivity else { return false }
        if Defaults[.enableHaptics] {
            triggerHapticIfAllowed()
        }
        callManager.bringCallAppToFront()
        return true
    }

    private func handleClosedMusicWaveformTapIfNeeded() -> Bool {
        guard shouldShowClosedMusicWaveformPlayPauseOverlay(for: nil),
              isHoveringClosedMusicWaveformControl else {
            return false
        }

        if Defaults[.enableHaptics] {
            triggerHapticIfAllowed()
        }
        musicManager.playPause()
        return true
    }

    private func hiddenHoverActivationContainsMouse(_ location: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return false
        }

        let horizontalPadding: CGFloat = 8
        let activationWidth = vm.closedNotchSize.width + horizontalPadding * 2
        let activationHeight = max(vm.closedNotchSize.height + zeroHeightHoverPadding, 14)

        let activationRect = CGRect(
            x: screen.frame.midX - activationWidth / 2,
            y: screen.frame.maxY - activationHeight,
            width: activationWidth,
            height: activationHeight
        )

        return activationRect.contains(location)
    }

    /// Cancels every long-lived task / event monitor this view owns. Called from
    /// `.onDisappear` and from `vm.onViewTeardown` on window close. Idempotent.
    private func performViewTeardown() {
        hoverTask?.cancel()
        stopHoverClickMonitor()
        stopHiddenEdgeHoverPolling()
        isHoveringClosedMusicWaveformControl = false
    }

    private func startHiddenEdgeHoverPolling() {
        guard hiddenEdgeHoverPollingTask == nil else { return }

        hiddenEdgeHoverPollingTask = Task { @MainActor in
            while !Task.isCancelled && self.shouldUseHiddenEdgeHoverPolling {
                let hovering = self.hiddenHoverActivationContainsMouse()
                if hovering != self.isHovering {
                    self.handleHover(hovering)
                }

                try? await Task.sleep(for: .milliseconds(50))
            }

            self.hiddenEdgeHoverPollingTask = nil
        }
    }

    private func stopHiddenEdgeHoverPolling() {
        hiddenEdgeHoverPollingTask?.cancel()
        hiddenEdgeHoverPollingTask = nil
    }

    private func startHoverClickMonitor() {
        guard Defaults[.openNotchOnHover] else { return }
        guard hoverClickMonitor == nil else { return }

        let handleClick: @Sendable () -> Void = { [weak vm, weak lockScreenManager] in
            Task { @MainActor in
                guard let vm, let lockScreenManager else { return }
                guard !lockScreenManager.isLocked else { return }
                guard vm.notchState == .closed else { return }
                guard !self.coordinator.isHoverOpenSuppressed else { return }
                guard self.isHovering else { return }
                guard !self.handleClosedCallTapIfNeeded() else { return }
                guard !self.handleClosedMusicWaveformTapIfNeeded() else { return }
                if Defaults[.enableHaptics] {
                    self.triggerHapticIfAllowed()
                }
                self.openNotch()
            }
        }

        // Global monitor catches clicks outside the app window (e.g. when
        // the cursor is at the very top screen edge and the click goes to
        // the system rather than our panel).
        hoverClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { _ in
            handleClick()
        }

        // Local monitor catches clicks that DO hit our window — at the
        // screen edge SwiftUI's .onTapGesture may not fire reliably, but
        // the NSEvent local monitor will.
        hoverClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            handleClick()
            return event
        }
    }

    private func stopHoverClickMonitor() {
        if let hoverClickMonitor {
            NSEvent.removeMonitor(hoverClickMonitor)
            self.hoverClickMonitor = nil
        }
        if let hoverClickLocalMonitor {
            NSEvent.removeMonitor(hoverClickLocalMonitor)
            self.hoverClickLocalMonitor = nil
        }
    }




    // MARK: - Hover Management
    
    /// Handle hover state changes with debouncing
    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()

        if hovering {
            startHoverClickMonitor()
        } else {
            stopHoverClickMonitor()
            if isHoveringClosedMusicWaveformControl {
                withAnimation(NooriMotion.change) {
                    isHoveringClosedMusicWaveformControl = false
                }
            }
        }

        if hovering {
            withAnimation(NooriMotion.hover) {
                isHovering = true
            }

            if vm.notchState == .closed && Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }

            guard vm.notchState == .closed,
                !isSneakPeekVisibleOnCurrentScreen,
                Defaults[.openNotchOnHover] else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.isSneakPeekVisibleOnCurrentScreen,
                          !self.coordinator.isHoverOpenSuppressed else { return }

                    self.openNotch()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(NooriMotion.hover) {
                        self.isHovering = false
                    }

                    if self.vm.notchState == .open && !self.shouldPreventAutoClose() {
                        self.vm.close()
                    }
                }
            }
        }
    }
    
    // Helper function to check if any popovers are active
    private func hasAnyActivePopovers() -> Bool {
     return vm.isMediaOutputPopoverActive
    }

    private func shouldPreventAutoClose() -> Bool {
        coordinator.firstLaunch || hasAnyActivePopovers() || vm.isAutoCloseSuppressed
    }
    
    // Helper to prevent rapid haptic feedback
    private func triggerHapticIfAllowed() {
        let now = Date()
        if now.timeIntervalSince(lastHapticTime) > 0.3 { // Minimum 300ms between haptics
            haptics.toggle()
            lastHapticTime = now
        }
    }
    




    // Estimate the height required for minimalistic overrides (notably web content) and clamp it to the notch bounds.
    
    // MARK: - Gesture Handling
    
    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleScrollGesture(isDownward: true, translation: translation, phase: phase)
    }
    
    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleScrollGesture(isDownward: false, translation: translation, phase: phase)
    }

    private func handleScrollGesture(isDownward: Bool, translation: CGFloat, phase: NSEvent.Phase) {
        let reverse = Defaults[.reverseScrollGestures]
        let shouldOpen = isDownward ? !reverse : reverse

        if shouldOpen {
            handleOpenScrollGesture(translation: translation, phase: phase)
        } else {
            guard Defaults[.closeGestureEnabled] else { return }
            handleCloseScrollGesture(translation: translation, phase: phase)
        }
    }

    private func handleOpenScrollGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        withAnimation(NooriMotion.gesture) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if phase == .ended {
            withAnimation(NooriMotion.gesture) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }
            withAnimation(NooriMotion.gesture) {
                gestureProgress = .zero
            }
            openNotch()
        }
    }

    private func handleCloseScrollGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open, !vm.isScrollGestureActive else { return }

        withAnimation(NooriMotion.gesture) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(NooriMotion.gesture) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(NooriMotion.gesture) {
                gestureProgress = .zero
                isHovering = false
            }
            vm.close()

            if Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }
        }
    }

    private func handleSkipGesture(direction: MusicManager.SkipDirection, translation: CGFloat, phase: NSEvent.Phase) {
        if phase == .ended {
            skipGestureActiveDirection = nil
            return
        }

        guard canPerformSkipGesture() else {
            skipGestureActiveDirection = nil
            return
        }

        if skipGestureActiveDirection == nil && translation > Defaults[.gestureSensitivity] {
            let effectiveDirection: MusicManager.SkipDirection
            if Defaults[.reverseSwipeGestures] {
                effectiveDirection = direction == .forward ? .backward : .forward
            } else {
                effectiveDirection = direction
            }
            skipGestureActiveDirection = effectiveDirection

            if Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }

            musicManager.handleSkipGesture(direction: effectiveDirection)
        }
    }

    private func canPerformSkipGesture() -> Bool {
        let canSkipInOpenHome = vm.notchState == .open && coordinator.currentView == .home
        let canSkipInClosedMusic = !Defaults[.openNotchOnHover] && isClosedMusicGestureContext

        return enableHorizontalMusicGestures
            && (canSkipInOpenHome || canSkipInClosedMusic)
            && (!musicManager.isPlayerIdle || musicManager.bundleIdentifier != nil)
            && !lockScreenManager.isLocked
            && !hasAnyActivePopovers()
            && !vm.isScrollGestureActive
    }

    private func shouldFixSizeForSneakPeek() -> Bool {
        guard isSneakPeekVisibleOnCurrentScreen, !controlHUDUnderLyrics else { return false }
        let style = resolvedSneakPeekStyle()
        
        // Original logic for other types
        let isMusicSneak = coordinator.sneakPeek.type == .music && vm.notchState == .closed && !vm.hideOnClosed && style == .standard
        let isOtherSneak = coordinator.sneakPeek.type != .music && vm.notchState == .closed
        
        return isMusicSneak || isOtherSneak
    }

    private func resolvedSneakPeekStyle() -> SneakPeekStyle {
        return coordinator.sneakPeek.styleOverride ?? Defaults[.sneakPeekStyles]
    }
}

private enum MusicSecondaryLiveActivity: Equatable {
    case recording
    case focus(FocusModeType)
    case capsLock(showLabel: Bool)

    var id: String {
        switch self {
        case .recording:
            return "recording"
        case .focus(let mode):
            return "focus-\(mode.rawValue)"
        case .capsLock(let showLabel):
            return showLabel ? "caps-lock-label" : "caps-lock-icon"
        }
    }
}



private struct MusicCapsLockLabelView: View {
    let color: Color

    var body: some View {
        Text("Caps Lock")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentTransition(.opacity)
    }
}

#if canImport(AppKit)
private typealias MusicSupplementFont = NSFont
#elseif canImport(UIKit)
private typealias MusicSupplementFont = UIFont
#endif
/// Lays its content out from the top of the window, whatever its height.
private struct PinnedToWindowTop: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}
