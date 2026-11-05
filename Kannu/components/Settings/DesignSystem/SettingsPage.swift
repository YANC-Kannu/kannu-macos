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

/// A page of Brain, in place of a `Form`: one scroll view across the whole panel, so its scrollbar sits at the
/// panel's edge and the wheel works anywhere on it, holding the page's sections in one column. The column stops at
/// `pageMaxWidth` and starts the page inset from the panel's leading edge, never centred.
///
/// A plain `VStack`, not a lazy one: every row is built when the page appears. A search or a deep link scrolls to a
/// row's id, and a lazy stack cannot scroll to a row it has not built. So a row's `onAppear` runs as the page opens,
/// not as the row scrolls into view (docs/SETTINGS.md, "Pages and sections").
struct SettingsPage<Content: View>: View {
    @Environment(\.settingsPageInset) private var inset
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
                content
            }
            // Capped first, then inset, so the inset never comes out of the column's width.
            .frame(maxWidth: SettingsTheme.pageMaxWidth, alignment: .leading)
            .padding(.horizontal, inset)
            .padding(.vertical, SettingsTheme.sectionGap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
