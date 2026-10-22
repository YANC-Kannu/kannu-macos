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

private struct NotchForegroundKey: EnvironmentKey {
    static let defaultValue: Color = .white
}

extension EnvironmentValues {
    /// Black or white: the text colour for whatever fill or skin is painted behind the notch.
    /// Set beside the notch subtree's `colorScheme` in `ContentView`.
    var notchForeground: Color {
        get { self[NotchForegroundKey.self] }
        set { self[NotchForegroundKey.self] = newValue }
    }
}

extension View {
    /// For notch content that sits on a dark surface of its own rather than on the notch's fill:
    /// a view that paints its own black background, and the content of every `.popover` opened
    /// from the notch. The popover window stays dark (VibrantDark, from the notch window's
    /// darkAqua) whatever the notch's colour scheme, but SwiftUI hands the popover content the
    /// presenting view's environment — so on a light notch fill its text would draw black on the
    /// dark popover. Pins both back to dark. `NotchPopoverAppearanceRulesTests` checks every notch
    /// popover has it.
    func notchDarkAppearance() -> some View {
        environment(\.colorScheme, .dark)
            .environment(\.notchForeground, .white)
    }
}

