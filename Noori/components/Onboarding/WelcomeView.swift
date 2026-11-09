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
import SwiftUI

/// The small welcome window shown on first launch: what Noori does, then Continue.
struct WelcomeView: View {
    var onContinue: () -> Void

    private struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let colors: [Color]
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    private let features: [Feature] = [
        Feature(
            icon: "music.note",
            colors: [Color(red: 1.0, green: 0.35, blue: 0.45), Color(red: 0.93, green: 0.18, blue: 0.4)],
            title: "Now Playing in your notch",
            detail: "Album art, a live visualizer and controls for Apple Music, Spotify and more. Hover the notch to open it."
        ),
        Feature(
            icon: "sparkles",
            colors: [Color(red: 0.62, green: 0.45, blue: 1.0), Color(red: 0.42, green: 0.3, blue: 0.95)],
            title: "Live activities",
            detail: "Charging, Focus, screen recording, camera and mic, and Caps Lock show up around the notch."
        ),
        Feature(
            icon: "speaker.wave.2.fill",
            colors: [Color(red: 0.3, green: 0.6, blue: 1.0), Color(red: 0.16, green: 0.42, blue: 0.95)],
            title: "Volume and brightness, redesigned",
            detail: "Clean HUDs in the notch replace the macOS ones."
        ),
        Feature(
            icon: "airpods",
            colors: [Color(red: 0.25, green: 0.8, blue: 0.6), Color(red: 0.12, green: 0.62, blue: 0.5)],
            title: "Bluetooth, Wi-Fi and AirDrop",
            detail: "See devices connect with their battery level, and get low-battery reminders."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 20) {
                ForEach(features) { feature in
                    featureRow(feature)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)

            Spacer(minLength: 24)

            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
            }
            .buttonStyle(WelcomeButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 40)
            .padding(.bottom, 28)
        }
        .frame(width: 460, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.36, blue: 0.95).opacity(0.55),
                    Color(red: 0.95, green: 0.45, blue: 0.6).opacity(0.35),
                    Color(nsColor: .windowBackgroundColor),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 18) {
                NotchIllustration()
                VStack(spacing: 6) {
                    Text("Welcome to Noori")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Your notch, now an island.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 36)
        }
        .frame(height: 230)
    }

    private func featureRow(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: feature.colors, startPoint: .top, endPoint: .bottom))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: feature.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(feature.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A small closed notch playing music: album tile, the notch, and visualizer bars.
private struct NotchIllustration: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 1.0, green: 0.55, blue: 0.35), Color(red: 0.9, green: 0.25, blue: 0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 22, height: 22)
            Spacer(minLength: 0)
            HStack(spacing: 2.5) {
                ForEach(0..<5) { index in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3, height: animate ? Self.peaks[index] : 4)
                        .animation(
                            .easeInOut(duration: 0.45 + Double(index) * 0.07)
                                .repeatForever(autoreverses: true),
                            value: animate
                        )
                }
            }
            .frame(height: 16)
        }
        .padding(.horizontal, 12)
        .frame(width: 210, height: 38)
        .background(
            UnevenRoundedRectangle(
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                style: .continuous
            )
            .fill(Color.black)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .onAppear { animate = true }
    }

    private static let peaks: [CGFloat] = [10, 15, 8, 13, 9]
}

private struct WelcomeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor)
                    .brightness(configuration.isPressed ? -0.08 : 0)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(NooriMotion.change, value: configuration.isPressed)
    }
}

/// Owns the welcome window.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindowController()

    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: WelcomeView { [weak self] in
            self?.close()
        })
        window.center()
        self.window = window

        NSApp.setActivationPolicy(.regular)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 1
        }
    }

    private func close() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                window.close()
                self?.window = nil
            }
        })
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        // Back to a menu-bar-only app unless Settings is open.
        if !NSApp.windows.contains(where: { $0.isVisible && $0.identifier?.rawValue == "NooriSettingsWindow" }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
