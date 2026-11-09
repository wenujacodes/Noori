/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import CoreBluetooth
import Foundation

/// Watches whether Bluetooth is on and reports changes (not the state at launch).
final class BluetoothPowerMonitor: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager?
    /// Last known on/off state; nil until CoreBluetooth reports the first one.
    private var isPoweredOn: Bool?
    private let onChange: (Bool) -> Void

    /// `onChange` runs on the main queue with true for on, false for off.
    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init()
        // No system alert asking to turn Bluetooth on when it's off.
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let poweredOn: Bool
        switch central.state {
        case .poweredOn:
            poweredOn = true
        case .poweredOff:
            poweredOn = false
        default:
            // .resetting, .unauthorized, .unsupported, .unknown: not an on/off change.
            return
        }

        defer { isPoweredOn = poweredOn }
        guard let previous = isPoweredOn, previous != poweredOn else { return }
        onChange(poweredOn)
    }
}
