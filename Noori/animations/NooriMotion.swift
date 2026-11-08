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
    /// The notch expanding: grows a little past full size, then settles back.
    static let notchOpen = Animation.spring(duration: 0.5, bounce: 0.3)

    /// The notch collapsing: shrinks a little past closed size, then settles back.
    static let notchClose = Animation.spring(duration: 0.45, bounce: 0.25)

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

    /// Open-notch content growing out of the notch, like Dynamic Island: it starts
    /// a little smaller, anchored to the top edge, and expands on the same spring as
    /// the notch so it feels attached to it. On close it shrinks back up into the notch.
    /// Opacity only covers the first/last moment so it never looks like a crossfade.
    /// It is blurred while moving and sharp once settled.
    static var notchContent: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.8, anchor: .top)
                .combined(with: motionBlur)
                .animation(notchOpen)
                .combined(with: .opacity.animation(.easeOut(duration: 0.12))),
            removal: .scale(scale: 0.85, anchor: .top)
                .combined(with: motionBlur)
                .animation(notchClose)
                .combined(with: .opacity.animation(.easeIn(duration: 0.12).delay(0.05)))
        )
    }

    /// Blurred at the start of an opening / end of a closing, sharp when settled.
    private static var motionBlur: AnyTransition {
        .modifier(
            active: MotionBlurModifier(radius: 12),
            identity: MotionBlurModifier(radius: 0)
        )
    }
}

private struct MotionBlurModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}
