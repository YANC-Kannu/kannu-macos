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

/// A note's tags in the notch editor, one line under its title: each tag as a chip (a click removes
/// it), then an "Add tag" field. While the field has focus, Kannu's tags in use follow as chips
/// (`TaskTagEditing.suggestions`, tasks' and notes' alike, `SharedTags`); a click adds one, and Return
/// adds what is typed, or the tag in use it starts. Escape clears the field.
///
/// Every note takes tags, read-only ones too (a Wispr Flow meeting, an Apple Notes copy): they are
/// Kannu's alone. The row only reports an edit (`onEdit`); where it is kept is the editor's call, so
/// nothing is written when a note is merely opened. The typed text lives with the editor (`typed`), so
/// Done, back or the notch closing can add it rather than lose it. The field holds nothing open
/// (REGRESSIONS entry 23).
struct NoteTagsRow: View {
    @Environment(\.notchForeground) private var notchForeground

    /// The note's tags, bare.
    let tags: [String]
    @Binding var typed: String
    /// The note's tags after a click or Return here.
    let onEdit: ([String]) -> Void

    @FocusState private var isFieldFocused: Bool
    /// Read as the field gains focus, never in the body: the saved notes can be hundreds.
    @State private var vocabulary: [String] = []
    @State private var colors: [String: TaskColor] = [:]

    private static let fieldID = "add-tag"

    private var suggestions: [TaskTagEditing.Suggestion] {
        isFieldFocused ? TaskTagEditing.suggestions(for: typed, existing: vocabulary, current: tags) : []
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        tagChip(tag)
                    }
                    TextField("Add tag", text: $typed)
                        .textFieldStyle(.plain)
                        .font(SettingsTheme.font(size: 11, weight: .medium))
                        .foregroundStyle(notchForeground.opacity(0.9))
                        .frame(width: 84)
                        .focused($isFieldFocused)
                        .onSubmit(addTyped)
                        .onExitCommand {
                            typed = ""
                            isFieldFocused = false
                        }
                        .id(Self.fieldID)
                    ForEach(suggestions, id: \.self) { pick in
                        suggestionChip(pick)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 22)
            }
            .onChange(of: tags) { _, _ in
                proxy.scrollTo(Self.fieldID, anchor: .trailing)
            }
        }
        .frame(height: 22)
        .onAppear { colors = SharedTags.colors() }
        .onChange(of: isFieldFocused) { _, focused in
            if focused { vocabulary = SharedTags.inUse() }
        }
    }

    /// Return: what is typed, or the tag in use it starts (`TaskTagEditing.returnPick`). The field
    /// keeps its focus for the next one.
    private func addTyped() {
        defer { typed = "" }
        guard let pick = TaskTagEditing.returnPick(for: typed, in: suggestions) else { return }
        onEdit(TaskTagEditing.adding(pick.tag, to: tags))
        isFieldFocused = true
    }

    /// One of the note's tags: its colour dot (none for a tag with no colour), "#name", and an ×. A
    /// click removes it.
    private func tagChip(_ tag: String) -> some View {
        Button {
            onEdit(TaskTagEditing.removing(tag, from: tags))
        } label: {
            HStack(spacing: 4) {
                colorDot(for: tag)
                Text(verbatim: "#\(tag)")
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(notchForeground.opacity(0.55))
            }
            .chipStyle(notchForeground)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(Text(verbatim: String(localized: "Remove tag \(tag)")))
    }

    /// A tag in use (its colour dot), or the typed text as a new tag (a +). A click adds it and gives
    /// the field its focus back.
    private func suggestionChip(_ pick: TaskTagEditing.Suggestion) -> some View {
        Button {
            onEdit(TaskTagEditing.adding(pick.tag, to: tags))
            typed = ""
            isFieldFocused = true
        } label: {
            HStack(spacing: 4) {
                switch pick {
                case .use(let tag):
                    colorDot(for: tag)
                    Text(verbatim: tag)
                case .create(let tag):
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                    Text(verbatim: tag)
                }
            }
            .chipStyle(notchForeground)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(Text(verbatim: String(localized: "Add tag \(pick.tag)")))
    }

    @ViewBuilder
    private func colorDot(for tag: String) -> some View {
        if let tint = colors[TaskColoring.key(for: tag)]?.tint {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
        }
    }
}

private extension View {
    /// The task form's tag chip (`TimerTaskForm`): a 20 pt capsule, 11 pt Geist medium.
    func chipStyle(_ foreground: Color) -> some View {
        self
            .font(SettingsTheme.font(size: 11, weight: .medium))
            .foregroundStyle(foreground.opacity(0.9))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(foreground.opacity(0.12)))
            .contentShape(Capsule())
    }
}
