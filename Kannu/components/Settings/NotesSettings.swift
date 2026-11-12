/*
 * Kannu (കണ്ണ്)
 * Copyright (C) 2024-2026 Kannu Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Kannu (കണ്ണ്)
 * See NOTICE for details.
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

import Combine
import Defaults
import SwiftUI

/// Brain › Notes, a product page: the notes lead (`NotesOverview`), and these settings follow. A note's › opens its own
/// page in the tab (`NotePage`), an in-tab swap under a "‹ Notes" back row, as Brain › Tasks opens a task's page
/// (docs/SETTINGS.md, "Section rules"). Search and deep links land on the settings below, so a Notes search or deep link
/// returns the tab to the list first. Each visit opens on the list.
struct NotesSettingsView: View {
    @ObservedObject private var visibility = BrainVisibility.shared
    @ObservedObject private var highlights = SettingsHighlightCoordinator.shared
    @Default(.enableNotes) private var enableNotes
    @Default(.enableAppleNotesSync) private var enableAppleNotesSync
    @Default(.appleNotesSyncScope) private var appleNotesSyncScope
    @State private var confirmNarrowingScope = false
    /// What the page shows from the saved notes and the sync, the list, a note's page and these settings alike: a copy,
    /// never the notes or the sync manager themselves, which the page used to observe whole. Read as the page appears
    /// and as Brain comes back on screen, then followed at most twice a second while it is on screen, and assigned only
    /// when it changed. Off screen it stays as it was (docs/SETTINGS.md, "Live data").
    @State private var data = NotesPageData()
    /// The note whose page is open in the tab; nil is the list. Only the selection: the list-detail layout
    /// (layout-proposal.md, D1) can show the same note beside the list.
    @State private var openNoteID: UUID?
    /// A note made in Apple Notes whose Delete waits for the question. On the tab, not on a row: the rows are lazy.
    @State private var pendingDelete: NoteItem?
    /// The row to bring back into view once the list has appeared: the note whose page was left, or the row a search
    /// or a deep link names.
    @State private var returnTo: AnyHashable?

    private func highlightID(_ title: String) -> String {
        SettingsTab.notes.highlightID(for: title)
    }

    /// Narrowing to the Kannu folder drops the local copies of every other note on the next sync
    /// (nothing in Notes is deleted), so it asks first; widening is the explicit choice it describes.
    private var scopeSelection: Binding<AppleNotesSyncScope> {
        Binding(
            get: { appleNotesSyncScope },
            set: { scope in
                guard scope != appleNotesSyncScope else { return }
                if scope == .kannuFolder, Defaults[.savedNotes].contains(where: { $0.madeInAppleNotes == true }) {
                    confirmNarrowingScope = true
                } else {
                    appleNotesSyncScope = scope
                    NotesManager.shared.syncWithAppleNotes()
                }
            }
        )
    }

    /// The open note, while Notes is on and the note is still saved.
    private var openNote: NoteItem? {
        guard enableNotes, let id = openNoteID else { return nil }
        return data.notes.first { $0.id == id }
    }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if let note = openNote {
                    SettingsPage {
                        SettingsSection {
                            TasksBackRow(parent: SettingsTab.notes.title) {
                                returnTo = note.id
                                openNoteID = nil
                            }
                        }
                        NotePage(note: note, isReadOnly: data.isReadOnly(note), delete: delete)
                    }
                    .settingsPageTitle(note.title)
                } else {
                    // The product first, then its settings (docs/SETTINGS.md, "Product pages").
                    SettingsProductPage(settingsTitle: String(localized: "Notes settings")) {
                        NotesOverview(data: data, open: { openNoteID = $0.id }, delete: delete)
                    } settings: {
                        settingsSections
                    }
                    .settingsPageTitle(SettingsTab.notes.title)
                    // The list has appeared: the row it should show, in view. After this update, so the row exists.
                    .onAppear {
                        guard let target = returnTo else { return }
                        returnTo = nil
                        DispatchQueue.main.async { proxy.scrollTo(target, anchor: .center) }
                    }
                }
            }
            // A page opens at its top.
            .id(openNoteID)
        }
        .navigationTitle("Notes")
        // Search and deep links land on the settings below the list, never on a note's page. Settings scrolled before
        // the list came back, so the list scrolls to the row again. `initial`: the link may arrive before this tab is
        // built.
        .onChange(of: highlights.activeHighlightID, initial: true) { _, id in
            guard let id, id.hasPrefix(highlightID("")), openNoteID != nil else { return }
            openNoteID = nil
            returnTo = id
        }
        .onChange(of: enableNotes) { _, _ in
            openNoteID = nil
        }
        .alert("Delete this note?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { note in
            Button("Delete", role: .destructive) { remove(note) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It was made in Apple Notes, and it also moves to Recently Deleted there.")
        }
        .onAppear {
            // Each visit opens on the list: `onAppear` runs again on every reopening (docs/REGRESSIONS.md, entry 22),
            // and a note left open would come back whole on a Brain that can be on a shared screen.
            openNoteID = nil
            returnTo = nil
            #if DEBUG
            if let fixture = NotesOverview.snapshotFixture {
                data = fixture.data
                openNoteID = fixture.openNoteID
                return
            }
            #endif
            // One read, not a subscription: the page opens on what is saved, and the subscription below takes over once
            // Brain is on screen.
            copyFromStores()
        }
        .task(id: visibility.isOnScreen) {
            #if DEBUG
            if NotesOverview.snapshotFixture != nil { return }
            #endif
            guard visibility.isOnScreen else { return }
            // Back on screen: what changed while Brain was not, which neither feed will send again.
            copyFromStores()
            // The notes and the sync's switch, scope and date tell through Defaults after a change; the sync's own state
            // through `objectWillChange` before one. Read through the run loop, the copy comes after both.
            for await _ in Defaults.publisher(keys: .savedNotes, .enableAppleNotesSync, .appleNotesSyncScope, .appleNotesLastSyncDate,
                                              options: [])
                .merge(with: AppleNotesSyncManager.shared.objectWillChange)
                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
                .values {
                copyFromStores()
            }
        }
    }

    @ViewBuilder
    private var settingsSections: some View {
        SettingsSection {
            Defaults.Toggle(key: .enableNotes) {
                Text("Enable Notes")
            }
            .settingsHighlight(id: highlightID("Enable Notes"))
            if enableNotes {
                Defaults.Toggle(key: .enableNotePinning) {
                    Text("Enable note pinning")
                }
                Defaults.Toggle(key: .enableNoteSearch) {
                    Text("Enable note search")
                }
                Defaults.Toggle(key: .enableNoteColorFiltering) {
                    Text("Enable color filtering")
                }
                Defaults.Toggle(key: .enableCreateFromClipboard) {
                    Text("Create notes from the clipboard")
                }
                Defaults.Toggle(key: .enableNoteCharCount) {
                    Text("Show character count")
                }
            }
        } header: {
            SettingsSectionHeader("General")
        }

        if enableNotes {
            SettingsSection {
                Defaults.Toggle(key: .enableAppleNotesSync) {
                    Text("Sync with Apple Notes")
                }
                .settingsHighlight(id: highlightID("Sync with Apple Notes"))
                .onChange(of: enableAppleNotesSync) { _, isOn in
                    // Turning it on is a click on the feature's own switch: after a Not now on
                    // "Control Notes", this is where macOS is asked again.
                    if isOn, LaunchPermissionManager.answer(for: .notesAutomation) == .deferred {
                        LaunchPermissionManager.shared.request(.notesAutomation, musicSource: Defaults[.mediaController])
                    }
                }

                if enableAppleNotesSync {
                    SettingsRow("Notes to sync", description: appleNotesSyncScope.description) {
                        SettingsSelect("Notes to sync", selection: scopeSelection, options: AppleNotesSyncScope.allCases,
                                       optionTitle: \.localizedName)
                    }
                    .settingsHighlight(id: highlightID("Notes to sync"))
                    .alert("Sync only the Kannu folder?", isPresented: $confirmNarrowingScope) {
                        Button("Sync Kannu folder") {
                            appleNotesSyncScope = .kannuFolder
                            NotesManager.shared.syncWithAppleNotes()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Notes made in Apple Notes outside the Kannu folder leave the notch. They stay in Apple Notes.")
                    }

                    // When it last synced, by the time of day, and Sync now, off while a sync runs. The list above says
                    // when one is running.
                    SettingsActionRow("Last synced", description: data.lastSync.map { NotesOverview.when($0, now: Date()) }
                                      ?? String(localized: "Not synced yet")) {
                        Button("Sync now") {
                            NotesManager.shared.syncWithAppleNotes()
                        }
                        .disabled(data.isSyncing)
                    }
                    .settingsHighlight(id: highlightID("Sync Now"))

                    if let error = data.lastError {
                        SettingsErrorText(error)
                    }
                }
            } header: {
                SettingsSectionHeader("Apple Notes")
            } footer: {
                SettingsFooterStack {
                    SettingsFooter("Notes made in Kannu go to the Kannu folder in Notes.")
                    SettingsFooter("macOS asks once before Kannu can control Notes.")
                }
            }
        }
    }

    /// The one place the page reads the notes and the sync: a fresh copy, assigned only when it changed. A note no longer
    /// saved, deleted here, in the notch or by a sync, closes its page.
    private func copyFromStores() {
        let latest = NotesPageData(AppleNotesSyncManager.shared)
        if latest != data { data = latest }
        if let id = openNoteID, !data.notes.contains(where: { $0.id == id }) {
            openNoteID = nil
        }
    }

    /// Delete, from a row's menu or a note's page. A note made in Apple Notes and linked to it asks first while sync is
    /// on, since `NotesManager.delete` then moves it to Recently Deleted there too. The note decides, not the scope:
    /// after a narrowing, such a note stays here until the next sync drops it, and its delete still reaches Notes. Any
    /// other goes at once.
    private func delete(_ note: NoteItem) {
        if enableAppleNotesSync, note.madeInAppleNotes != false, note.appleNotesId != nil {
            pendingDelete = note
        } else {
            remove(note)
        }
    }

    /// Reads the notes again at once, one read on the press: the throttle could hold the next copy for up to half a
    /// second, and the deleted note's row with it, a click on which would open a note no longer saved.
    private func remove(_ note: NoteItem) {
        if openNoteID == note.id { openNoteID = nil }
        NotesManager.shared.delete(note)
        copyFromStores()
    }
}
