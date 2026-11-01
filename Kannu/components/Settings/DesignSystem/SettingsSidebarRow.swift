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

/// One row of Brain's sidebar: a tab, Back, or the Settings row. It takes strings, never a tab, so
/// the sidebar's navigation stays in `SettingsView`.
struct SettingsSidebarRow: View {
    private let title: String
    private let systemImage: String
    private let isSelected: Bool
    private let badge: String?
    private let action: () -> Void
    @State private var isHovering = false

    init(_ title: String, systemImage: String, isSelected: Bool = false, badge: String? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.badge = badge
        self.action = action
    }

    /// Nil at rest, so the row draws no fill of its own and the paper shows through.
    private var fill: Color? {
        if isSelected { return SettingsTheme.selection }
        return isHovering ? SettingsTheme.hover : nil
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsTheme.sidebarRowContent) {
                Image(systemName: systemImage)
                    .frame(width: SettingsTheme.sidebarGlyph)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let badge {
                    Text(verbatim: badge)
                        .font(SettingsTheme.micro)
                        .foregroundStyle(SettingsTheme.onPrimary)
                        .padding(.horizontal, SettingsTheme.sidebarBadgeHorizontalInset)
                        .padding(.vertical, SettingsTheme.sidebarBadgeVerticalInset)
                        .background(Capsule().fill(SettingsTheme.ink))
                }
            }
            .font(SettingsTheme.body)
            .foregroundStyle(SettingsTheme.ink)
            .padding(.horizontal, SettingsTheme.sidebarRowInset)
            .frame(height: SettingsTheme.sidebarRowHeight)
            .background {
                if let fill {
                    RoundedRectangle(cornerRadius: SettingsTheme.sidebarRowRadius, style: .continuous).fill(fill)
                }
            }
            .contentShape(Rectangle())
        }
        // Or the root's button chrome lands on the row.
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
