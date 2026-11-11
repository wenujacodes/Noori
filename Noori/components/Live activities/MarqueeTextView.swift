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

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct MeasureSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
        })
    }
}

struct MarqueeText: View {
    @Binding var text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat
    /// Called when a scroll starts with how long one full pass takes, so a
    /// sneak peek can stay open until the whole text has been shown.
    var onScrollPass: ((TimeInterval) -> Void)? = nil
    
    @State private var textSize: CGSize = .zero
    @State private var offset: CGFloat = 0
    @State private var isAnimating: Bool = false
    /// Changes on every restart; a loop stops as soon as it's no longer current,
    /// so restarts (appear, resize, new text) never leave several loops running
    /// that keep snapping the text back to the start.
    @State private var loopID = UUID()
    
    init(_ text: Binding<String>, font: Font = .body, nsFont: NSFont.TextStyle = .body, textColor: Color = .primary, backgroundColor: Color = .clear, minDuration: Double = 3.0, frameWidth: CGFloat = 200, onScrollPass: ((TimeInterval) -> Void)? = nil) {
        _text = text
        self.onScrollPass = onScrollPass
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
    }
    
    private var needsScrolling: Bool {
        textSize.width > frameWidth
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 20) {
                Text(text)
                Text(text)
                    .opacity(needsScrolling ? 1 : 0)
            }
            .id(text)
            .font(font)
            .foregroundColor(textColor)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: offset)
            .background(backgroundColor)
            .modifier(MeasureSizeModifier())
            .onPreferenceChange(SizePreferenceKey.self) { size in
                // The measured row is text + 20 pt gap + text, so one copy is
                // (width - 20) / 2. Halving the whole row over-measured by 10 pt,
                // and the loop's snap back to the start jumped sideways.
                self.textSize = CGSize(width: max(0, (size.width - 20) / 2), height: NSFont.preferredFont(forTextStyle: nsFont).pointSize)
                resetAndStart()
            }
            .onChange(of: text) { _, _ in
                resetAndStart()
            }
            // The space can change after the text appears (a HUD settling to
            // its width); recheck whether it needs to scroll.
            .onChange(of: frameWidth) { _, _ in
                resetAndStart()
            }
            .onAppear {
                resetAndStart()
            }
            .onDisappear {
                isAnimating = false
            }
        }
        .frame(width: frameWidth, alignment: .leading)
        .clipped()
        // Sized from the font, not the measured text, which is 0 until the first
        // measurement and would hide the text if that never comes.
        .frame(height: NSFont.preferredFont(forTextStyle: nsFont).pointSize * 1.3)
    }
    
    private func resetAndStart() {
        let id = UUID()
        loopID = id
        isAnimating = false
        withAnimation(.none) {
            offset = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard loopID == id, needsScrolling else { return }
            isAnimating = true
            // Pause, one pass, then a moment on the start of the text again.
            onScrollPass?(minDuration + Double(textSize.width / 30) + 0.8)
            startAnimationLoop(id: id)
        }
    }
    
    private func startAnimationLoop(id: UUID) {
        guard loopID == id, isAnimating, needsScrolling else { return }
        
        // Duration based on speed (approx 30 pts per second)
        let duration = Double(textSize.width / 30)
        
        // 1. Initial/Restart Pause
        DispatchQueue.main.asyncAfter(deadline: .now() + minDuration) {
            guard loopID == id, isAnimating else { return }
            
            // 2. Linear Move
            withAnimation(.linear(duration: duration)) {
                offset = -(textSize.width + 20) // Text width + spacing
            }
            
            // 3. Wait for move to finish
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                guard loopID == id, isAnimating else { return }
                
                // 4. Snap back instantly
                withAnimation(.none) {
                    offset = 0
                }
                
                // 5. Repeat
                startAnimationLoop(id: id)
            }
        }
    }
}

struct MusicExplicitBadge: View {
    var label: String = "E"
    var fontSize: CGFloat = 9
    var height: CGFloat = 14
    var horizontalPadding: CGFloat = 4
    var minWidth: CGFloat? = nil
    var foregroundColor: Color = .black
    var backgroundColor: Color = .white
    var cornerRadius: CGFloat? = nil
    var body: some View {
        Text(label)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundColor(foregroundColor)
            .padding(.horizontal, max(horizontalPadding, height * 0.2))
            .frame(minWidth: minWidth, minHeight: height)
            .background(
                RoundedRectangle(
                    cornerRadius: cornerRadius ?? max(4, height * 0.28),
                    style: .continuous
                )
                .fill(backgroundColor)
            )
            .fixedSize()
    }
}

