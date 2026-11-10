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

/// The current song's album art behind the notch (Settings › Music › Player).
/// The top stays black so the notch still blends with the camera housing, and a
/// new cover crossfades in.
struct AlbumArtNotchBackground: View {
    enum Style {
        /// The open notch: the cover fairly sharp at the top, melting into a heavy
        /// blur toward the bottom so the controls and lyrics stay readable.
        case open
        /// Behind the closed notch's lyrics: the whole cover heavily blurred.
        case closedLyrics
    }

    @ObservedObject private var musicManager = MusicManager.shared

    let style: Style
    /// Height of the solid black band at the top (the closed notch's height).
    let topBlack: CGFloat

    private var artID: ObjectIdentifier { ObjectIdentifier(musicManager.albumArt) }

    var body: some View {
        ZStack {
            layers
                .id(artID)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.5), value: artID)
        // Black at the top (the camera area), fading into the art below it.
        .mask {
            VStack(spacing: 0) {
                Color.clear.frame(height: topBlack)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: style == .open ? 36 : 14)
                Color.black
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var layers: some View {
        switch style {
        case .open:
            ZStack {
                // A light blur hides the stretched pixels of small covers.
                cover(blur: 3)
                // The heavy blur takes over from about the middle down.
                cover(blur: 30)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.35),
                                .init(color: .black, location: 0.7),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.2), .black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        case .closedLyrics:
            cover(blur: 30)
                .overlay { Color.black.opacity(0.4) }
        }
    }

    private func cover(blur: CGFloat) -> some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .blur(radius: blur, opaque: true)
    }
}
