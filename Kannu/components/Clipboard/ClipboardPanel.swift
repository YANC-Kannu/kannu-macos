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

private func applyClipboardCornerMask(_ view: NSView, radius: CGFloat) {
    view.wantsLayer = true
    view.layer?.masksToBounds = true
    view.layer?.cornerRadius = radius
    view.layer?.backgroundColor = NSColor.clear.cgColor
    if #available(macOS 13.0, *) {
        view.layer?.cornerCurve = .continuous
    }
}

class ClipboardPanel: NSPanel {
    
    static let preferredSize = CGSize(width: 320, height: 400)

    init() {
        // Created at its real size, like every other panel: installing content into a 0x0
        // window and sizing it afterwards is what doubled the hosting view (REGRESSIONS 19).
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.preferredSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        
        setupWindow()
        setupContentView()
    }
    
    // Override to allow the panel to become key window (required for TextField focus)
    override var canBecomeKey: Bool {
        return true
    }
    
    // Override to allow the panel to become main window (required for text input)
    override var canBecomeMain: Bool {
        return true
    }
    
    private func setupWindow() {
        // One shared invariant set (hidesOnDeactivate = false included): panels that
        // omitted it vanished the moment the app deactivated, which a fullscreen app
        // forces instantly (2026-09-30).
        configureAsOverlay(level: .floating)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true  // Enable dragging
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        
        // Allow dragging from any part of the window
        styleMask.insert(.fullSizeContentView)
        
        ScreenCaptureVisibilityManager.shared.register(self, scope: .panel)
        
        // Accept mouse moved events for proper hover behavior
        acceptsMouseMovedEvents = true
    }
    
    private func setupContentView() {
        let contentView = ClipboardPanelView {
            self.close()
        }
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.sizingOptions = []
        applyClipboardCornerMask(hostingView, radius: 12)
        setHostedContent(hostingView)
    }
    
    func positionNearNotch() {
        // The screen the user is looking at is the one under the pointer. NSScreen.main is the
        // key window's screen, which — summoned over a fullscreen app on another display — is
        // the wrong one: the panel opened there instead, running and not visible (2026-09-30).
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        let saved: NSPoint? = Defaults[.clipboardPanelPositionSaved]
            ? NSPoint(x: Defaults[.clipboardPanelPositionX], y: Defaults[.clipboardPanelPositionY])
            : nil
        let origin = ClipboardPanelPlacement.origin(saved: saved, panelSize: frame.size,
                                                    visibleFrame: screen.visibleFrame)
        withoutSavingPosition { setFrameOrigin(origin) }
    }

    /// Origin changes Kannu makes itself are not the user's chosen spot. The old override saved
    /// *every* move — programmatic placement and AppKit constraining the frame included — so one
    /// bad placement persisted and was restored forever after.
    private var isProgrammaticMove = false
    private func withoutSavingPosition(_ body: () -> Void) {
        isProgrammaticMove = true
        body()
        isProgrammaticMove = false
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        guard !isProgrammaticMove, isVisible else { return }
        Defaults[.clipboardPanelPositionSaved] = true
        Defaults[.clipboardPanelPositionX] = frame.origin.x
        Defaults[.clipboardPanelPositionY] = frame.origin.y
    }
    
}

struct ClipboardPanelView: View {
    let onClose: () -> Void
    @ObservedObject var clipboardManager = ClipboardManager.shared

    var body: some View {
        ClipboardPanelContent(history: clipboardManager.regularHistory, pinned: clipboardManager.pinnedItems,
                              historyIsEmpty: clipboardManager.clipboardHistory.isEmpty, onClose: onClose)
    }
}

/// What the panel draws, from the lists `ClipboardPanelView` hands it. Nothing here holds the clipboard manager: a press
/// calls it. So a DEBUG snapshot board draws this from made-up copies and never touches the manager, whose first touch
/// loads the saved history and deletes the image files it does not name (docs/REGRESSIONS.md, entry 22's 2026-11-11
/// addendum).
struct ClipboardPanelContent: View {
    /// The copies that are not pinned, newest first, and the pinned ones.
    let history: [ClipboardItem]
    let pinned: [ClipboardItem]
    /// Whether the manager holds no copy at all, which is what Clear History's button checks.
    let historyIsEmpty: Bool
    let onClose: () -> Void
    @State private var selectedTab: ClipboardTab
    @State private var searchText = ""
    @State private var hoveredItemId: UUID?

