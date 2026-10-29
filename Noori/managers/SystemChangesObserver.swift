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
    private let volumeFeedbackPlayer = VolumeFeedbackPlayer.shared

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
    private var brightnessEnabled = false
    private var keyboardBacklightEnabled = false

    init(coordinator: NooriViewCoordinator) {
        self.coordinator = coordinator
    }

    func startObserving(volumeEnabled: Bool, brightnessEnabled: Bool, keyboardBacklightEnabled: Bool) {
        self.volumeEnabled = volumeEnabled
        self.brightnessEnabled = brightnessEnabled
        self.keyboardBacklightEnabled = keyboardBacklightEnabled

        volumeController.onVolumeChange = { [weak self] volume, muted in
            guard let self, self.volumeEnabled else { return }
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

        brightnessController.onBrightnessChange = { [weak self] brightness in
            guard let self, self.brightnessEnabled else { return }
            self.sendBrightnessNotification(value: brightness)
        }
        brightnessController.start()

        configureKeyboardBacklightCallback()
        if keyboardBacklightEnabled {
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
        volumeController.adjust(by: delta)
        volumeFeedbackPlayer.playIfNeeded()
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
        if isBacklight {
            keyboardBacklightController.adjust(by: delta)
        } else {
            brightnessController.adjust(by: delta)
        }
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

private final class VolumeFeedbackPlayer {
    static let shared = VolumeFeedbackPlayer()

    private let queue = DispatchQueue(label: "com.wenujacodes.noori.volume-feedback-player")
    private var player: AVAudioPlayer?
    private var lastPlayDate: Date = .distantPast
    private let minimumInterval: TimeInterval = 0.08
    private var didLogMissingAsset = false

    private init() {}

    func playIfNeeded() {
        guard Defaults[.playVolumeChangeFeedback] else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            guard now.timeIntervalSince(self.lastPlayDate) >= self.minimumInterval else { return }
            self.lastPlayDate = now
            self.preparePlayerIfNeeded()
            guard let player = self.player else { return }
            player.currentTime = 0
            player.play()
        }
    }

    private func preparePlayerIfNeeded() {
        if player != nil { return }
        guard let url = Bundle.main.url(forResource: "audio-feedback", withExtension: "m4a") else {
            if !didLogMissingAsset {
                NSLog("⚠️ audio-feedback.m4a is missing from the app bundle; volume feedback disabled.")
                didLogMissingAsset = true
            }
            return
        }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.volume = 1
            audioPlayer.prepareToPlay()
            player = audioPlayer
        } catch {
            if !didLogMissingAsset {
                NSLog("⚠️ Failed to initialize volume feedback player: \(error.localizedDescription)")
                didLogMissingAsset = true
            }
        }
    }
}
