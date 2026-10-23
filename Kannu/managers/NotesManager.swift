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
import Foundation

/// Every change to the saved notes goes through here: what is stored, the files beside it, and the
/// push to Apple Notes. The notch's Notes tab keeps only the editor's state; the integrations
/// tracked for later (Shortcuts actions, drag-to-task, MCP tools) get the same single write path.
@MainActor
final class NotesManager {
    static let shared = NotesManager()

    private init() {}

    /// What an editor holds for one note.
    struct Draft {
        var id: UUID
        var title: String
        var content: String
        var imageData: Data?
        var colorIndex: Int
    }

    /// Stores `draft`, creating the note if it is new. When the stored note already says the same,
    /// nothing is written — no modification date, no image file, no push — so opening a note and
    /// going back leaves it where it was in the list. Returns whether anything was saved.
    @discardableResult
    func save(_ draft: Draft) -> Bool {
        var notes = Defaults[.savedNotes]
        let index = notes.firstIndex { $0.id == draft.id }
        if index == nil, draft.title.isEmpty, draft.content.isEmpty, draft.imageData == nil {
            return false
        }

        let title = draft.title.isEmpty ? String(localized: "Untitled Note") : draft.title
        let existing = index.map { notes[$0] }
        let imageChanged = draft.imageData != existing?.getImageData()
        if let existing,
           existing.title == title,
           existing.content == draft.content,
           existing.colorIndex == draft.colorIndex,
           !imageChanged {
            return false
        }

        var imageFileName = existing?.imageFileName
        if imageChanged {
            if let old = imageFileName {
                try? FileManager.default.removeItem(at: NoteItem.noteImageDataDirectory.appendingPathComponent(old))
            }
            imageFileName = nil
            if let data = draft.imageData {
                let name = "note_image_\(draft.id.uuidString).png"
                try? data.write(to: NoteItem.noteImageDataDirectory.appendingPathComponent(name))
                imageFileName = name
            }
        }

        let now = Date()
        if let index {
            notes[index].title = title
            notes[index].content = draft.content
            notes[index].colorIndex = draft.colorIndex
            notes[index].imageFileName = imageFileName
            notes[index].modificationDate = now
        } else {
            notes.insert(NoteItem(
                id: draft.id,
                title: title,
                content: draft.content,
                creationDate: now,
                modificationDate: now,
                colorIndex: draft.colorIndex,
                isPinned: false,
                imageFileName: imageFileName
            ), at: 0)
        }
        Defaults[.savedNotes] = notes
        pushToAppleNotes(draft.id)
        return true
    }

    func delete(_ note: NoteItem) {
        var notes = Defaults[.savedNotes]
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        deleteRemoteIfLinked(notes[index])
        removeAttachments(of: notes[index])
        notes.remove(at: index)
        Defaults[.savedNotes] = notes
    }

    func clearAll() {
        for note in Defaults[.savedNotes] {
            deleteRemoteIfLinked(note)
            removeAttachments(of: note)
        }
        Defaults[.savedNotes] = []
    }

    func togglePin(_ note: NoteItem) {
        var notes = Defaults[.savedNotes]
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].isPinned.toggle()
        Defaults[.savedNotes] = notes
    }

    // MARK: - Apple Notes

    /// Runs a two-way sync and applies its result to the notes as they are when it finishes, not to
    /// the snapshot it started from (`AppleNotesMergePolicy.reconcile`).
    func syncWithAppleNotes() {
        guard Defaults[.enableAppleNotesSync] else { return }
        let snapshot = Defaults[.savedNotes]
        Task {
            guard let merged = await AppleNotesSyncManager.shared.sync(localNotes: snapshot) else { return }
            let before = Dictionary(snapshot.map { ($0.id, $0.modificationDate) }, uniquingKeysWith: { first, _ in first })
            Defaults[.savedNotes] = AppleNotesMergePolicy.reconcile(
                current: Defaults[.savedNotes],
                merged: merged,
                snapshot: before,
                id: \.id,
                modified: \.modificationDate,
                keep: { now, synced in
                    var kept = now
                    if kept.appleNotesId == nil {
                        kept.appleNotesId = synced.appleNotesId
                        kept.appleNotesSyncedAt = synced.appleNotesSyncedAt
                    }
                    return kept
                }
            )
        }
    }

    private func pushToAppleNotes(_ id: UUID) {
        guard Defaults[.enableAppleNotesSync],
              let note = Defaults[.savedNotes].first(where: { $0.id == id }) else { return }
        Task {
            guard let pushed = await AppleNotesSyncManager.shared.pushNote(note) else { return }
            // Only the link is written back: the content may have moved on while the push ran.
            var notes = Defaults[.savedNotes]
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[index].appleNotesId = pushed.appleNotesId
            notes[index].appleNotesSyncedAt = pushed.appleNotesSyncedAt
            Defaults[.savedNotes] = notes
        }
    }

    /// Also reaches a note whose first push is still running: the sync manager queues the delete
    /// behind it and finds the id it created.
    private func deleteRemoteIfLinked(_ note: NoteItem) {
        guard Defaults[.enableAppleNotesSync] else { return }
        Task {
            await AppleNotesSyncManager.shared.deleteRemoteNote(noteId: note.id, appleNotesId: note.appleNotesId)
        }
    }

    // MARK: - Files

    private func removeAttachments(of note: NoteItem) {
        if let fileName = note.imageFileName {
            try? FileManager.default.removeItem(at: NoteItem.noteImageDataDirectory.appendingPathComponent(fileName))
        }
    }
}