    /// The panel opens on History with nothing under the pointer; a board may open Favorites, or put a row under the
    /// pointer, whose buttons show only then.
    init(history: [ClipboardItem], pinned: [ClipboardItem], historyIsEmpty: Bool, onClose: @escaping () -> Void,
         selectedTab: ClipboardTab = .history, hoveredItemId: UUID? = nil) {
        self.history = history
        self.pinned = pinned
        self.historyIsEmpty = historyIsEmpty
        self.onClose = onClose
        _selectedTab = State(initialValue: selectedTab)
        _hoveredItemId = State(initialValue: hoveredItemId)
    }

    var filteredItems: [ClipboardItem] {
        let allItems = selectedTab == .history ? history : pinned

        if searchText.isEmpty {
            return allItems
        } else {
            return allItems.filter { item in
                item.preview.localizedCaseInsensitiveContains(searchText) ||
                item.type.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with tabs
            ClipboardPanelHeader(
                selectedTab: $selectedTab,
                searchText: $searchText,
                historyCount: history.count,
                pinnedCount: pinned.count,
                historyIsEmpty: historyIsEmpty,
                onClose: onClose
            )

            Rectangle()
                .fill(SettingsTheme.line)
                .frame(height: SettingsTheme.hairline)
                .accessibilityHidden(true)

            // Content
            if filteredItems.isEmpty {
                ClipboardPanelEmptyState(
                    hasSearch: !searchText.isEmpty,
                    isHistoryTab: selectedTab == .history
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredItems) { item in
                            ClipboardPanelItemRow(
                                item: item,
                                isHovered: hoveredItemId == item.id,
                                isPinned: pinned.contains(where: { $0.id == item.id })
                            ) { hoverId in
                                hoveredItemId = hoverId
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 320, height: 400)
        .background(SettingsTheme.panel)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
        // A window of its own, so it applies Brain's root itself, as a sheet does (docs/SETTINGS.md, "The floating
        // panels").
        .settingsDesignSystem()
    }
}

struct ClipboardPanelHeader: View {
    @Binding var selectedTab: ClipboardTab
    @Binding var searchText: String
    let historyCount: Int
    let pinnedCount: Int
    let historyIsEmpty: Bool
    let onClose: () -> Void
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Title and close button
            HStack {
                // Close button
                NativeStyleCloseButton(action: onClose)
                
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(SettingsTheme.ink)
                    .font(.system(size: 16, weight: .medium))

                Text("Clipboard Manager")
                    .font(SettingsTheme.sheetTitle)
                    .foregroundStyle(SettingsTheme.ink)

                Spacer()
                
                // Clear button
                Button(action: {
                    if selectedTab == .history {
                        ClipboardManager.shared.clearHistory()
                    } else {
                        ClipboardManager.shared.pinnedItems.removeAll()
                        ClipboardManager.shared.savePinnedItemsToDefaults()
                    }
                }) {
                    Image(systemName: "trash")
                        .foregroundStyle(SettingsTheme.destructive)
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedTab == .history ? historyIsEmpty : pinnedCount == 0)
                .hoverTooltip(clearTooltip, edge: .below)
                .accessibilityLabel(clearTooltip)
            }
            .padding(.horizontal, SettingsMetrics.cardPadding)
            .padding(.top, SettingsMetrics.cardPadding)

            // History or Favorites: Brain's two-option choice, each with how many it holds.
            SettingsSelect("Clipboard", selection: tabSelection, options: ClipboardTab.allCases,
                           optionTitle: segmentTitle, style: .segmented) { tab in
                Image(systemName: tab.icon)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsMetrics.cardPadding)

            // Search bar (always visible), in Brain's field chrome. The chrome hides the field's label, so what to type
            // is its prompt.
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SettingsTheme.inkSecondary)
                    .font(.system(size: 12))

                TextField("Search clipboard...", text: $searchText, prompt: Text("Search clipboard..."))
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(SettingsTheme.body)
                    .focused($isSearchFieldFocused)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SettingsTheme.inkSecondary)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverTooltip(String(localized: "Clear Search"), edge: .below)
                    .accessibilityLabel(String(localized: "Clear Search"))
                }
            }
            .settingsField(isFocused: isSearchFieldFocused)
            .padding(.horizontal, SettingsMetrics.cardPadding)
        }
        .padding(.bottom, 8)
    }

    private var clearTooltip: String {
        selectedTab == .history ? String(localized: "Clear History") : String(localized: "Clear Favorites")
    }

    /// A tab's name, then how many it holds when it holds any, as the panel's count capsule said.
    private func segmentTitle(_ tab: ClipboardTab) -> String {
        let count = tab == .history ? historyCount : pinnedCount
        return count > 0 ? "\(tab.localizedName) \(count.formatted())" : tab.localizedName
    }

    /// The panel switched tabs with this ease before the segments, and still does.
    private var tabSelection: Binding<ClipboardTab> {
        Binding(get: { selectedTab }, set: { tab in
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        })
    }
}

