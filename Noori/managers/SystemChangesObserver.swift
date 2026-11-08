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
import CoreGraphics
import Defaults
import AppKit
import AVFoundation

final class SystemChangesObserver: MediaKeyInterceptorDelegate {
    private weak var coordinator: NooriViewCoordinator?
    private let volumeController = SystemVolumeController.shared
    private let brightnessController = SystemBrightnessController.shared
    private let keyboardBacklightController = SystemKeyboardBacklightController.shared
    private let mediaKeyInterceptor = MediaKeyInterceptor.shared

    private static let headsetIconSymbols: Set<String> = [
        "airpods",
        "airpodspro",
        "airpodsmax",
        "beats.headphones",
        "headphones"
    ]

    private var standardVolumeStep: Float {
        Float(Defaults[.volumeStepPercent]) / 100.0
    }
    private var fineVolumeStep: Float {
        Float(Defaults[.volumeFineStepPercent]) / 100.0
    }
    private var standardBrightnessStep: Float {
        Float(Defaults[.brightnessStepPercent]) / 100.0
    }
    private var fineBrightnessStep: Float {
        Float(Defaults[.brightnessFineStepPercent]) / 100.0
    }

    private var volumeEnabled = false
    /// The last volume shown (or seen at start), so the HUD only appears when the
    /// volume really changes, not when the audio system reports its current level.
    private var lastVolumeState: (volume: Float, muted: Bool)?
    /// Same for brightness and keyboard backlight: both report their current level when they start.
    private var lastBrightness: Float?
    private var lastBacklight: Float?
    private var brightnessEnabled = false
    private var keyboardBacklightEnabled = false

    init(coordinator: NooriViewCoordinator) {
        self.coordinator = coordinator
    }

    /// Returns true when the media key tap is running (needs Accessibility permission).
    @discardableResult
    func startObserving(volumeEnabled: Bool, brightnessEnabled: Bool, keyboardBacklightEnabled: Bool) -> Bool {
        self.volumeEnabled = volumeEnabled
        self.brightnessEnabled = brightnessEnabled
        self.keyboardBacklightEnabled = keyboardBacklightEnabled

        // Remember the current level so the first report after launch doesn't show a HUD.
        lastVolumeState = (volumeController.currentVolume, volumeController.isMuted)
        volumeController.onVolumeChange = { [weak self] volume, muted in
            guard let self, self.volumeEnabled else { return }
            guard self.volumeStateChanged(volume: volume, muted: muted) else { return }
            let value = muted ? 0 : volume
            Task { @MainActor in
                self.sendVolumeNotification(value: value, isMuted: muted)
            }
        }
        volumeController.onRouteChange = { [weak self] in
            guard let self, self.volumeEnabled else { return }
            let muted = self.volumeController.isMuted
            Task { @MainActor in
                self.sendVolumeNotification(value: muted ? 0 : self.volumeController.currentVolume, isMuted: muted)
            }
        }
        volumeController.start()

        lastBrightness = brightnessController.currentBrightness
        brightnessController.onBrightnessChange = { [weak self] brightness in
            guard let self, self.brightnessEnabled else { return }
            guard Self.levelChanged(brightness, from: &self.lastBrightness) else { return }
            self.sendBrightnessNotification(value: brightness)
        }
        brightnessController.start()

        configureKeyboardBacklightCallback()
        if keyboardBacklightEnabled {
            lastBacklight = keyboardBacklightController.currentLevel
            keyboardBacklightController.start()
        }

        mediaKeyInterceptor.delegate = self
        let tapStarted = mediaKeyInterceptor.start()
        if !tapStarted {
            NSLog("⚠️ Media key interception unavailable; system HUD will remain visible")
        }
        mediaKeyInterceptor.configuration = MediaKeyConfiguration(
            interceptVolume: volumeEnabled,
            interceptBrightness: brightnessEnabled,
            interceptCommandModifiedBrightness: keyboardBacklightEnabled
        )
        return tapStarted
    }

    /// Tries to install the media key tap again, e.g. after Accessibility was granted.
    func retryKeyInterception() -> Bool {
        mediaKeyInterceptor.start()
    }

    func update(volumeEnabled: Bool, brightnessEnabled: Bool, keyboardBacklightEnabled: Bool) {
        self.volumeEnabled = volumeEnabled
        self.brightnessEnabled = brightnessEnabled
        let backlightStateChanged = self.keyboardBacklightEnabled != keyboardBacklightEnabled
        self.keyboardBacklightEnabled = keyboardBacklightEnabled

        if keyboardBacklightEnabled {
            configureKeyboardBacklightCallback()
        } else {
            keyboardBacklightController.onBacklightChange = nil
        }

        if backlightStateChanged {
            if keyboardBacklightEnabled {
                lastBacklight = keyboardBacklightController.currentLevel
                keyboardBacklightController.start()
            } else {
                keyboardBacklightController.stop()
            }
        }

        mediaKeyInterceptor.configuration = MediaKeyConfiguration(
            interceptVolume: volumeEnabled,
            interceptBrightness: brightnessEnabled,
            interceptCommandModifiedBrightness: keyboardBacklightEnabled
        )
    }

    func stopObserving() {
        mediaKeyInterceptor.stop()
        mediaKeyInterceptor.delegate = nil

        volumeController.stop()
        volumeController.onVolumeChange = nil
        volumeController.onRouteChange = nil

        brightnessController.stop()
        brightnessController.onBrightnessChange = nil

        keyboardBacklightController.stop()
        keyboardBacklightController.onBacklightChange = nil
    }

    // MARK: - MediaKeyInterceptorDelegate

