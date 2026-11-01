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
import KeyboardShortcuts
import SwiftUI

struct Shortcuts: View {
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.enableShortcuts) var enableShortcuts
    @Default(.enableStatsFeature) var enableStatsFeature

    private func highlightID(_ title: String) -> String {
        SettingsTab.shortcuts.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableShortcuts) {
                    Text("Enable global keyboard shortcuts")
                }
                .settingsHighlight(id: highlightID("Enable global keyboard shortcuts"))
            } header: {
                SettingsSectionHeader("General")
            } footer: {
                SettingsFooter("Keyboard shortcuts are off by default. Enable this toggle to activate global hotkeys for notch controls.")
            }

            if enableShortcuts {
                shortcutsSection
            }
        }
        .navigationTitle("Shortcuts")
    }

    var shortcutsSection: some View {
        Section {
            shortcutRow("Toggle Sneak Peek:", name: .toggleSneakPeek,
                        description: Text("Sneak Peek shows the media title and artist under the notch for a few seconds."))
            shortcutRow("Toggle Notch Open:", name: .toggleNotchOpen,
                        description: Text("Toggle the Dynamic Island open or closed from anywhere."))
            shortcutRow("Start Demo Timer:", name: .startDemoTimer,
                        description: enableTimerFeature
                            ? Text("Starts a 5-minute demo timer to test the timer live activity feature. Only works when timer feature is enabled.")
                            : Text("Timer feature is disabled"),
                        isEnabled: enableTimerFeature)
            // The recorder shows the real shortcut; the old text claimed a default of Cmd+Shift+V.
            shortcutRow("Clipboard History:", name: .clipboardHistoryPanel,
                        description: enableClipboardManager
                            ? Text("Opens the clipboard history panel. Only works when clipboard feature is enabled.")
                            : Text("Clipboard feature is disabled"),
                        isEnabled: enableClipboardManager)
            shortcutRow("Screen Assistant:", name: .screenAssistantPanel,
                        description: Defaults[.enableScreenAssistant]
                            ? Text("Opens the AI assistant panel for file analysis and conversation. Only works when screen assistant feature is enabled.")
                            : Text("Screen Assistant feature is disabled"),
                        isEnabled: Defaults[.enableScreenAssistant])
        } header: {
            SettingsSectionHeader("Shortcuts")
        }
    }

    /// A shortcut: what it does on the leading side, the recorder trailing.
    private func shortcutRow(_ title: LocalizedStringKey, name: KeyboardShortcuts.Name, description: Text,
                             isEnabled: Bool = true) -> some View {
        LabeledContent {
            KeyboardShortcuts.Recorder(for: name)
                .disabled(!isEnabled)
        } label: {
            SettingsRowLabel(title, description: description)
        }
    }
}

/// The user's shortcut for a global hotkey as macOS draws it ("⇧⌘C"), or "not set".
@MainActor
func shortcutDescription(for name: KeyboardShortcuts.Name) -> String {
    KeyboardShortcuts.getShortcut(for: name)?.description ?? String(localized: "not set")
}
