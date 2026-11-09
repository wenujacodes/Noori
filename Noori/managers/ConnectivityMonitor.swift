/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import CoreWLAN
import Defaults
import Foundation
import SwiftUI

/// What the connectivity HUD shows: "<title> · <status>", e.g. "Wi-Fi · Off".
@MainActor
final class ConnectivityHUDState: ObservableObject {
    static let shared = ConnectivityHUDState()
    @Published var title = ""
    @Published var status = ""
    /// Green for on/connected states, red for off/disconnected.
    @Published var isPositive = true
}

/// Watches Wi-Fi (on/off, connected/disconnected) and the AirDrop setting, and
/// shows a notch HUD when one changes. The Wi-Fi network name isn't shown: macOS
/// only gives it to apps with Location permission, which Noori doesn't ask for.
@MainActor
final class ConnectivityMonitor: NSObject {
    static let shared = ConnectivityMonitor()

    private let hudDuration: TimeInterval = 2.5

    // Wi-Fi
    private let wifiClient = CWWiFiClient.shared()
    private var wifiPowerOn: Bool?
    private var wifiConnected: Bool?
    private var wifiLinkCheck: DispatchWorkItem?

    // AirDrop
    private var airDropMode: String?
    private var airDropTimer: Timer?

    private override init() {
        super.init()
    }

    func start() {
        startWiFi()
        startAirDrop()
    }

    // MARK: - Wi-Fi

    private func startWiFi() {
        let interface = wifiClient.interface()
        wifiPowerOn = interface?.powerOn()
        wifiConnected = interface.map(Self.isAssociated)
        wifiClient.delegate = self
        try? wifiClient.startMonitoringEvent(with: .powerDidChange)
        try? wifiClient.startMonitoringEvent(with: .linkDidChange)
    }

    /// True while joined to a network. Works without Location permission
    /// (unlike the network name).
    nonisolated private static func isAssociated(_ interface: CWInterface) -> Bool {
        interface.powerOn() && (interface.rssiValue() != 0 || interface.transmitRate() > 0)
    }

    private func handleWiFiPowerChange() {
        guard let interface = wifiClient.interface() else { return }
        let isOn = interface.powerOn()
        guard isOn != wifiPowerOn else { return }
        wifiPowerOn = isOn
        // Turning Wi-Fi off also drops the network; the Off HUD covers that.
        wifiConnected = Self.isAssociated(interface)
        show(title: "Wi-Fi", status: isOn ? "On" : "Off", isPositive: isOn,
             icon: "wifi", enabled: Defaults[.showWiFiChanges])
    }

    /// Link events come in bursts while joining or leaving; check once things settle.
    private func scheduleWiFiLinkCheck() {
        wifiLinkCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.handleWiFiLinkChange() }
        }
        wifiLinkCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func handleWiFiLinkChange() {
        guard let interface = wifiClient.interface(), interface.powerOn(), wifiPowerOn == true else { return }
        let connected = Self.isAssociated(interface)
        guard connected != wifiConnected else { return }
        wifiConnected = connected
        show(title: "Wi-Fi", status: connected ? "Connected" : "Disconnected", isPositive: connected,
             icon: "wifi", enabled: Defaults[.showWiFiChanges])
    }

    // MARK: - AirDrop

    private func startAirDrop() {
        airDropMode = Self.readAirDropMode()
        // sharingd posts no public notification for this setting, so check it
        // every couple of seconds (a cheap preferences read).
        airDropTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { ConnectivityMonitor.shared.checkAirDrop() }
        }
    }

    /// "Off", "Contacts Only" or "Everyone" (sometimes "Everyone for 10 Minutes").
    nonisolated private static func readAirDropMode() -> String? {
        let domain = "com.apple.sharingd" as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("DiscoverableMode" as CFString, domain) as? String
    }

    private func checkAirDrop() {
        let mode = Self.readAirDropMode()
        guard let mode, mode != airDropMode else { return }
        let hadValue = airDropMode != nil
        airDropMode = mode
        guard hadValue else { return }

        let isOff = mode == "Off"
        let status: String
        switch mode {
        case "Off": status = String(localized: "Off")
        case "Contacts Only": status = String(localized: "Contacts Only")
        default: status = String(localized: "Everyone")
        }
        show(title: "AirDrop", status: status, isPositive: !isOff,
             icon: "dot.radiowaves.up.forward", enabled: Defaults[.showAirDropChanges])
    }

    // MARK: - HUD

    private func show(title: String, status: String, isPositive: Bool, icon: String, enabled: Bool) {
        guard enabled else { return }
        let state = ConnectivityHUDState.shared
        state.title = title
        state.status = status
        state.isPositive = isPositive
        NooriViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .connectivity,
            duration: hudDuration,
            value: 0,
            icon: icon
        )
    }
}

extension ConnectivityMonitor: CWEventDelegate {
    nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { ConnectivityMonitor.shared.handleWiFiPowerChange() }
        }
    }

    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { ConnectivityMonitor.shared.scheduleWiFiLinkCheck() }
        }
    }
}
