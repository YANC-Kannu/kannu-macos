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

/// How far a page and its large title start from the panel's leading edge. The window measures the panel
/// once and says `pageInset` or `pageInsetWide` here, so the title and the cards line up. A page drawn
/// outside the window, such as a board, starts at `pageInset`.
struct SettingsPageInsetKey: EnvironmentKey {
    static let defaultValue = SettingsTheme.pageInset
}

extension EnvironmentValues {
    var settingsPageInset: CGFloat {
        get { self[SettingsPageInsetKey.self] }
        set { self[SettingsPageInsetKey.self] = newValue }
    }
}
