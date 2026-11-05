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

/// A card inside a section's card: a callout, or a row's expanded details (docs/SETTINGS.md, "The content standard").
/// The card's own colour with a hairline in the line colour, so it reads as a boundary, not a third surface.
extension View {
    func settingsCalloutCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: SettingsMetrics.cardCornerRadius, style: .continuous)
        return self
            .padding(SettingsMetrics.cardPadding)
            .background(SettingsTheme.card, in: shape)
            .overlay { shape.strokeBorder(SettingsTheme.line, lineWidth: SettingsTheme.hairline) }
    }
}
