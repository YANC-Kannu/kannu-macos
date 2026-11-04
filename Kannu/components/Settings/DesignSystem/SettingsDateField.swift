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

/// A date and time: a button showing it, opening a popover that holds the system's calendar grid and its time
/// field. Those two stay native: they cannot be restyled. The title is the button's label for VoiceOver and the full
/// date its value; what is around the field draws its name.
struct SettingsDateField: View {
    private let title: Text
    @Binding private var selection: Date
    private let range: ClosedRange<Date>
    @State private var isOpen = false
    @FocusState private var calendarHasFocus: Bool

    init(_ title: LocalizedStringKey, selection: Binding<Date>, in range: ClosedRange<Date>) {
        self.title = Text(title)
        _selection = selection
        self.range = range
    }

    /// `Date()...`, read as running to `Date.distantFuture`.
    init(_ title: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeFrom<Date>) {
        self.init(title, selection: selection, in: range.lowerBound...Date.distantFuture)
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: SettingsMetrics.iconGap) {
                Image(systemName: "calendar")
                    .accessibilityHidden(true)
                Text(verbatim: selection.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .buttonStyle(SettingsButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(Text(verbatim: selection.formatted(date: .complete, time: .shortened)))
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: SettingsMetrics.rowContent) {
                DatePicker(selection: $selection, in: range, displayedComponents: .date) { title }
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .focused($calendarHasFocus)
                DatePicker(selection: $selection, in: range, displayedComponents: .hourAndMinute) { title }
                    .datePickerStyle(.field)
                    .labelsHidden()
            }
            .padding(SettingsTheme.popoverInset)
            .background(SettingsTheme.panel)
            // As SettingsSelectList does: focus a turn later, and Escape closes only the popover, never the sheet
            // under it (Set End Time, New Task's reminder).
            .onExitCommand { isOpen = false }
            .onAppear { DispatchQueue.main.async { calendarHasFocus = true } }
        }
        // Closing Brain runs this, while `isOpen` survives the close (docs/REGRESSIONS.md, entry 22).
        .onDisappear { isOpen = false }
    }
}
