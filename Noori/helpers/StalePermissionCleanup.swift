/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import ApplicationServices
import Defaults
import Foundation
import Security

/// Clears a stale Accessibility entry after Noori's code signature changes.
///
/// macOS ties the Accessibility permission to the app's signature. When the
/// signature changes (1.2.1 moved from ad-hoc to a certificate), the old
/// "Noori" entry stays in System Settings, still switched on, but no longer
/// applies, and asking again doesn't replace it: the brightness keys stopped
/// working until the old entry was removed by hand. When the signature is new
/// and Accessibility isn't working, Noori removes its own entry first, so the
/// prompt that follows adds a fresh one that works.
enum StalePermissionCleanup {
    /// Run once at launch, before anything asks for Accessibility.
    static func run() {
        guard let requirement = currentDesignatedRequirement() else { return }
        defer { Defaults[.lastSigningRequirement] = requirement }

        let previous = Defaults[.lastSigningRequirement]
        guard previous != requirement, !AXIsProcessTrusted(),
              let bundleID = Bundle.main.bundleIdentifier else { return }

        // Only Noori's own entry; harmless when there is none.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            NSLog("Noori's signature changed; cleared its old Accessibility entry")
        } catch {
            NSLog("Couldn't clear the old Accessibility entry: \(error)")
        }
    }

    /// The running app's designated requirement as text (it names the bundle id
    /// and the signing certificate, or for ad-hoc builds the exact build).
    private static func currentDesignatedRequirement() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return nil }
        return text as String
    }
}
