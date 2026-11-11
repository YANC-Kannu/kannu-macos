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

/// Brain › Notes' product, above its settings: the notes, pinned first and then the latest edit first, as the notch's
/// Notes tab lists them, under Apple Notes' sync status while sync is on (docs/SETTINGS.md, "Product pages"). A row's ›
/// opens the note's own page in the tab (`NotePage`, the in-tab swap), and its right-click menu holds the rest.
///
/// It shows what is saved and starts nothing of its own: no sync, no AppleScript and no file read. Pin, Copy, Open in
/// Notes and Delete act only on a press, through `NotesManager`, the notes' one write path, as the notch's rows make
/// them; New note opens its sheet (`NewNoteSheet`), which saves on Add.
///
/// Nothing here observes the notes or the sync. `NotesSettingsView`, which holds this, the note's page and the settings
/// below, copies what they show into one value, `NotesPageData`, at most twice a second while Brain is on screen, and
/// hands it down; off screen the copy stays as it was (docs/SETTINGS.md, "Live data"). A row says when its note was
/// last edited by the time of day or the date, so the page keeps no clock.
struct NotesOverview: View {
    let data: NotesPageData
    /// Opens a note's own page in the tab. `NotesSettingsView` holds which note is open.
    let open: (NoteItem) -> Void
    /// Deletes a note, asking first for one made in Apple Notes. `NotesSettingsView` holds the question.
    let delete: (NoteItem) -> Void
    @Default(.enableNotes) private var enabled
    /// The empty state's New note, which opens the same sheet as the header's.
    @State private var showsNewNote = false

