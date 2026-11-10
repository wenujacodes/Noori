/*
 * Noori
 * Copyright (C) 2026 Wenuja Liyanamana
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI

/// The closed-notch call pill: a green phone and the call's elapsed time on the
/// left, a small decorative waveform on the right (like iPhone's call activity).
struct CallLiveActivity: View {
    @EnvironmentObject var vm: NooriViewModel
    @ObservedObject var callManager = CallActivityManager.shared
    var isHovering: Bool = false
    var gestureProgress: CGFloat = 0
    @State private var isExpanded = false

    static let callGreen = Color(red: 0.204, green: 0.780, blue: 0.349)

    private var wingHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
    }

    private var baseWingWidth: CGFloat {
        max(0, wingHeight + gestureProgress / 2)
    }

    private var leftWingWidth: CGFloat {
        guard isExpanded else { return 0 }
        // Room for the phone and "0:00"; an hour-long call needs a bit more.
        let elapsed = callManager.callStartDate.map { Date().timeIntervalSince($0) } ?? 0
        return baseWingWidth + (elapsed >= 3600 ? 48 : 30)
    }

    private var rightWingWidth: CGFloat {
        isExpanded ? baseWingWidth + 14 : 0
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .background {
                    if isExpanded {
                        HStack(spacing: 5) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Self.callGreen)
                            CallElapsedTimeText(start: callManager.callStartDate ?? Date())
                        }
                        .fixedSize()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.leading, 2)
                        .transition(.opacity)
                    }
                }
                .frame(width: leftWingWidth, height: wingHeight)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + (isHovering ? 8 : 0))

            Color.clear
                .background {
                    if isExpanded {
                        CallWaveformView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .padding(.trailing, 2)
                            .transition(.opacity)
                    }
                }
                .frame(width: rightWingWidth, height: wingHeight)
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(callManager.activeApp.map { "Call in \($0.name)" } ?? "Call"))
        .onAppear {
            withAnimation(NooriMotion.appear) { isExpanded = true }
        }
        .onChange(of: callManager.isCallActive) { _, active in
            withAnimation(NooriMotion.appear) { isExpanded = active }
        }
    }
}

/// "0:00" counting up from `start`, refreshed once a second.
private struct CallElapsedTimeText: View {
    let start: Date

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            Text(Self.format(context.date.timeIntervalSince(start)))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(CallLiveActivity.callGreen)
                .lineLimit(1)
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// A gentle, decorative call waveform: thin rounded bars going from white to
/// peach. It's not driven by real audio.
private struct CallWaveformView: View {
    private let barCount = 9
    private let barWidth: CGFloat = 2
    private let spacing: CGFloat = 2
    private let maxHeight: CGFloat = 14
    private let minHeight: CGFloat = 3

    /// The peach the bars fade to (RGB).
    private static let peach: (r: Double, g: Double, b: Double) = (1.0, 0.62, 0.42)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(color(for: index))
                        .frame(width: barWidth, height: height(for: index, at: t))
                }
            }
            .frame(height: maxHeight)
        }
    }

    private func height(for index: Int, at t: TimeInterval) -> CGFloat {
        let i = Double(index)
        // Two slow sine waves per bar, offset so neighbours move differently.
        let a = sin(t * 3.1 + i * 0.9)
        let b = sin(t * 4.7 + i * 1.7 + 1.3)
        // Bars in the middle swing a bit more than the ends.
        let centerWeight = 1 - abs(i - Double(barCount - 1) / 2) / Double(barCount) * 0.9
        let level = ((a + b) / 4 + 0.5) * centerWeight
        return minHeight + (maxHeight - minHeight) * CGFloat(max(0, min(1, level)))
    }

    private func color(for index: Int) -> Color {
        let fraction = Double(index) / Double(barCount - 1)
        return Color(
            red: 1 + (Self.peach.r - 1) * fraction,
            green: 1 + (Self.peach.g - 1) * fraction,
            blue: 1 + (Self.peach.b - 1) * fraction
        )
    }
}
