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

struct ClipboardSettings: View {
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.clipboardHistorySize) var clipboardHistorySize
    @Default(.showClipboardIcon) var showClipboardIcon
    @Default(.clipboardDisplayMode) var clipboardDisplayMode

    private func highlightID(_ title: String) -> String {
        SettingsTab.clipboard.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableClipboardManager) {
                    Text("Enable Clipboard Manager")
                }
                .settingsHighlight(id: highlightID("Enable Clipboard Manager"))
                .onChange(of: enableClipboardManager) { _, enabled in
                    if enabled {
                        clipboardManager.startMonitoring()
                    } else {
                        clipboardManager.stopMonitoring()
                    }
                }
            } header: {
                SettingsSectionHeader("Clipboard Manager")
            } footer: {
                // The shortcut is the user's (default ⇧⌘C); the old text said Cmd+Shift+V.
                SettingsFooter("Monitor clipboard changes and keep a history of recent copies. With global keyboard shortcuts on, \(shortcutDescription(for: .clipboardHistoryPanel)) opens the history.")
            }

            if enableClipboardManager {
                Section {
                    Defaults.Toggle(key: .showClipboardIcon) {
                        Text("Show Clipboard Icon")
                    }
                    .settingsHighlight(id: highlightID("Show Clipboard Icon"))

                    Picker("Display Mode", selection: $clipboardDisplayMode) {
                        ForEach(ClipboardDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .settingsHighlight(id: highlightID("Display Mode"))

                    Picker("History Size", selection: $clipboardHistorySize) {
                        Text("3 items").tag(3)
                        Text("5 items").tag(5)
                        Text("7 items").tag(7)
                        Text("10 items").tag(10)
                    }
                    .pickerStyle(.menu)
                    .settingsHighlight(id: highlightID("History Size"))

                    LabeledContent("Current Items") {
                        Text("\(clipboardManager.clipboardHistory.count)")
                    }

                    LabeledContent("Pinned Items") {
                        Text("\(clipboardManager.pinnedItems.count)")
                    }

                    LabeledContent("Monitoring Status") {
                        Text(clipboardManager.isMonitoring ? "Active" : "Stopped")
                            .foregroundColor(clipboardManager.isMonitoring ? .green : .secondary)
                    }
                } header: {
                    SettingsSectionHeader("Settings")
                } footer: {
                    switch clipboardDisplayMode {
                    case .popover:
                        SettingsFooter("Popover mode shows clipboard as a dropdown attached to the clipboard button.")
                    case .panel:
                        SettingsFooter("Panel mode shows clipboard in a floating window near the notch.")
                    case .separateTab:
                        SettingsFooter("Separate Tab mode integrates Copied Items and Notes into a single view. If both are enabled, Notes appear on the right and Clipboard on the left.")
                    }
                }

                Section {
                    SettingsActionRow {
                        Button("Clear Pinned Items", role: .destructive) {
                            clipboardManager.pinnedItems.removeAll()
                            clipboardManager.savePinnedItemsToDefaults()
                        }
                        .foregroundColor(.red)
                        .disabled(clipboardManager.pinnedItems.isEmpty)

                        Button("Clear Clipboard History", role: .destructive) {
                            clipboardManager.clearHistory()
                        }
                        .foregroundColor(.red)
                        .disabled(clipboardManager.clipboardHistory.isEmpty)
                    }
                } header: {
                    SettingsSectionHeader("Actions")
                } footer: {
                    SettingsFooter("Clear clipboard history removes recent copies. Clear pinned items removes your favorites. Both actions are permanent.")
                }

                if !clipboardManager.clipboardHistory.isEmpty {
                    Section {
                        ForEach(clipboardManager.clipboardHistory) { item in
                            VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                                HStack(spacing: SettingsMetrics.rowContent) {
                                    Image(systemName: item.type.icon)
                                        .foregroundColor(.blue)
                                        .frame(width: 16)
                                        .accessibilityHidden(true)
                                    Text(item.type.displayName)
                                        .settingsDescriptionStyle()
                                    Spacer()
                                    Text(verbatim: timeAgoString(from: item.timestamp))
                                        .settingsDescriptionStyle()
                                }
                                Text(verbatim: item.preview)
                                    .font(.body)
                                    .monospaced()
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                        }
                    } header: {
                        SettingsSectionHeader("Current History")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Clipboard")
        .onAppear {
            if enableClipboardManager && !clipboardManager.isMonitoring {
                clipboardManager.startMonitoring()
            }
        }
    }

    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}
