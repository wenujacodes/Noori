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

/// The Bluetooth rune, drawn as a path because SF Symbols has no Bluetooth logo.
/// HUD icon strings use `BluetoothGlyph.onIcon` / `.offIcon` to ask for it.
struct BluetoothGlyph: View {
    static let onIcon = "noori.bluetooth"
    static let offIcon = "noori.bluetooth.slash"

    /// True for HUD icon strings that should draw this glyph.
    static func handles(_ icon: String) -> Bool {
        icon == onIcon || icon == offIcon
    }

    var isOff: Bool = false

    var body: some View {
        ZStack {
            BluetoothRuneShape()
                .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            if isOff {
                SlashShape()
                    .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
        .frame(width: 12, height: 16)
    }
}

/// The ᛒ-style rune: a vertical stem with two arrowheads on the right.
private struct BluetoothRuneShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        // Lower-left tail, up through the centre to the top arrowhead, down the stem.
        path.move(to: point(0.12, 0.28))
        path.addLine(to: point(0.88, 0.72))
        path.addLine(to: point(0.5, 0.98))
        path.addLine(to: point(0.5, 0.02))
        path.addLine(to: point(0.88, 0.28))
        path.addLine(to: point(0.12, 0.72))
        return path
    }
}

private struct SlashShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - 2, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: rect.maxX + 2, y: rect.maxY - 1))
        return path
    }
}

enum BluetoothBatteryColor {
    /// Green at 75% and up, then smoothly yellow (50%), orange (25%) and red (10% and below).
    static func color(for level: CGFloat) -> Color {
        let stops: [(level: CGFloat, rgb: (CGFloat, CGFloat, CGFloat))] = [
            (0.10, (0.95, 0.27, 0.23)),  // red
            (0.25, (1.00, 0.58, 0.00)),  // orange
            (0.50, (1.00, 0.80, 0.00)),  // yellow
            (0.75, (0.20, 0.78, 0.35)),  // green
        ]
        let clamped = min(max(level, 0), 1)
        if clamped <= stops[0].level { return rgb(stops[0].rgb) }
        if clamped >= stops[stops.count - 1].level { return rgb(stops[stops.count - 1].rgb) }
        for index in 1..<stops.count where clamped <= stops[index].level {
            let lower = stops[index - 1]
            let upper = stops[index]
            let t = (clamped - lower.level) / (upper.level - lower.level)
            return rgb((
                lower.rgb.0 + (upper.rgb.0 - lower.rgb.0) * t,
                lower.rgb.1 + (upper.rgb.1 - lower.rgb.1) * t,
                lower.rgb.2 + (upper.rgb.2 - lower.rgb.2) * t
            ))
        }
        return rgb(stops[stops.count - 1].rgb)
    }

    private static func rgb(_ c: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(red: c.0, green: c.1, blue: c.2)
    }
}
