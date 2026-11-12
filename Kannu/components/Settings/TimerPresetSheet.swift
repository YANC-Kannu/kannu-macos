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

import Defaults
import SwiftUI

/// Add Preset, or a preset's edit, from Brain › Timer's tiles (the design review's finding 25: the presets as tiles,
/// editing in a sheet). Its name, its length in the stepper rows Custom Timer uses, and its colour, saved on Add or Save,
/// never as typed, so Cancel leaves the preset as it was. A preset needs a name and a length over 0:00: a blank name is a
/// blank row in the notch's preset list, and a 0:00 preset would ring a second after it started. A length the steppers
/// cannot show, over 23:59:59, which only an older version could save, is kept unless the steppers are moved.
struct TimerPresetSheet: View {
    enum Target: Identifiable {
        case add
        case edit(TimerPreset)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let preset): return preset.id.uuidString
            }
        }
    }

    let target: Target
    /// The length the steppers opened on, so an edit that leaves them writes no length of its own.
    private let openedLength: TimeInterval
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var color: Color
    /// Set by the first save: Return in the name field and the default button are one save, never two.
    @State private var saved = false
    @FocusState private var nameFocused: Bool

    init(target: Target) {
        self.target = target
        // A new preset starts as the old Add Preset did: five minutes, in the accent colour, with a name still to type.
        let preset: TimerPreset
        switch target {
        case .add: preset = TimerPreset(name: "", duration: 5 * 60, color: Defaults[.accentColor])
        case .edit(let existing): preset = existing
        }
        let parts = TimerPreset.components(for: preset.duration)
        let hours = min(parts.hours, 23)
        openedLength = TimerPreset.duration(from: TimerPreset.DurationComponents(hours: hours, minutes: parts.minutes,
                                                                               seconds: parts.seconds))
        _name = State(initialValue: preset.name)
        _hours = State(initialValue: hours)
        _minutes = State(initialValue: parts.minutes)
        _seconds = State(initialValue: parts.seconds)
        _color = State(initialValue: preset.color)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var duration: TimeInterval {
        TimerPreset.duration(from: TimerPreset.DurationComponents(hours: hours, minutes: minutes, seconds: seconds))
    }
    private var canSave: Bool { !trimmedName.isEmpty && duration > 0 }

    private var isNew: Bool {
        if case .add = target { return true }
        return false
    }

    var body: some View {
        SettingsSheet(isNew ? Text("Add preset") : Text("Edit preset")) {
            TextField("Name", text: $name, prompt: Text("Preset name"))
                .focused($nameFocused)
                .onSubmit(save)
                .settingsField(isFocused: nameFocused)
            SettingsStepperRow("Hours", value: $hours, in: 0...23, valueText: Text("\(hours)"))
            SettingsStepperRow("Minutes", value: $minutes, in: 0...59, valueText: Text("\(minutes)"))
            SettingsStepperRow("Seconds", value: $seconds, in: 0...59, valueText: Text("\(seconds)"))
            SettingsColorPickerRow(title: String(localized: "Accent color"), selection: $color)
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isNew ? "Add" : "Save", action: save)
                .buttonStyle(SettingsButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .onAppear {
            // A new preset's name is what is left to type; an edit opens on the length, its name already there.
            if isNew { nameFocused = true }
        }
    }

    private func save() {
        guard canSave, !saved else { return }
        saved = true
        switch target {
        case .add:
            Defaults[.timerPresets].append(TimerPreset(name: trimmedName, duration: duration, color: color))
        case .edit(let original):
            var presets = Defaults[.timerPresets]
            // Gone since the sheet opened: nothing to save into.
            guard let index = presets.firstIndex(where: { $0.id == original.id }) else { break }
            presets[index].name = trimmedName
            if duration != openedLength { presets[index].duration = duration }
            // Only a colour picked here: converting an untouched one could move its stored value.
            if color != original.color { presets[index].updateColor(color) }
            Defaults[.timerPresets] = presets
        }
        dismiss()
    }
}
