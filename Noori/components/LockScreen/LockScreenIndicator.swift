/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 * Based on Atoll, Copyright (C) 2024-2026 Atoll Contributors
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import SkyLightWindow
import SwiftUI

/// State the lock indicator view animates from.
@MainActor
final class LockScreenIndicatorModel: ObservableObject {
    @Published var isLocked = true
    @Published var isShown = false
}

/// The closed notch, widened a little, with a lock icon on its left side.
/// Shown on the lock screen; the lock opens briefly on unlock before it hides.
struct LockScreenIndicatorView: View {
    @ObservedObject var model: LockScreenIndicatorModel
    let notchSize: CGSize
    let isNooriMode: Bool
    @State private var isHovering = false

    static func indicatorSize(for notchSize: CGSize) -> CGFloat {
        max(0, notchSize.height - 12)
    }

    static func horizontalPadding(isNooriMode: Bool) -> CGFloat {
        isNooriMode ? 8 : cornerRadiusInsets.closed.bottom
    }

    static func totalSize(for notchSize: CGSize, isNooriMode: Bool) -> CGSize {
        let width = notchSize.width
            + indicatorSize(for: notchSize) * 2
            + horizontalPadding(isNooriMode: isNooriMode) * 2
        return CGSize(width: width, height: notchSize.height + (isNooriMode ? nooriTopOffset : 0))
    }

    private var indicatorSize: CGFloat { Self.indicatorSize(for: notchSize) }
    private var totalWidth: CGFloat { Self.totalSize(for: notchSize, isNooriMode: isNooriMode).width }
    /// Scale that shrinks the wide shape back to the plain notch width.
    private var collapsedScale: CGFloat { totalWidth > 0 ? notchSize.width / totalWidth : 1 }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: model.isLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: indicatorSize, height: notchSize.height, alignment: .leading)
                .opacity(model.isShown ? 1 : 0)

            Color.black
                .frame(width: notchSize.width, height: notchSize.height)

            Color.clear
                .frame(width: indicatorSize, height: notchSize.height)
        }
        .padding(.horizontal, Self.horizontalPadding(isNooriMode: isNooriMode))
        .background(Color.black)
        .clipShape(
            isNooriMode
                ? AnyShape(NooriPillShape(
                    cornerRadius: max(notchSize.height / 2, nooriPillCornerRadiusInsets.closed.standard)
                  ))
                : AnyShape(NotchShape(
                    topCornerRadius: cornerRadiusInsets.closed.top,
                    bottomCornerRadius: cornerRadiusInsets.closed.bottom
                  ))
        )
        .scaleEffect(x: model.isShown ? 1 : collapsedScale, y: 1, anchor: .center)
        // Hover only gives feedback (slight grow + haptic); it never opens the notch.
        .scaleEffect(isHovering ? 1.04 : 1, anchor: .top)
        .opacity(model.isShown ? 1 : 0)
        .onHover { hovering in
            withAnimation(NooriMotion.hover) {
                isHovering = hovering
            }
            if hovering {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
        }
        .padding(.top, isNooriMode ? nooriTopOffset : 0)
        .frame(width: totalWidth, height: notchSize.height + (isNooriMode ? nooriTopOffset : 0), alignment: .top)
    }
}

/// Owns the lock screen window. Normal windows don't draw over the lock screen,
/// so this one is handed to SkyLight, like Atoll's lock screen live activity.
@MainActor
final class LockScreenIndicatorWindowManager {
    static let shared = LockScreenIndicatorWindowManager()

    private var window: NSWindow?
    private var hostingView: NSHostingView<LockScreenIndicatorView>?
    private var hasDelegated = false
    private var hideTask: Task<Void, Never>?
    private let model = LockScreenIndicatorModel()
    private weak var viewModel: NooriViewModel?

    private let showAnimation = Animation.spring(response: 0.45, dampingFraction: 0.85)
    private let hideAnimation = Animation.smooth(duration: 0.3)
    /// How long the open lock stays visible after unlocking.
    private let unlockHold: Duration = .milliseconds(450)

    private init() {}

    func configure(viewModel: NooriViewModel) {
        self.viewModel = viewModel
    }

    func showLocked() {
        hideTask?.cancel()
        hideTask = nil
        guard let context = context() else { return }

        model.isLocked = true
        model.isShown = false
        present(notchSize: context.notchSize, isNooriMode: context.isNooriMode, on: context.screen)

        DispatchQueue.main.async {
            withAnimation(self.showAnimation) {
                self.model.isShown = true
            }
        }
    }

    func showUnlockedAndHide() {
        guard let window, window.isVisible else { return }
        hideTask?.cancel()

        withAnimation(NooriMotion.change) {
            model.isLocked = false
        }

        hideTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.unlockHold)
            guard !Task.isCancelled else { return }
            withAnimation(self.hideAnimation) {
                self.model.isShown = false
            }
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            self.window?.orderOut(nil)
        }
    }

    private func context() -> (notchSize: CGSize, isNooriMode: Bool, screen: NSScreen)? {
        let screens = NSScreen.screens
        let screen = screens.first { $0.localizedName == viewModel?.screen }
            ?? screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main
        guard let screen else { return nil }

        var notchSize = viewModel?.closedNotchSize ?? .zero
        if notchSize.width <= 0 || notchSize.height <= 0 {
            notchSize = getClosedNotchSize(screen: screen.localizedName)
        }
        return (notchSize, shouldUseNooriMode(for: screen.localizedName), screen)
    }

    private func present(notchSize: CGSize, isNooriMode: Bool, on screen: NSScreen) {
        let size = LockScreenIndicatorView.totalSize(for: notchSize, isNooriMode: isNooriMode)
        let frame = NSRect(
            x: (screen.frame.midX - size.width / 2).rounded(),
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        let window = self.window ?? makeWindow(frame: frame)
        window.setFrame(frame, display: true)

        let view = LockScreenIndicatorView(model: model, notchSize: notchSize, isNooriMode: isNooriMode)
        if let hostingView {
            hostingView.rootView = view
            hostingView.frame = CGRect(origin: .zero, size: frame.size)
        } else {
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(origin: .zero, size: frame.size)
            hostingView = hosting
            window.contentView = hosting
        }

        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
        }
        window.orderFrontRegardless()
    }

    private func makeWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.animationBehavior = .none
        ScreenCaptureVisibilityManager.shared.register(window, scope: .entireInterface)
        self.window = window
        return window
    }
}
