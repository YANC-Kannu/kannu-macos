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

import Defaults
import SwiftUI

/// The moon, or the sun in dark. It reads the appearance the window really has, so from Match macOS
/// it picks the opposite of what is on screen.
struct SettingsAppearanceToggle: View {
    @Default(.brainAppearance) private var appearance
    @Environment(\.colorScheme) private var colorScheme

    private var label: String {
        colorScheme == .dark ? String(localized: "Use light appearance") : String(localized: "Use dark appearance")
    }

    var body: some View {
        Button {
            appearance = colorScheme == .dark ? .light : .dark
        } label: {
            Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                .font(SettingsTheme.body)
                .foregroundStyle(SettingsTheme.ink)
                .frame(width: SettingsTheme.titleRowHeight, height: SettingsTheme.titleRowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
