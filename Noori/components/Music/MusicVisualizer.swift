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
import Defaults

/// The music visualizer's bars: thin white capsules that bounce to random
/// heights while music plays and rest low when it's paused.
///
/// Pure SwiftUI on purpose. It used to be an AppKit view (CAShapeLayers), and
/// an AppKit view inside the notch made macOS sometimes drop the notch's
/// rounded clip, leaving a square-cornered box until the next hover.
struct AudioSpectrumView: View {
    @Binding var isPlaying: Bool

    private let barCount = Defaults[.visualizerBarCount]
    private static let barWidth: CGFloat = 2
    private static let height: CGFloat = 14
    private static let restingScale: CGFloat = 0.35
    /// How often the bars pick new heights (as before: 0.3 s up, 0.3 s back).
    private static let step: Duration = .milliseconds(300)

    @State private var scales: [CGFloat] = []

    var body: some View {
        HStack(spacing: Self.barWidth) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(.white)
                    .frame(width: Self.barWidth, height: Self.height)
                    .scaleEffect(y: scale(at: index), anchor: .center)
            }
        }
        .frame(width: CGFloat(barCount) * Self.barWidth * 2, height: Self.height, alignment: .leading)
        // Runs only while playing, and stops when the view goes away.
        .task(id: isPlaying) {
            guard isPlaying else {
                withAnimation(.easeOut(duration: 0.3)) { scales = [] }
                return
            }
            var up = true
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.3)) {
                    scales = up
                        ? (0..<barCount).map { _ in CGFloat.random(in: Self.restingScale...1) }
                        : scales.map { max(Self.restingScale, $0 * 0.55) }
                }
                up.toggle()
                try? await Task.sleep(for: Self.step)
            }
        }
    }

    private func scale(at index: Int) -> CGFloat {
        index < scales.count ? scales[index] : Self.restingScale
    }
}

#Preview {
    AudioSpectrumView(isPlaying: .constant(true))
        .frame(width: 16, height: 20)
        .padding()
        .background(.black)
}
