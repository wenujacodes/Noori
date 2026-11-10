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
import Contacts
import Defaults
import SwiftUI

/// A new message shown in the notch. Kept in memory only.
struct IncomingMessage: Identifiable, Equatable {
    let id: Int
    let senderName: String
    let initials: String
    let avatar: NSImage?
    let text: String
    let handle: String
    let service: String
    let chatGUID: String?
    let groupName: String?

    var isSMS: Bool { service.caseInsensitiveCompare("SMS") == .orderedSame || service.uppercased() == "RCS" }

    static func == (lhs: IncomingMessage, rhs: IncomingMessage) -> Bool { lhs.id == rhs.id }
}

/// Shows new iMessages/SMS in the notch with a quick reply.
///
/// Reads `~/Library/Messages/chat.db` read-only (needs Full Disk Access) and wakes on
/// file-system events from the database files. Contact names come from Contacts when
/// allowed. Replies are sent with AppleScript to Messages. Message contents are never
/// logged or written to disk; only the last seen ROWID is stored.
@MainActor
final class MessagesNotificationManager: ObservableObject {
    static let shared = MessagesNotificationManager()

    enum SendState: Equatable {
        case idle
        case sending
        case sent
        case failed
    }

    @Published private(set) var current: IncomingMessage?
    @Published private(set) var hasDatabaseAccess = false
    @Published private(set) var contactsStatus: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    @Published private(set) var isWatching = false
    @Published var replyText = ""
    @Published private(set) var sendState: SendState = .idle

    /// The notification card's own state, driven by the manager.
    let presentation = MessageNotificationPresentation()

    private lazy var monitor = MessagesDatabaseMonitor(lastSeenKey: .messagesLastSeenRowID) { row in
        Task { @MainActor in
            MessagesNotificationManager.shared.handleNewMessage(row)
        }
    }
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private let contactStore = CNContactStore()
    private var contactCache: [String: (name: String?, image: NSImage?)] = [:]

    private var panelController: MessageNotificationPanelController?
    private var hideTask: Task<Void, Never>?
    private var isHovering = false
    private var isFieldFocused = false

