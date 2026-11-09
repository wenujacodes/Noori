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
    /// The notch expanding: a quick spring that settles without overshooting.
    /// The single bounce at the end comes from `notchOpenBounce` (shape only).
    static let notchOpen = Animation.spring(response: 0.32, dampingFraction: 1.0)

    /// The notch collapsing: a smooth spring with no overshoot or bounce
    /// (overshooting would uncover the real notch).
    static let notchClose = Animation.spring(response: 0.45, dampingFraction: 1.0)

    /// Picks the open or close motion for a notch state change.
    static func notch(opening: Bool) -> Animation {
        opening ? notchOpen : notchClose
    }

    /// The single bounce of the black notch shape when it opens: at its peak it is
    /// 3% wider and 4% taller. Only the shape bounces; the content inside stays put.
    static let notchOpenBounce = CGSize(width: 1.025, height: 1.035)
    /// The swell waits while the notch grows fast, rises to peak as it reaches
    /// full size (about 0.3s in), then eases back, so opening and bounce read
    /// as one continuous motion.
    static let notchBounceWait: TimeInterval = 0.07
    static let notchBounceRise: TimeInterval = 0.2
    static let notchBounceFall: TimeInterval = 0.4

    /// The closed notch reacting to the pointer (hover lift).
    static let hover = Animation.bouncy.speed(1.2)

    /// Something appearing in or leaving the notch: HUDs, live activities, sneak peeks.
    static let appear = Animation.smooth(duration: 0.3)

    /// A value, icon or label changing in place.
    static let change = Animation.smooth(duration: 0.2)

    /// Following a scroll or swipe gesture.
    static let gesture = Animation.smooth

    /// The open-notch content fading in and out. Instead of fading the whole
    /// block, it hands the fade to its parts (`fadesWithNotchContent()`), so the
    /// album art and visualizer, which glide in from the closed notch, stay
    /// fully visible and never flash black.
    static var notchContentFade: AnyTransition {
        let fade = AnyTransition.modifier(
            active: NotchContentFadeModifier(opacity: 0),
            identity: NotchContentFadeModifier(opacity: 1)
        )
        // Opening: the controls finish fading in exactly as the notch reaches
        // full size, not before. Closing: they blur and fade out as the notch shrinks.
        return .asymmetric(
            insertion: fade.animation(.easeOut(duration: contentFadeInDuration).delay(contentFadeInDelay)),
            removal: fade.animation(.easeOut(duration: contentFadeOutDuration))
        )
    }

    /// The controls start fading in once the notch is part-way open...
    static let contentFadeInDelay: TimeInterval = 0.1
    /// ...and are fully shown when it reaches full size (about 0.33s in).
    static let contentFadeInDuration: TimeInterval = 0.19
    /// How long the title and controls take to blur and fade out on close.
    static let contentFadeOutDuration: TimeInterval = 0.25
    /// How blurred the title and controls are when fully faded out.
    static let contentFadeBlur: CGFloat = 10
}

private struct NotchContentFadeModifier: ViewModifier, Animatable {
    var opacity: Double

    var animatableData: Double {
        get { opacity }
        set { opacity = newValue }
    }

    func body(content: Content) -> some View {
        content.environment(\.notchContentOpacity, opacity)
    }
}

extension EnvironmentValues {
    /// How far the open-notch content has faded in (0 = hidden, 1 = shown).
    @Entry var notchContentOpacity: Double = 1
}

private struct FadesWithNotchContentModifier: ViewModifier {
    /// Fade-in progress while opening (from the `notchContentFade` transition).
    @Environment(\.notchContentOpacity) private var openingOpacity
    /// Closing is read from the notch state instead: views on their way out
    /// stop receiving the transition's value, so they would stay sharp.
    @EnvironmentObject private var vm: NooriViewModel
    /// When false the view stays sharp and fully visible (it glides instead).
    let enabled: Bool

    func body(content: Content) -> some View {
        let isClosing = vm.notchState == .closed
        let opacity = !enabled ? 1 : (isClosing ? 0 : openingOpacity)
        content
            .blur(radius: (1 - opacity) * NooriMotion.contentFadeBlur)
            .opacity(opacity)
            .animation(
                isClosing ? .easeOut(duration: NooriMotion.contentFadeOutDuration) : nil,
                value: isClosing
            )
    }
}

extension View {
    /// Open-notch content that fades and blurs in and out with the notch.
    /// Views that glide in from the closed notch (album art, visualizer) pass
    /// `false` while the closed notch shows them, so they stay sharp.
    func fadesWithNotchContent(_ enabled: Bool = true) -> some View {
        modifier(FadesWithNotchContentModifier(enabled: enabled))
    }
}
