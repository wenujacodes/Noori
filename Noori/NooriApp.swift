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

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SkyLightWindow

@main
struct NooriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) var openWindow

    let updaterController: SPUStandardUpdaterController
    init() {
        // Skip Sparkle's launch-time update check during UI testing.
        // The update feed comes from SUFeedURL in Info.plist.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !AppRuntimeEnvironment.isUITesting,
            updaterDelegate: nil, userDriverDelegate: nil)

        // Initialize the settings window controller with the updater controller
        SettingsWindowController.shared.setUpdaterController(updaterController)
    }

    var body: some Scene {
        // Noori has no menu bar icon; Settings, Restart and Quit live in the notch's right-click menu.
        Settings { EmptyView() }
    }

    @CommandsBuilder
    var commands: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                SettingsWindowController.shared.showWindow()
            }
        }
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

extension AppDelegate {
    static var shared: AppDelegate? {
        NSApplication.shared.delegate as? AppDelegate
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSScreen: NSWindow] = [:]
    var viewModels: [NSScreen: NooriViewModel] = [:]
    var window: NSWindow?
    let vm: NooriViewModel = .init()
    @ObservedObject var coordinator = NooriViewCoordinator.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    let dndManager = DoNotDisturbManager.shared  // NEW: DND detection
    let bluetoothAudioManager = BluetoothAudioManager.shared  // NEW: Bluetooth audio detection
    let mediaControlsStateCoordinator = MediaControlsStateCoordinator.shared
    var closeNotchWorkItem: DispatchWorkItem?
    private var previousScreens: [NSScreen]?
    private var cancellables = Set<AnyCancellable>()
    private var windowsHiddenForLock = false
    private var optionalShortcutHandlersRegistered = false
    private weak var focusWithoutDevToolsMenuItem: NSMenuItem?
    private weak var focusUseDevToolsMenuItem: NSMenuItem?
    
    // Debouncing mechanism for window size updates
    private var windowSizeUpdateWorkItem: DispatchWorkItem?
//    let calendarManager = CalendarManager.shared
//    var closeNotchWorkItem: DispatchWorkItem?
//    private var previousScreens: [NSScreen]?
//    private var onboardingWindowController: NSWindowController?
//    private var cancellables = Set<AnyCancellable>()
//    
//    // Debouncing mechanism for window size updates
//    private var windowSizeUpdateWorkItem: DispatchWorkItem?
    
    private func debouncedUpdateWindowSize() {
        // Cancel any existing work item
        windowSizeUpdateWorkItem?.cancel()
        
        // Create new work item with delay
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateWindowSizeIfNeeded()
        }
        
