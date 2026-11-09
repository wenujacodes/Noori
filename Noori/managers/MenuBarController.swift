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
import Defaults
import Sparkle

/// Noori's menu bar icon. Left-click opens or closes the notch; right-click (or
/// Control-click) shows Settings, Check for Updates, Restart and Quit.
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var updater: SPUUpdater?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
    }

    /// Call once at launch. Shows or hides the icon with the "Show menu bar icon" setting.
    func install(updater: SPUUpdater?) {
        self.updater = updater
        Defaults.publisher(.showMenuBarIcon)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                MainActor.assumeIsolated { self?.setVisible(show) }
            }
            .store(in: &cancellables)
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                // Placeholder icon until Noori has its own.
                let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Noori")
                image?.isTemplate = true
                button.image = image
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isMenuClick = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)
        if isMenuClick {
            showMenu()
        } else {
            AppDelegate.shared?.toggleNotchFromMenuBar()
        }
    }

    private func showMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let settings = NSMenuItem(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let updates = NSMenuItem(title: String(localized: "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        updates.isEnabled = updater?.canCheckForUpdates ?? false
        menu.addItem(updates)

        menu.addItem(.separator())

        let restart = NSMenuItem(title: String(localized: "Restart Noori"), action: #selector(restart), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)

        let quit = NSMenuItem(title: String(localized: "Quit Noori"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Show the menu under the icon, then detach it so a left-click opens the notch again.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow()
    }

    @objc private func checkForUpdates() {
        updater?.checkForUpdates()
    }

    @objc private func restart() {
        restartNoori()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
