/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import Combine
import CoreAudio
import Defaults
import Foundation

/// Notices when a voice or video call is going on in a known call app
/// (WhatsApp, FaceTime, Zoom, Teams, Discord, Slack, Telegram) so the closed
/// notch can show the call pill.
///
/// It reads Core Audio's per-process objects (macOS 14.2+): a call is an app
/// whose processes have both microphone input and audio output running. No
/// audio is captured and no permission is needed; Core Audio only says whether
/// each process's input/output is running. Changes arrive through property
/// listeners, so nothing runs while no call app is using audio.
@MainActor
final class CallActivityManager: ObservableObject {
    static let shared = CallActivityManager()

    /// A call has been going for at least `minimumCallDuration`.
    @Published private(set) var isCallActive = false
    /// When the call's audio started (the pill's timer counts from here).
    @Published private(set) var callStartDate: Date?
    /// The known call app the call is in.
    @Published private(set) var activeApp: CallApp?

    struct CallApp: Equatable {
        let name: String
        /// Bundle ids of the app and its helpers (matched exactly or as a
        /// prefix followed by a dot, e.g. `net.whatsapp.WhatsApp.ServiceExtension`).
        let processBundleIDs: [String]
        /// Bundle ids of the app itself, used to bring it to the front.
        let appBundleIDs: [String]

        func matches(_ bundleID: String) -> Bool {
            processBundleIDs.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
        }
    }

    static let knownApps: [CallApp] = [
        CallApp(name: "WhatsApp",
                processBundleIDs: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"],
                appBundleIDs: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]),
        // FaceTime (and iPhone calls relayed to the Mac) run their audio in avconferenced.
        CallApp(name: "FaceTime",
                processBundleIDs: ["com.apple.FaceTime", "com.apple.avconferenced"],
                appBundleIDs: ["com.apple.FaceTime"]),
        CallApp(name: "Zoom",
                processBundleIDs: ["us.zoom.xos"],
                appBundleIDs: ["us.zoom.xos"]),
        CallApp(name: "Microsoft Teams",
                processBundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"],
                appBundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"]),
        CallApp(name: "Discord",
                processBundleIDs: ["com.hnc.Discord"],
                appBundleIDs: ["com.hnc.Discord"]),
        CallApp(name: "Slack",
                processBundleIDs: ["com.tinyspeck.slackmacgap"],
                appBundleIDs: ["com.tinyspeck.slackmacgap"]),
        CallApp(name: "Telegram",
                processBundleIDs: ["ru.keepcoder.Telegram"],
                appBundleIDs: ["ru.keepcoder.Telegram"]),
    ]

    /// The mic has to stay on this long before the pill shows, so voice notes
    /// and short mic blips don't flash it.
    private let minimumCallDuration: TimeInterval = 3
    /// The audio has to stay off this long before the pill goes away.
    private let endDebounce: TimeInterval = 1.2
    /// While a call is showing or about to, re-check this often in case a
    /// listener notification is missed.
    private let safetyCheckInterval: TimeInterval = 2

