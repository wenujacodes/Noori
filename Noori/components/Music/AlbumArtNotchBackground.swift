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

/// The current song's album art filling the open notch behind the player
/// (Settings › Music › "Album art background"). It's dimmed so the text stays
/// readable, and the top stays black so the notch still blends with the
/// camera housing. A new cover crossfades in.
struct AlbumArtNotchBackground: View {
    @ObservedObject private var musicManager = MusicManager.shared

    /// Height of the solid black band at the top (the closed notch's height).
    let topBlack: CGFloat

    var body: some View {
        ZStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                // A light blur hides the stretched pixels of small covers.
                .blur(radius: 3, opaque: true)
                .id(ObjectIdentifier(musicManager.albumArt))
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.5), value: ObjectIdentifier(musicManager.albumArt))
        // Dim it, a little more toward the bottom where the controls are.
        .overlay {
            LinearGradient(
                colors: [.black.opacity(0.25), .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        // Black at the top (the camera area), fading into the art below it.
        .mask {
            VStack(spacing: 0) {
                Color.clear.frame(height: topBlack)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 36)
                Color.black
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
