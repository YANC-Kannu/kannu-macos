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

import AppKit
import Defaults
import SwiftUI

/// A note's own page in Brain › Notes: the in-tab swap a row's › opens (docs/SETTINGS.md, "Section rules": a sub-page),
/// under the "‹ Notes" back row `NotesSettingsView` draws. It shows the note whole and read-only: when it was last
/// edited, its text and its image, with Pin, Copy and Delete, and Open in Notes for a note made there. The notch's Notes
/// tab edits notes, and Apple Notes edits the ones made there.
///
/// It is handed the note and nothing else of the page, so the list-detail layout (layout-proposal.md, D1) can stand it
/// beside the list at wide windows, driven by the same selection. Like the list, it reads the page's copy, never the
/// notes: an edit in the notch shows here within half a second while Brain is on screen. Its one hook reads the note's
/// image from its file, off the main thread, once per image; it keeps no clock.
struct NotePage: View {
    let note: NoteItem
    let isReadOnly: Bool
    /// Deletes the note, asking first for one made in Apple Notes. `NotesSettingsView` holds the question.
    let delete: (NoteItem) -> Void
    @Default(.enableNotePinning) private var pinning
    @State private var image: NSImage?

    /// Changes when the note's image does: the file keeps its name when the image is replaced.
    private var imageKey: String {
        "\(note.imageFileName ?? "")|\(note.modificationDate.timeIntervalSince1970)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardPadding) {
            HStack(alignment: .firstTextBaseline, spacing: SettingsMetrics.rowContent) {
                NoteColorDot(note: note)
                Text(verbatim: Self.meta(note, isReadOnly: isReadOnly, now: Date()))
                    .settingsDescriptionStyle()
                Spacer(minLength: SettingsMetrics.rowContent)
                actions
            }
            if !note.content.isEmpty {
                Text(verbatim: note.content)
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let image {
                // A preview, at most the prose width and a hero card's height, so a tall image never fills the page.
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: SettingsTheme.proseMaxWidth, maxHeight: SettingsTheme.heroMinHeight, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
                    .accessibilityLabel(Text("Image"))
            }
        }
        .padding(SettingsMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: SettingsTheme.sectionRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        // The image from its file, off the main thread, as the notch's row reads its thumbnail: once per image, never
        // as the page draws. A board takes the fixture's and reads no file.
        .task(id: imageKey) {
            #if DEBUG
            if let fixture = NotesOverview.snapshotFixture {
                image = fixture.images[note.id]
                return
            }
            #endif
            guard let fileName = note.imageFileName else {
                image = nil
                return
            }
            let url = NoteItem.noteImageDataDirectory.appendingPathComponent(fileName)
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            // A newer read has started (the note was saved again) or the page has gone: this one's image is old.
            guard !Task.isCancelled else { return }
            image = data.flatMap { NSImage(data: $0) }
        }
    }

    /// Open in Notes first for a note made there, then Pin or Unpin while pinning is on, Copy and Delete: the notch's
    /// row's actions, each on a press only.
    private var actions: some View {
        HStack(spacing: SettingsMetrics.rowContent) {
            if isReadOnly {
                Button("Open in Notes") { NotesManager.shared.openInNotes(note) }
            }
            if pinning {
                glyph(note.isPinned ? "pin.slash" : "pin", note.isPinned ? String(localized: "Unpin") : String(localized: "Pin")) {
                    NotesManager.shared.togglePin(note)
                }
            }
            glyph("doc.on.doc", String(localized: "Copy")) {
                NotesOverview.copy(note)
            }
            glyph("trash", String(localized: "Delete"), role: .destructive) {
                delete(note)
            }
        }
    }

    /// A glyph button, quiet, its name its tooltip and its label for VoiceOver.
    private func glyph(_ symbol: String, _ name: String, role: ButtonRole? = nil,
                       action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(SettingsButtonStyle(.quiet))
        .help(name)
        .accessibilityLabel(name)
    }

    /// "Edited 4:57 PM", and "Made in Apple Notes" after it for a note shown read-only.
    static func meta(_ note: NoteItem, isReadOnly: Bool, now: Date) -> String {
        let edited = String(localized: "Edited \(NotesOverview.when(note.modificationDate, now: now))")
        return isReadOnly ? edited + " · " + String(localized: "Made in Apple Notes") : edited
    }
}
