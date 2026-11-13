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

/// D1's one measurement (layout-proposal, David 2026-11-06) for a tab that shows a list and an item's page side by side
/// (`SettingsListDetail`): whether the panel holds both, by the width function (`ListDetailLayout`, with the page inset
/// and a settings column's width), into a flag rather than the width, so a resize redraws the tab only when it crosses.
/// Put on the tab's outermost view, which all its pages share, so a page in the list's place moves beside it as the
/// window widens. One `onGeometryChange`, never `minWidth:` (SwiftUI's size bridge would clamp the window to it,
/// docs/REGRESSIONS.md entry 17).
private struct SettingsListDetailFits: ViewModifier {
    @Binding var fits: Bool
    @Environment(\.settingsPageInset) private var inset

    func body(content: Content) -> some View {
        content.onGeometryChange(for: Bool.self) { geometry in
            ListDetailLayout.showsPageBeside(panelWidth: geometry.size.width, inset: inset, pageWidth: SettingsTheme.pageMaxWidth)
        } action: { fits = $0 }
    }
}

extension View {
    /// Whether this tab's panel holds a list and an item's page side by side, into `fits` (`SettingsListDetailFits`).
    func settingsListDetailFits(_ fits: Binding<Bool>) -> some View {
        modifier(SettingsListDetailFits(fits: fits))
    }
}