        // Store reference and schedule
        windowSizeUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        installTopMenuItemsIfNeeded()
    }

    /// Clicking Noori's app icon while it's running (Finder, Launchpad, Spotlight,
    /// Dock): the first click opens the notch, a click while it's open opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let viewModel: NooriViewModel = {
            if Defaults[.showOnAllDisplays], let main = NSScreen.main, let screenVM = viewModels[main] {
                return screenVM
            }
            return vm
        }()

        closeNotchWorkItem?.cancel()
        closeNotchWorkItem = nil

        if viewModel.notchState == .open {
            SettingsWindowController.shared.showWindow()
            return false
        }

        viewModel.open()
        // Close again after a few seconds unless the pointer is over it, like the
        // open-notch shortcut. A click within that time opens Settings.
        let workItem = DispatchWorkItem { [weak viewModel] in
            guard let viewModel, viewModel.notchState == .open,
                  !viewModel.isMouseHovering() else { return }
            viewModel.close()
        }
        closeNotchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
        return false
    }

    
    func applicationWillTerminate(_ notification: Notification) {

        // Guarantee the native OSD is usable after we exit: if we were
        // suppressing it, OSDUIHelper is SIGSTOP-frozen and the async restore in
        // enableSystemHUD() would not finish before the process dies. Resume it
        // synchronously here so it is never left frozen. (See issue #568.)
        SystemOSDManager.resumeOSDUIHelperForTermination()

        // Cancel any pending window size updates
        windowSizeUpdateWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)

        // Restore Lunar's native OSD if integration was active
        LunarManager.shared.appWillTerminate()
    }
    
    @objc func onScreenLocked(_: Notification) {
        print("Screen locked")
        hideWindowsForLock()
    }

    @objc func onScreenUnlocked(_: Notification) {
        print("Screen unlocked")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.restoreWindowsAfterLock()
            self.adjustWindowPosition(changeAlpha: true)
        }
    }

    private func hideWindowsForLock() {
        guard !windowsHiddenForLock else { return }
        windowsHiddenForLock = true

        if Defaults[.showOnAllDisplays] {
            for window in windows.values {
                window.alphaValue = 0
                window.orderOut(nil)
            }
        } else if let window = window {
            window.alphaValue = 0
            window.orderOut(nil)
        }
    }

    private func restoreWindowsAfterLock() {
        guard windowsHiddenForLock else { return }
        windowsHiddenForLock = false

        if Defaults[.showOnAllDisplays] {
            for window in windows.values {
                window.orderFrontRegardless()
                window.alphaValue = 1
            }
        } else if let window = window {
            window.orderFrontRegardless()
            window.alphaValue = 1
        }
    }
    
    private func cleanupWindows(shouldInvert: Bool = false) {
        if shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays] {
            for (screen, window) in windows {
                // Tear down the hosted ContentView before dropping the window
                // (`.onDisappear` is unreliable for borderless panels).
                viewModels[screen]?.onViewTeardown?()
                viewModels[screen]?.onViewTeardown = nil
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
                window.close()
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            vm.onViewTeardown?()
            vm.onViewTeardown = nil
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            window.close()
            self.window = nil
        }
    }

    /// Rebuilds the notch's CGSSpace membership from the current hide option and the
    /// live windows. The space pins the notch above every space (fullscreen included)
    /// and is used **only** for "Never hide"; the hide options keep the set empty so
    /// FullscreenMediaDetector can hide the notch. Assigning the whole set lets the
    /// CGSSpace diff additions/removals, so this is safe to call on any change.
    @MainActor
    private func syncNotchSpaceMembership() {
        guard Defaults[.hideNotchOption] == .never else {
            NotchSpaceManager.shared.notchSpace.windows = []
            return
        }
        if Defaults[.showOnAllDisplays] {
            NotchSpaceManager.shared.notchSpace.windows = Set(windows.values)
        } else if let window = window {
            NotchSpaceManager.shared.notchSpace.windows = [window]
        } else {
            NotchSpaceManager.shared.notchSpace.windows = []
        }
    }

    private func createNooriWindow(for screen: NSScreen, with viewModel: NooriViewModel)
        -> NSWindow
    {
        // Use the current required size instead of always using openNotchSize
        let baseSize = calculateRequiredNotchSize()
        let requiredSize = adjustedSizeForScreen(baseSize, screen: screen)
        let roundedWidth = requiredSize.width.rounded()
        let roundedHeight = requiredSize.height.rounded()
        
        let window = NooriWindow(
            contentRect: NSRect(
                x: 0, y: 0, width: roundedWidth, height: roundedHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.animationBehavior = .none
        // collectionBehavior is configured in NooriWindow.init

        let hostingView = FirstMouseHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
                //.moveToSky()
        )
        // Noori sizes and centers this window itself. Without this, SwiftUI grows the
        // window to fit wider content (like the inline sneak peek) while keeping its
        // left edge fixed, which pushes the notch off-center.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        
        window.orderFrontRegardless()
        // Pin above every space (fullscreen included) only for "Never hide"; the
        // hide options leave the window on the collectionBehavior path so
        // FullscreenMediaDetector can hide it. See NotchSpaceManager.
        if Defaults[.hideNotchOption] == .never {
            NotchSpaceManager.shared.notchSpace.windows.insert(window)
        }
        //SkyLightOperator.shared.delegateWindow(window)
        return window
    }

    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false)
    {
        if changeAlpha {
            window.alphaValue = 0
        }
        
        // Use the same centering logic as updateWindowSizeIfNeeded()
        let screenFrame = screen.frame
        let centerX = screenFrame.origin.x + (screenFrame.width / 2)
        let roundedWidth = window.frame.width.rounded()
        let roundedHeight = window.frame.height.rounded()
        let newX = (centerX - (roundedWidth / 2)).rounded()
        let newY = (screenFrame.origin.y + screenFrame.height - roundedHeight).rounded()

        window.setFrame(NSRect(
            x: newX,
            y: newY,
            width: roundedWidth,
            height: roundedHeight
        ), display: false)
        
        if changeAlpha {
            window.alphaValue = 1
        }
    }
    
    private func updateWindowSizeIfNeeded() {
        // Calculate required size based on current state
        let requiredSize = calculateRequiredNotchSize()
        let animateResize = shouldAnimateResize(for: requiredSize)
        resizeWindows(to: requiredSize, animated: animateResize, force: false)
    }

    private func updateWindowSizeForTabSwitch() {
        let requiredSize = calculateRequiredNotchSize()
        resizeWindows(to: requiredSize, animated: false, force: true)
    }
    
    private func calculateRequiredNotchSize() -> CGSize {
        // Check if inline sneak peek is showing and notch is closed
        let airPodsListeningModeSneakActive = vm.notchState == .closed &&
                                      coordinator.sneakPeek.show &&
                                      coordinator.sneakPeek.type == .bluetoothAudio &&
                                      coordinator.sneakPeek.value < 0 &&
                                      AirPodsListeningMode.fromHUDSymbol(coordinator.sneakPeek.icon) != nil
        let isInlineSneakPeekActive = vm.notchState == .closed && 
                                      Defaults[.enableSneakPeek] &&
                                      (
                                          coordinator.expandingView.show &&
                                          coordinator.expandingView.type == .music &&
                                          Defaults[.sneakPeekStyles] == .inline ||
                                          airPodsListeningModeSneakActive
                                      )
        
        // If inline sneak peek is active, widen the window to fit the expanded content
        // (keeping the normal height, so the shadow and the open transition aren't clipped).
        if isInlineSneakPeekActive {
            // Album art (~32) + Middle section (380) + Visualizer (~32) + horizontal padding (28) + clip shape margin (12)
            let inlineSneakPeekWidth: CGFloat = 460
            let base = addShadowPadding(
                to: minimalisticOpenNotchSize(isNooriMode: shouldUseNooriMode(for: vm.screen)),
                isMinimalistic: true
            )
            return CGSize(width: max(base.width, inlineSneakPeekWidth), height: base.height)
        }

        // Check for battery HUD expansion
        if vm.notchState == .closed && 
           coordinator.expandingView.show && 
           coordinator.expandingView.type == .battery &&
           Defaults[.showPowerStatusNotifications] {
            
            let batteryModel = BatteryStatusViewModel.shared
            if let kind = batteryModel.activeTemporaryHUDKind {
                let closedNotchHeight = vm.effectiveClosedNotchHeight
                let closedNotchWidth = vm.closedNotchSize.width
                
                let style: BatteryNotificationStyle = {
                    switch kind {
                    case .charging: return .compact
                    case .lowBattery: return Defaults[.lowBatteryHUDStyle]
                    case .fullBattery: return Defaults[.fullBatteryHUDStyle]
                    }
                }()
                
                var width = closedNotchWidth
                var height = closedNotchHeight
                
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
                
                // Never smaller than the normal window: sizing it exactly to the HUD
                // cut off its rounded bottom (and the hover growth), leaving square corners.
                let batterySize = addShadowPadding(to: CGSize(width: width, height: height), isMinimalistic: true)
                let base = addShadowPadding(
                    to: minimalisticOpenNotchSize(isNooriMode: shouldUseNooriMode(for: vm.screen)),
                    isMinimalistic: true
                )
                return CGSize(
                    width: max(base.width, batterySize.width),
                    height: max(base.height, batterySize.height)
                )
            }
        }
        
        let baseSize = minimalisticOpenNotchSize(isNooriMode: shouldUseNooriMode(for: vm.screen))
        
        let adjustedContentSize = baseSize
        let result = addShadowPadding(
            to: adjustedContentSize,
            isMinimalistic: true
        )

        return result
    }

    /// Adjusts a base notch size for a specific screen by adding Noori
    /// shadow insets and top-offset only when the screen lacks a physical notch
    /// and the user has chosen the Noori style.
    private func adjustedSizeForScreen(_ baseSize: CGSize, screen: NSScreen) -> CGSize {
        guard shouldUseNooriMode(for: screen.localizedName) else {
            return baseSize
        }
        var adjusted = baseSize
        adjusted.width += nooriShadowInset * 2
        adjusted.height += nooriTopOffset
        return adjusted
    }

    func ensureWindowSize(_ size: CGSize, animated: Bool, force: Bool = false) {
        resizeWindows(to: size, animated: animated, force: force)
    }

    private func resizeWindows(to size: CGSize, animated: Bool, force: Bool) {
        guard size.width > 0, size.height > 0 else { return }

        if Defaults[.showOnAllDisplays] {
            for (screen, window) in windows {
                let screenSize = adjustedSizeForScreen(size, screen: screen)
                if force || window.frame.size != screenSize {
                    resizeWindow(window, on: screen, to: screenSize, animated: animated)
                }
            }
        } else if let window {
            let screen = window.screen ?? NSScreen.screens.first { $0.frame.intersects(window.frame) } ?? NSScreen.main ?? NSScreen.screens.first
            guard let screen else { return }
            let screenSize = adjustedSizeForScreen(size, screen: screen)
            if force || window.frame.size != screenSize {
                resizeWindow(window, on: screen, to: screenSize, animated: animated)
            }
        }
    }

    private func resizeWindow(_ window: NSWindow, on screen: NSScreen, to size: CGSize, animated: Bool) {
        let screenFrame = screen.frame
        // Clamp width to screen width so the notch never extends beyond screen edges on scaled displays
        let clampedWidth = min(size.width, screenFrame.width).rounded()
        let clampedHeight = min(size.height, screenFrame.height).rounded()
        let centerX = screenFrame.midX
        let newX = (centerX - (clampedWidth / 2)).rounded()
        let newY = (screenFrame.origin.y + screenFrame.height - clampedHeight).rounded()
        let targetFrame = NSRect(x: newX, y: newY, width: clampedWidth, height: clampedHeight)

        window.setFrame(targetFrame, display: true)
    }

    private func shouldAnimateResize(for newSize: CGSize) -> Bool {
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {

        LockScreenManager.shared.configure(viewModel: vm)
        LockScreenIndicatorWindowManager.shared.configure(viewModel: vm)
        ConnectivityMonitor.shared.start()
        
        // Migrate legacy progress bar settings
        Defaults.Keys.migrateProgressBarStyle()
        Defaults.Keys.migrateMusicAuxControls()
        Defaults.Keys.migrateMusicControlSlots()
        Defaults.Keys.migrateCapsLockTintMode()
        Defaults.Keys.migrateThirdPartyDDCIntegration()

        Defaults.publisher(.enableThirdPartyDDCIntegration, options: [])
            .sink { _ in
                Defaults.Keys.syncLegacyThirdPartyDDCKeys()
            }
            .store(in: &cancellables)

        Defaults.publisher(.thirdPartyDDCProvider, options: [])
            .sink { _ in
                Defaults.Keys.syncLegacyThirdPartyDDCKeys()
            }
            .store(in: &cancellables)
        
        // Initialize idle animations (load bundled + built-in face)

        installTopMenuItemsIfNeeded()

        Defaults.publisher(.focusMonitoringMode, options: [])
            .sink { [weak self] _ in
                self?.updateFocusMenuState()
            }
            .store(in: &cancellables)
        
        // Setup SystemHUD Manager
        SystemHUDManager.shared.setup(coordinator: coordinator)

        // Setup BetterDisplay integration
        BetterDisplayManager.shared.configure(coordinator: coordinator)

        // Setup Lunar integration
        LunarManager.shared.configure(coordinator: coordinator)
        
        // Setup ScreenRecording Manager
        if Defaults[.enableScreenRecordingDetection] && !AppRuntimeEnvironment.isUITesting {
            ScreenRecordingManager.shared.startMonitoring()
        }

        // Setup Do Not Disturb Manager
        if Defaults[.enableDoNotDisturbDetection] && !AppRuntimeEnvironment.isUITesting {
            dndManager.startMonitoring()
        }

        // Setup Privacy Indicator Manager (camera/mic; skipped under UI testing).
        if !AppRuntimeEnvironment.isUITesting {
            PrivacyIndicatorManager.shared.startMonitoring()
        }
        
        // Observe tab changes - use immediate resize to keep the notch pinned
        // Deferred to next run loop tick because @Published fires on willSet,
        // so coordinator.currentView still holds the OLD value at emission time.
        coordinator.$currentView.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateWindowSizeForTabSwitch()
            }
        }.store(in: &cancellables)

        
        Defaults.publisher(.openNotchWidth, options: []).sink { [weak self] _ in
            self?.debouncedUpdateWindowSize()
        }.store(in: &cancellables)

        // Sneak peeks can need a wider window than the closed notch. Resize (and
        // re-center) when one starts or ends, instead of letting the window drift.
        // Deferred a tick because @Published fires before the new value is stored.
        Publishers.Merge(
            coordinator.$expandingView.map { _ in () },
            coordinator.$sneakPeek.map { _ in () }
        )
        .sink { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.vm.notchState == .closed else { return }
                self.updateWindowSizeIfNeeded()
            }
        }
        .store(in: &cancellables)

        MemoryUsageMonitor.shared.startMonitoring()

        Defaults.publisher(.enableShortcuts, options: []).sink { [weak self] change in
            Task { @MainActor [weak self] in
                guard let self else { return }
                KeyboardShortcuts.isEnabled = change.newValue
                self.updateFeatureShortcutAvailability()
            }
        }.store(in: &cancellables)



        // Pin/unpin the notch above all spaces when the hide option changes:
        // "Never hide" joins the max-level CGSSpace, the hide options leave it.
        Defaults.publisher(.hideNotchOption, options: []).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncNotchSpaceMembership()
            }
        }.store(in: &cancellables)
        
        
        // Observe screen recording settings changes
        Defaults.publisher(.enableScreenRecordingDetection, options: []).sink { _ in
            if Defaults[.enableScreenRecordingDetection] {
                ScreenRecordingManager.shared.startMonitoring()
            } else {
                ScreenRecordingManager.shared.stopMonitoring()
            }
        }.store(in: &cancellables)
        
        Defaults.publisher(.enableDoNotDisturbDetection, options: []).sink { [weak self] _ in
            guard let self else { return }

            if Defaults[.enableDoNotDisturbDetection] {
                self.dndManager.startMonitoring()
            } else {
                self.dndManager.stopMonitoring()
            }
        }.store(in: &cancellables)

        // Note: Polling setting removed - now uses event-driven private API detection only

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            self?.adjustWindowPosition(changeAlpha: true)
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            self?.adjustWindowPosition()
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            DispatchQueue.main.async {
                window.alphaValue =
                    self.coordinator.selectedScreen == self.coordinator.preferredScreen ? 1 : 0
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            self.cleanupWindows(shouldInvert: true)

            if !Defaults[.showOnAllDisplays] {
                let viewModel = self.vm
                let window = self.createNooriWindow(
                    for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
                self.window = window
                self.adjustWindowPosition(changeAlpha: true)
            } else {
                self.adjustWindowPosition()
            }
        }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(onScreenLocked(_:)),
            name: NSNotification.Name(rawValue: "com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(onScreenUnlocked(_:)),
            name: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"), object: nil)

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            guard Defaults[.enableShortcuts] else { return }

            self.coordinator.toggleSneakPeek(
                status: !self.coordinator.sneakPeek.show,
                type: .music,
                duration: 3.0
            )
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            guard let self = self else { return }
            guard Defaults[.enableShortcuts] else { return }

            let mouseLocation = NSEvent.mouseLocation

            var viewModel = self.vm

            if Defaults[.showOnAllDisplays] {
                for screen in NSScreen.screens {
                    if screen.frame.contains(mouseLocation) {
                        if let screenViewModel = self.viewModels[screen] {
                            viewModel = screenViewModel
                            break
                        }
                    }
                }
            }

            self.closeNotchWorkItem?.cancel()
            self.closeNotchWorkItem = nil

            switch viewModel.notchState {
            case .closed:
                viewModel.open()

                let workItem = DispatchWorkItem { [weak viewModel] in
                    viewModel?.close()
                }
                self.closeNotchWorkItem = workItem

                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
            case .open:
                viewModel.close()
            }
        }

        KeyboardShortcuts.isEnabled = Defaults[.enableShortcuts]
        registerOptionalShortcutHandlers()
        updateFeatureShortcutAvailability()

        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createNooriWindow(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }
        
        // First-run setup (there is no onboarding window).
        if coordinator.firstLaunch {
            applyDefaultSetup()
            coordinator.firstLaunch = false
        }
        
        previousScreens = NSScreen.screens


    }

    private func installTopMenuItemsIfNeeded() {
        guard let mainMenu = NSApp.mainMenu else { return }
        if mainMenu.items.contains(where: { $0.identifier?.rawValue == "Noori.Focus.Menu" }) {
            updateFocusMenuState()
            return
        }

        let insertionIndex = preferredMenuInsertionIndex(in: mainMenu)

        let focusMenuItem = NSMenuItem(title: "Focus", action: nil, keyEquivalent: "")
        focusMenuItem.identifier = NSUserInterfaceItemIdentifier("Noori.Focus.Menu")
        let focusSubmenu = NSMenu(title: "Focus")

        let withoutDevTools = NSMenuItem(
            title: FocusMonitoringMode.withoutDevTools.displayName,
            action: #selector(selectFocusWithoutDevTools),
            keyEquivalent: ""
        )
        withoutDevTools.target = self

        let useDevTools = NSMenuItem(
            title: FocusMonitoringMode.useDevTools.displayName,
            action: #selector(selectFocusUseDevTools),
            keyEquivalent: ""
        )
        useDevTools.target = self

        focusSubmenu.addItem(withoutDevTools)
        focusSubmenu.addItem(useDevTools)
        focusMenuItem.submenu = focusSubmenu
        mainMenu.insertItem(focusMenuItem, at: insertionIndex)

        focusWithoutDevToolsMenuItem = withoutDevTools
        focusUseDevToolsMenuItem = useDevTools

        let accessibilityMenuItem = NSMenuItem(title: "Accessibility", action: nil, keyEquivalent: "")
        accessibilityMenuItem.identifier = NSUserInterfaceItemIdentifier("Noori.Accessibility.Menu")
        let accessibilitySubmenu = NSMenu(title: "Accessibility")

        let requestAccessibility = NSMenuItem(
            title: "Request Accessibility Access",
            action: #selector(requestAccessibilityAccess),
            keyEquivalent: ""
        )
        requestAccessibility.target = self

        let openAccessibility = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        openAccessibility.target = self

        accessibilitySubmenu.addItem(requestAccessibility)
        accessibilitySubmenu.addItem(openAccessibility)
        accessibilityMenuItem.submenu = accessibilitySubmenu
        mainMenu.insertItem(accessibilityMenuItem, at: insertionIndex + 1)

        let permissionsMenuItem = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        permissionsMenuItem.identifier = NSUserInterfaceItemIdentifier("Noori.Permissions.Menu")
        let permissionsSubmenu = NSMenu(title: "Permissions")

        let openDevTools = NSMenuItem(
            title: "Open Developer Tools Settings",
            action: #selector(openDeveloperToolsSettingsFromMenu),
            keyEquivalent: ""
        )
        openDevTools.target = self

        permissionsSubmenu.addItem(openDevTools)
        permissionsMenuItem.submenu = permissionsSubmenu
        mainMenu.insertItem(permissionsMenuItem, at: insertionIndex + 2)

        let toolsMenuItem = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        toolsMenuItem.identifier = NSUserInterfaceItemIdentifier("Noori.Tools.Menu")
        let toolsSubmenu = NSMenu(title: "Tools")

        let loggingLevelItem = NSMenuItem(title: "Logging Level", action: nil, keyEquivalent: "")
        let loggingLevelSubmenu = NSMenu(title: "Logging Level")
        
        let levels: [(String, LogLevel)] = [
            ("No Logging", .none),
            ("Error", .error),
            ("Warning", .warning),
            ("Info", .info),
            ("Debug", .debug)
        ]
        
        for (title, level) in levels {
            let item = NSMenuItem(title: title, action: #selector(setLogLevel(_:)), keyEquivalent: "")
            item.target = self
            item.tag = level.rawValue
            item.state = (Defaults[.logLevel] == level) ? NSControl.StateValue.on : NSControl.StateValue.off
            loggingLevelSubmenu.addItem(item)
        }
        loggingLevelItem.submenu = loggingLevelSubmenu
        toolsSubmenu.addItem(loggingLevelItem)

        toolsSubmenu.addItem(NSMenuItem.separator())
        
        let exportLogsItem = NSMenuItem(title: "Export Logs", action: #selector(exportLogs), keyEquivalent: "")
        exportLogsItem.target = self
        toolsSubmenu.addItem(exportLogsItem)

        toolsMenuItem.submenu = toolsSubmenu
        mainMenu.insertItem(toolsMenuItem, at: insertionIndex + 3)

        updateFocusMenuState()
    }

    private func preferredMenuInsertionIndex(in mainMenu: NSMenu) -> Int {
        if let index = mainMenu.items.firstIndex(where: { $0.title == "Window" }) {
            return index
        }
        if let index = mainMenu.items.firstIndex(where: { $0.title == "Help" }) {
            return index
        }
        return max(mainMenu.numberOfItems, 0)
    }

    private func updateFocusMenuState() {
        let mode = Defaults[.focusMonitoringMode]
        focusWithoutDevToolsMenuItem?.state = mode == .withoutDevTools ? .on : .off
        focusUseDevToolsMenuItem?.state = mode == .useDevTools ? .on : .off
    }

    @objc private func selectFocusWithoutDevTools() {
        Defaults[.focusMonitoringMode] = .withoutDevTools
        updateFocusMenuState()
    }

    @objc private func selectFocusUseDevTools() {
        Defaults[.focusMonitoringMode] = .useDevTools
        updateFocusMenuState()
    }

    @objc private func requestAccessibilityAccess() {
        AccessibilityPermissionStore.shared.requestAuthorizationPrompt()
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermissionStore.shared.openSystemSettings()
    }

    @objc private func openDeveloperToolsSettingsFromMenu() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_DevTools",
            "x-apple.systempreferences:com.apple.preference.security"
        ]

        for candidate in urls {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    @objc private func setLogLevel(_ sender: NSMenuItem) {
        guard let level = LogLevel(rawValue: sender.tag) else { return }
        Defaults[.logLevel] = level
        
        guard let mainMenu = NSApp.mainMenu,
              let toolsItem = mainMenu.item(withTitle: "Tools"),
              let toolsMenu = toolsItem.submenu,
              let loggingItem = toolsMenu.items.first(where: { $0.title == "Logging Level" }),
              let loggingSubmenu = loggingItem.submenu else { return }
              
        for item in loggingSubmenu.items {
            item.state = (item.tag == level.rawValue) ? NSControl.StateValue.on : NSControl.StateValue.off
        }
    }

    @objc private func exportLogs() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "Noori_Logs.zip"
        savePanel.title = "Export Logs & Crash Reports"
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            
            Task.detached(priority: .utility) {
                do {
                    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    
                    let logsFile = tempDir.appendingPathComponent("app_logs.txt")
                    let logProcess = Process()
                    logProcess.executableURL = URL(fileURLWithPath: "/usr/bin/log")
                    logProcess.arguments = ["show", "--predicate", "subsystem == 'com.wenujacodes.Noori' OR subsystem == 'com.wenujacodes.Noori.dev'", "--info", "--debug", "--last", "2d"]
                    
                    let pipe = Pipe()
                    logProcess.standardOutput = pipe
                    try logProcess.run()
                    logProcess.waitUntilExit()
                    
                    let logData = pipe.fileHandleForReading.readDataToEndOfFile()
                    try logData.write(to: logsFile)
                    
                    let diagDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/DiagnosticReports")
                    let allFiles = (try? FileManager.default.contentsOfDirectory(at: diagDir, includingPropertiesForKeys: nil)) ?? []
                    for file in allFiles where file.lastPathComponent.contains("Noori") {
                        try? FileManager.default.copyItem(at: file, to: tempDir.appendingPathComponent(file.lastPathComponent))
                    }
                    
                    let sysDiagDir = URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")
                    let sysFiles = (try? FileManager.default.contentsOfDirectory(at: sysDiagDir, includingPropertiesForKeys: nil)) ?? []
                    for file in sysFiles where file.lastPathComponent.contains("Noori") {
                        try? FileManager.default.copyItem(at: file, to: tempDir.appendingPathComponent(file.lastPathComponent))
                    }
                    
                    let zipProcess = Process()
                    zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    zipProcess.currentDirectoryURL = tempDir
                    let items = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
                    zipProcess.arguments = ["-r", url.path] + items
                    
                    try zipProcess.run()
                    zipProcess.waitUntilExit()
                    
                    try? FileManager.default.removeItem(at: tempDir)
                    
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Logs Exported"
                        alert.informativeText = "Logs and crash reports have been successfully exported to \(url.lastPathComponent)."
                        alert.alertStyle = .informational
                        alert.runModal()
                    }
                } catch {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Export Failed"
                        alert.informativeText = "Failed to export logs: \(error.localizedDescription)"
                        alert.alertStyle = .critical
                        alert.runModal()
                    }
                }
            }
        }
    }

    private func registerOptionalShortcutHandlers() {
        guard !optionalShortcutHandlersRegistered else { return }
        optionalShortcutHandlersRegistered = true





    }

    @MainActor
    private func updateFeatureShortcutAvailability() {
    }

    @MainActor
    private func updateShortcut(_ name: KeyboardShortcuts.Name, isEnabled: Bool) {
        if isEnabled {
            KeyboardShortcuts.enable(name)
        } else {
            KeyboardShortcuts.disable(name)
        }
    }
    
    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }
    
    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.map { $0.localizedName })
                != Set(previousScreens?.map { $0.localizedName } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens
        
        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                self?.cleanupWindows()
                self?.adjustWindowPosition()
            }
        }
    }
    
    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreens = Set(NSScreen.screens)
            
            for screen in windows.keys where !currentScreens.contains(screen) {
                if let window = windows[screen] {
                    viewModels[screen]?.onViewTeardown?()
                    viewModels[screen]?.onViewTeardown = nil
                    window.close()
                    windows.removeValue(forKey: screen)
                    viewModels.removeValue(forKey: screen)
                }
            }
            
            for screen in currentScreens {
                if windows[screen] == nil {
                    let viewModel = NooriViewModel(screen: screen.localizedName)
                    let window = createNooriWindow(for: screen, with: viewModel)
                    
                    windows[screen] = window
                    viewModels[screen] = viewModel
                }
                
                if let window = windows[screen], let viewModel = viewModels[screen] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)
                    
                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let selectedScreen: NSScreen

            if let preferredScreen = NSScreen.screens.first(where: {
                $0.localizedName == coordinator.preferredScreen
            }) {
                coordinator.selectedScreen = coordinator.preferredScreen
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main {
                coordinator.selectedScreen = mainScreen.localizedName
                selectedScreen = mainScreen
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }
            
            vm.screen = selectedScreen.localizedName
            vm.notchSize = getClosedNotchSize(screen: selectedScreen.localizedName)
            
            if window == nil {
                window = createNooriWindow(for: selectedScreen, with: vm)
            }
            
            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)
                
                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }
    }
    
    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }
    
    @objc func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    
    
    /// First-run setup: launch at login and haptics on, and a display style that matches the Mac's screen.
    private func applyDefaultSetup() {
        // On by default; the user can turn it off in Settings.
        LaunchAtLogin.isEnabled = true
        Defaults[.enableHaptics] = true

        // Notch Macs keep the standard notch; Macs without one get the Noori pill.
        let hasNotch = (NSScreen.main?.safeAreaInsets.top ?? 0) > 0
        Defaults[.externalDisplayStyle] = hasNotch ? .notch : .noori
    }
}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}

@MainActor
final class MediaControlsStateCoordinator {
    static let shared = MediaControlsStateCoordinator()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        Defaults.publisher(.showStandardMediaControls)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                self?.handleStateChange(showStandard: change.newValue)
            }
            .store(in: &cancellables)
    }

    private func handleStateChange(showStandard: Bool) {
        restoreMusicLiveActivity(clearCache: showStandard)
    }


    private func restoreMusicLiveActivity(clearCache: Bool) {
        guard let cached = Defaults[.cachedMusicLiveActivityPreference] else { return }

        if NooriViewCoordinator.shared.musicLiveActivityEnabled != cached {
            NooriViewCoordinator.shared.musicLiveActivityEnabled = cached
        }

        if clearCache {
            Defaults[.cachedMusicLiveActivityPreference] = nil
        }
    }




}


/// Relaunches Noori (used by the notch's right-click menu).
func restartNoori() {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier,
          let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    NSApplication.shared.terminate(nil)
}
