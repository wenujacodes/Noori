//
//  ControlsSettings.swift
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

struct HUDAndOSDSettingsView: View {
    var body: some View {
        // HUD includes the step size and display integration sections in its single Form.
        HUD()
    }
}

// MARK: - External Display Integrations Settings Section

struct ExternalDisplayIntegrationsSection: View {
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.thirdPartyDDCProvider) var thirdPartyDDCProvider
    @Default(.enableExternalVolumeControlListener) var enableExternalVolumeControlListener
    @Default(.volumeStepPercent) var volumeStepPercent
    @Default(.volumeFineStepPercent) var volumeFineStepPercent
    @Default(.brightnessStepPercent) var brightnessStepPercent
    @Default(.brightnessFineStepPercent) var brightnessFineStepPercent
    @ObservedObject private var betterDisplayManager = BetterDisplayManager.shared
    @ObservedObject private var lunarManager = LunarManager.shared

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var providerStatusText: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if betterDisplayManager.isRunning { return "Running" }
            if betterDisplayManager.isDetected { return "Not running" }
            return "Not detected"
        case .lunar:
            if lunarManager.isConnected { return "Connected" }
            if lunarManager.isRunning { return "Running" }
            if lunarManager.isDetected { return "Not running" }
            return "Not detected"
        }
    }

    private var providerStatusColor: Color {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if betterDisplayManager.isRunning { return .green }
            if betterDisplayManager.isDetected { return .orange }
            return .secondary
        case .lunar:
            if lunarManager.isConnected { return .green }
            if lunarManager.isRunning { return .orange }
            if lunarManager.isDetected { return .orange }
            return .secondary
        }
    }

    private var providerStatusDescription: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if !betterDisplayManager.isDetected {
                return "Install [BetterDisplay](https://betterdisplay.pro) to control external display brightness (and optional volume) through Noori's HUD."
            }
            if !betterDisplayManager.isRunning {
                return "BetterDisplay is installed but not currently running. Launch BetterDisplay to enable integration."
            }
            return "BetterDisplay OSD events will be routed through Noori's active HUD style. Brightness is always routed; volume is routed when external volume control listener is enabled below. Make sure BetterDisplay's OSD integration is enabled in Settings › Application › Integration."
        case .lunar:
            if !lunarManager.isDetected {
                return "Install [Lunar](https://lunar.fyi) to control external display brightness, contrast, and optional volume through Noori's HUD via DDC."
            }
            if !lunarManager.isRunning {
                return "Lunar is installed but not currently running. Launch Lunar to enable integration."
            }
            if lunarManager.isConnected {
                return "Connected to Lunar's DDC socket. Brightness and contrast adjustments are shown through Noori's HUD; volume follows when external volume control listener is enabled below."
            }
            return "Lunar is running but the socket connection is not yet established. It will connect automatically."
        }
    }

    private func refreshDetectionStatus() {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            betterDisplayManager.refreshDetectionStatus()
        case .lunar:
            lunarManager.refreshDetectionStatus()
        }
    }

    var body: some View {
        // Sections only; shown inside the Controls page Form.
        Group {
            Section {
                Stepper(value: $volumeStepPercent, in: 1...25) {
                    HStack {
                        Text("Volume step")
                        Spacer()
                        Text("\(volumeStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Volume step"))
                .disabled(enableExternalVolumeControlListener)

                Stepper(value: $volumeFineStepPercent, in: 1...25) {
                    HStack {
                        Text("Volume fine step")
                        Spacer()
                        Text("\(volumeFineStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Volume fine step"))
                .disabled(enableExternalVolumeControlListener)

                if enableExternalVolumeControlListener {
                    Text("Disabled while external display volume integration is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Stepper(value: $brightnessStepPercent, in: 1...25) {
                    HStack {
                        Text("Brightness step")
                        Spacer()
                        Text("\(brightnessStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Brightness step"))
                .disabled(enableThirdPartyDDCIntegration)

                Stepper(value: $brightnessFineStepPercent, in: 1...25) {
                    HStack {
                        Text("Brightness fine step")
                        Spacer()
                        Text("\(brightnessFineStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Brightness fine step"))
                .disabled(enableThirdPartyDDCIntegration)

                if enableThirdPartyDDCIntegration {
                    Text("Disabled while external display brightness integration is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Step size")
            } footer: {
                Text("Percent change per key press. Fine step applies when holding Shift+Option.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Toggle("Enable third-party DDC app integration", isOn: $enableThirdPartyDDCIntegration)
                    .settingsHighlight(id: highlightID("Third-party DDC app integration"))

                if enableThirdPartyDDCIntegration {
                    Picker("Provider", selection: $thirdPartyDDCProvider) {
                        ForEach(ThirdPartyDDCProvider.allCases) { provider in
                            HStack {
                                AppIconImage(
                                    bundleIdentifiers: provider.bundleIdentifiers,
                                    symbolFallback: "display",
                                    symbolColor: .secondary
                                )
                                Text(provider.displayName)
                            }
                            .tag(provider)
                        }
                    }
                    .settingsHighlight(id: highlightID("Third-party DDC provider"))

                    Toggle("Enable external volume control listener", isOn: $enableExternalVolumeControlListener)
                        .settingsHighlight(id: highlightID("Enable external volume control listener"))

                    Text(
                        enableExternalVolumeControlListener
                        ? "Noori's built-in volume key interception is disabled while external volume listening is on. Volume HUD/OSD will follow \(thirdPartyDDCProvider.displayName) payloads."
                        : "Noori keeps native volume key interception. External provider volume payloads are ignored while this is off."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(providerStatusText)
                            .font(.caption)
                            .foregroundStyle(providerStatusColor)
                    }

                    Text(providerStatusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        refreshDetectionStatus()
                    } label: {
                        Label("Refresh detection", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                } else {
                    Text("Enable to route BetterDisplay or Lunar display adjustments through Noori's active HUD style.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if enableThirdPartyDDCIntegration {
                    Text("Noori always listens to selected-provider brightness events, and listens to provider volume events only when external volume listener is enabled.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }
}



struct HUD: View {
    @EnvironmentObject var vm: NooriViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.progressBarStyle) var progressBarStyle
    @Default(.enableSystemHUD) var enableSystemHUD
    @Default(.enableVolumeHUD) var enableVolumeHUD
    @Default(.enableBrightnessHUD) var enableBrightnessHUD
    @Default(.enableKeyboardBacklightHUD) var enableKeyboardBacklightHUD
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.systemHUDSensitivity) var systemHUDSensitivity
    @ObservedObject var coordinator = NooriViewCoordinator.shared
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var hasAccessibilityPermission: Bool {
        accessibilityPermission.isAuthorized
    }

    private var colorCodingDisabled: Bool {
        progressBarStyle == .segmented
    }

    var body: some View {
        Form {
            if !hasAccessibilityPermission && !enableThirdPartyDDCIntegration {
                Section {
                    SettingsPermissionCallout(
                        message: "Accessibility permission lets Noori replace the native volume, brightness, and keyboard HUDs.",
                        requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                        openSettingsAction: { accessibilityPermission.openSystemSettings() }
                    )
                } header: {
                    Text("Accessibility")
                }
            }

            Section {
                Toggle("Show Noori HUD", isOn: $enableSystemHUD)
            } footer: {
                Text("Replaces the macOS volume, brightness, and keyboard backlight pop-ups with Noori's HUD in the notch.")
            }

            if enableSystemHUD && (hasAccessibilityPermission || enableThirdPartyDDCIntegration) {
                Section {
                    Toggle("Volume HUD", isOn: $enableVolumeHUD)
                    Toggle("Brightness HUD", isOn: $enableBrightnessHUD)
                    Toggle("Keyboard backlight HUD", isOn: $enableKeyboardBacklightHUD)
                        .disabled(enableThirdPartyDDCIntegration)
                        .help(enableThirdPartyDDCIntegration ? "Disabled while external display integration is active \u{2014} brightness keys are handled by the external app." : "")
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Choose which system controls should display HUD notifications.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }


            Section {
                if !colorCodingDisabled && Defaults[.useColorCodedBatteryDisplay] {
                    Defaults.Toggle(key: .useSmoothColorGradient) {
                        Text("Smooth color transitions")
                    }
                    .settingsHighlight(id: highlightID("Smooth color transitions"))
                }

                Defaults.Toggle(key: .showProgressPercentages) {
                    Text("Show percentages beside progress bars")
                }
                .settingsHighlight(id: highlightID("Show percentages beside progress bars"))
            } header: {
                Text("Progress bars")
            } footer: {
                if colorCodingDisabled {
                    Text("Color-coded fills and smooth gradients are unavailable in Segmented mode. Switch to Hierarchical or Gradient to adjust these options.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if Defaults[.useSmoothColorGradient] {
                    Text("Smooth transitions blend Green (0–60%), Yellow (60–85%), and Red (85–100%) through the entire fill.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("Discrete transitions snap between Green (0–60%), Yellow (60–85%), and Red (85–100%).")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section {
                Picker("HUD style", selection: $inlineHUD) {
                    Text("Default")
                        .tag(false)
                    Text("Inline")
                        .tag(true)
                }
                .settingsHighlight(id: highlightID("HUD style"))
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.progressBarStyle] = .hierarchical
                        }
                    }
                }
                Picker("Progress bar style", selection: $progressBarStyle) {
                    Text("Hierarchical")
                        .tag(ProgressBarStyle.hierarchical)
                    Text("Gradient")
                        .tag(ProgressBarStyle.gradient)
                    Text("Segmented")
                        .tag(ProgressBarStyle.segmented)
                }
                .settingsHighlight(id: highlightID("Progressbar style"))
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("Enable glowing effect")
                }
                .settingsHighlight(id: highlightID("Enable glowing effect"))
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("Use accent color")
                }
                .settingsHighlight(id: highlightID("Use accent color"))
            } header: {
                HStack {
                    Text("Appearance")
                }
            }

            // Step size and third-party display integrations
            ExternalDisplayIntegrationsSection()
        }
        .navigationTitle("Controls")
        .onAppear {
            accessibilityPermission.refreshStatus()
        }
        .onChange(of: accessibilityPermission.isAuthorized) { _, granted in
            if !granted {
                enableSystemHUD = false
            }
        }
    }
}
