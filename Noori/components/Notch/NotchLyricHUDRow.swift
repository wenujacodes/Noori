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

/// Volume, brightness or keyboard backlight, shown as a bar under the lyrics in the
/// closed notch while lyrics are showing (instead of the wide inline HUD).
struct NotchLyricHUDRow: View {
    let type: SneakContentType
    let value: CGFloat
    let width: CGFloat

    @ObservedObject private var muteState = VolumeMuteState.shared

    private var clamped: CGFloat { min(1, max(0, value)) }
    private var isMuted: Bool { type == .volume && (muteState.isMuted || clamped == 0) }

    private var symbol: String {
        switch type {
        case .volume:
            if isMuted { return "speaker.slash.fill" }
            if clamped < 0.3 { return "speaker.wave.1.fill" }
            if clamped < 0.8 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return clamped < 0.6 ? "sun.min.fill" : "sun.max.fill"
        default:
            return clamped < 0.5 ? "light.min" : "light.max"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 20)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule()
                        .fill(isMuted ? Color.red : .white)
                        .frame(width: geo.size.width * (isMuted ? max(clamped, muteState.level) : clamped))
                }
            }
            .frame(height: 5)
            .animation(NooriMotion.change, value: clamped)

            Text("\(Int((clamped * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
                .contentTransition(.numericText())
                .animation(NooriMotion.change, value: clamped)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(width: width)
    }
}
