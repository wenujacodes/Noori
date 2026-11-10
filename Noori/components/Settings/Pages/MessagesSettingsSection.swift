/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Contacts
import Defaults
import SwiftUI

/// Settings › Live Activities › Messages: new message alerts in the notch.
struct MessagesSettingsSection: View {
    let highlightID: (String) -> String

    @ObservedObject private var manager = MessagesNotificationManager.shared
    @Default(.showMessageNotifications) private var showMessageNotifications

    var body: some View {
        Section {
            Defaults.Toggle(key: .showMessageNotifications) {
                Text("Show new messages in the notch")
            }
            .settingsHighlight(id: highlightID("Show new messages in the notch"))

            Defaults.Toggle(key: .messageNotificationsQuickReply) {
                Text("Allow quick reply")
            }
            .disabled(!showMessageNotifications)
            .settingsHighlight(id: highlightID("Allow quick reply"))

            HStack {
                Text("Full Disk Access")
                Spacer()
                if manager.hasDatabaseAccess {
                    statusLabel("Allowed", color: .green)
                } else {
                    statusLabel("Not allowed", color: .orange)
                    Button("Open Settings") {
                        manager.openFullDiskAccessSettings()
                    }
                    .controlSize(.small)
                    Button("Check Again") {
                        manager.refreshPermissions()
                    }
                    .controlSize(.small)
                }
            }
            .settingsHighlight(id: highlightID("Messages Full Disk Access"))

            HStack {
                Text("Contacts")
                Spacer()
                switch manager.contactsStatus {
                case .authorized:
                    statusLabel("Allowed", color: .green)
                case .notDetermined:
                    statusLabel("Not asked yet", color: .secondary)
                    Button("Allow") {
                        manager.requestContactsAccessIfNeeded()
                    }
                    .controlSize(.small)
                default:
                    statusLabel("Not allowed", color: .orange)
                    Button("Open Settings") {
                        manager.openContactsSettings()
                    }
                    .controlSize(.small)
                }
            }
            .settingsHighlight(id: highlightID("Messages Contacts access"))
        } header: {
            Text("Messages")
        } footer: {
            Text("Shows new iMessages and texts in the notch, with a reply field. Reading them needs Full Disk Access: in System Settings › Privacy & Security › Full Disk Access, turn on Noori, then come back here (you may need to restart Noori). Contacts shows names and photos instead of phone numbers. The first reply asks to let Noori control Messages. Nothing from your messages is saved.")
        }
        .onAppear {
            manager.refreshPermissions()
        }
    }

    private func statusLabel(_ title: LocalizedStringKey, color: Color) -> some View {
        Text(title)
            .foregroundColor(color)
    }
}
