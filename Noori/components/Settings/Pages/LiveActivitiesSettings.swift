//
//  LiveActivitiesSettings.swift
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

struct LiveActivitiesSettings: View {
    @ObservedObject var coordinator = NooriViewCoordinator.shared
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @ObservedObject var privacyManager = PrivacyIndicatorManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared

    @Default(.enableScreenRecordingDetection) var enableScreenRecordingDetection
    @Default(.enableDoNotDisturbDetection) var enableDoNotDisturbDetection
    @Default(.focusIndicatorNonPersistent) var focusIndicatorNonPersistent
    @Default(.capsLockIndicatorTintMode) var capsLockTintMode

    private func highlightID(_ title: String) -> String {
        SettingsTab.liveActivities.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableScreenRecordingDetection) {
                    Text("Enable Screen Recording Detection")
                }
                .settingsHighlight(id: highlightID("Enable Screen Recording Detection"))

                Defaults.Toggle(key: .showRecordingIndicator) {
                    Text("Show Recording Indicator")
                }
                .disabled(!enableScreenRecordingDetection)
                .settingsHighlight(id: highlightID("Show Recording Indicator"))

                if recordingManager.isMonitoring {
                    HStack {
                        Text("Detection status")
                        Spacer()
                        if recordingManager.isRecording {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("Recording detected")
                                    .foregroundColor(.red)
                            }
                        } else {
                            Text("Active - No Recording")
                                .foregroundColor(.green)
                        }
                    }
                }
            } header: {
                Text("Screen recording")
            } footer: {
                Text("Uses event-driven private API for real-time screen recording detection")
            }

            Section {
                Defaults.Toggle(key: .enableDoNotDisturbDetection) {
                    Text("Enable Focus Detection")
                }
                .settingsHighlight(id: highlightID("Enable Focus Detection"))

                Defaults.Toggle(key: .showDoNotDisturbIndicator) {
                    Text("Show Focus Indicator")
                }
                .disabled(!enableDoNotDisturbDetection)
                .settingsHighlight(id: highlightID("Show Focus Indicator"))

                Defaults.Toggle(key: .showDoNotDisturbLabel) {
                    Text("Show Focus Label")
                }
                .disabled(!enableDoNotDisturbDetection || focusIndicatorNonPersistent)
                .help(focusIndicatorNonPersistent ? "Labels are forced to compact on/off text while brief toast mode is enabled." : "Show the active Focus name inside the indicator.")
                .settingsHighlight(id: highlightID("Show Focus Label"))

                Defaults.Toggle(key: .focusIndicatorNonPersistent) {
                    Text("Show Focus as brief toast")
                }
                .disabled(!enableDoNotDisturbDetection)
                .settingsHighlight(id: highlightID("Show Focus as brief toast"))
                .help("When enabled, Focus appears briefly (on/off) and then collapses instead of staying visible.")

                if doNotDisturbManager.isMonitoring {
                    HStack {
                        Text("Focus status")
                        Spacer()
                        if doNotDisturbManager.isDoNotDisturbActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.purple)
                                    .frame(width: 8, height: 8)
                                Text(doNotDisturbManager.currentFocusModeName.isEmpty ? "Focus Enabled" : doNotDisturbManager.currentFocusModeName)
                                    .foregroundColor(.purple)
                            }
                        } else {
                            Text("Active - No Focus")
                                .foregroundColor(.green)
                        }
                    }
                } else {
                    HStack {
                        Text("Focus status")
                        Spacer()
                        Text("Disabled")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Do Not Disturb")
            } footer: {
                Text("Listens for Focus session changes via distributed notifications")
            }

            Section {
                Defaults.Toggle(key: .enableCapsLockIndicator) {
                    Text("Show Caps Lock Indicator")
                }
                .settingsHighlight(id: highlightID("Show Caps Lock Indicator"))

                Defaults.Toggle(key: .showCapsLockLabel) {
                    Text("Show Caps Lock label")
                }
                .disabled(!Defaults[.enableCapsLockIndicator])
                .settingsHighlight(id: highlightID("Show Caps Lock label"))

                Picker("Caps Lock color", selection: $capsLockTintMode) {
                    ForEach(CapsLockIndicatorTintMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!Defaults[.enableCapsLockIndicator])
                .settingsHighlight(id: highlightID("Caps Lock color"))
            } header: {
                Text("Caps Lock indicator")
            } footer: {
                Text("Adds a notch HUD when Caps Lock is enabled, with optional label and tint controls.")
            }

            Section {
                Defaults.Toggle(key: .enableCameraDetection) {
                    Text("Enable Camera Detection")
                }
                .settingsHighlight(id: highlightID("Enable Camera Detection"))
                Defaults.Toggle(key: .enableMicrophoneDetection) {
                    Text("Enable Microphone Detection")
                }
                .settingsHighlight(id: highlightID("Enable Microphone Detection"))

                if privacyManager.isMonitoring {
                    HStack {
                        Text("Camera status")
                        Spacer()
                        if privacyManager.cameraActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Camera active")
                                    .foregroundColor(.green)
                            }
                        } else {
                            Text("Inactive")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Microphone status")
                        Spacer()
                        if privacyManager.microphoneActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.yellow)
                                    .frame(width: 8, height: 8)
                                Text("Microphone active")
                                    .foregroundColor(.yellow)
                            }
                        } else {
                            Text("Inactive")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Privacy indicators")
            } footer: {
                Text("Shows green camera icon and yellow microphone icon when in use. Uses event-driven CoreAudio and CoreMediaIO APIs.")
            }

            Section {
                Toggle(
                    "Enable music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                .settingsHighlight(id: highlightID("Enable music live activity"))
            } header: {
                Text("Media live activity")
            } footer: {
                Text("Use the Media tab to configure sneak peek.")
            }

        }
        .navigationTitle("Live Activities")
    }
}
