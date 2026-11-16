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

/// Whether a view stands in a Brain list's column beside an item's page (`SettingsListDetail`): `ListDetailLayout.listWidth`
/// wide, too narrow for a row whose controls fill a settings column, which stacks there instead (Time to log's card,
/// `TimeToLogSection`). False wherever a page has the panel to itself.
struct SettingsInListColumnKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var settingsInListColumn: Bool {
        get { self[SettingsInListColumnKey.self] }
        set { self[SettingsInListColumnKey.self] = newValue }
    }
}
