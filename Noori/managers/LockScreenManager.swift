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

import AppKit
import Combine
import SwiftUI

/// Tracks whether the Mac's screen is locked so the notch can stay out of the way
/// while locked (closes the notch and hides sneak peeks / HUDs on lock).
@MainActor
class LockScreenManager: ObservableObject {
    static let shared = LockScreenManager()

    private let coordinator = NooriViewCoordinator.shared
    private weak var viewModel: NooriViewModel?

    @Published var isLocked: Bool = false
    /// Kept for the music HUD logic in ContentView; Noori no longer delays it after unlock.
    @Published var shouldDelayPostUnlockMusicHUD: Bool = false

    private var lockStatePollTask: Task<Void, Never>?

    private init() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        center.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)
        // macOS sometimes delays `screenIsUnlocked`; session-active usually fires earlier.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screenUnlocked), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        lockStatePollTask?.cancel()
    }

    func configure(viewModel: NooriViewModel) {
        self.viewModel = viewModel
    }

    var currentLockStatus: Bool { isLocked }

    @objc private func screenLocked() {
        guard !isLocked else { return }
        Logger.log("LockScreenManager: Screen locked", category: .lifecycle)
        isLocked = true
        viewModel?.closeForLockScreen()

        if coordinator.expandingView.show {
            coordinator.toggleExpandingView(status: false, type: coordinator.expandingView.type)
        }
        if coordinator.sneakPeek.show {
            coordinator.toggleSneakPeek(status: false, type: coordinator.sneakPeek.type)
        }
        LockScreenIndicatorWindowManager.shared.showLocked()
        startLockStatePolling()
    }

    @objc private func screenUnlocked() {
        guard isLocked else { return }
        Logger.log("LockScreenManager: Screen unlocked", category: .lifecycle)
        isLocked = false
        LockScreenIndicatorWindowManager.shared.showUnlockedAndHide()
        stopLockStatePolling()
    }

    // Fallback for late/missed unlock notifications: poll the session lock state while locked.
    private static func isSessionScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private func startLockStatePolling() {
        lockStatePollTask?.cancel()
        lockStatePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
                await MainActor.run {
                    guard let self, self.isLocked else { return }
                    if !Self.isSessionScreenLocked() {
                        self.screenUnlocked()
                    }
                }
            }
        }
    }

    private func stopLockStatePolling() {
        lockStatePollTask?.cancel()
        lockStatePollTask = nil
    }
}
