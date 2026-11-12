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
import SwiftUI

/// Brain › Clipboard's product, above its settings: the pinned items and how many there are, then History, folded until
/// it is opened, with how many copies it holds (docs/SETTINGS.md, "Product pages").
///
/// It shows what the clipboard manager holds and starts nothing of its own: no capture and no poll. A row's Copy, Pin
/// and Delete, the header's clears and Open history panel act only on a press, through the manager's own calls, as the
/// notch's clipboard panel makes them.
///
/// Nothing here observes the manager. `ClipboardSettings`, which holds this and the settings below, copies what both show
/// into one value, `ClipboardPageData`, at most twice a second while Brain is on screen, and hands it down; off screen the
/// copy stays as it was (docs/SETTINGS.md, "Live data"). A row says when it was copied by its date, so the page keeps no
/// clock.
struct ClipboardOverview: View {
    let data: ClipboardPageData
    @Default(.enableClipboardManager) private var enabled
    /// History starts folded: a copy can be anything, a password typed in a plain app included (the capture policy skips
    /// only concealed, transient and token-shaped copies), and a full-screen Brain can be on a shared screen. Brain's
    /// content is kept for the app's life, so the page folds it again each time it appears, Brain's reopening included.
    @State private var showsHistory = false

    #if DEBUG
    /// DEBUG snapshot boards only (`DebugSnapshots`): fixtures in place of this Mac's copies and pinned items, so none of
    /// them lands in a PNG. Set, the page never reads, follows or starts the clipboard manager.
    static var snapshotFixture: ClipboardOverviewFixture?
    #endif

    /// The clipboard manager's switch: off, the page shows its off card and the header nothing. On a board, the
    /// fixture's, never this Mac's switch.
    static func managerOn(_ enabled: Bool) -> Bool {
        #if DEBUG
        if let fixture = snapshotFixture { return fixture.clipboardOn }
        #endif
        return enabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
            if !Self.managerOn(enabled) {
                // Nothing is captured while it is off, so there is nothing current to show.
                SettingsSection {
                    ClipboardMessage(title: String(localized: "Clipboard manager is off"), message: nil) {
                        Button("Turn on") { enabled = true }
                    }
                }
            } else if data.pinned.isEmpty && data.history.isEmpty {
                // History fills itself, so the empty state teaches and has nothing to press.
                SettingsSection {
                    ClipboardMessage(title: String(localized: "No clipboard history"),
                                     message: String(localized: "Copy something to get started")) {
                        EmptyView()
                    }
                }
            } else {
                pinned
                if !data.history.isEmpty {
                    history
                }
            }
        }
        .onAppear {
            // Folded on every visit: `onAppear` runs again each time Brain reopens (docs/REGRESSIONS.md, entry 22).
            showsHistory = false
            #if DEBUG
            if let fixture = Self.snapshotFixture { showsHistory = fixture.showsHistory }
            #endif
        }
    }

    // MARK: - Pinned, and History

    /// The pinned items, oldest pin first as the manager keeps them, with their count beside the header.
    private var pinned: some View {
        SettingsSection {
            if data.pinned.isEmpty {
                SettingsNoteRow("Nothing pinned yet", description: "Pin items from history to save them here")
            } else {
                ForEach(data.pinned) { item in
                    ClipboardPageRow(item: item, isPinned: true)
                }
            }
        } header: {
            HStack(spacing: SettingsMetrics.rowContent) {
                SettingsSectionHeader("Pinned items")
                if !data.pinned.isEmpty {
                    Text(verbatim: data.pinned.count.formatted())
                        .settingsDescriptionStyle()
                }
            }
        }
    }

    /// The copies that are not pinned, newest first, folded behind their count until History is opened.
    private var history: some View {
        SettingsSection {
            DisclosureGroup(isExpanded: $showsHistory) {
                VStack(alignment: .leading, spacing: SettingsTheme.sectionRowGap) {
                    ForEach(data.history) { item in
                        ClipboardPageRow(item: item, isPinned: false)
                    }
                }
            } label: {
                // The count beside the title, not pushed to the far end: the space after it is the disclosure's own
                // button, which opens History.
                HStack(spacing: SettingsMetrics.rowContent) {
                    Text("History")
                    Text(verbatim: data.history.count.formatted())
                        .settingsDescriptionStyle()
                }
            }
        }
    }
}

/// Clipboard's header actions (docs/SETTINGS.md, "Product pages"): "…", which clears History or the pinned items, then
/// the page's one primary verb, Open history panel, the notch's floating clipboard panel. Nothing while the clipboard
/// manager is off, as the clears were hidden then.
struct ClipboardHeaderActions: View {
    @ObservedObject private var visibility = BrainVisibility.shared
    @Default(.enableClipboardManager) private var enabled
    /// Whether there is anything to clear, followed only while Brain is on screen.
    @State private var hasHistory = false
    @State private var hasPinned = false