    nonisolated static let autoHideDelay: TimeInterval = 6

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        Defaults.publisher(.showMessageNotifications)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.beginWatching()
                    self.requestContactsAccessIfNeeded()
                } else {
                    self.stopWatching()
                    self.dismiss()
                }
            }
            .store(in: &cancellables)

        // Full Disk Access is granted in System Settings, so check again when the
        // user comes back to Noori.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPermissions() }
            .store(in: &cancellables)

        Defaults.publisher(.messageNotificationsQuickReply, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.panelController?.updateSize(animated: false) }
            .store(in: &cancellables)
    }

    /// Re-checks Full Disk Access and Contacts; starts watching if access just arrived.
    func refreshPermissions() {
        contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        monitor.checkAccess { readable in
            Task { @MainActor in
                let manager = MessagesNotificationManager.shared
                manager.hasDatabaseAccess = readable
                if readable, Defaults[.showMessageNotifications], !manager.isWatching {
                    manager.beginWatching()
                }
            }
        }
    }

    private func beginWatching() {
        monitor.start { readable, watching in
            Task { @MainActor in
                let manager = MessagesNotificationManager.shared
                manager.hasDatabaseAccess = readable
                // The toggle may have been turned off meanwhile.
                manager.isWatching = watching && Defaults[.showMessageNotifications]
                if !Defaults[.showMessageNotifications] { manager.monitor.stop() }
            }
        }
    }

    private func stopWatching() {
        monitor.stop()
        isWatching = false
    }

    // MARK: - Presenting

    private func handleNewMessage(_ row: MessagesDatabaseRow) {
        guard Defaults[.showMessageNotifications] else { return }
        guard !LockScreenManager.shared.isLocked else { return }
        // Messages itself is in front: the user is already looking at it.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.MobileSMS" { return }
        // Don't replace a card the user is typing a reply into.
        if current != nil, isFieldFocused || !replyText.isEmpty { return }

        let contact = contactInfo(for: row.handle)
        let name = contact.name ?? Self.formattedHandle(row.handle)
        let groupName = row.isGroupChat
            ? (row.chatDisplayName ?? String(localized: "Group conversation"))
            : nil

        let message = IncomingMessage(
            id: row.rowID,
            senderName: name,
            initials: Self.initials(for: contact.name),
            avatar: contact.image,
            text: row.text,
            handle: row.handle,
            service: row.service,
            chatGUID: row.chatGUID,
            groupName: groupName
        )
        present(message)
    }

    private func present(_ message: IncomingMessage) {
        replyText = ""
        sendState = .idle
        isHovering = false
        isFieldFocused = false
        current = message
        presentation.message = message

        if panelController == nil {
            panelController = MessageNotificationPanelController(manager: self)
        }
        closeOpenNotches()
        NooriViewCoordinator.shared.suppressHoverOpen(until: .distantFuture)
        panelController?.show(on: Self.targetScreen())
        scheduleAutoHide()
    }

    /// Hides the card (Esc, moving away, timeout, after sending).
    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        guard current != nil else { return }
        current = nil
        isHovering = false
        isFieldFocused = false
        panelController?.hide { [weak self] in
            guard let self, self.current == nil else { return }
            self.presentation.message = nil
            self.replyText = ""
            self.sendState = .idle
        }
        // Let the pointer leave before hovering can open the notch again.
        NooriViewCoordinator.shared.suppressHoverOpen(until: Date().addingTimeInterval(0.8))
    }

    /// Opens the conversation in Messages.
    func openInMessages() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        dismiss()
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            hideTask?.cancel()
        } else {
            // Moving away dismisses, unless a reply is being typed.
            scheduleAutoHide(after: isFieldFocused ? Self.autoHideDelay : 1.0)
        }
    }

    func setFieldFocused(_ focused: Bool) {
        isFieldFocused = focused
        if focused {
            hideTask?.cancel()
        } else if !isHovering {
            scheduleAutoHide()
        }
    }

    /// The user clicked into another app: stop treating the reply as being typed.
    func panelDidResignKey() {
        setFieldFocused(false)
    }

    private func scheduleAutoHide(after delay: TimeInterval = MessagesNotificationManager.autoHideDelay) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            guard !self.isHovering, !self.isFieldFocused, self.sendState != .sending else {
                // Still in use: look again later.
                self.scheduleAutoHide()
                return
            }
            self.dismiss()
        }
    }

    private func closeOpenNotches() {
        guard let delegate = AppDelegate.shared else { return }
        for vm in [delegate.vm] + Array(delegate.viewModels.values) where vm.notchState == .open {
            vm.close()
        }
    }

    private static func targetScreen() -> NSScreen? {
        if Defaults[.showOnAllDisplays] {
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        }
        let name = NooriViewCoordinator.shared.selectedScreen
        return NSScreen.screens.first { $0.localizedName == name } ?? NSScreen.main
    }

    // MARK: - Replying

    func sendReply() {
        guard let message = current, Defaults[.messageNotificationsQuickReply] else { return }
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, sendState != .sending else { return }

        sendState = .sending
        hideTask?.cancel()

        Task { [weak self] in
            let success = await Self.send(text, to: message)
            guard let self, self.current?.id == message.id else { return }
            if success {
                self.sendState = .sent
                self.replyText = ""
                try? await Task.sleep(for: .seconds(0.9))
                if self.current?.id == message.id { self.dismiss() }
            } else {
                self.sendState = .failed
                self.scheduleAutoHide()
            }
        }
    }

    private static func send(_ text: String, to message: IncomingMessage) async -> Bool {
        let body = appleScriptString(text)
        var scripts: [String] = []
        if let guid = message.chatGUID {
            scripts.append("""
            tell application id "com.apple.MobileSMS"
                send \(body) to chat id \(appleScriptString(guid))
            end tell
            """)
        }
        // One-to-one fallback: the person on the same service.
        if message.groupName == nil, !message.handle.isEmpty {
            let serviceType = message.isSMS ? "SMS" : "iMessage"
            scripts.append("""
            tell application id "com.apple.MobileSMS"
                set targetAccount to 1st account whose service type = \(serviceType)
                send \(body) to participant \(appleScriptString(message.handle)) of targetAccount
            end tell
            """)
        }
        for script in scripts {
            if (try? await AppleScriptHelper.execute(script)) != nil {
                return true
            }
        }
        return false
    }

    /// A quoted AppleScript string literal with backslashes and quotes escaped.
    static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
        return "\"\(escaped)\""
    }

    // MARK: - Contacts

    func requestContactsAccessIfNeeded() {
        guard CNContactStore.authorizationStatus(for: .contacts) == .notDetermined else {
            contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
            return
        }
        contactStore.requestAccess(for: .contacts) { [weak self] _, _ in
            Task { @MainActor in
                self?.contactCache.removeAll()
                self?.contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
            }
        }
    }

    func openContactsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
            NSWorkspace.shared.open(url)
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func contactInfo(for handle: String) -> (name: String?, image: NSImage?) {
        guard !handle.isEmpty else { return (nil, nil) }
        if let cached = contactCache[handle] { return cached }
        let status = CNContactStore.authorizationStatus(for: .contacts)
        contactsStatus = status
        guard status == .authorized else { return (nil, nil) }

        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
        ]
        let predicate: NSPredicate = handle.contains("@")
            ? CNContact.predicateForContacts(matchingEmailAddress: handle)
            : CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: handle))

        var result: (name: String?, image: NSImage?) = (nil, nil)
        if let contact = try? contactStore.unifiedContacts(matching: predicate, keysToFetch: keys).first {
            var name = CNContactFormatter.string(from: contact, style: .fullName)
            if name?.isEmpty ?? true { name = contact.nickname.isEmpty ? nil : contact.nickname }
            if name?.isEmpty ?? true { name = contact.organizationName.isEmpty ? nil : contact.organizationName }
            let image = contact.imageDataAvailable ? contact.thumbnailImageData.flatMap(NSImage.init(data:)) : nil
            result = (name, image)
        }
        contactCache[handle] = result
        return result
    }

    private static func initials(for name: String?) -> String {
        guard let name, !name.isEmpty else { return "" }
        let parts = name.split(separator: " ").filter { $0.first?.isLetter == true }
        let letters = parts.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.joined()
    }

    private static func formattedHandle(_ handle: String) -> String {
        handle.isEmpty ? String(localized: "Unknown sender") : handle
    }
}
