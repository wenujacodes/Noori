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
import Defaults
import SwiftUI

/// What the message card shows and how far it has dropped down.
@MainActor
final class MessageNotificationPresentation: ObservableObject {
    @Published var message: IncomingMessage?
    @Published var isExpanded = false
    /// The closed notch it grows out of and shrinks back into.
    @Published var closedSize: CGSize = getClosedNotchSize()
    @Published var hasPhysicalNotch = true

    static let cardWidth: CGFloat = 400
    static let messageRowHeight: CGFloat = 54
    static let replyRowHeight: CGFloat = 30
    static let shadowInset: CGFloat = 20

    /// Content starts under the camera on notched screens.
    var topInset: CGFloat { hasPhysicalNotch ? closedSize.height + 6 : 12 }

    func cardSize(quickReply: Bool) -> CGSize {
        let height = topInset + Self.messageRowHeight + (quickReply ? 10 + Self.replyRowHeight : 0) + 14
        return CGSize(width: max(Self.cardWidth, closedSize.width + 40), height: height)
    }
}

/// The black card that drops out of the notch for a new message, iPhone style.
struct MessageNotificationView: View {
    @ObservedObject var manager: MessagesNotificationManager
    @ObservedObject var presentation: MessageNotificationPresentation
    @Default(.messageNotificationsQuickReply) private var quickReply
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let expanded = presentation.isExpanded
        let cardSize = presentation.cardSize(quickReply: quickReply)
        let size = expanded ? cardSize : presentation.closedSize
        let shape = NotchShape(
            topCornerRadius: expanded ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top,
            bottomCornerRadius: expanded ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom
        )

