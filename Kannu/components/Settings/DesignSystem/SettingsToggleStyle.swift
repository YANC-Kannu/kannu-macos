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

/// Brain's switch. A real `Button` inside, so the keyboard works, and a real switch for VoiceOver.
///
/// `showsLabel` is explicit rather than read from `.labelsHidden()`, because a custom style's label
/// ignores that modifier and the `Spacer` would still push a row apart.
struct SettingsToggleStyle: ToggleStyle {
    /// False where a row draws the title itself. VoiceOver reads the label either way.
    var showsLabel = true

    func makeBody(configuration: Configuration) -> some View {
        Control(configuration: configuration, showsLabel: showsLabel)
    }

    /// Not `.plain`: what that does to a disabled fill is the system's to change, and it would dim
    /// the track a second time here. This one only shows a press.
    private struct TrackButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? SettingsTheme.pressedOpacity : 1)
        }
    }

    // Not `Body`: a type of that name inside a style collides with the protocol's associated type.
    private struct Control: View {
        let configuration: ToggleStyleConfiguration
        let showsLabel: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            HStack(spacing: SettingsMetrics.rowContent) {
                if showsLabel {
                    VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) { configuration.label }
                    Spacer(minLength: SettingsMetrics.rowContent)
                }
                Button { configuration.isOn.toggle() } label: { track }
                    .buttonStyle(TrackButtonStyle())
            }
            .accessibilityRepresentation {
                // The root's labelled-row style would otherwise reach this switch too.
                Toggle(isOn: configuration.$isOn) { configuration.label }
                    .toggleStyle(.switch)
                    .labeledContentStyle(.automatic)
            }
        }

        private var track: some View {
            Capsule()
                .fill(configuration.isOn ? SettingsTheme.accent : SettingsTheme.controlOff)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(SettingsTheme.knob).padding(SettingsTheme.toggleKnobInset)
                }
                .frame(width: SettingsTheme.toggleWidth, height: SettingsTheme.toggleHeight)
                .opacity(isEnabled ? 1 : SettingsTheme.disabledOpacity)
                .animation(reduceMotion ? nil : .easeOut(duration: SettingsTheme.quickAnimation),
                           value: configuration.isOn)
                .contentShape(Capsule())
        }
    }
}
