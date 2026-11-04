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

/// Brain's text field: the native `TextField` or `SecureField`, plain, inside our chrome, so typing, the caret,
/// input methods, secure entry and `LeftState`'s focus restore (SettingsWindowController.swift) stay AppKit's.
/// It goes last on the field's chain, so `.focused`, `.onSubmit` and `.onExitCommand` stay on the field.
/// It hides the field's own label, which VoiceOver keeps: a field's name goes beside it, and what to type goes in
/// `prompt:`.
///
/// No `onSubmit:` parameter, ever: `WorklogConsentRulesTests` finds a send-on-Return by the literal modifier.
struct SettingsField: ViewModifier {
    /// The caller's focus, where it keeps its own: one field never carries two focus bindings.
    let isFocused: Bool?
    @FocusState private var tracksFocus: Bool
    @Environment(\.isEnabled) private var isEnabled

    private static let shape = RoundedRectangle(cornerRadius: SettingsTheme.fieldRadius, style: .continuous)

    func body(content: Content) -> some View {
        Group {
            if isFocused == nil {
                content.focused($tracksFocus)
            } else {
                content
            }
        }
        .labelsHidden()
        .textFieldStyle(.plain)
        .padding(SettingsTheme.fieldInset)
        .background(Self.shape.fill(SettingsTheme.card))
        .overlay(Self.shape.strokeBorder(SettingsTheme.line))
        .overlay {
            if isFocused ?? tracksFocus {
                Self.shape.strokeBorder(SettingsTheme.accentStrong, lineWidth: SettingsTheme.focusRingWidth)
            }
        }
        .opacity(isEnabled ? 1 : SettingsTheme.disabledOpacity)
    }
}

extension View {
    /// Brain's field chrome. Last on a `TextField` or `SecureField` chain.
    func settingsField(isFocused: Bool? = nil) -> some View {
        modifier(SettingsField(isFocused: isFocused))
    }
}
