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

/// A title row that opens and closes the rows under it. All of them sit in one view, so a long list
/// keeps the native style for now (`AllTasksPage`).
struct SettingsDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        Control(configuration: configuration)
    }

    private struct Control: View {
        let configuration: DisclosureGroupStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            VStack(alignment: .leading, spacing: SettingsMetrics.rowContent) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: SettingsTheme.quickAnimation)) {
                        configuration.isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: SettingsMetrics.rowContent) {
                        configuration.label
                        Spacer(minLength: SettingsMetrics.rowContent)
                        Image(systemName: "chevron.right")
                            .font(SettingsTheme.description)
                            .foregroundStyle(SettingsTheme.ink)
                            .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(configuration.isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))

                if configuration.isExpanded {
                    configuration.content
                }
            }
        }
    }
}
