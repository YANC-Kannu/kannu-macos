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

/// The sideways agent pill on a notched MacBook's closed notch: the dot (or dots) in a left wing, the
/// hardware housing in the middle, and one still app icon in a right wing, all at the closed height.
/// It replaced the band that grew below the housing (`AgentPillLayout.belowNotch`, still in Brain).
///
/// - Both wings are the same width, so the housing stays centred on the camera:
///   `max(what the left wing holds, the icon) + 2 × wingPadding`, the music wings' arithmetic.
/// - The icon is `closedHeight − 12` square, the size of the download and lock-screen wings' icons.
/// - The left wing holds the dots (Classic three, Minimal one) and, while a high finding waits, the
///   security shield beside them, which widens both wings so the housing never moves off centre.
struct ClosedAgentPillLayout: Equatable {
    static let wingPadding: CGFloat = 6
    /// Closed height minus this is the icon's side, as in `DownloadLiveActivity` and the lock pill.
    static let iconInset: CGFloat = 12
    /// `AgentTrafficLightDots`' defaults: what the band draws, drawn here at the same size.
    static let dotSize: CGFloat = 10
    static let dotSpacing: CGFloat = 6
    /// The shield glyph's slot (`SecurityShieldGlyph`, 9 pt type) and its gap from the dots.
    static let shieldWidth: CGFloat = 10
    static let shieldSpacing: CGFloat = 6

    let closedHeight: CGFloat
    let housingWidth: CGFloat
    let dotCount: Int
    let showsShield: Bool

    init(closedHeight: CGFloat, housingWidth: CGFloat, dotCount: Int, showsShield: Bool) {
        self.closedHeight = max(0, closedHeight)
        self.housingWidth = max(0, housingWidth)
        self.dotCount = max(0, dotCount)
        self.showsShield = showsShield
    }

    /// The square app icon in the right wing.
    var iconSize: CGFloat { max(0, closedHeight - Self.iconInset) }

    var dotsWidth: CGFloat {
        guard dotCount > 0 else { return 0 }
        return CGFloat(dotCount) * Self.dotSize + CGFloat(dotCount - 1) * Self.dotSpacing
    }

    /// The dots, and the shield beside them while it shows.
    var leftContentWidth: CGFloat {
        guard showsShield else { return dotsWidth }
        return dotsWidth + (dotsWidth > 0 ? Self.shieldSpacing : 0) + Self.shieldWidth
    }

    /// Each wing's width; the two are always equal.
    var wingWidth: CGFloat { max(leftContentWidth, iconSize) + 2 * Self.wingPadding }

    /// The whole pill: both wings and the housing between them.
    var width: CGFloat { housingWidth + 2 * wingWidth }

    /// Where the dots (and shield) sit in the left wing: centred in it, vertically centred.
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