    func mediaKeyInterceptor(
        _ interceptor: MediaKeyInterceptor,
        didReceiveVolumeCommand direction: MediaKeyDirection,
        step: MediaKeyStep,
        isRepeat: Bool,
        modifiers: NSEvent.ModifierFlags
    ) {
        guard volumeEnabled else { return }
        SystemOSDManager.suppressNativeOSDNow()
        
        let baseStep = volumeStep(for: step)
        let delta = direction == .up ? baseStep : -baseStep
        let before = volumeController.currentVolume
        volumeController.adjust(by: delta)

        // Already at 0% or 100%: the volume doesn't change, so no change is reported.
        // Still show the HUD so the key press gets feedback.
        let after = volumeController.currentVolume
        if abs(after - before) < 0.0005 {
            let muted = volumeController.isMuted
            Task { @MainActor in
                self.sendVolumeNotification(value: muted ? 0 : after, isMuted: muted)
            }
        }
    }

    /// True (and remembered) when the volume or mute state differs from the last one seen.
    private func volumeStateChanged(volume: Float, muted: Bool) -> Bool {
        if let last = lastVolumeState, last.muted == muted, abs(last.volume - volume) < 0.0005 {
            return false
        }
        lastVolumeState = (volume, muted)
        return true
    }

    func mediaKeyInterceptorDidToggleMute(_ interceptor: MediaKeyInterceptor) {
        guard volumeEnabled else { return }
        SystemOSDManager.suppressNativeOSDNow()
        volumeController.toggleMute()
    }

    func mediaKeyInterceptor(
        _ interceptor: MediaKeyInterceptor,
        didReceiveBrightnessCommand direction: MediaKeyDirection,
        step: MediaKeyStep,
        isRepeat: Bool,
        modifiers: NSEvent.ModifierFlags
    ) {
        let isBacklight = modifiers.contains(.command) && keyboardBacklightEnabled
        guard isBacklight || brightnessEnabled else { return }
        SystemOSDManager.suppressNativeOSDNow()

        let baseStep = brightnessStep(for: step)
        let delta = direction == .up ? baseStep : -baseStep
        let before = isBacklight ? keyboardBacklightController.currentLevel : brightnessController.currentBrightness
        if isBacklight {
            keyboardBacklightController.adjust(by: delta)
        } else {
            brightnessController.adjust(by: delta)
        }

        // Already at 0% or 100%: nothing changes, so nothing is reported.
        // Still show the HUD so the key press gets feedback.
        let atLimit = direction == .up ? before >= 0.999 : before <= 0.001
        if atLimit {
            if isBacklight {
                sendKeyboardBacklightNotification(value: before)
            } else {
                sendBrightnessNotification(value: before)
            }
        }
    }

    /// True (and remembered) when a level differs from the last one seen.
    private static func levelChanged(_ value: Float, from last: inout Float?) -> Bool {
        if let previous = last, abs(previous - value) < 0.0005 {
            return false
        }
        last = value
        return true
    }

    // MARK: - HUD Dispatch

    @MainActor
    private func sendVolumeNotification(value: Float, isMuted: Bool) {
        // The CoreAudio volume write wakes the native OSD; suppress it immediately
        // so only our notch HUD shows (parity with brightness). No-op unless active.
        SystemOSDManager.suppressNativeOSDNow()

        if HUDSuppressionCoordinator.shared.shouldSuppressVolumeHUD {
            return
        }

        // Send to notch HUD if enabled
        if Defaults[.enableSystemHUD] && Defaults[.enableVolumeHUD] {
            Task { @MainActor in
                guard let coordinator else { return }
                coordinator.toggleSneakPeek(
                    status: true,
                    type: .volume,
                    value: CGFloat(value),
                    icon: ""
                )
            }
        }
    }

    @MainActor
    private func resolvedVolumeIcon(isMuted: Bool) -> String {
        guard let icon = BluetoothAudioManager.shared.activeDeviceIconSymbol() else { return "" }
        if isMuted && Self.headsetIconSymbols.contains(icon) {
            return "headphones.slash"
        }
        return icon
    }

    private func sendBrightnessNotification(value: Float) {
        // Send to notch HUD if enabled
        if Defaults[.enableSystemHUD] && Defaults[.enableBrightnessHUD] {
            Task { @MainActor in
                guard let coordinator else { return }
                coordinator.toggleSneakPeek(
                    status: true,
                    type: .brightness,
                    value: CGFloat(value),
                    icon: ""
                )
            }
        }
    }

    private func sendKeyboardBacklightNotification(value: Float) {
        // Send to notch HUD if enabled
        if Defaults[.enableSystemHUD] && Defaults[.enableKeyboardBacklightHUD] {
            Task { @MainActor in
                guard let coordinator else { return }
                coordinator.toggleSneakPeek(
                    status: true,
                    type: .backlight,
                    value: CGFloat(value),
                    icon: ""
                )
            }
        }
    }

    private func configureKeyboardBacklightCallback() {
        if keyboardBacklightEnabled {
            keyboardBacklightController.onBacklightChange = { [weak self] value in
                guard let self, self.keyboardBacklightEnabled else { return }
                guard Self.levelChanged(value, from: &self.lastBacklight) else { return }
                self.sendKeyboardBacklightNotification(value: value)
            }
        } else {
            keyboardBacklightController.onBacklightChange = nil
        }
    }
}

private extension SystemChangesObserver {
    func volumeStep(for step: MediaKeyStep) -> Float {
        switch step {
        case .standard:
            return standardVolumeStep
        case .fine:
            return fineVolumeStep
        }
    }

    func brightnessStep(for step: MediaKeyStep) -> Float {
        switch step {
        case .standard:
            return standardBrightnessStep
        case .fine:
            return fineBrightnessStep
        }
    }
}