    private var isMonitoring = false
    private var pendingStartApp: CallApp?
    private var pendingStartDate: Date?
    private var startWork: DispatchWorkItem?
    private var endWork: DispatchWorkItem?
    private var safetyTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private var processListListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [(AudioObjectID, AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []

    private init() {
        guard !AppRuntimeEnvironment.isUITesting else { return }
        Defaults.publisher(.showCallLiveActivity)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                MainActor.assumeIsolated {
                    if enabled { self?.startMonitoring() } else { self?.stopMonitoring() }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isMonitoring else { return }
        guard #available(macOS 14.2, *) else { return }
        isMonitoring = true

        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.processListChanged()
            }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
            processListListener = block
        }
        processListChanged()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        if let block = processListListener {
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            processListListener = nil
        }
        removeProcessListeners()
        cancelPendingStart()
        endWork?.cancel()
        endWork = nil
        endCall()
    }

    /// Brings the app the call is in to the front.
    func bringCallAppToFront() {
        guard let app = activeApp else { return }
        let running = NSWorkspace.shared.runningApplications.first { candidate in
            guard let id = candidate.bundleIdentifier else { return false }
            return app.appBundleIDs.contains(id) && candidate.activationPolicy == .regular
        }
        if let running {
            running.unhide()
            running.activate()
        } else if let id = app.appBundleIDs.first,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Listeners

    private func processListChanged() {
        guard isMonitoring else { return }
        removeProcessListeners()

        // Listen to the input/output state of the known call apps' processes only.
        for processID in Self.processObjectIDs() {
            guard let bundleID = Self.bundleID(of: processID),
                  Self.knownApps.contains(where: { $0.matches(bundleID) }) else { continue }
            for selector in [kAudioProcessPropertyIsRunningInput, kAudioProcessPropertyIsRunningOutput] {
                var address = Self.address(selector)
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    MainActor.assumeIsolated {
                        self?.evaluate()
                    }
                }
                if AudioObjectAddPropertyListenerBlock(processID, &address, .main, block) == noErr {
                    processListeners.append((processID, selector, block))
                }
            }
        }
        evaluate()
    }

    private func removeProcessListeners() {
        for (processID, selector, block) in processListeners {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListenerBlock(processID, &address, .main, block)
        }
        processListeners.removeAll()
    }

    // MARK: - Call state

    /// The known app that has both mic input and audio output running right now.
    private func currentCallApp() -> CallApp? {
        var input = Set<Int>()
        var output = Set<Int>()
        for processID in Self.processObjectIDs() {
            guard let bundleID = Self.bundleID(of: processID),
                  let index = Self.knownApps.firstIndex(where: { $0.matches(bundleID) }) else { continue }
            if Self.boolProperty(kAudioProcessPropertyIsRunningInput, of: processID) { input.insert(index) }
            if Self.boolProperty(kAudioProcessPropertyIsRunningOutput, of: processID) { output.insert(index) }
        }
        // Output is required too: recording a voice note uses the mic but plays nothing.
        guard let index = input.intersection(output).min() else { return nil }
        return Self.knownApps[index]
    }

    private func evaluate() {
        guard isMonitoring else { return }
        let app = currentCallApp()

        if let app {
            endWork?.cancel()
            endWork = nil
            if isCallActive {
                if activeApp != app { activeApp = app }
            } else if pendingStartApp == nil {
                pendingStartApp = app
                pendingStartDate = Date()
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.confirmStart() }
                }
                startWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + minimumCallDuration, execute: work)
            } else {
                pendingStartApp = app
            }
        } else {
            cancelPendingStart()
            if isCallActive && endWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.confirmEnd() }
                }
                endWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + endDebounce, execute: work)
            }
        }
        updateSafetyTimer()
    }

    private func confirmStart() {
        startWork = nil
        guard isMonitoring, let app = currentCallApp() else {
            cancelPendingStart()
            updateSafetyTimer()
            return
        }
        activeApp = app
        callStartDate = pendingStartDate ?? Date()
        pendingStartApp = nil
        pendingStartDate = nil
        isCallActive = true
        updateSafetyTimer()
    }

    private func confirmEnd() {
        endWork = nil
        if currentCallApp() == nil {
            endCall()
        }
        updateSafetyTimer()
    }

    private func endCall() {
        if isCallActive { isCallActive = false }
        callStartDate = nil
        activeApp = nil
        updateSafetyTimer()
    }

    private func cancelPendingStart() {
        startWork?.cancel()
        startWork = nil
        pendingStartApp = nil
        pendingStartDate = nil
    }

    private func updateSafetyTimer() {
        let needed = isMonitoring && (isCallActive || pendingStartApp != nil)
        if needed, safetyTimer == nil {
            let timer = Timer(timeInterval: safetyCheckInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            safetyTimer = timer
        } else if !needed, let timer = safetyTimer {
            timer.invalidate()
            safetyTimer = nil
        }
    }

    // MARK: - Core Audio helpers

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func processObjectIDs() -> [AudioObjectID] {
        guard #available(macOS 14.2, *) else { return [] }
        var address = address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func bundleID(of processID: AudioObjectID) -> String? {
        guard #available(macOS 14.2, *) else { return nil }
        var address = address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(processID, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() as String?,
              !string.isEmpty else { return nil }
        return string
    }

    private static func boolProperty(_ selector: AudioObjectPropertySelector, of processID: AudioObjectID) -> Bool {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(processID, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }
}
