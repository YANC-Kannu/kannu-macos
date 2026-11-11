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

/// New note, Brain › Notes' one primary verb (layout-proposal.md §5 item 7, David's "Yes, add the sheet", 2026-11-11): a
/// note's title, its text and its colour, saved on Add through `NotesManager.save`, the notes' one write path, as a note
/// made in the notch is (and pushed to Apple Notes while sync is on). Nothing is saved as it is typed, so Cancel leaves
/// nothing behind. Return is Add in either field (docs/SETTINGS.md, "Section rules": a sheet). A note's own page stays
/// read-only; the notch edits notes.
struct NewNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var text: String
    @State private var colorIndex: Int
    /// The new note's id, one per sheet: Return can reach both a field's submit and Add, and the second save of the same
    /// note finds it already saved and writes nothing, where a fresh id would save it twice.
    @State private var noteID = UUID()
    @FocusState private var focused: Field?

    private enum Field { case title, text }

    init(title: String = "", text: String = "", colorIndex: Int = 0) {
        _title = State(initialValue: title)
        _text = State(initialValue: text)
        _colorIndex = State(initialValue: colorIndex)
    }

    /// `NotesManager.save` refuses a new note with no title and no text; so does Add.
    private var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        SettingsSheet("New note", subtitle: Text("Saved as your newest note.")) {
            TextField("Title", text: $title, prompt: Text("Groceries"))
                .focused($focused, equals: .title)
                .onSubmit(add)
                .settingsField(isFocused: focused == .title)
            TextField("Text", text: $text, prompt: Text("Milk, eggs and bread"), axis: .vertical)
                .lineLimit(4...12)
                .focused($focused, equals: .text)
                .onSubmit(add)
                .settingsField(isFocused: focused == .text)
            SettingsRow("Color") {
                SettingsSelect("Color", selection: $colorIndex, options: Array(NoteItem.colors.indices),
                               optionTitle: { NoteItem.colorNames[$0] }) { index in
                    Image(systemName: "circle.fill")
                        .foregroundStyle(NoteItem.color(at: index))
                        .accessibilityHidden(true)
                }
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Add", action: add)
                .buttonStyle(SettingsButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(isEmpty)
        }
        // The title first, as New Task's sheet focuses its own.
        .onAppear { focused = .title }
    }

    /// The one write: a new note, at once, through the notes' own path; then the sheet closes.
    private func add() {
        guard !isEmpty else { return }
        NotesManager.shared.save(NotesManager.Draft(id: noteID, title: title, content: text, imageData: nil,
                                                    colorIndex: colorIndex))
        dismiss()
    }
}
