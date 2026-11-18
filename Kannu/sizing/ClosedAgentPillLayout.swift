/*
 * Kannu (കണ്ണ്)
 * Copyright (C) 2024-2026 Kannu Contributors
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

import Foundation

/// The sideways agent pill on a notched MacBook's closed notch: the lit dot in a left wing, the hardware
/// housing in the middle, and one still app icon in a right wing, all at the closed height. It replaced the
/// band that grew below the housing, which 2.0 removed with the Classic three-dot style (David, 2026-11-18).
///
/// - Both wings are the same width, so the housing stays centred on the camera:
///   `max(what the left wing holds, the icon) + 2 × wingPadding`, the music wings' arithmetic.
/// - The icon is `closedHeight − 16` square: 16 pt on a 32 pt notch (David, 2026-11-18: "reduce the logo
///   size a bit"), so a wing is 28 pt and the pill 28 | housing | 28.
/// - The left wing holds the dot and, while a high finding waits, the security shield beside it, which
///   widens both wings so the housing never moves off centre.
struct ClosedAgentPillLayout: Equatable {
    static let wingPadding: CGFloat = 6
    /// Closed height minus this is the icon's side, here and in the lock-screen pill.
    static let iconInset: CGFloat = 16
    /// `AgentTrafficLightDots`' default: the dot every display draws, drawn here at the same size.
    static let dotSize: CGFloat = 10
    /// The shield glyph's slot (`SecurityShieldGlyph`, 9 pt type) and its gap from the dot.
    static let shieldWidth: CGFloat = 10
    static let shieldSpacing: CGFloat = 6

    let closedHeight: CGFloat
    let housingWidth: CGFloat
    let showsShield: Bool

    init(closedHeight: CGFloat, housingWidth: CGFloat, showsShield: Bool) {
        self.closedHeight = max(0, closedHeight)
        self.housingWidth = max(0, housingWidth)
        self.showsShield = showsShield
    }

    /// The app icon's side for a closed notch this tall, never negative.
    static func iconSize(closedHeight: CGFloat) -> CGFloat { max(0, closedHeight - iconInset) }

    /// The square app icon in the right wing.
    var iconSize: CGFloat { Self.iconSize(closedHeight: closedHeight) }

    /// The dot, and the shield beside it while it shows.
    var leftContentWidth: CGFloat {
        guard showsShield else { return Self.dotSize }
        return Self.dotSize + Self.shieldSpacing + Self.shieldWidth
    }

    /// Each wing's width; the two are always equal.
    var wingWidth: CGFloat { max(leftContentWidth, iconSize) + 2 * Self.wingPadding }

    /// The whole pill: both wings and the housing between them.
    var width: CGFloat { housingWidth + 2 * wingWidth }

    /// Where the dot (and shield) sit in the left wing: centred in it, vertically centred.
    var leftContentRect: CGRect {
        CGRect(x: (wingWidth - leftContentWidth) / 2, y: (closedHeight - Self.dotSize) / 2,
               width: leftContentWidth, height: Self.dotSize)
    }

    /// Where the icon sits in the right wing, measured from the pill's leading edge.
    var iconRect: CGRect {
        CGRect(x: wingWidth + housingWidth + (wingWidth - iconSize) / 2, y: (closedHeight - iconSize) / 2,
               width: iconSize, height: iconSize)
    }
}
