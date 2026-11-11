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

/// Brain's stepper: − and + in one capsule. The value reads beside it, never inside (`SettingsStepperRow`).
/// VoiceOver reads one element with a label, a value and an adjustable action; with Full Keyboard Access it is
/// one stop, and ↑ ↓ step. No press-and-hold repeat: a held arrow key repeats.
struct SettingsStepper<Value: Strideable>: View {
    @Binding private var value: Value
    private let range: ClosedRange<Value>
    private let step: Value.Stride
    private let label: Text
    private let valueDescription: Text?
    @Environment(\.isEnabled) private var isEnabled

    init(value: Binding<Value>, in range: ClosedRange<Value>, step: Value.Stride = 1,
         valueDescription: Text? = nil, label: () -> Text) {
        _value = value
        self.range = range
        self.step = step
        self.valueDescription = valueDescription
        self.label = label()
    }

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", by: -1, atItsEnd: value <= range.lowerBound)
            Rectangle()
                .fill(SettingsTheme.line)
                .frame(width: SettingsTheme.hairline, height: SettingsTheme.stepperHeight)
            stepButton("plus", by: 1, atItsEnd: value >= range.upperBound)
        }
        .background(RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous).fill(SettingsTheme.card))
        .overlay(RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous).strokeBorder(SettingsTheme.line))
        .fixedSize()
        .opacity(isEnabled ? 1 : SettingsTheme.disabledOpacity)
        .focusable(isEnabled, interactions: .activate)
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard isEnabled else { return .ignored }
            nudge(press.key == .upArrow ? 1 : -1)
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(valueDescription ?? Text(verbatim: "\(value)"))
        .accessibilityAdjustableAction { direction in nudge(direction == .increment ? 1 : -1) }
    }

    /// At its end of the range a button turns `controlOff` and is disabled: a colour, not a second dim. It never
    /// takes the keyboard: the stepper is the one stop.
    private func stepButton(_ symbol: String, by direction: Int, atItsEnd: Bool) -> some View {
        Button { nudge(direction) } label: {
            Image(systemName: symbol)
                .font(SettingsTheme.description)
                .foregroundStyle(atItsEnd ? SettingsTheme.controlOff : SettingsTheme.ink)
                .frame(width: SettingsTheme.stepperButtonWidth, height: SettingsTheme.stepperHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .focusable(false)
        .disabled(atItsEnd)
    }

    /// Arrows, VoiceOver's adjust and the buttons land here, clamped to the range. A disabled stepper ignores
    /// them, as its buttons do a click.
    private func nudge(_ direction: Int) {
        guard isEnabled else { return }
        // From a value inside the range, measured before stepping: `advanced(by:)` near the type's limit would trap.
        let current = min(max(value, range.lowerBound), range.upperBound)
        let bound = direction > 0 ? range.upperBound : range.lowerBound
        let next = abs(current.distance(to: bound)) <= step ? bound : current.advanced(by: direction > 0 ? step : -step)
        if next != value { value = next }
    }

    /// A press only. `.plain` would dim a disabled button a second time.
    private struct PressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? SettingsTheme.pressedOpacity : 1)
        }
    }
}
