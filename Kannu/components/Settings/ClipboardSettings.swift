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

/// Brain › Clipboard, a product page: the pinned items and History lead (`ClipboardOverview`), and these settings
/// follow.
struct ClipboardSettings: View {
    @ObservedObject private var visibility = BrainVisibility.shared
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.clipboardHistorySize) var clipboardHistorySize
    @Default(.showClipboardIcon) var showClipboardIcon
    @Default(.clipboardDisplayMode) var clipboardDisplayMode
    /// What the page shows from the clipboard manager, the product and these settings alike: a copy, never the manager
    /// itself, which the page used to observe whole. Read as the page appears and as Brain comes back on screen, then
    /// followed at most twice a second while it is on screen, and assigned only when it changed. Off screen it stays as
    /// it was (docs/SETTINGS.md, "Live data").
    @State private var clipboard = ClipboardPageData()

    private func highlightID(_ title: String) -> String {
        SettingsTab.clipboard.highlightID(for: title)
    }

    var body: some View {
        // The product first, then its settings (docs/SETTINGS.md, "Product pages").
        SettingsProductPage(settingsTitle: String(localized: "Clipboard settings")) {
            ClipboardOverview(data: clipboard)
        } settings: {
            SettingsSection {
                Defaults.Toggle(key: .enableClipboardManager) {
                    Text("Enable clipboard manager")
                }
                .settingsHighlight(id: highlightID("Enable Clipboard Manager"))
                .onChange(of: enableClipboardManager) { _, enabled in
                    if enabled {
                        ClipboardManager.shared.startMonitoring()
                    } else {
                        ClipboardManager.shared.stopMonitoring()
                    }
                }
            } header: {
                SettingsSectionHeader("Clipboard manager")
            } footer: {
                // The shortcut is the user's (default ⇧⌘C); the old text said Cmd+Shift+V.
                SettingsFooter("Monitor clipboard changes and keep a history of recent copies. With global keyboard shortcuts on, \(shortcutDescription(for: .clipboardHistoryPanel)) opens the history.")
            }

            if enableClipboardManager {
                SettingsSection {
                    Defaults.Toggle(key: .showClipboardIcon) {
                        Text("Show clipboard icon")
                    }
                    .settingsHighlight(id: highlightID("Show Clipboard Icon"))

                    SettingsRow("Display mode") {
                        SettingsSelect("Display mode", selection: $clipboardDisplayMode,
                                       options: ClipboardDisplayMode.allCases, optionTitle: \.displayName)
                    }
                    .settingsHighlight(id: highlightID("Display Mode"))

                    SettingsRow("History size") {
                        SettingsSelect("History size", selection: $clipboardHistorySize, choices: [
                            3: String(localized: "3 items"),
                            5: String(localized: "5 items"),
                            7: String(localized: "7 items"),
                            10: String(localized: "10 items"),
                        ])
                    }
                    .settingsHighlight(id: highlightID("History Size"))

                    // The counts moved up, beside Pinned Items and History.
                    LabeledContent("Monitoring status") {
                        SettingsStatusText(clipboard.isMonitoring ? String(localized: "Active") : String(localized: "Stopped"),
                                           isReady: clipboard.isMonitoring)
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
                // The clears moved to the header's "…", and the history list up, as History (`ClipboardOverview`).
            }
        }
        .navigationTitle("Clipboard")
        .onAppear {
            #if DEBUG
            if let fixture = ClipboardOverview.snapshotFixture {
                clipboard = fixture.data
                return
            }
            #endif
            // As before: Brain starts the manager when it is on and not running yet (`startMonitoring` checks).
            if enableClipboardManager {
                ClipboardManager.shared.startMonitoring()
            }
            // One read, not a subscription: the page opens on what the manager holds, and the subscription below takes
            // over once Brain is on screen.
            copyFromStore()
        }
        .task(id: visibility.isOnScreen) {
            #if DEBUG
            if ClipboardOverview.snapshotFixture != nil { return }
            #endif
            guard visibility.isOnScreen else { return }
            // Back on screen: what changed while Brain was not, which `objectWillChange` will not send again.
            copyFromStore()
            // `objectWillChange` comes before a change; read through the run loop, the copy comes after it.
            for await _ in ClipboardManager.shared.objectWillChange
                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
                .values {
                copyFromStore()
            }
        }
    }

    /// The one place the page reads the manager's state: a fresh copy, assigned only when it changed.
    private func copyFromStore() {
        let latest = ClipboardPageData(ClipboardManager.shared)
        if latest != clipboard { clipboard = latest }
    }
}
