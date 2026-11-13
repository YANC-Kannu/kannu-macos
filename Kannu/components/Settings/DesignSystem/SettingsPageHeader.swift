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

/// A page's large title, above its `SettingsPage`. It sits outside the page's scroll view, so it stays put, and
/// starts where the page does. A product page's actions sit on the same row, at its trailing end, which stops where
/// the page's product column does (docs/SETTINGS.md, "Product pages").
struct SettingsPageHeader: View {
    let title: String
    /// Icon buttons first, the page's one primary verb last. Most pages have none.
    var actions: AnyView?
    @Environment(\.settingsPageInset) private var inset

    var body: some View {
        HStack(spacing: SettingsTheme.sectionLabelGap) {
            Text(verbatim: title)
                .font(SettingsTheme.pageTitle)
                .foregroundStyle(SettingsTheme.ink)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let actions {
                actions
            }
        }
        .frame(maxWidth: SettingsTheme.productMaxWidth, alignment: .leading)
        .padding(.horizontal, inset)
        .padding(.top, SettingsTheme.pageHeaderTop)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
