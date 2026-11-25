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

/// The call pill on the closed notch: the calling app's still icon in a left wing, the housing in
/// the middle, and in a right wing a phone glyph with the elapsed time, or a ringing glyph alone
/// while it rings, and a camera glyph while the camera is on.
///
/// Modelled on `ClosedAgentPillLayout`, whose icon size and wing padding it shares:
/// - Both wings are the same width, so the housing stays centred on the camera:
///   `max(the icon, what the right wing holds) + 2 × wingPadding`.
/// - The time has one fixed slot, wide enough for "59:59" at its 11 pt; an hour-long call's
///   "1:00:00" scales down into it. So the pill never changes width while a call runs.
struct ClosedCallPillLayout: Equatable {
    static let wingPadding: CGFloat = ClosedAgentPillLayout.wingPadding
    /// The phone, ringing and camera glyphs' slot.
    static let glyphWidth: CGFloat = 12
    /// Between the glyph, the time and the camera glyph.
    static let spacing: CGFloat = 4
    /// The elapsed time's slot.
    static let timeWidth: CGFloat = 34

    let closedHeight: CGFloat
    let housingWidth: CGFloat
    /// False while it rings: the ringing glyph stands alone.
    let showsTime: Bool
    let showsCamera: Bool

    init(closedHeight: CGFloat, housingWidth: CGFloat, showsTime: Bool, showsCamera: Bool) {
        self.closedHeight = max(0, closedHeight)
        self.housingWidth = max(0, housingWidth)
        self.showsTime = showsTime
        self.showsCamera = showsCamera
    }

    /// The square app icon in the left wing: the agent pill's, `closedHeight − 16`.
    var iconSize: CGFloat { ClosedAgentPillLayout.iconSize(closedHeight: closedHeight) }

    /// The glyph, then the time and the camera glyph while each shows.
    var rightContentWidth: CGFloat {
        var width = Self.glyphWidth
        if showsTime { width += Self.spacing + Self.timeWidth }
        if showsCamera { width += Self.spacing + Self.glyphWidth }
        return width
    }

    /// Each wing's width; the two are always equal.
    var wingWidth: CGFloat { max(iconSize, rightContentWidth) + 2 * Self.wingPadding }

    /// The whole pill: both wings and the housing between them.
    var width: CGFloat { housingWidth + 2 * wingWidth }

    /// Where the icon sits in the left wing: centred in it, vertically centred.
    var iconRect: CGRect {
        CGRect(x: (wingWidth - iconSize) / 2, y: (closedHeight - iconSize) / 2, width: iconSize, height: iconSize)
    }

    /// Where the glyph, time and camera sit in the right wing, measured from the pill's leading edge.
    var rightContentRect: CGRect {
        CGRect(x: wingWidth + housingWidth + (wingWidth - rightContentWidth) / 2, y: 0,
               width: rightContentWidth, height: closedHeight)
    }
}
