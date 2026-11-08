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

import Foundation
import ApplicationServices
import Defaults
import Combine

class SystemHUDManager {
    static let shared = SystemHUDManager()
    
    private var changesObserver: SystemChangesObserver?
    private weak var coordinator: NooriViewCoordinator?
    private var isSetupComplete = false
    private var isSystemOperationInProgress = false
    private var keyInterceptionRetryTimer: Timer?
    
    private init() {
        // Set up observer for settings changes
        setupSettingsObserver()
    }
    
    private func setupSettingsObserver() {
        // Observe master HUD toggle
        Defaults.publisher(.enableSystemHUD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete else {
                return
            }
            Task { @MainActor in
                if change.newValue {
                    await self.startSystemObserver()
                } else {
                    await self.stopSystemObserver()
                }
            }
        }.store(in: &cancellables)
        
        // Observe individual HUD toggles
        Defaults.publisher(.enableVolumeHUD, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, self.requiresSystemToggleHandling else {
                return
            }
            let flags = self.resolvedControlFlags()
            self.changesObserver?.update(
                volumeEnabled: flags.volume,
                brightnessEnabled: flags.brightness,
                keyboardBacklightEnabled: flags.backlight
            )
        }.store(in: &cancellables)
        
        Defaults.publisher(.enableBrightnessHUD, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, self.requiresSystemToggleHandling else {
                return
            }
            let flags = self.resolvedControlFlags()
            self.changesObserver?.update(
                volumeEnabled: flags.volume,
                brightnessEnabled: flags.brightness,
                keyboardBacklightEnabled: flags.backlight
            )
        }.store(in: &cancellables)

        Defaults.publisher(.enableKeyboardBacklightHUD, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, self.requiresSystemToggleHandling else {
                return
            }
            let flags = self.resolvedControlFlags()
            self.changesObserver?.update(
                volumeEnabled: flags.volume,
                brightnessEnabled: flags.brightness,
                keyboardBacklightEnabled: flags.backlight
            )
        }.store(in: &cancellables)
        
        // Restart observer when third-party DDC integration state changes.
        Defaults.publisher(.enableThirdPartyDDCIntegration, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete else { return }
            Task { @MainActor in
                await self.startSystemObserver()
            }
        }.store(in: &cancellables)

        Defaults.publisher(.thirdPartyDDCProvider, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete else { return }
            Task { @MainActor in
                await self.startSystemObserver()
            }
        }.store(in: &cancellables)

        Defaults.publisher(.enableExternalVolumeControlListener, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete else { return }
            Task { @MainActor in
                await self.startSystemObserver()
            }
        }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()

    private var requiresSystemToggleHandling: Bool {
        Defaults[.enableSystemHUD]
    }
    
    /// Public property to check if system operations are in progress
    var isOperationInProgress: Bool {
        return isSystemOperationInProgress
    }
    
    func setup(coordinator: NooriViewCoordinator) {
        self.coordinator = coordinator

        // Re-resolve flags when a DDC helper starts/stops so brightness handling
        // recovers if the helper is quit while integration stays enabled.
        Task { @MainActor in
            Publishers.Merge(
                BetterDisplayManager.shared.$isRunning.removeDuplicates().map { _ in () },
                LunarManager.shared.$isRunning.removeDuplicates().map { _ in () }
            )
            .sink { [weak self] in
                guard let self, self.isSetupComplete,
                      Defaults[.enableThirdPartyDDCIntegration] else { return }
                Task { @MainActor in
                    await self.startSystemObserver()
                }
            }
            .store(in: &self.cancellables)
        }
        
        // Start observer if the HUD is enabled
        if Defaults[.enableSystemHUD] {
            Task { @MainActor in
                await startSystemObserver()
                self.isSetupComplete = true
            }
        } else {
            isSetupComplete = true
        }
    }
    
    /// Resolves the effective control flags, applying third-party DDC overrides.
    private func resolvedControlFlags() -> (volume: Bool, brightness: Bool, backlight: Bool) {
        var volumeEnabled = Defaults[.enableVolumeHUD]
        var brightnessEnabled = Defaults[.enableBrightnessHUD]
        var keyboardBacklightEnabled = Defaults[.enableKeyboardBacklightHUD]

        // Surrender brightness to the DDC helper only when it is actually running;
        // otherwise keep handling it ourselves so HUDs still show (and the native
        // OSD isn't left permanently suppressed) when the helper has been quit.
        let ddcProviderRunning: Bool = {
            switch Defaults[.thirdPartyDDCProvider] {
            case .betterDisplay: return BetterDisplayManager.checkRunning()
            case .lunar: return LunarManager.checkRunning()
            }
        }()

        if Defaults[.enableThirdPartyDDCIntegration] && ddcProviderRunning {
            brightnessEnabled = false
            keyboardBacklightEnabled = false

            // Optional: route volume exclusively from the selected external provider.
            if Defaults[.enableExternalVolumeControlListener] {
                volumeEnabled = false
            }
        }

        return (volumeEnabled, brightnessEnabled, keyboardBacklightEnabled)
    }

    @MainActor
    private func startSystemObserver() async {
        guard let coordinator = coordinator, !isSystemOperationInProgress else { return }
        
        isSystemOperationInProgress = true

        // Stop any existing observer directly (cannot call stopSystemObserver()
        // because isSystemOperationInProgress is already true).
        changesObserver?.stopObserving()
        changesObserver = nil
        
        changesObserver = SystemChangesObserver(coordinator: coordinator)
        stopKeyInterceptionRetry()

        let flags = resolvedControlFlags()
        let keysCaught = changesObserver?.startObserving(
            volumeEnabled: flags.volume,
            brightnessEnabled: flags.brightness,
            keyboardBacklightEnabled: flags.backlight
        ) ?? false

        if keysCaught {
            // Noori handles the media keys, so hide the native OSD to avoid duplicates.
            SystemOSDManager.disableSystemHUD()
        } else {
            // Without the key tap (no Accessibility permission yet) Noori can't show
            // brightness HUDs, so keep the native OSD visible and retry until permission arrives.
            if SystemOSDManager.isSuppressingNativeOSD {
                SystemOSDManager.enableSystemHUD()
            }
            startKeyInterceptionRetry()
        }
        
        print("System observer started (HUD: \(Defaults[.enableSystemHUD]), ThirdPartyDDC: \(Defaults[.enableThirdPartyDDCIntegration]), Provider: \(Defaults[.thirdPartyDDCProvider].displayName), ExternalVolumeListener: \(Defaults[.enableExternalVolumeControlListener]))")
        isSystemOperationInProgress = false
    }
    
    @MainActor
    private func stopSystemObserver() async {
        guard !isSystemOperationInProgress else { return }
        
        isSystemOperationInProgress = true
        stopKeyInterceptionRetry()
        changesObserver?.stopObserving()
        changesObserver = nil
        
        // Re-enable system HUD when we stop observing
        SystemOSDManager.enableSystemHUD()
        
        print("System observer stopped")
        isSystemOperationInProgress = false
    }
    
    // MARK: - Key interception retry

    /// Polls for Accessibility permission and installs the key tap once it is granted,
    /// so users don't have to restart Noori after allowing access.
    @MainActor
    private func startKeyInterceptionRetry() {
        guard keyInterceptionRetryTimer == nil else { return }
        // Scheduled on the main run loop, so the callback already runs on the main actor.
        // Uses the shared instance instead of capturing self (this manager is a singleton).
        keyInterceptionRetryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                SystemHUDManager.shared.retryKeyInterceptionIfPermitted()
            }
        }
    }

    @MainActor
    private func retryKeyInterceptionIfPermitted() {
        guard AXIsProcessTrusted(), let observer = changesObserver else { return }
        guard observer.retryKeyInterception() else { return }
        stopKeyInterceptionRetry()
        SystemOSDManager.disableSystemHUD()
        NSLog("✅ Accessibility granted; Noori now handles the media keys")
    }

    private func stopKeyInterceptionRetry() {
        keyInterceptionRetryTimer?.invalidate()
        keyInterceptionRetryTimer = nil
    }

    deinit {
        keyInterceptionRetryTimer?.invalidate()
        cancellables.removeAll()
        Task { @MainActor in
            await stopSystemObserver()
        }
    }
}