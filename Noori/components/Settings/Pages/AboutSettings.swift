//
//  AboutSettings.swift
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

struct About: View {
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.releaseVersionNumber ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.buildVersionNumber ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Version info")
                }

                UpdaterSettingsView(updater: updaterController.updater)

                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.open(productPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                                .foregroundStyle(.primary)
                            Text("GitHub")
                                .foregroundStyle(.primary)
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())
                .listRowSeparator(.hidden)

                Text("Made with ❤️ by Wenuja Liyanamana")
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            }
        }
        .toolbar {
            //            Button("Welcome window") {
            //                openWindow(id: "onboarding")
            //            }
            //            .controlSize(.extraLarge)
            CheckForUpdatesView(updater: updaterController.updater)
        }
        .navigationTitle("About")
    }
}
