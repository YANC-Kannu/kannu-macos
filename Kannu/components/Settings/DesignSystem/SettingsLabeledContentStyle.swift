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

/// A labelled row: the title leading, the content trailing, inside a `Form` or out of it.
///
/// It leaves the content's colour alone: a style-level secondary would also grey what is typed into a
/// `TextField` in the slot. A bare value says `.foregroundStyle(.secondary)` itself.
struct SettingsLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: SettingsMetrics.rowContent) {
            configuration.label
            Spacer(minLength: SettingsMetrics.rowContent)
            configuration.content
        }
    }
}
