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
import Combine
import CoreImage
import Defaults
import SwiftUI

/// The blurred covers behind the notch, made once per song.
///
/// Blurring in SwiftUI (`.blur`) redoes the work on every frame the notch
/// grows or shrinks, which made opening and closing stutter. Like Lyrimuse's
/// backdrop, the cover is instead shrunk and blurred once with Core Image, off
/// the main thread, and the notch only shows the finished small bitmaps
/// (scaling a small image up is nearly free and adds its own softness).
@MainActor
final class AlbumArtBackdrop: ObservableObject {
    static let shared = AlbumArtBackdrop()

    /// The cover, softened a little (about 256 px).
    @Published private(set) var soft: NSImage?
    /// The cover, heavily blurred (a 64 px image).
    @Published private(set) var heavy: NSImage?
    /// Changes with every new cover, for the crossfade.
    @Published private(set) var revision = 0

    private var cancellables = Set<AnyCancellable>()
    private var renderTask: Task<Void, Never>?
    private var renderedArt: ObjectIdentifier?

    private static let context = CIContext(options: [.cacheIntermediates: false])

    private init() {
        // Only does work while one of the album art backgrounds is turned on.
        Publishers.CombineLatest3(
            MusicManager.shared.$albumArt,
            Defaults.publisher(.albumArtNotchBackground).map(\.newValue),
            Defaults.publisher(.albumArtClosedLyricsBackground).map(\.newValue)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] art, open, closed in
            guard let self else { return }
            if open || closed {
                self.render(art)
            } else {
                self.renderTask?.cancel()
                self.renderedArt = nil
                self.soft = nil
                self.heavy = nil
            }
        }
        .store(in: &cancellables)
    }

    private func render(_ art: NSImage) {
        let id = ObjectIdentifier(art)
        guard id != renderedArt else { return }
        renderedArt = id
        renderTask?.cancel()
        guard let cgImage = art.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        renderTask = Task.detached(priority: .userInitiated) {
            let soft = Self.blurred(cgImage, side: 256, radius: 1.5)
            let heavy = Self.blurred(cgImage, side: 64, radius: 6)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.renderedArt == id else { return }
                self.soft = soft.map { NSImage(cgImage: $0, size: .zero) }
                self.heavy = heavy.map { NSImage(cgImage: $0, size: .zero) }
                self.revision &+= 1
            }
        }
    }

    /// The cover cropped square, shrunk to `side` pixels and blurred by
    /// `radius` pixels (edges clamped, so they don't fade to transparent).
    nonisolated private static func blurred(_ source: CGImage, side: Int, radius: Double) -> CGImage? {
        let w = source.width, h = source.height
        guard w > 0, h > 0 else { return nil }
        let s = min(w, h)
        guard let square = source.cropping(to: CGRect(x: (w - s) / 2, y: (h - s) / 2, width: s, height: s)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // High-quality shrink averages the pixels (no moiré on halftone covers).
        ctx.interpolationQuality = .high
        ctx.draw(square, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let small = ctx.makeImage() else { return nil }

        let input = CIImage(cgImage: small)
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return small }
        blur.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage?.cropped(to: input.extent) else { return small }
        return context.createCGImage(output, from: input.extent)
    }
}

/// The current song's album art behind the notch (Settings › Music › Player).
/// One view for both the closed notch's lyrics and the open notch, so opening
/// and closing never crossfade between two differently blurred copies: the
/// heavily blurred cover always stays, and opening only fades in the sharper
/// cover over its top half. The top stays black so the notch still blends with
/// the camera housing, and a new cover crossfades in.
struct AlbumArtNotchBackground: View {
    @ObservedObject private var backdrop = AlbumArtBackdrop.shared

    /// Show the sharper cover at the top (the open notch).
    let sharpTop: Bool
    /// Height of the solid black band at the top (the closed notch's height).
    let topBlack: CGFloat

    var body: some View {
        // Solid black at the top (the camera area), then the art, fading in
        // from black just below it.
        VStack(spacing: 0) {
            Color.black.frame(height: topBlack)
            ZStack {
                layers
                    .id(backdrop.revision)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.5), value: backdrop.revision)
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
            }
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var layers: some View {
        ZStack {
            cover(backdrop.heavy)
            // The sharper cover over the top, melting into the blur from about
            // the middle down. Only its opacity changes when the notch opens.
            cover(backdrop.soft)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.35),
                            .init(color: .clear, location: 0.7),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .animation(.easeOut(duration: 0.3)) { $0.opacity(sharpTop ? 1 : 0) }
        }
        // Darker toward the bottom, where the controls and lyrics are.
        .overlay {
            LinearGradient(
                colors: [.black.opacity(0.25), .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private func cover(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            Color.black
        }
    }
}
