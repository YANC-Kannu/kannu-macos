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

/// The one badge beside a title on a page: "Beta", "Alpha", "Built-in" (docs/SETTINGS.md, "Section rules"). Quiet on
/// purpose, the secondary ink on the line colour, in the caption's size and title case, so it is never the loudest thing
/// in its row. A decorative chip, so it is not selectable.
struct SettingsBadge: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text)
            .font(SettingsTheme.caption)
            .foregroundStyle(SettingsTheme.inkSecondary)
            .lineLimit(1)
            .padding(SettingsTheme.badgeInset)
            .background(SettingsTheme.line, in: RoundedRectangle(cornerRadius: SettingsTheme.badgeRadius, style: .continuous))
            .fixedSize()
    }
}
