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

/// Brain's button. A custom style cannot see `.keyboardShortcut(.defaultAction)`, so a sheet's default
/// action asks for `.primary` itself; `SettingsDesignSystemRulesTests` holds every site to that.
struct SettingsButtonStyle: ButtonStyle {
    enum Prominence { case standard, primary }
    private let prominence: Prominence

    init(_ prominence: Prominence = .standard) { self.prominence = prominence }

    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration, prominence: prominence)
    }

    // Not `Body`: a type of that name inside a style collides with the protocol's associated type.
    private struct Chrome: View {
        let configuration: ButtonStyleConfiguration
        let prominence: Prominence
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlSize) private var controlSize
        @State private var isHovering = false

        /// docs/SETTINGS.md reserves the small size for controls inside a card.
        private var isSmall: Bool { controlSize == .small || controlSize == .mini }

        private var labelColor: Color {
            if prominence == .primary { return SettingsTheme.onPrimary }
            return configuration.role == .destructive ? SettingsTheme.destructive : SettingsTheme.ink
        }

        private var chromeColor: Color {
            if prominence == .primary { return SettingsTheme.ink }
            // `.onHover` keeps firing on a disabled button, hence the check.
            return isEnabled && (configuration.isPressed || isHovering) ? SettingsTheme.selection : SettingsTheme.card
        }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
            configuration.label
                // A native button keeps its width and takes one line; a row must not squeeze a word in two.
                .fixedSize(horizontal: true, vertical: false)
                .font(isSmall ? SettingsTheme.description : SettingsTheme.bodyStrong)
                .foregroundStyle(labelColor)
                .padding(isSmall ? SettingsTheme.buttonInsetSmall : SettingsTheme.buttonInset)
                .background(shape.fill(chromeColor))
                .overlay {
                    if prominence == .standard { shape.strokeBorder(SettingsTheme.line) }
                }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : SettingsTheme.disabledOpacity)
                .onHover { isHovering = $0 }
        }
    }
}
