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

/// When a Brain list shows its selected item's page beside it (layout-proposal D1, David 2026-11-06): once the panel
/// holds the page inset, the list, the inset again, the item's page and a last inset. Narrower, the page takes the
/// list's place, the in-tab swap. A function of the panel's width alone, so a page reads it from one measurement and
/// never needs `minWidth:` (SwiftUI's size bridge would clamp the window to it, docs/REGRESSIONS.md entry 17),
/// `ViewThatFits` (which builds every layout it tries) or `.inspector`. Foundation only, so the test target compiles it.
enum ListDetailLayout {
    /// The list's width beside the page: a task's title, its caption with one tag, and the row's three controls.
    static let listWidth: CGFloat = 360

    /// Whether a panel `panelWidth` wide holds the list and a page `pageWidth` wide side by side, `inset` before the
    /// list, between the two and after the page. With Brain's widths (an inset of 48 and the 720-pt settings column)
    /// that is a panel of 1,224 pt: a 14-inch Mac in full screen, never the window's first size.
    static func showsPageBeside(panelWidth: CGFloat, inset: CGFloat, pageWidth: CGFloat) -> Bool {
        panelWidth >= inset + listWidth + inset + pageWidth + inset
    }
}