        ZStack(alignment: .top) {
            if let message = presentation.message {
                card(for: message)
                    .frame(width: cardSize.width, height: cardSize.height, alignment: .top)
                    // Fades in once the notch is part-way open, like the open notch content.
                    .blur(radius: expanded ? 0 : NooriMotion.contentFadeBlur)
                    .opacity(expanded ? 1 : 0)
                    .animation(
                        expanded
                            ? .easeOut(duration: NooriMotion.contentFadeInDuration).delay(NooriMotion.contentFadeInDelay)
                            : .easeOut(duration: NooriMotion.contentFadeOutDuration),
                        value: expanded
                    )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(.black)
        .clipShape(shape)
        .contentShape(shape)
        .shadow(color: .black.opacity(expanded ? 0.6 : 0), radius: 10)
        .animation(NooriMotion.notch(opening: expanded), value: expanded)
        .onHover { manager.setHovering($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: isFieldFocused) { _, focused in
            manager.setFieldFocused(focused)
        }
        .onChange(of: presentation.message?.id) { _, _ in
            isFieldFocused = false
        }
        .environment(\.colorScheme, .dark)
    }

    private func card(for message: IncomingMessage) -> some View {
        VStack(spacing: 10) {
            messageRow(message)
                .frame(height: MessageNotificationPresentation.messageRowHeight, alignment: .top)
            if quickReply {
                replyRow(message)
                    .frame(height: MessageNotificationPresentation.replyRowHeight)
            }
        }
        .padding(.top, presentation.topInset)
        .padding(.horizontal, cornerRadiusInsets.opened.top + 2)
        .padding(.bottom, 14)
    }

    // MARK: - Message

    private func messageRow(_ message: IncomingMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            MessageAvatar(message: message)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(message.senderName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("now")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                if let groupName = message.groupName {
                    Text(groupName)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Text(message.text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(message.groupName == nil ? 2 : 1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { manager.openInMessages() }
        .help("Open in Messages")
    }

    // MARK: - Reply

    private func replyRow(_ message: IncomingMessage) -> some View {
        let trimmed = manager.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let accent: Color = message.isSMS ? .green : .blue

        return HStack(spacing: 8) {
            TextField(
                "",
                text: $manager.replyText,
                prompt: Text(message.isSMS ? "Text Message" : "iMessage")
                    .foregroundColor(.white.opacity(0.4))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .focused($isFieldFocused)
            .onSubmit { manager.sendReply() }
            .onExitCommand { manager.dismiss() }
            .disabled(manager.sendState == .sending || manager.sendState == .sent)
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(isFieldFocused ? 0.18 : 0.06)))
            )
            .animation(NooriMotion.change, value: isFieldFocused)

            Button {
                manager.sendReply()
            } label: {
                ZStack {
                    Circle()
                        .fill(sendButtonColor(accent: accent, isEmpty: trimmed.isEmpty))
                    sendButtonIcon
                }
                .frame(width: MessageNotificationPresentation.replyRowHeight,
                       height: MessageNotificationPresentation.replyRowHeight)
                .contentShape(Circle())
            }
            .buttonStyle(MessageSendButtonStyle())
            .disabled(trimmed.isEmpty || manager.sendState == .sending || manager.sendState == .sent)
            .help(manager.sendState == .failed
                  ? String(localized: "Couldn't send. Check that Noori may control Messages in System Settings › Privacy & Security › Automation.")
                  : String(localized: "Send"))
            .animation(NooriMotion.change, value: manager.sendState)
        }
    }

    private func sendButtonColor(accent: Color, isEmpty: Bool) -> Color {
        switch manager.sendState {
        case .failed: return .red
        case .sent: return accent
        default: return isEmpty ? Color.white.opacity(0.15) : accent
        }
    }

    @ViewBuilder
    private var sendButtonIcon: some View {
        switch manager.sendState {
        case .sending:
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        case .idle:
            Image(systemName: "paperplane.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct MessageSendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Contact photo, or initials (or a person) on a gray circle, with a small Messages badge.
private struct MessageAvatar: View {
    let message: IncomingMessage
    private let size: CGFloat = 40

    private static let messagesIcon: NSImage? = {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS") else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let avatar = message.avatar {
                    Image(nsImage: avatar)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [Color(white: 0.62), Color(white: 0.45)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        if message.initials.isEmpty {
                            Image(systemName: "person.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white)
                        } else {
                            Text(message.initials)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            Group {
                if let icon = Self.messagesIcon {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: "message.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.green))
                }
            }
            .frame(width: 18, height: 18)
            .offset(x: 4, y: 4)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Panel

/// A borderless, non-activating panel above the notch window. It becomes key when
/// clicked so the reply field gets the typing, without activating Noori.
final class MessageNotificationPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }

    /// Esc while the panel is key.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class MessageNotificationPanelController {
    private let panel: MessageNotificationPanel
    private let presentation: MessageNotificationPresentation
    private var screen: NSScreen?
    /// Bumped on every show so a pending hide doesn't order out a newer card.
    private var generation = 0

    init(manager: MessagesNotificationManager) {
        presentation = manager.presentation
        panel = MessageNotificationPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        // Just above the notch window (.mainMenu + 3).
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .stationary]
        panel.onCancel = { [weak manager] in manager?.dismiss() }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak manager] _ in
            MainActor.assumeIsolated { manager?.panelDidResignKey() }
        }

        let hostingView = FirstMouseHostingView(
            rootView: MessageNotificationView(manager: manager, presentation: manager.presentation)
        )
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        ScreenCaptureVisibilityManager.shared.register(panel, scope: .entireInterface)
    }

    func show(on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        generation += 1
        self.screen = screen

        let wasVisible = panel.isVisible && presentation.isExpanded
        presentation.closedSize = getClosedNotchSize(screen: screen.localizedName)
        presentation.hasPhysicalNotch = screen.safeAreaInsets.top > 0
        updateSize(animated: false)

        if wasVisible {
            // A newer message replaces the one on screen; the card stays open.
            return
        }
        var noAnimation = Transaction()
        noAnimation.disablesAnimations = true
        withTransaction(noAnimation) { presentation.isExpanded = false }
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [presentation] in
            withAnimation(NooriMotion.notchOpen) {
                presentation.isExpanded = true
            }
        }
    }

    func hide(completion: @escaping () -> Void) {
        let hideGeneration = generation
        withAnimation(NooriMotion.notchClose) {
            presentation.isExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.generation == hideGeneration else { return }
            self.panel.orderOut(nil)
            completion()
        }
    }

    /// Sizes the panel to the open card (plus shadow room), pinned top-center.
    func updateSize(animated: Bool) {
        guard let screen = screen ?? NSScreen.main else { return }
        let card = presentation.cardSize(quickReply: Defaults[.messageNotificationsQuickReply])
        let inset = MessageNotificationPresentation.shadowInset
        let width = (card.width + inset * 2).rounded()
        let height = (card.height + inset).rounded()
        let frame = NSRect(
            x: (screen.frame.midX - width / 2).rounded(),
            y: (screen.frame.maxY - height).rounded(),
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true, animate: animated)
    }
}
