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

/// Decides what the notch shows as the cover when the playing app gives no
/// real one. Music apps may show their own icon; other apps (browsers, video
/// sites) show a plain music-note cover instead of their icon or a site logo.
enum NowPlayingArtwork {
    /// Players Noori knows, for apps that don't mark themselves as music apps.
    private static let knownMusicApps: Set<String> = [
        "com.apple.Music",
        "com.apple.podcasts",
        "com.spotify.client",
        "com.amazon.music",
        "sh.cider.genten.mac",
        "com.github.th-ch.youtube-music",
        "com.tidal.desktop",
        "com.deezer.deezer-desktop",
        "com.qobuz.QobuzDesktop",
        "com.coppertino.Vox",
        "com.colliderli.iina",
        "org.videolan.vlc",
    ]

    private static var musicAppCache: [String: Bool] = [:]
    private static let cacheLock = NSLock()

    /// True for music players: known ones, and apps whose Info.plist puts them
    /// in the Music category.
    static func isMusicApp(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        if knownMusicApps.contains(bundleIdentifier) { return true }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = musicAppCache[bundleIdentifier] { return cached }
        var result = false
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           let category = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String {
            result = category == "public.app-category.music"
        }
        musicAppCache[bundleIdentifier] = result
        return result
    }

    /// The cover shown when there's no real one: a dark tile with a music note,
    /// like Apple Music's empty cover.
    static let placeholder: NSImage = {
        let side: CGFloat = 300
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: side, height: side)
        NSGradient(
            starting: NSColor(white: 0.30, alpha: 1),
            ending: NSColor(white: 0.18, alpha: 1)
        )?.draw(in: rect, angle: -90)
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.4, weight: .regular)
        if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let tinted = NSImage(size: note.size)
            tinted.lockFocus()
            note.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor(white: 1, alpha: 0.55).set()
            NSRect(origin: .zero, size: note.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(
                at: NSPoint(x: (side - note.size.width) / 2, y: (side - note.size.height) / 2),
                from: .zero, operation: .sourceOver, fraction: 1
            )
        }
        image.unlockFocus()
        return image
    }()

    /// True when the picture is mostly one flat color, like a site's logo tile
    /// (Facebook's blue "f"), rather than a cover or a video frame. Dark frames
    /// don't count, so a dim video thumbnail isn't mistaken for a logo.
    static func looksLikeLogo(_ image: NSImage) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Count pixels per coarse color (4 levels per channel).
        var counts: [Int: Int] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let key = (Int(pixels[i]) >> 6) << 4 | (Int(pixels[i + 1]) >> 6) << 2 | Int(pixels[i + 2]) >> 6
            counts[key, default: 0] += 1
        }
        guard let (key, count) = counts.max(by: { $0.value < $1.value }), key != 0 else { return false }
        return Double(count) / Double(side * side) >= 0.6
    }
}
