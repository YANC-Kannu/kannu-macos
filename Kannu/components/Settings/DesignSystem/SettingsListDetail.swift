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

import SwiftUI

/// A Brain list's first page and, while the panel holds both, the page of the item opened from it beside it
/// (layout-proposal D1, David 2026-11-06; docs/SETTINGS.md, "Section rules"): Brain › Tasks' list and a task's page,
/// Brain › Notes' notes and a note's page. The tab decides, from `settingsListDetailFits(_:)`'s flag and what is open,
/// whether an item's page shows beside the list or in its place; this lays the two out. The first page stands in a
/// column of `ListDetailLayout.listWidth` with the page inset on each side; the item's page follows with no inset of
/// its own, so the list's trailing inset is the gap, and its scroll view runs to the panel's edge. Two scroll views, so
/// the item's page stays put while the list scrolls. The first page is the stack's first child at both widths, so
/// crossing the width keeps it, scrolled where it was. No `minWidth:` (SwiftUI's size bridge would clamp the window to
/// it, docs/REGRESSIONS.md entry 17), no `ViewThatFits` (it builds every layout it tries) and no `.inspector`.
struct SettingsListDetail<First: View, Beside: View>: View {
    /// Whether the item's page shows beside the first page; false, the first page has the panel to itself.
    let showsBeside: Bool
    @ViewBuilder var first: () -> First
    @ViewBuilder var beside: () -> Beside
    @Environment(\.settingsPageInset) private var inset

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            first()
                .frame(width: showsBeside ? inset + ListDetailLayout.listWidth + inset : nil)
            if showsBeside {
                beside()
                    // The list's own trailing inset is the space between the two.
                    .environment(\.settingsPageInset, 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
