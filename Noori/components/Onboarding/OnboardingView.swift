/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 * Based on Atoll, Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll, and then for Noori
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import AVFoundation
import Defaults

enum OnboardingStep {
    case welcome
    case musicPermission
    case finished
}


struct OnboardingView: View {
    @State private var step: OnboardingStep = .welcome
    @State private var showFocusMonitoringChoice = false
    @State private var didPresentFocusMonitoringChoice = false
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .musicPermission
                    }
                }
                .transition(.opacity)

            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        applyDefaultSetup()
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .finished
                        }
                    }
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
        .onAppear {
            guard !didPresentFocusMonitoringChoice else { return }
            didPresentFocusMonitoringChoice = true
            showFocusMonitoringChoice = true
        }
        .confirmationDialog(
            "Focus detection mode",
            isPresented: $showFocusMonitoringChoice,
            titleVisibility: .visible
        ) {
            Button("Use DevTools") {
                Defaults[.focusMonitoringMode] = .useDevTools
            }

            Button("Use without DevTools") {
                Defaults[.focusMonitoringMode] = .withoutDevTools
            }

            Button("Later", role: .cancel) {}
        } message: {
            Text("This is optional. You can change it any time in Settings.")
        }
    }

}

/// First-run setup: haptics on, and a display style that matches the Mac's screen.
func applyDefaultSetup() {
    Defaults[.enableHaptics] = true

    // Notch Macs keep the standard notch; Macs without one get the Noori pill.
    let hasNotch = (NSScreen.main?.safeAreaInsets.top ?? 0) > 0
    Defaults[.externalDisplayStyle] = hasNotch ? .notch : .noori
}

