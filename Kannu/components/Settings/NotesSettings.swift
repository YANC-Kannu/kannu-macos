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

import Defaults
import SwiftUI

struct NotesSettingsView: View {
    @EnvironmentObject var vm: KannuViewModel
    @ObservedObject var coordinator = KannuViewCoordinator.shared
    @ObservedObject private var appleNotesSync = AppleNotesSyncManager.shared
    @Default(.enableNotes) private var enableNotes
    @Default(.enableAppleNotesSync) private var enableAppleNotesSync
    @Default(.appleNotesLastSyncDate) private var appleNotesLastSyncDate
    @Default(.appleNotesSyncScope) private var appleNotesSyncScope
    @State private var confirmNarrowingScope = false

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

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableNotes) {
                    Text("Enable Notes")
                }
                if enableNotes {
                    Defaults.Toggle(key: .enableNotePinning) {
                        Text("Enable Note Pinning")
                    }
                    Defaults.Toggle(key: .enableNoteSearch) {
                        Text("Enable Note Search")
                    }
                    Defaults.Toggle(key: .enableNoteColorFiltering) {
                        Text("Enable Color Filtering")
                    }
                    Defaults.Toggle(key: .enableCreateFromClipboard) {
                        Text("Enable Create from Clipboard")
                    }
                    Defaults.Toggle(key: .enableNoteCharCount) {
                        Text("Show Character Count")
                    }
                }
            } header: {
                SettingsSectionHeader("General")
            } footer: {
                SettingsFooter("Customize how you organize and create notes. Enabling color filtering and search helps manage large lists.")
            }

            if enableNotes {
                Section {
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
                        Picker(selection: scopeSelection) {
                            ForEach(AppleNotesSyncScope.allCases) { scope in
                                Text(scope.localizedName).tag(scope)
                            }
                        } label: {
                            SettingsRowLabel("Notes to sync", description: appleNotesSyncScope.description, tint: nil)
                        }
                        .settingsHighlight(id: highlightID("Notes to sync"))
                        .alert("Sync Only the Kannu Folder?", isPresented: $confirmNarrowingScope) {
                            Button("Sync Kannu Folder") {
                                appleNotesSyncScope = .kannuFolder
                                NotesManager.shared.syncWithAppleNotes()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Notes made in Apple Notes outside the Kannu folder leave the notch. They stay in Apple Notes.")
                        }

                        LabeledContent {
                            HStack(spacing: 8) {
                                if appleNotesSync.isSyncing {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Button("Sync Now") {
                                    NotesManager.shared.syncWithAppleNotes()
                                }
                                .disabled(appleNotesSync.isSyncing)
                            }
                        } label: {
                            if let lastSync = appleNotesLastSyncDate {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Last synced")
                                    Text(lastSync, style: .relative)
                                        .settingsDescriptionStyle()
                                }
                            } else {
                                Text("Not synced yet")
                            }
                        }
                        .settingsHighlight(id: highlightID("Sync Now"))

                        if let error = appleNotesSync.lastError {
                            SettingsErrorText(error)
                        }
                    }
                } header: {
                    SettingsSectionHeader("Apple Notes")
                } footer: {
                    SettingsFooter("Two-way sync with the macOS Notes app. Notes made in Kannu go to the Kannu folder in Notes. Kannu asks macOS to let it control Notes the first time it syncs, or on the Permissions row in Brain › General.")
                }
            }
        }
        .navigationTitle("Notes")
    }
}