    var body: some View {
        HStack(spacing: SettingsMetrics.rowContent) {
            if ClipboardOverview.managerOn(enabled) {
                SettingsMoreMenu {
                    // Both clear at once, as the buttons they replace did. The notch's tab asks first; one rule for
                    // Brain, the popover and the panel is a follow-up (followups.md).
                    Button("Clear history", role: .destructive) {
                        ClipboardManager.shared.clearHistory()
                    }
                    .disabled(!hasHistory)
                    Button("Clear pinned items", role: .destructive) {
                        ClipboardManager.shared.pinnedItems.removeAll()
                        ClipboardManager.shared.savePinnedItemsToDefaults()
                    }
                    .disabled(!hasPinned)
                }
                // On a press only: the panel the shortcut opens in Panel mode, whatever the mode, since the verb names it.
                Button("Open history panel") {
                    ClipboardPanelManager.shared.showClipboardPanel(trigger: "brain")
                }
                .buttonStyle(SettingsButtonStyle(.primary))
            }
        }
        // Two flags, passed on only when one changes; each `$` sends its current value as it subscribes.
        .task(id: visibility.isOnScreen) {
            #if DEBUG
            if ClipboardOverview.snapshotFixture != nil { return }
            #endif
            guard visibility.isOnScreen else { return }
            for await (historyEmpty, pinnedEmpty) in ClipboardManager.shared.$clipboardHistory.map(\.isEmpty)
                .combineLatest(ClipboardManager.shared.$pinnedItems.map(\.isEmpty))
                .removeDuplicates(by: ==)
                .values {
                hasHistory = !historyEmpty
                hasPinned = !pinnedEmpty
            }
        }
    }
}

// MARK: - A row, and the card in the rows' place

/// One copy: what it holds, its kind and when it was copied; then Copy, Pin or Unpin, and Delete, as the notch's
/// clipboard panel offers them. A pinned row has no Delete: there, the panel's and the popover's Delete only unpin, so
/// Unpin says what it does.
private struct ClipboardPageRow: View {
    let item: ClipboardItem
    let isPinned: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: SettingsMetrics.rowContent) {
                glyph("doc.on.doc", String(localized: "Copy")) {
                    ClipboardManager.shared.copyToClipboard(item)
                }
                glyph(isPinned ? "pin.slash" : "pin", isPinned ? String(localized: "Unpin") : String(localized: "Pin")) {
                    ClipboardManager.shared.togglePin(for: item)
                }
                if !isPinned {
                    glyph("trash", String(localized: "Delete"), role: .destructive) {
                        ClipboardManager.shared.deleteItem(item)
                    }
                }
            }
        } label: {
            SettingsRowLabel(
                verbatim: item.preview,
                description: "\(item.type.displayName) · \(item.timestamp.formatted(date: .abbreviated, time: .shortened))"
            )
            .lineLimit(2)
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
}

/// The rows' place when there is nothing to list, or the page's while the clipboard manager is off: the status, at most
/// one line that teaches, and at most one action (docs/SETTINGS.md, "Product pages"). It sits in a section's card, whose
/// padding is the hero's, so it is as tall as the hero less that padding.
private struct ClipboardMessage<Action: View>: View {
    let title: String
    let message: String?
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: SettingsMetrics.cardPadding) {
            Image(systemName: SettingsTab.clipboard.systemImage)
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

/// What Brain › Clipboard shows from the clipboard manager, copied in one value, so one throttled subscription carries
/// it and the page redraws only when it changed (docs/SETTINGS.md, "Live data"). The product and the settings below
/// both read it; nothing on the page reads the manager's state another way.
struct ClipboardPageData: Equatable {
    var pinned: [ClipboardItem] = []
    /// The copies not pinned, as the panel's History lists them.
    var history: [ClipboardItem] = []
    var isMonitoring = false

    init() {}

    /// The manager as it is now.
    init(_ manager: ClipboardManager) {
        pinned = manager.pinnedItems
        history = manager.regularHistory
        isMonitoring = manager.isMonitoring
    }

    /// A copy never changes once it is captured: what it holds is constant, and pinning moves it to the other list. So
    /// its id stands for it, and two readings differ only where an id or the monitoring does.
    static func == (lhs: ClipboardPageData, rhs: ClipboardPageData) -> Bool {
        lhs.pinned.map(\.id) == rhs.pinned.map(\.id) && lhs.history.map(\.id) == rhs.history.map(\.id)
            && lhs.isMonitoring == rhs.isMonitoring
    }
}

#if DEBUG
/// DEBUG snapshot boards only: what Brain › Clipboard shows in place of this Mac's clipboard, and whether History is
/// drawn open.
struct ClipboardOverviewFixture {
    var data: ClipboardPageData
    var showsHistory = false
    /// The clipboard manager: off, the page shows its off card in place of the pins and History, and the header nothing.
    var clipboardOn = true
}
#endif
