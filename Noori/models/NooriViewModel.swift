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

import Combine
import Defaults
import SwiftUI

@MainActor
class NooriViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = NooriViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: NooriAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    var cancellables: Set<AnyCancellable> = []

    /// Teardown hook ContentView registers in `onAppear`; the window-cleanup path
    /// invokes it before closing the panel since `.onDisappear` is unreliable for
    /// borderless panels, preventing leaked hover-polling Tasks from accumulating.
    var onViewTeardown: (() -> Void)?
    
    @Published var hideOnClosed: Bool = true
    @Published var isMediaOutputPopoverActive: Bool = false
    @Published var shouldRecheckHover: Bool = false
    @Published var isScrollGestureActive: Bool = false
    private var scrollGestureSuppressionTokens: Set<UUID> = []
    @Published private(set) var isAutoCloseSuppressed: Bool = false
    private var autoCloseSuppressionTokens: Set<UUID> = []

    func setScrollGestureSuppression(_ active: Bool, token: UUID) {
        if active {
            let inserted = scrollGestureSuppressionTokens.insert(token).inserted
            if inserted {
                isScrollGestureActive = true
            }
        } else {
            if scrollGestureSuppressionTokens.remove(token) != nil {
                isScrollGestureActive = !scrollGestureSuppressionTokens.isEmpty
            }
        }
    }

    private func resetScrollGestureSuppression() {
        scrollGestureSuppressionTokens.removeAll()
        isScrollGestureActive = false
    }

    func setAutoCloseSuppression(_ active: Bool, token: UUID) {
        if active {
            let inserted = autoCloseSuppressionTokens.insert(token).inserted
            if inserted {
                isAutoCloseSuppressed = true
            }
        } else if autoCloseSuppressionTokens.remove(token) != nil {
            isAutoCloseSuppressed = !autoCloseSuppressionTokens.isEmpty
        }
    }

    private func resetAutoCloseSuppression() {
        autoCloseSuppressionTokens.removeAll()
        isAutoCloseSuppressed = false
    }

    

    @Published var screen: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()
    
    @MainActor
    deinit {
        destroy()
    }

    func destroy() {
        onViewTeardown?()
        onViewTeardown = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screen: String? = nil) {
        animation = animationLibrary.animation

        super.init()
        
        self.screen = screen
        notchSize = getClosedNotchSize(screen: screen)
        closedNotchSize = notchSize

        setupDetectorObserver()

    }

    
    private func setupDetectorObserver() {
        // 1) Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.enableFullscreenMediaDetection)
            .map(\.newValue)

        // 2) For each non‑nil screen name, map to a Bool publisher for that screen's status
        let statusPublisher = $screen
            .compactMap { $0 }
            .removeDuplicates()
            .map { screenName in
                self.detector.$fullscreenStatus
                    .map { $0[screenName] ?? false }
                    .removeDuplicates()
            }
            .switchToLatest()

        // 3) Combine enabled & status, animate only on changes
        Publishers.CombineLatest(statusPublisher, enabledPublisher)
            .map { status, enabled in enabled && status }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }
    
    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = NSScreen.screens.first { $0.localizedName == screen }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screen)
        if let frame = screenFrame {
            
            let baseY = frame.maxY - notchSize.height
            let baseX = frame.midX - notchSize.width / 2
            
            return position.y >= baseY && position.x >= baseX && position.x <= baseX + notchSize.width
        }
        
        return false
    }

    func open() {
        let targetSize = calculateDynamicNotchSize()

        let applyWindowResize: () -> Void = {
            guard let delegate = AppDelegate.shared else { return }
            delegate.ensureWindowSize(
                addShadowPadding(to: targetSize, isMinimalistic: true),
                animated: false,
                force: true
            )
        }

        // NooriViewModel is @MainActor, so this always runs on the main thread.
        applyWindowResize()

        notchSize = targetSize
        notchState = .open

        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
    }
    
    private func calculateDynamicNotchSize() -> CGSize {
        let baseSize = minimalisticOpenNotchSize(isNooriMode: shouldUseNooriMode(for: screen))
        return baseSize
    }

    func close() {
        let targetSize = getClosedNotchSize(screen: screen)
        notchSize = targetSize
        closedNotchSize = targetSize
        notchState = .closed
        resetScrollGestureSuppression()
        resetAutoCloseSuppression()

        coordinator.currentView = .home
    }

    func closeForLockScreen() {
        let targetSize = getClosedNotchSize(screen: screen)
        withAnimation(.none) {
            notchSize = targetSize
            closedNotchSize = targetSize
            notchState = .closed
            resetScrollGestureSuppression()
            resetAutoCloseSuppression()
        }
    }

}
