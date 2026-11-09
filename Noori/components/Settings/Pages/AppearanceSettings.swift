//
//  AppearanceSettings.swift
//  Noori
//
//  Split out of SettingsView.swift, created by Richard Kunkli on 07/08/2024
//  for boring.notch and carried over through Atoll. See NOTICE.
//
import AppKit
import Combine
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect
import UniformTypeIdentifiers

struct Appearance: View {
    @ObservedObject var coordinator = NooriViewCoordinator.shared
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.openNotchWidth) var openNotchWidth
    @Default(.closedNotchWidth) var closedNotchWidth
    @Default(.customizePhysicalNotchWidth) var customizePhysicalNotchWidth
    @Default(.externalDisplayStyle) private var externalDisplayStyle

    @State private var speed: CGFloat = 1.0

    private var notchWidthRange: ClosedRange<Double> {
        let minW = Double(currentRecommendedMinimumNotchWidth())
        let maxW = min(900, Double(maxAllowedNotchWidth()))
        return minW...max(minW, maxW)
    }
    private var defaultOpenNotchWidth: CGFloat {
        currentRecommendedMinimumNotchWidth()
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.appearance.highlightID(for: title)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }




    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableShadow) {
                    Text("Enable window shadow")
                }
                .settingsHighlight(id: highlightID("Enable window shadow"))
            } header: {
                Text("General")
            }

            // Screens without a notch: external displays, and Macs without one.
            Section {
                Picker("Style on screens without a notch", selection: $externalDisplayStyle) {
                    ForEach(ExternalDisplayStyle.allCases) { style in
                        Text(style.localizedName)
                            .tag(style)
                    }
                }
                .onChange(of: externalDisplayStyle) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
                .settingsHighlight(id: highlightID("Display style"))
                Text(externalDisplayStyle.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Display style")
            }

            notchWidthControls()

            NotchHeightSettingsSection()
        }
        .navigationTitle("Appearance")
    }

    @ViewBuilder
    private func notchWidthControls() -> some View {
        Section {
            let closedRange = Double(80)...400

            let closedWidthBinding = Binding<Double>(
                get: { Double(closedNotchWidth) },
                set: { newValue in
                    let clamped = min(max(newValue, closedRange.lowerBound), closedRange.upperBound)
                    let value = CGFloat(clamped)
                    if closedNotchWidth != value {
                        closedNotchWidth = value
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            )

            VStack(alignment: .leading, spacing: 10) {
                Defaults.Toggle(key: .customizePhysicalNotchWidth) {
                    Text("Customize physical notch width")
                }
                .onChange(of: customizePhysicalNotchWidth) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
                .settingsHighlight(id: highlightID("Customize physical notch width"))
                
                Slider(
                    value: closedWidthBinding,
                    in: closedRange,
                    // 10 px steps: tick marks like the other sliders, without
                    // the dense row a 5 px step draws over this range.
                    step: 10
                ) {
                    HStack {
                        Text("Closed notch / pill width")
                        Spacer()
                        Text("\(Int(closedNotchWidth)) px")
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: highlightID("Closed notch / pill width"))

            }
        } header: {
            HStack {
                Text("Notch width")
            }
        }
    }

}

/// Notch height (moved here from General, next to the notch width).
struct NotchHeightSettingsSection: View {
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode

    var body: some View {
        Section {
            Picker(selection: $notchHeightMode, label:
                    Text("Notch display height")) {
                Text("Match real notch size")
                    .tag(WindowHeightMode.matchRealNotchSize)
                Text("Match menubar height")
                    .tag(WindowHeightMode.matchMenuBar)
                Text("Custom height")
                    .tag(WindowHeightMode.custom)
            }
                    .onChange(of: notchHeightMode) {
                        switch notchHeightMode {
                        case .matchRealNotchSize:
                            notchHeight = 38
                        case .matchMenuBar:
                            notchHeight = 44
                        case .custom:
                            notchHeight = 38
                        }
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                    .settingsHighlight(id: SettingsTab.appearance.highlightID(for: "Notch display height"))
            if notchHeightMode == .custom {
                Slider(value: $notchHeight, in: 15...45, step: 1) {
                    Text("Custom notch size - \(notchHeight, specifier: "%.0f")")
                }
                .onChange(of: notchHeight) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
            Picker("Non-notch display height", selection: $nonNotchHeightMode) {
                Text("Match menubar height")
                    .tag(WindowHeightMode.matchMenuBar)
                Text("Match real notch size")
                    .tag(WindowHeightMode.matchRealNotchSize)
                Text("Custom height")
                    .tag(WindowHeightMode.custom)
            }
            .onChange(of: nonNotchHeightMode) {
                switch nonNotchHeightMode {
                case .matchMenuBar:
                    nonNotchHeight = 24
                case .matchRealNotchSize:
                    nonNotchHeight = 32
                case .custom:
                    nonNotchHeight = 32
                }
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            if nonNotchHeightMode == .custom {
                Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                    Text("Custom notch size - \(nonNotchHeight, specifier: "%.0f")")
                }
                .onChange(of: nonNotchHeight) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("Notch height")
        }
    }
}
