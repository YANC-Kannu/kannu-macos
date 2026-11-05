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

/// Brain's slider: a track filled with the accent up to a knob. It draws no label: `SettingsSliderRow` draws the
/// title and the readout, and VoiceOver reads the label, the value and an adjustable action. With Full Keyboard
/// Access it takes focus; the arrows step, Home and End go to the ends.
///
/// No animation: the knob follows the value. Right to left it is drawn mirrored, as a native slider is.
struct SettingsSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    @Binding private var value: Value
    private let range: ClosedRange<Value>
    private let step: Value.Stride?
    private let label: Text
    private let valueDescription: Text?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.layoutDirection) private var layoutDirection

    init(value: Binding<Value>, in range: ClosedRange<Value>, step: Value.Stride? = nil,
         valueDescription: Text? = nil, label: () -> Text) {
        _value = value
        self.range = range
        self.step = step
        self.valueDescription = valueDescription
        self.label = label()
    }

    var body: some View {
        GeometryReader { proxy in
            let travel = max(0, proxy.size.width - SettingsTheme.sliderKnob)
            ZStack(alignment: .leading) {
                Capsule().fill(SettingsTheme.line).frame(height: SettingsTheme.sliderTrackHeight)
                Capsule().fill(SettingsTheme.accent)
                    .frame(width: travel * fraction + SettingsTheme.sliderKnob / 2, height: SettingsTheme.sliderTrackHeight)
                Circle().fill(SettingsTheme.knob)
                    .overlay(Circle().strokeBorder(SettingsTheme.controlOff))
                    .frame(width: SettingsTheme.sliderKnob, height: SettingsTheme.sliderKnob)
                    .offset(x: travel * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            // Brain does not move by its background (SettingsWindowController), so a drag here is the slider's.
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard isEnabled, travel > 0 else { return }
                set(fraction: (drag.location.x - SettingsTheme.sliderKnob / 2) / travel)
            })
            // Drawn left to right, so the fill, the knob and a drag measure from one edge; the whole slider is
            // then mirrored when Brain is right to left.
            .environment(\.layoutDirection, .leftToRight)
        }
        .flipsForRightToLeftLayoutDirection(true)
        .frame(height: SettingsTheme.sliderKnob)
        .opacity(isEnabled ? 1 : SettingsTheme.disabledOpacity)
        .focusable(isEnabled, interactions: .activate)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end]) { press in
            guard isEnabled else { return .ignored }
            switch press.key {
            case .home: set(fraction: 0)
            case .end: set(fraction: 1)
            case .upArrow: nudge(1)
            case .downArrow: nudge(-1)
            // Mirrored right to left, so → steps back there.
            default: nudge((press.key == .rightArrow) == (layoutDirection == .leftToRight) ? 1 : -1)
            }
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(valueDescription ?? Text(Double(value), format: .number.precision(.fractionLength(0...2))))
        .accessibilityAdjustableAction { direction in nudge(direction == .increment ? 1 : -1) }
    }

    /// Where the value sits along the range, 0 to 1; 0 when the range has no span.
    private var fraction: CGFloat {
        let lower = Double(range.lowerBound), span = Double(range.upperBound) - lower
        guard span > 0 else { return 0 }
        return CGFloat(min(max((Double(value) - lower) / span, 0), 1))
    }

    private func set(fraction: CGFloat) {
        let lower = Double(range.lowerBound), span = Double(range.upperBound) - lower
        set(lower + span * Double(min(max(fraction, 0), 1)))
    }

    /// Arrows and VoiceOver's adjust: one step, or `sliderKeyboardFraction` of the range when there is none. A
    /// disabled slider ignores them, as it does a drag.
    private func nudge(_ direction: Int) {
        guard isEnabled else { return }
        let span = Double(range.upperBound) - Double(range.lowerBound)
        let size = step.map { Double($0) } ?? span * SettingsTheme.sliderKeyboardFraction
        set(Double(value) + Double(direction) * size)
    }

    /// Clamped to the range and snapped to the step, counted from the lower bound; the upper bound itself is kept,
    /// so End and a drag past the end reach it when the step does not divide the range. Only a change is written, so a
    /// drag that stays on one step does not write the same setting again and again.
    private func set(_ raw: Double) {
        let lower = Double(range.lowerBound), upper = Double(range.upperBound)
        var next = min(max(raw, lower), upper)
        if let step, step > 0, next < upper {
            let size = Double(step)
            next = min(lower + ((next - lower) / size).rounded() * size, upper)
        }
        if Value(next) != value { value = Value(next) }
    }
}