struct ClipboardPanelEmptyState: View {
    let hasSearch: Bool
    let isHistoryTab: Bool
    
    var body: some View {
        // Brain's empty state, as Clipboard's page draws its own: the glyph at the page title's size, the status, one line.
        VStack(spacing: SettingsMetrics.cardPadding) {
            Image(systemName: hasSearch ? "magnifyingglass" : (isHistoryTab ? "doc.on.clipboard" : "heart.fill"))
                .font(SettingsTheme.pageTitle)
                .foregroundStyle(SettingsTheme.inkSecondary)
            
            if hasSearch {
                Text("No results found")
                    .font(SettingsTheme.cardTitle)
                    .foregroundStyle(SettingsTheme.ink)

                Text("Try adjusting your search terms")
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.inkSecondary)
            } else {
                Text(isHistoryTab ? "No clipboard history" : "No favorites")
                    .font(SettingsTheme.cardTitle)
                    .foregroundStyle(SettingsTheme.ink)

                Text(isHistoryTab ? "Copy something to get started" : "Pin items to add them to favorites")
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClipboardPanelItemRow: View {
    let item: ClipboardItem
    let isHovered: Bool
    let isPinned: Bool
    let onHover: (UUID?) -> Void
    @State private var justCopied = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Type icon
            Image(systemName: item.type.icon)
                .font(.system(size: 14))
                .foregroundStyle(SettingsTheme.accentStrong)
                .frame(width: SettingsTheme.listRowIcon)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .font(SettingsTheme.body)
                    .foregroundStyle(SettingsTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    Text(item.type.displayName)
                        .font(SettingsTheme.description)
                        .foregroundStyle(SettingsTheme.inkSecondary)
                    
                    Spacer()
                    
                    Text(timeAgoString(from: item.timestamp))
                        .font(SettingsTheme.description)
                        .foregroundStyle(SettingsTheme.inkSecondary)
                }
            }
            
            Spacer()
            
            // Action buttons (shown on hover)
            if isHovered {
                HStack(spacing: 6) {
                    // Pin/Unpin button
                    Button(action: {
                        if isPinned {
                            ClipboardManager.shared.unpinItem(item)
                        } else {
                            ClipboardManager.shared.pinItem(item)
                        }
                    }) {
                        Image(systemName: isPinned ? "heart.fill" : "heart")
                            .font(.system(size: 11))
                            .foregroundStyle(isPinned ? SettingsTheme.accentStrong : SettingsTheme.ink)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverTooltip(favoriteTooltip, edge: .below)
                    .accessibilityLabel(favoriteTooltip)
                    
                    // Copy button
                    Button(action: {
                        ClipboardManager.shared.copyToClipboard(item)
                        
                        withAnimation(.easeInOut(duration: 0.2)) {
                            justCopied = true
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                justCopied = false
                            }
                        }
                    }) {
                        Image(systemName: justCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(justCopied ? SettingsTheme.success : SettingsTheme.ink)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverTooltip(String(localized: "Copy"), edge: .below)
                    .accessibilityLabel(String(localized: "Copy"))
                    
                    // Delete button
                    Button(action: {
                        if isPinned {
                            ClipboardManager.shared.unpinItem(item)
                        } else {
                            ClipboardManager.shared.deleteItem(item)
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsTheme.destructive)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverTooltip(String(localized: "Delete"), edge: .below)
                    .accessibilityLabel(String(localized: "Delete"))
                }
            }
        }
        .padding(.horizontal, SettingsMetrics.cardPadding)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                .fill(isHovered ? SettingsTheme.hover : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                onHover(hovering ? item.id : nil)
            }
        }
        .onTapGesture {
            ClipboardManager.shared.copyToClipboard(item)
        }
    }
    
    private var favoriteTooltip: String {
        isPinned ? String(localized: "Remove Favorite") : String(localized: "Add Favorite")
    }

    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return String(localized: "Just now")
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return String(localized: "\(minutes)m ago")
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return String(localized: "\(hours)h ago")
        } else {
            let days = Int(interval / 86400)
            return String(localized: "\(days)d ago")
        }
    }
}

private struct NativeStyleCloseButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 13, height: 13)
                .background(isHovered ? Color.red.opacity(0.8) : Color.red)
                .clipShape(Circle())
                .scaleEffect(isHovered ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        // Far-left of the panel (x=16, 13pt wide): a trailing-aligned bubble would grow off the
        // window's left edge, so it lines up with the button's leading edge instead.
        .hoverTooltip(String(localized: "Close"), edge: .below, alignment: .leading, isHovering: isHovered)
        .accessibilityLabel(String(localized: "Close"))
    }
}

#Preview {
    ClipboardPanelView {
        print("Close panel")
    }
}
