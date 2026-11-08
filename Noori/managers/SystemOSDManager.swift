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
import AppKit
import os

class SystemOSDManager {
    private init() {}

    // Tracks the PID we most recently suspended. macOS jetsam-exits OSDUIHelper
    // when idle and launchd respawns it on the next media-key press as a fresh
    // process, so we need to re-SIGSTOP every new incarnation.
    private struct SuppressionState {
        var task: Task<Void, Never>?
        var lastSuspendedPID: Int32 = -1
        // True while suppressing the native OSD (between disable/enableSystemHUD).
        var active = false
        // True while the Mac is asleep — watcher pauses, not cancelled.
        var systemSleeping = false
        // Invalidates asynchronous enable/disable work left over from an older
        // settings state. HUD style switches update several Defaults in quick
        // succession, so those transitions must not race each other.
        var transitionGeneration: UInt64 = 0
        // Coalesces immediate suppression requests from a key event and its
        // resulting system-value notification.
        var immediateSuppressionInFlight = false
    }
    private static let suppressionState = OSAllocatedUnfairLock(initialState: SuppressionState())

    /// Call once at startup to register sleep/wake observers.
    /// Safe to call multiple times — observers are registered only once.
    private static let sleepWakeSetupOnce: Void = {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            handleSystemSleep()
        }
        nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            handleSystemWake()
        }
    }()

    // MARK: - Sleep / Wake

    private static func handleSystemSleep() {
        // Mark as sleeping so the watcher loop exits its current poll immediately.
        suppressionState.withLock { $0.systemSleeping = true }
        // Stop the watcher task while sleeping.
        stopSuppressionWatcher()
    }

    private static func handleSystemWake() {
        suppressionState.withLock { $0.systemSleeping = false }
        // If suppression was still active when we went to sleep, restart the watcher.
        let active = suppressionState.withLock { $0.active }
        if active {
            // Reset the last-suspended PID so the watcher immediately re-suspends
            // the fresh OSDUIHelper that launchd may have spawned during wake.
            suppressionState.withLock { $0.lastSuspendedPID = -1 }
            startSuppressionWatcher()
        }
    }

    // MARK: - Public API

    /// True while Noori is hiding the native macOS OSD.
    public static var isSuppressingNativeOSD: Bool {
        suppressionState.withLock { $0.active }
    }

    /// Re-enables the system HUD by restarting OSDUIHelper
    public static func enableSystemHUD() {
        let generation = suppressionState.withLock { state -> UInt64 in
            state.active = false
            state.transitionGeneration &+= 1
            return state.transitionGeneration
        }
        stopSuppressionWatcher()
        Task.detached(priority: .background) {
            await enableSystemHUDAsync(generation: generation)
        }
    }
    
    private static func enableSystemHUDAsync(generation: UInt64) async {
        guard isCurrentTransition(generation, active: false) else { return }

        do {
            // First, stop any existing (possibly suspended) OSDUIHelper process
            for pid in osduiHelperPIDs() {
                kill(pid, SIGKILL)
            }

            guard isCurrentTransition(generation, active: false) else { return }
            
            // Small delay to ensure process is fully stopped
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            guard isCurrentTransition(generation, active: false) else { return }
            
            // Then kickstart it again to ensure it's running properly
            let kickstart = Process()
            kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            kickstart.arguments = ["kickstart", "gui/\(getuid())/com.apple.OSDUIHelper"]
            try kickstart.run()
            kickstart.waitUntilExit()

            // A replacement HUD may have been selected while launchctl was
            // running. In that case the current suppression transition owns the
            // helper; stop this stale restoration immediately.
            guard isCurrentTransition(generation, active: false) else {
                suppressNativeOSDNow()
                return
            }
            
            // Additional delay to ensure service is fully started
            try await Task.sleep(nanoseconds: 300_000_000) // 300ms
            guard isCurrentTransition(generation, active: false) else { return }
            
            await MainActor.run {
                print("✅ System HUD re-enabled")
            }
        } catch {
            guard isCurrentTransition(generation, active: false) else { return }
            await MainActor.run {
                NSLog("❌ Error while trying to re-enable OSDUIHelper: \(error)")
            }
            
            // Fallback: Try to restart the service using launchctl load
            do {
                let fallbackTask = Process()
                fallbackTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                fallbackTask.arguments = ["load", "-w", "/System/Library/LaunchAgents/com.apple.OSDUIHelper.plist"]
                try fallbackTask.run()
                fallbackTask.waitUntilExit()

                guard isCurrentTransition(generation, active: false) else {
                    suppressNativeOSDNow()
                    return
                }
                
                await MainActor.run {
                    print("✅ System HUD re-enabled via fallback method")
                }
            } catch {
                await MainActor.run {
                    NSLog("❌ Fallback method also failed: \(error)")
                }
            }
        }
    }

    /// Synchronously resumes OSDUIHelper for app termination.
    ///
    /// `enableSystemHUD()` restarts the helper on a detached background `Task`,
    /// which never runs to completion when the process is already terminating —
    /// so a SIGSTOP-frozen OSDUIHelper stays frozen after Noori quits, breaking
    /// every native OSD Noori does not replace (keyboard backlight,
    /// external-display brightness, …) and leaving a stuck HUD on screen. This
    /// sends SIGCONT inline and blocks until it lands, guaranteeing the helper
    /// is resumed before Noori exits. Idempotent; safe to call from a
    /// termination handler.
    public static func resumeOSDUIHelperForTermination() {
        suppressionState.withLock { state in
            state.active = false
            state.transitionGeneration &+= 1
        }

        // Cancel the watcher and wait for it to fully exit before resuming. A
        // bare cancel is cooperative, so an in-flight suspendOSDUIHelper() could
        // otherwise land its SIGSTOP after our SIGCONT and re-freeze the helper.
        // Bridge the async drain to this synchronous path with a bounded wait.
        if let watcher = stopSuppressionWatcher() {
            let drained = DispatchSemaphore(value: 0)
            Task { await watcher.value; drained.signal() }
            _ = drained.wait(timeout: .now() + 1.0)
        }

        resumeOSDUIHelperProcess()
    }

    /// Disables the system HUD by stopping OSDUIHelper, and starts a
    /// background watcher that re-suspends any future incarnation launchd
    /// spawns (macOS auto-exits OSDUIHelper on idle).
    public static func disableSystemHUD() {
        // Ensure sleep/wake observers are registered.
        _ = sleepWakeSetupOnce
        let generation = suppressionState.withLock { state -> UInt64 in
            state.active = true
            state.transitionGeneration &+= 1
            return state.transitionGeneration
        }
        Task.detached(priority: .background) {
            await disableSystemHUDAsync(generation: generation)
        }
        startSuppressionWatcher()
    }

    /// Immediately SIGSTOPs OSDUIHelper, bypassing the 150ms watcher poll. The
    /// CoreAudio volume write wakes/respawns the helper to draw the native OSD
    /// (brightness's private APIs never do), and the watcher can lose that race.
    /// No-op unless suppression is active.
    public static func suppressNativeOSDNow() {
        let generation = suppressionState.withLock { state -> UInt64? in
            guard state.active, !state.immediateSuppressionInFlight else { return nil }
            state.immediateSuppressionInFlight = true
            return state.transitionGeneration
        }
        guard let generation else { return }

        Task.detached(priority: .userInitiated) {
            defer {
                suppressionState.withLock { $0.immediateSuppressionInFlight = false }
            }

            guard isCurrentTransition(generation, active: true) else { return }
            if let pid = osduiHelperPID() {
                let lastPID = suppressionState.withLock { $0.lastSuspendedPID }
                if pid == lastPID {
                    return
                }
            }

            guard isCurrentTransition(generation, active: true) else { return }
            suspendOSDUIHelper()

            // If the user disabled Noori's HUD replacement while SIGSTOP was in
            // flight, undo that stale suppression immediately. The current
            // restoration transition will still perform its clean restart.
            guard isCurrentTransition(generation, active: true) else {
                resumeOSDUIHelperProcess()
                return
            }

            if let pid = osduiHelperPID() {
                suppressionState.withLock { $0.lastSuspendedPID = pid }
            }
        }
    }
    
    private static func disableSystemHUDAsync(generation: UInt64) async {
        guard isCurrentTransition(generation, active: true) else { return }

        do {
            let kickstart = Process()
            kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            // Force a clean helper instance. A plain kickstart is a no-op when
            // OSDUIHelper is already running, and macOS may replace that lingering
            // process on the first media key, briefly exposing the native HUD.
            kickstart.arguments = ["kickstart", "-k", "gui/\(getuid())/com.apple.OSDUIHelper"]
            try kickstart.run()
            kickstart.waitUntilExit()

            guard isCurrentTransition(generation, active: true) else { return }

            // launchctl kickstart returns once the request is queued, not after
            // OSDUIHelper has actually forked. At cold boot the helper can take
            // a while to appear — a fixed sleep races and the SIGSTOP misses,
            // letting the native OSD render on the first volume/brightness key.
            // Poll for the PID up to ~5s, then suspend, and retry if launchd
            // respawned a fresh copy between kickstart and SIGSTOP.
            var attempts = 0
            while attempts < 3 {
                guard isCurrentTransition(generation, active: true) else { return }
                let appeared = await waitForOSDUIHelper(timeoutMillis: 5000)
                guard isCurrentTransition(generation, active: true) else { return }
                if !appeared {
                    await MainActor.run {
                        NSLog("⚠️ OSDUIHelper did not appear within timeout; retrying SIGSTOP anyway")
                    }
                }

                suspendOSDUIHelper()

                // Settle, then confirm a process is actually present (and thus
                // suspended). If none is running, launchd hasn't spawned it yet
                // or the prior STOP raced — loop and try again.
                try await Task.sleep(nanoseconds: 250_000_000) // 250ms
                guard isCurrentTransition(generation, active: true) else { return }
                if let pid = osduiHelperPID() {
                    suppressionState.withLock { $0.lastSuspendedPID = pid }
                    break
                }
                attempts += 1
            }

            if isCurrentTransition(generation, active: true) {
                await MainActor.run {
                    print("✅ System HUD disabled")
                }
            }
        } catch {
            guard isCurrentTransition(generation, active: true) else { return }
            await MainActor.run {
                NSLog("❌ Error while trying to hide OSDUIHelper: \(error)")
            }
        }
    }

    /// Polls for an OSDUIHelper process, returning true as soon as one appears
    /// or false if `timeoutMillis` elapses with no match.
    private static func waitForOSDUIHelper(timeoutMillis: Int) async -> Bool {
        let pollIntervalNanos: UInt64 = 200_000_000 // 200ms
        let maxAttempts = max(1, timeoutMillis / 200)
        for _ in 0..<maxAttempts {
            if isOSDUIHelperRunning() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanos)
        }
        return isOSDUIHelperRunning()
    }

    private static func isCurrentTransition(_ generation: UInt64, active: Bool) -> Bool {
        suppressionState.withLock {
            $0.transitionGeneration == generation && $0.active == active
        }
    }

    /// Background loop that catches OSDUIHelper respawns. macOS exits the
    /// helper after a short idle period (JETSAM_REASON_MEMORY_IDLE_EXIT) and
    /// launchd spins up a brand-new process on the next volume/brightness
    /// keypress — that fresh PID renders the native OSD before any one-shot
    /// SIGSTOP can hit it. While a suspended helper exists the loop just waits
    /// for it to exit (no polling); only when no helper is running does it
    /// check every 150ms, using in-process lookups instead of spawning pgrep.
    ///
    /// The loop exits immediately when the Mac sleeps (systemSleeping == true)
    /// and is restarted by handleSystemWake() when the machine wakes up again.
    private static func startSuppressionWatcher() {
        let newTask = Task.detached(priority: .background) {
            while !Task.isCancelled {
                // Pause the watcher entirely while the system is asleep.
                // handleSystemWake() will cancel this task and spawn a fresh one.
                let sleeping = suppressionState.withLock { $0.systemSleeping }
                if sleeping {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                    continue
                }

                if let pid = osduiHelperPID() {
                    let lastPID = suppressionState.withLock { $0.lastSuspendedPID }
                    if pid != lastPID {
                        suspendOSDUIHelper()
                        suppressionState.withLock { $0.lastSuspendedPID = pid }
                    }
                    // The helper is suspended: sleep until it exits (jetsam or
                    // launchd restart) instead of polling. The timeout is a safety net.
                    await waitForProcessExit(pid: pid, timeoutSeconds: 5)
                } else {
                    // No helper yet: check again shortly so a fresh one is caught fast.
                    try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                }
            }
        }

        let previous = suppressionState.withLock { state -> Task<Void, Never>? in
            let prior = state.task
            state.task = newTask
            return prior
        }
        previous?.cancel()
    }

    /// Cancels the suppression watcher. Returns the cancelled task so callers
    /// that must not race it (e.g. termination) can wait for it to fully exit.
    @discardableResult
    private static func stopSuppressionWatcher() -> Task<Void, Never>? {
        let previous = suppressionState.withLock { state -> Task<Void, Never>? in
            let prior = state.task
            state.task = nil
            state.lastSuspendedPID = -1
            return prior
        }
        previous?.cancel()
        return previous
    }

    /// PIDs of all running OSDUIHelper processes, found in-process (no pgrep spawn).
    private static func osduiHelperPIDs() -> [pid_t] {
        let capacity = Int(proc_listallpids(nil, 0)) + 32
        guard capacity > 32 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [] }

        var nameBuffer = [CChar](repeating: 0, count: 64)
        var matches: [pid_t] = []
        for pid in pids.prefix(min(count, capacity)) where pid > 0 {
            let length = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            guard length > 0 else { continue }
            if String(cString: nameBuffer) == "OSDUIHelper" {
                matches.append(pid)
            }
        }
        return matches
    }

    /// Returns the newest OSDUIHelper PID (latest start time), or nil if none.
    private static func osduiHelperPID() -> Int32? {
        osduiHelperPIDs().max { startTime(of: $0) < startTime(of: $1) }
    }

    private static func startTime(of pid: pid_t) -> Double {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
        return Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000
    }

    /// Sends SIGSTOP to all OSDUIHelper processes. Idempotent.
    private static func suspendOSDUIHelper() {
        for pid in osduiHelperPIDs() {
            kill(pid, SIGSTOP)
        }
    }

    /// Sends SIGCONT to all OSDUIHelper processes. Idempotent.
    private static func resumeOSDUIHelperProcess() {
        for pid in osduiHelperPIDs() {
            kill(pid, SIGCONT)
        }
    }

    /// Check if OSDUIHelper is currently running
    public static func isOSDUIHelperRunning() -> Bool {
        !osduiHelperPIDs().isEmpty
    }

    /// Suspends until `pid` exits, the task is cancelled, or the timeout passes.
    private static func waitForProcessExit(pid: pid_t, timeoutSeconds: Double) async {
        // Holds the "finish" closure so the cancellation handler can wake this wait.
        let finishHook = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(initialState: nil)

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let source = DispatchSource.makeProcessSource(
                    identifier: pid,
                    eventMask: .exit,
                    queue: .global(qos: .background)
                )
                let done = OSAllocatedUnfairLock(initialState: false)
                let finish: @Sendable () -> Void = {
                    let first = done.withLock { finished -> Bool in
                        defer { finished = true }
                        return !finished
                    }
                    guard first else { return }
                    source.cancel()
                    continuation.resume()
                }
                finishHook.withLock { $0 = finish }
                source.setEventHandler(handler: finish)
                source.resume()
                // The process may have exited before the source was armed.
                if kill(pid, 0) != 0 { finish() }
                DispatchQueue.global(qos: .background).asyncAfter(
                    deadline: .now() + timeoutSeconds,
                    execute: finish
                )
                if Task.isCancelled { finish() }
            }
        } onCancel: {
            finishHook.withLock { $0 }?()
        }
    }

    /// Async version of status checking to avoid main thread blocking
    public static func isOSDUIHelperRunningAsync() async -> Bool {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .background) {
                let result = isOSDUIHelperRunning()
                continuation.resume(returning: result)
            }
        }
    }
}