    #if DEBUG
    /// DEBUG snapshot boards only (`DebugSnapshots`): fixtures in place of this Mac's notes and sync, so none of them
    /// lands in a PNG. Set, the page never reads the notes, follows the sync or reads an image file.
    static var snapshotFixture: NotesOverviewFixture?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
            if !enabled {
                // The notch shows no notes while it is off, so there is nothing current to show.
                SettingsSection {
                    NotesMessage(title: String(localized: "Notes is off"), message: nil) {
                        Button("Turn On") { enabled = true }
                    }
                }
            } else {
                if data.syncOn {
                    syncStatus
                }
                if data.notes.isEmpty {
                    SettingsSection {
                        // The header's verb again, in the standard style, as Security's empty state draws its own.
                        NotesMessage(title: String(localized: "No notes yet"),
                                     message: String(localized: "Write your first note here or in the notch.")) {
                            Button("New note") { showsNewNote = true }
                        }
                    }
                } else {
                    SettingsSection {
                        // Lazy, unlike the page around it: with Apple Notes' whole account synced the list can hold
                        // hundreds of notes, and a plain stack builds every row as the page opens. No search or deep
                        // link lands on a row, and going back scrolls to a note by this `ForEach`'s own id, which a
                        // lazy stack reaches before the row is built (docs/SETTINGS.md, "Pages and sections").
                        LazyVStack(alignment: .leading, spacing: SettingsTheme.sectionRowGap) {
                            ForEach(data.notes) { note in
                                NotesListRow(note: note, isReadOnly: data.isReadOnly(note), open: open, delete: delete)
                                    .id(note.id)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showsNewNote) { NewNoteSheet() }
    }

    /// One line above the notes: syncing, the last sync's time, never synced yet, or the last sync's error. It reads
    /// the copy, never the sync manager, and starts no sync: Sync now is a press in the settings below.
    private var syncStatus: some View {
        Group {
            if !data.isSyncing, let error = data.lastError {
                SettingsErrorText(error)
            } else {
                SettingsStatusText(Self.syncLine(data, now: Date()), isReady: !data.isSyncing && data.lastSync != nil)
            }
        }
        // In line with the cards' text, as Usage's "Models this week" heading.
        .padding(.horizontal, SettingsTheme.sectionPadding.leading)
    }

    static func syncLine(_ data: NotesPageData, now: Date) -> String {
        if data.isSyncing { return String(localized: "Syncing with Apple Notes") }
        guard let lastSync = data.lastSync else { return String(localized: "Not synced with Apple Notes yet") }
        // " · " as the rows' captions: "at" would not read before a date.
        return String(localized: "Synced with Apple Notes · \(when(lastSync, now: now))")
    }

    /// The time of day for today, the date and time otherwise: read when the page draws, never kept up to date.
    static func when(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Copy, as the notch's row copies a note: its text, and its image when it has one. The image is read from its
    /// file here, on the press, never as the page draws.
    static func copy(_ note: NoteItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(note.content, forType: .string)
        if let imageData = note.getImageData(), let tiff = NSImage(data: imageData)?.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}

/// Notes' header actions (docs/SETTINGS.md, "Product pages"): the gear, which goes to the page's first settings row,
/// then New note, the page's one primary verb, which opens its sheet on a press. No New note while Notes is off: the
/// notch shows no notes then.
struct NotesHeaderActions: View {
    @Default(.enableNotes) private var enabled
    @State private var showsNewNote = false

    var body: some View {
        HStack(spacing: SettingsMetrics.rowContent) {
            Button {
                // The first settings row, which is always built.
                SettingsHighlightCoordinator.shared.requestAgentStatusNavigation(highlightID: SettingsDeepLink.notesEnableHighlightID)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(SettingsButtonStyle(.quiet))
            .help(String(localized: "Notes settings"))
            .accessibilityLabel(String(localized: "Notes settings"))
            if enabled {
                Button("New note") { showsNewNote = true }
                    .buttonStyle(SettingsButtonStyle(.primary))
            }
        }
        .sheet(isPresented: $showsNewNote) { NewNoteSheet() }
    }
}

// MARK: - A row, and the card in the rows' place

/// One note: its colour, its title and a caption, when it was last edited and how its text starts, then a › to its
/// own page, where everything about it lives (docs/SETTINGS.md, "Section rules": a long list of similar rows). Pin,
/// Copy, Open in Notes and Delete are on the right-click menu and on the note's page.
private struct NotesListRow: View {
    let note: NoteItem
    let isReadOnly: Bool
    let open: (NoteItem) -> Void
    let delete: (NoteItem) -> Void
    @Default(.enableNotePinning) private var pinning

    var body: some View {
        LabeledContent {
            Button {
                open(note)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(SettingsButtonStyle(.quiet))
            .help(String(localized: "Open note"))
            .accessibilityLabel(String(localized: "Open note"))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: SettingsMetrics.rowContent) {
                NoteColorDot(note: note)
                SettingsRowLabel(Text(verbatim: note.title), description: Text(verbatim: Self.caption(note, now: Date())))
                    .lineLimit(2)
            }
        }
        .contextMenu {
            Button("Open note") { open(note) }
            Divider()
            // As the notch's rows: a note can be pinned or unpinned only while pinning is on.
            if pinning {
                if note.isPinned {
                    Button("Unpin") { NotesManager.shared.togglePin(note) }
                } else {
                    Button("Pin") { NotesManager.shared.togglePin(note) }
                }
            }
            Button("Copy") { NotesOverview.copy(note) }
            if isReadOnly {
                Button("Open in Notes") { NotesManager.shared.openInNotes(note) }
            }
            Divider()
            Button("Delete", role: .destructive) { delete(note) }
        }
    }

    /// "4:57 PM · Milk, eggs, bread": the last edit, then the text's first line. A note with no text says only when.
    static func caption(_ note: NoteItem, now: Date) -> String {
        let edited = NotesOverview.when(note.modificationDate, now: now)
        // One split at most: the first line that has text, never the whole note cut into lines.
        let firstLine = note.content.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isNewline).first.map {
            String($0.prefix(200)).trimmingCharacters(in: .whitespaces)
        } ?? ""
        return firstLine.isEmpty ? edited : edited + " · " + firstLine
    }
}

/// A note's colour before its title: a pin in that colour when the note is pinned, as the notch marks one, a dot
/// otherwise. One column a list row's icon wide, so every title starts on the same edge. The colour is the note's own,
/// from the notch's palette.
struct NoteColorDot: View {
    let note: NoteItem

    var body: some View {
        Group {
            if note.isPinned {
                Image(systemName: "pin.fill")
                    .accessibilityLabel(Text("Pinned"))
            } else {
                Image(systemName: "circle.fill")
                    .accessibilityHidden(true)
            }
        }
        .font(SettingsTheme.description)
        .foregroundStyle(note.color)
        .frame(width: SettingsTheme.listRowIcon)
    }
}

/// The rows' place when there is nothing to list, or the page's while Notes is off: the status, at most one line that
/// teaches, and at most one action (docs/SETTINGS.md, "Product pages"), as Clipboard's. It sits in a section's card,
/// whose padding is the hero's, so it is as tall as the hero less that padding.
private struct NotesMessage<Action: View>: View {
    let title: String
    let message: String?
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: SettingsMetrics.cardPadding) {
            Image(systemName: SettingsTab.notes.systemImage)
                .font(SettingsTheme.pageTitle)
                .foregroundStyle(SettingsTheme.inkSecondary)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(SettingsTheme.cardTitle)
                .foregroundStyle(SettingsTheme.ink)
                .textSelection(.enabled)
            if let message {
                // The body's size on the secondary ink: an empty state's one line teaches, so it reads as text.
                Text(verbatim: message)
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: SettingsTheme.proseMaxWidth)
            }
            action()
        }
        .frame(maxWidth: .infinity,
               minHeight: SettingsTheme.heroMinHeight - SettingsTheme.sectionPadding.top - SettingsTheme.sectionPadding.bottom)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - The data

/// What Brain › Notes shows from the saved notes and the sync, copied in one value, so one throttled subscription
/// carries it and the page redraws only when it changed (docs/SETTINGS.md, "Live data"). The list, a note's page and
/// the settings below all read it; nothing on the page reads the notes or the sync's state another way.
struct NotesPageData: Equatable {
    /// Pinned first, then the latest edit first, as the notch's Notes tab sorts them.
    var notes: [NoteItem] = []
    var syncOn = false
    var scope: AppleNotesSyncScope = .kannuFolder
    var isSyncing = false
    var lastError: String?
    var lastSync: Date?

    init() {}

    /// The saved notes and the sync as they are now.
    @MainActor
    init(_ sync: AppleNotesSyncManager) {
        notes = Self.ordered(Defaults[.savedNotes])
        syncOn = Defaults[.enableAppleNotesSync]
        scope = Defaults[.appleNotesSyncScope]
        lastSync = Defaults[.appleNotesLastSyncDate]
        isSyncing = sync.isSyncing
        lastError = sync.lastError
    }

    /// A note made in Apple Notes while sync reads the whole account: shown, never edited here or in the notch.
    func isReadOnly(_ note: NoteItem) -> Bool {
        note.isReadOnlyMirror(syncEnabled: syncOn, scope: scope)
    }

    static func ordered(_ notes: [NoteItem]) -> [NoteItem] {
        notes.sorted { $0.isPinned != $1.isPinned ? $0.isPinned : $0.modificationDate > $1.modificationDate }
    }
}

#if DEBUG
/// DEBUG snapshot boards only: what Brain › Notes shows in place of this Mac's notes and sync, the note whose page is
/// drawn open, if any, and the images its notes would read from their files.
struct NotesOverviewFixture {
    var data: NotesPageData
    var openNoteID: UUID?
    var images: [UUID: NSImage] = [:]
}
#endif
