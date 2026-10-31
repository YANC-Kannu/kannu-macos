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

/// Where hover may open the notch on a MacBook display: the hardware notch itself, and nothing
/// around it. The hover area also takes in the +8 pt growth, the music and agent wings (which sit
/// over menu-bar items) and the agent band below the notch (which sits over window toolbars and
/// tabs); resting there must not open a panel over what the user was about to click.
enum NotchInteractionGeometry {
    /// The hardware notch in screen coordinates, or nil on a screen without one.
    ///
    /// Width mirrors `getClosedNotchSize` in `sizing/matters.swift`: the screen minus the menu-bar
    /// areas either side of the notch (`NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`),
    /// plus the 4 pt it draws. Centred like the window Kannu draws it in (`resizeWindow`), so the
    /// rect is the notch Kannu actually draws over the hardware one. Height is `safeAreaInsets.top`,
    /// measured down from the top edge.
    static func physicalNotchRect(screenFrame: CGRect, leftAreaWidth: CGFloat, rightAreaWidth: CGFloat,
                                  topInset: CGFloat) -> CGRect? {
        guard topInset > 0 else { return nil }
        let width = screenFrame.width - leftAreaWidth - rightAreaWidth + 4
        guard width > 0 else { return nil }
        return CGRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - topInset,
                      width: width, height: topInset)
    }

    /// Whether a pointer location is on the hardware notch. The top edge is inclusive: the pointer
    /// pinned against the top of the screen reports `y == screenFrame.maxY`, and that counts.
    static func isOnPhysicalNotch(_ point: CGPoint, notch: CGRect) -> Bool {
        point.x >= notch.minX && point.x <= notch.maxX && point.y >= notch.minY && point.y <= notch.maxY
    }

    /// How far past the open notch's edge the pointer still counts as on it, so a pointer resting
    /// on the edge never flaps the notch shut.
    static let openNotchMargin: CGFloat = 4

    /// The open notch's body in screen coordinates, from its frame in its window (SwiftUI's
    /// `.global` space: origin top-left, y down), or nil before it has been laid out.
    ///
    /// The window is pinned to the top of its screen and centred on it (`positionWindow` and
    /// `resizeWindow` in `KannuApp.swift`), and the body is centred in the window, so only the
    /// body's size and its distance from the top are needed; the window's own width is not.
    static func openNotchRect(screenFrame: CGRect, bodyInWindow body: CGRect) -> CGRect? {
        guard body.width > 0, body.height > 0 else { return nil }
        return CGRect(x: screenFrame.midX - body.width / 2, y: screenFrame.maxY - body.maxY,
                      width: body.width, height: body.height)
    }

    /// Whether a pointer location is on the open notch, `margin` included on every side, or on one
    /// of the `attached` windows hanging off it. Those lie past the body's edge but are the notch
    /// all the same: the calendar a reminder's date field drops (AppKit's
    /// `_NSDatePickerOverlayPanel`, a child window of the panel it opens from), a popover. David,
    /// 2026-10-29: "the hover on calendar out of notch area of kannu closes notch". No margin
    /// around them: they have their own edges.
    static func isOnOpenNotch(_ point: CGPoint, notch: CGRect, attached: [CGRect] = [],
                              margin: CGFloat = openNotchMargin) -> Bool {
        notch.insetBy(dx: -margin, dy: -margin).contains(point) || attached.contains { $0.contains(point) }
    }
}
