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

    /// Whether the main screen has a physical notch.
    private var mainScreenHasPhysicalNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

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

            // Show display style picker only on non-notch Macs (main screen has no physical notch)
            if !mainScreenHasPhysicalNotch {
                Section {
                    Picker("Main screen style", selection: $externalDisplayStyle) {
                        ForEach(ExternalDisplayStyle.allCases) { style in
                            Text(style.localizedName)
                                .tag(style)
                        }
                    }
                    .onChange(of: externalDisplayStyle) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                    .settingsHighlight(id: highlightID("Main screen style"))
                    Text(externalDisplayStyle.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Display style")
                }
            }

            notchWidthControls()
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
