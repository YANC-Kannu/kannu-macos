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
/// action asks for `.primary` itself; `SettingsDesignSystemRulesTests` holds every site to that. `.quiet` is
/// bare at rest and fills only under the pointer: a glyph on a row, a back row, a menu's ⋯.
///
/// `flush` is for a lone quiet button, such as a back row or "Open ›". Bare at rest, its inset cannot be seen, so its
/// label would look 8 pt off the text above it. Flush, the label sits on the column and the fill under the pointer
/// reaches left by the inset instead.
struct SettingsButtonStyle: ButtonStyle {
    enum Prominence { case standard, primary, quiet }
    private let prominence: Prominence
    private let flush: Bool

    init(_ prominence: Prominence = .standard, flush: Bool = false) {
        self.prominence = prominence
        self.flush = flush
    }

    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration, prominence: prominence, flush: flush)
    }

    // Not `Body`: a type of that name inside a style collides with the protocol's associated type.
    private struct Chrome: View {
        let configuration: ButtonStyleConfiguration
        let prominence: Prominence
        let flush: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlSize) private var controlSize
        @State private var isHovering = false

        /// docs/SETTINGS.md reserves the small size for controls inside a card.
        private var isSmall: Bool { controlSize == .small || controlSize == .mini }

        private var inset: EdgeInsets { isSmall || prominence == .quiet ? SettingsTheme.buttonInsetSmall : SettingsTheme.buttonInset }

        private var labelColor: Color {
            if prominence == .primary { return SettingsTheme.onPrimary }
            return configuration.role == .destructive ? SettingsTheme.destructive : SettingsTheme.ink
        }

        /// Nil leaves a quiet button bare at rest.
        private var chromeColor: Color? {
            switch prominence {
            case .primary: return SettingsTheme.ink
            // `.onHover` keeps firing on a disabled button, hence the check.
            case .standard: return isEnabled && (configuration.isPressed || isHovering) ? SettingsTheme.selection : SettingsTheme.card
            case .quiet: return isEnabled && (configuration.isPressed || isHovering) ? SettingsTheme.hover : nil
            }
        }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
            configuration.label
                // A native button keeps its width and takes one line; a row must not squeeze a word in two.
                .fixedSize(horizontal: true, vertical: false)
                .font(isSmall ? SettingsTheme.description : SettingsTheme.bodyStrong)
                .foregroundStyle(labelColor)
                .padding(inset)
                .background {
                    if let chromeColor { shape.fill(chromeColor) }
                }
                .overlay {
                    if prominence == .standard { shape.strokeBorder(SettingsTheme.line) }
                }
                .contentShape(shape)
                // A mouse hovers before it presses, so the hover fill alone would show no press.
                .opacity(!isEnabled ? SettingsTheme.disabledOpacity : configuration.isPressed ? SettingsTheme.pressedOpacity : 1)
                .onHover { isHovering = $0 }
                // Flush: the button's frame starts at its label, so the label sits on the column; the chrome and the
                // pointer's area reach past it to the left. Quiet only: a filled button would draw its chrome outside
                // its frame at rest.
                .padding(.leading, flush && prominence == .quiet ? -inset.leading : .zero)
        }
    }
}
