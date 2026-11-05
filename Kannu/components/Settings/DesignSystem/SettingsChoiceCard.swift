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

/// The one way a choice card says "selected" (docs/SETTINGS.md, "Choices"): an accent ring around its tile, and its name
/// in ink, medium when chosen. No dot, no pill and no tinted fill. VoiceOver hears the name as selected.
extension View {
    /// The ring, in the tile's own shape. The strong accent: the ring is the one mark that says selected, and the eye
    /// blue is 2.3:1 on a light card, under the 3:1 such a mark needs.
    func settingsChoiceRing<S: InsettableShape>(_ shape: S, isSelected: Bool) -> some View {
        overlay {
            if isSelected {
                shape.strokeBorder(SettingsTheme.accentStrong, lineWidth: SettingsTheme.choiceRingWidth)
            }
        }
    }

    /// The card's name, under its tile.
    func settingsChoiceLabel(isSelected: Bool) -> some View {
        font(isSelected ? SettingsTheme.bodyStrong : SettingsTheme.body)
            .foregroundStyle(SettingsTheme.ink)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
