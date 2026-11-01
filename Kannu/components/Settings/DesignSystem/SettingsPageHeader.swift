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

/// A page's large title, above its `Form`. It sits outside the page's scroll view, so it stays put.
struct SettingsPageHeader: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(SettingsTheme.pageTitle)
            .foregroundStyle(SettingsTheme.ink)
            .textSelection(.enabled)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsTheme.pageInset)
            .padding(.top, SettingsTheme.pageInset)
    }
}