struct MusicTitleMarqueeView: View {
    let text: String
    let isExplicit: Bool
    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat
    let alignment: Alignment
    let badgeSpacing: CGFloat
    let badgeLabel: String
    let badgeFontSize: CGFloat?
    let badgeHeight: CGFloat?
    let badgeForegroundColor: Color
    let badgeBackgroundColor: Color
    let badgeHorizontalPadding: CGFloat
    let badgeMinWidth: CGFloat?
    let badgeCornerRadius: CGFloat?
    let onScrollPass: ((TimeInterval) -> Void)?

    init(
        text: String,
        isExplicit: Bool,
        font: Font = .body,
        nsFont: NSFont.TextStyle = .body,
        textColor: Color = .primary,
        backgroundColor: Color = .clear,
        minDuration: Double = 0.5,
        frameWidth: CGFloat = 200,
        alignment: Alignment = .leading,
        badgeSpacing: CGFloat = 6,
        badgeLabel: String = "E",
        badgeFontSize: CGFloat? = nil,
        badgeHeight: CGFloat? = nil,
        badgeForegroundColor: Color = .black,
        badgeBackgroundColor: Color = .white,
        badgeHorizontalPadding: CGFloat = 4,
        badgeMinWidth: CGFloat? = nil,
        badgeCornerRadius: CGFloat? = nil,
        onScrollPass: ((TimeInterval) -> Void)? = nil
    ) {
        self.onScrollPass = onScrollPass
        self.text = text
        self.isExplicit = isExplicit
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
        self.alignment = alignment
        self.badgeSpacing = badgeSpacing
        self.badgeLabel = badgeLabel
        self.badgeFontSize = badgeFontSize
        self.badgeHeight = badgeHeight
        self.badgeForegroundColor = badgeForegroundColor
        self.badgeBackgroundColor = badgeBackgroundColor
        self.badgeHorizontalPadding = badgeHorizontalPadding
        self.badgeMinWidth = badgeMinWidth
        self.badgeCornerRadius = badgeCornerRadius
    }

    private var resolvedBadgeHeight: CGFloat {
        badgeHeight ?? max(12, NSFont.preferredFont(forTextStyle: nsFont).pointSize * 1.12)
    }

    private var resolvedBadgeFontSize: CGFloat {
        badgeFontSize ?? max(8, resolvedBadgeHeight * 0.6)
    }

    private var reservedBadgeWidth: CGFloat {
        guard isExplicit else { return 0 }
        return resolvedBadgeHeight + (resolvedBadgeHeight * 0.7) + badgeSpacing
    }

    private var titleFrameWidth: CGFloat {
        max(0, frameWidth - reservedBadgeWidth)
    }

    /// Width of the title as actually drawn in `font`. Measuring with `nsFont`
    /// instead could under-measure (e.g. 12 pt semibold vs. subheadline), so a
    /// slightly-too-long title wouldn't scroll and would overflow its frame.
    @State private var renderedTextWidth: CGFloat = 0

    private var needsScrolling: Bool {
        ceil(renderedTextWidth) > titleFrameWidth
    }

    var body: some View {
        HStack(spacing: badgeSpacing) {
            if needsScrolling {
                MarqueeText(
                    .constant(text),
                    font: font,
                    nsFont: nsFont,
                    textColor: textColor,
                    backgroundColor: backgroundColor,
                    minDuration: minDuration,
                    frameWidth: titleFrameWidth,
                    onScrollPass: onScrollPass
                )
            } else {
                Text(text)
                    .font(font)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if isExplicit {
                MusicExplicitBadge(
                    label: badgeLabel,
                    fontSize: resolvedBadgeFontSize,
                    height: resolvedBadgeHeight,
                    horizontalPadding: badgeHorizontalPadding,
                    minWidth: badgeMinWidth,
                    foregroundColor: badgeForegroundColor,
                    backgroundColor: badgeBackgroundColor,
                    cornerRadius: badgeCornerRadius
                )
            }
        }
        .frame(width: frameWidth, alignment: alignment)
        .background(alignment: .leading) {
            // Invisible copy of the title, only to measure its real width.
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    renderedTextWidth = width
                }
        }
    }
}
