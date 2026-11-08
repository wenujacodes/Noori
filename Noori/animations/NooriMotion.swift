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

/// The few motions Noori uses everywhere, so the notch moves consistently,
/// the way built-in macOS UI does. Prefer these over one-off timings.
enum NooriMotion {
    /// The notch expanding: a quick spring with a light bounce.
    static let notchOpen = Animation.spring(response: 0.42, dampingFraction: 0.8)

    /// The notch collapsing: the same speed, settling without a bounce.
    static let notchClose = Animation.spring(response: 0.45, dampingFraction: 1.0)

    /// Picks the open or close motion for a notch state change.
    static func notch(opening: Bool) -> Animation {
        opening ? notchOpen : notchClose
    }

    /// The closed notch reacting to the pointer (hover lift).
    static let hover = Animation.bouncy.speed(1.2)

    /// Something appearing in or leaving the notch: HUDs, live activities, sneak peeks.
    static let appear = Animation.smooth(duration: 0.3)

    /// A value, icon or label changing in place.
    static let change = Animation.smooth(duration: 0.2)

    /// Following a scroll or swipe gesture.
    static let gesture = Animation.smooth
}
