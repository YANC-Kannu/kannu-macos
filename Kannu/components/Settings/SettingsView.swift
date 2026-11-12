//
//  SettingsView.swift
//  DynamicIsland
//
//  Created by Richard Kunkli on 07/08/2024.
//
import AppKit
import Combine
import Defaults
import SwiftUI

/// Which sidebar list a tab belongs to. The list on screen follows the selected tab.
enum SettingsTabGroup {
    /// The sidebar's top: what Kannu does.
    case product
    /// Behind the sidebar's Settings row, with a Back row.
    case settings
    /// The sidebar's foot, with the Settings row.
    case info

    /// Only the Settings row has a name of its own.
    var title: String? {
        switch self {
        case .settings:         return String(localized: "Settings")
        case .product, .info:   return nil
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case liveActivities
    case appearance
    case lockScreen
    case media
    case devices
    case extensions
    case timer
    case hudAndOSD
    case battery
    case stats
    case clipboard
    case screenAssistant
    case downloads
    case shelf
    case shortcuts
    case notes
    case tasks
    case agentStatus
    case agentSecurity
    case llmUsage
    case about

    var id: String { rawValue }

    /// Which sidebar list this tab is on.
    var group: SettingsTabGroup {
        switch self {
        case .agentStatus, .agentSecurity, .llmUsage, .tasks, .timer, .notes, .clipboard:
            return .product
        case .general, .appearance, .liveActivities, .lockScreen, .media, .devices, .hudAndOSD,
             .battery, .stats, .shelf, .downloads, .screenAssistant, .shortcuts, .extensions:
            return .settings
        case .about:
            return .info
        }
    }

    var isBeta: Bool { self == .downloads || self == .extensions }

    /// The sidebar's order: the product list, then the Settings list, then About. Search jumps to the first match in
    /// this order, so it follows the sidebar's, and the menu bar's Go menu lists the product pages in it.
    static var sidebarOrder: [SettingsTab] {
        let ordered: [SettingsTab] = [
            .agentStatus,
            .agentSecurity,
            .llmUsage,
            .tasks,
            .timer,
            .notes,
            .clipboard,
            .general,
            .appearance,
            .liveActivities,
            .lockScreen,
            .media,
            .devices,
            .hudAndOSD,
            .battery,
            .stats,
            .shelf,
            .downloads,
            .screenAssistant,
            .shortcuts,
            .extensions,
            .about
        ]

        return ordered
    }

    /// The product list, in the sidebar's order: the Go menu's pages, ⌘1 to ⌘7.
    static var productPages: [SettingsTab] { sidebarOrder.filter { $0.group == .product } }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .liveActivities: return String(localized: "Live activities")
        case .appearance: return String(localized: "Appearance")
        case .lockScreen: return String(localized: "Lock screen")
        case .media: return String(localized: "Media")
        case .devices: return String(localized: "Devices")
        case .extensions: return String(localized: "Extensions")
        case .timer: return String(localized: "Timer")
        case .hudAndOSD: return String(localized: "HUD and OSD")
        case .battery: return String(localized: "Battery")
        case .stats: return String(localized: "Stats")
        case .clipboard: return String(localized: "Clipboard")
        case .screenAssistant: return String(localized: "Screen Assistant")
        case .downloads: return String(localized: "Downloads")
        case .shelf: return String(localized: "Shelf")
        case .shortcuts: return String(localized: "Shortcuts")
        case .notes: return String(localized: "Notes")
        case .tasks: return String(localized: "Tasks")
        case .agentStatus: return String(localized: "Agents")
        case .agentSecurity: return String(localized: "Security")
        case .llmUsage: return String(localized: "Usage")
        case .about: return String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .liveActivities: return "waveform.path.ecg"
        case .appearance: return "paintpalette"
        case .lockScreen: return "lock.laptopcomputer"
        case .media: return "play.laptopcomputer"
        case .devices: return "headphones"
        case .extensions: return "puzzlepiece.extension"
        case .timer: return "timer"
        case .hudAndOSD: return "dial.medium.fill"
        case .battery: return "battery.100.bolt"
        case .stats: return "chart.xyaxis.line"
        case .clipboard: return "clipboard"
        case .screenAssistant: return "brain.head.profile"
        case .downloads: return "square.and.arrow.down"
        case .shelf: return "books.vertical"
        case .shortcuts: return "keyboard"
        case .notes: return "note.text"
        case .tasks: return "checklist"
        case .agentStatus: return "light.beacon.max"
        case .agentSecurity: return "shield.lefthalf.filled"
        case .llmUsage: return "gauge.with.dots.needle.bottom.50percent"
        case .about: return "info.circle"
        }
    }

    func highlightID(for title: String) -> String {
        "\(rawValue)-\(title)"
    }
}

private struct SettingsSearchEntry: Identifiable {
    let tab: SettingsTab
    let title: String
    let keywords: [String]
    /// A `var` so a search can redirect it (`landingOnABuiltRow`).
    var highlightID: String?

    var id: String { "\(tab.rawValue)-\(title)" }
}

/// Highlight ids that external callers (outside this file) can deep-link to. Typed constants
/// so the string can never drift from the row's own `.settingsHighlight(id:)` registration.
enum SettingsDeepLink {
    static let smartCaffeinateHighlightID = SettingsTab.agentStatus.highlightID(for: "Smart caffeinate")
    static let securityFindingsHighlightID = SettingsTab.agentSecurity.highlightID(for: "Security findings")
    /// Brain › Tasks › Sources, on its first row, Local tasks, which is always there: where the notch
    /// Tasks popover's "Manage tasks…", "Add a source…" and Brain glyph land.
    static let tasksSourcesHighlightID = SettingsTab.tasks.highlightID(for: "Sources")
    /// Brain › Tasks › Sources, each connected source's row: where going back from its page lands,
    /// and where search lands for the rows on that page.
    static let tasksJiraSourceHighlightID = SettingsTab.tasks.highlightID(for: "Jira Cloud")
    static let tasksGitLabSourceHighlightID = SettingsTab.tasks.highlightID(for: "GitLab")
    static let tasksGitHubSourceHighlightID = SettingsTab.tasks.highlightID(for: "GitHub")
    static let tasksLinearSourceHighlightID = SettingsTab.tasks.highlightID(for: "Linear")
    static let tasksTodoistSourceHighlightID = SettingsTab.tasks.highlightID(for: "Todoist")
    static let tasksAppleRemindersSourceHighlightID = SettingsTab.tasks.highlightID(for: "Apple Reminders")
    /// Brain › Tasks › Sources › Add a source: where search lands for a source not connected, whose
    /// row is not there.
    static let tasksAddSourceHighlightID = SettingsTab.tasks.highlightID(for: "Add a source")

    /// Each source's row, by source.
    static let taskSourceRows: [TaskSource: String] = [
        .jira: tasksJiraSourceHighlightID, .gitlab: tasksGitLabSourceHighlightID, .github: tasksGitHubSourceHighlightID,
        .linear: tasksLinearSourceHighlightID, .todoist: tasksTodoistSourceHighlightID,
        .appleReminders: tasksAppleRemindersSourceHighlightID,
    ]
    /// Brain › Tasks › Your tasks, the All tasks row that opens the list: where search lands. The
    /// id keeps its old "Task list" name, so no link breaks.
    static let tasksListHighlightID = SettingsTab.tasks.highlightID(for: "Task list")
    /// The All tasks page itself, opened, on its back row: the popover's "Show all in Brain" and a
    /// click on a task reminder. `TasksSettings` opens the page for this id.
    static let tasksListOpenID = SettingsTab.tasks.highlightID(for: "Task list page")
    /// Brain › Tasks › Time to log, shown while an entry waits: the popover's "… more in Brain".
    static let tasksTimeToLogHighlightID = SettingsTab.tasks.highlightID(for: "Time to log")
    /// Brain › Agents' switch: where search lands for the tab's other rows while monitoring is off.
    static let agentMonitoringHighlightID = SettingsTab.agentStatus.highlightID(for: "Enable Agent Monitoring")
    /// Brain › Stats' switch: where search lands for the tab's other rows while stats monitoring is off.
    static let statsMonitoringHighlightID = SettingsTab.stats.highlightID(for: "Enable system stats monitoring")
    /// Brain › Security's first settings row, built whenever Agent Status is on: where Security's gear lands.
    static let securityAlertsHighlightID = SettingsTab.agentSecurity.highlightID(for: "High-severity alerts in the notch")
    /// Brain › Security › ADR scans, ADR Discovery's row, with its install command and Check again: where Connect ADR
    /// lands.
    static let securityConnectADRHighlightID = SettingsTab.agentSecurity.highlightID(for: "Connect ADR")
    /// Brain › Usage's switch, its first row and always built: where Usage's gear lands, and its empty state's
    /// "Turn on a provider" while the monitor is off.
    static let usageMonitorHighlightID = SettingsTab.llmUsage.highlightID(for: "Enable LLM Usage Monitor")
    /// Brain › Usage › Providers, on its first row: where the empty state's "Turn on a provider" lands while the monitor
    /// is on.
    static let usageProvidersHighlightID = SettingsTab.llmUsage.highlightID(for: "Claude Provider")
    /// Brain › Timer's switch, its first row and always built: where Timer's gear lands.
    static let timerFeatureHighlightID = SettingsTab.timer.highlightID(for: "Enable timer feature")
}

final class SettingsHighlightCoordinator: ObservableObject {
    /// `SettingsView` is constructed exactly once for the app's whole life
    /// (`SettingsWindowController` builds it a single time), so this is reachable from
    /// outside the file for callers that want to open Settings AND jump to a specific
    /// row — e.g. a notch control's "click to change in Settings" action.
    static let shared = SettingsHighlightCoordinator()

    #if DEBUG
    /// DEBUG snapshot boards only (`DebugSnapshots`): an animated scroll does not move in their
    /// off-screen window, and one with no animation does.
    static var snapshotScrollsAtOnce = false
    #endif

    struct ScrollRequest: Identifiable, Equatable {
        let id: String
        fileprivate let tab: SettingsTab
    }

    @Published fileprivate var pendingScrollRequest: ScrollRequest?
    @Published private(set) var activeHighlightID: String?

    private var clearWorkItem: DispatchWorkItem?

    fileprivate func focus(on entry: SettingsSearchEntry) {
        guard let highlightID = entry.highlightID else { return }
        pendingScrollRequest = ScrollRequest(id: highlightID, tab: entry.tab)
        activateHighlight(id: highlightID)
    }

    /// External entry point for deep-linking into a Settings row. Deliberately typed with a
    /// plain String rather than exposing `SettingsTab`/`SettingsSearchEntry` outward — callers
    /// outside this file only ever need to name a highlight id, not construct one of this
    /// file's private navigation types. The tab comes from the id's own prefix
    /// ("agentSecurity-Security findings" opens Agent Security), so a row can move between
    /// tabs without every notch call site knowing.
    func requestAgentStatusNavigation(highlightID: String) {
        let tab = SettingsTab.allCases.first { highlightID.hasPrefix($0.rawValue + "-") } ?? .agentStatus
        pendingScrollRequest = ScrollRequest(id: highlightID, tab: tab)
        activateHighlight(id: highlightID)
    }

    /// The menu bar's Go and File menus: a page, as its sidebar row opens it. The request a search pick sends, through
    /// the same switch point, but for no row: nothing pulses, and `SettingsForm` finds nothing to scroll to.
    func requestPage(_ tab: SettingsTab) {
        pendingScrollRequest = ScrollRequest(id: tab.rawValue, tab: tab)
    }

    /// File › New Task: Brain › Tasks opens New Task as soon as it can. Taken once, so the tab built again later
    /// never opens it a second time.
    @Published var pendingNewTask = false

    func consumeScrollRequest(_ request: ScrollRequest) {
        guard pendingScrollRequest?.id == request.id else { return }
        pendingScrollRequest = nil
    }

    private func activateHighlight(id: String) {
        activeHighlightID = id
        clearWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard self?.activeHighlightID == id else { return }
            self?.activeHighlightID = nil
        }

        clearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }
}

private struct SettingsHighlightModifier: ViewModifier {
    let id: String
    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator
    @State private var animatePulse = false

    private var isActive: Bool {
        highlightCoordinator.activeHighlightID == id
    }

    func body(content: Content) -> some View {
        content
            .id(id)
            .background(highlightBackground)
            .onChange(of: isActive) { _, active in
                animatePulse = active
            }
            .onAppear {
                if isActive {
                    animatePulse = true
                }
            }
    }

    private var highlightBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                SettingsTheme.accent.opacity(isActive ? (animatePulse ? 0.95 : 0.4) : 0),
                lineWidth: 2
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SettingsTheme.accent.opacity(isActive ? 0.08 : 0))
            )
            .padding(-4)
            .shadow(color: SettingsTheme.accent.opacity(isActive ? 0.25 : 0), radius: animatePulse ? 8 : 2)
            // Bounded, never `.repeatForever` (docs/REGRESSIONS.md, entry 22). At the clear `isActive`
            // moves the stroke's colour with no animation, then `animatePulse` moves nothing the
            // colour reads, so nothing ever replaced its repeating animator. It ran on behind the
            // closed window, which is only ordered out, at 40-60 % CPU until Kannu quit.
            .animation(
                isActive ? .easeInOut(duration: 0.8).repeatCount(3, autoreverses: true) : .default,
                value: animatePulse
            )
    }
}

extension View {
    func settingsHighlight(id: String) -> some View {
        modifier(SettingsHighlightModifier(id: id))
    }

    @ViewBuilder
    func settingsHighlightIfPresent(_ id: String?) -> some View {
        if let id {
            settingsHighlight(id: id)
        } else {
            self
        }
    }
}

private struct SettingsForm<Content: View>: View {
    let tab: SettingsTab
    /// A product page's actions, on its title's row: Agents' gear, Security's gear and Scan now or Connect ADR, Usage's
    /// gear and Refresh, Timer's gear and Start timer, and Clipboard's "…" and Open history panel. Each reads its own
    /// store.
    var actions: AnyView? = nil
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A sub-page's own title (Brain › Tasks' All tasks). Nil is the tab's.
    @State private var pageTitle: String?
    /// A flag, not the panel's width, so a resize redraws the page only when it crosses `widePanelWidth`.
    @State private var isWidePanel = false

    private var scrollAnimation: Animation? {
        #if DEBUG
        if SettingsHighlightCoordinator.snapshotScrollsAtOnce { return nil }
        #endif
        return reduceMotion ? nil : .easeInOut(duration: 0.45)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                SettingsPageHeader(title: pageTitle ?? tab.title, actions: actions)
                content()
                    .onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { request -> SettingsHighlightCoordinator.ScrollRequest? in
                        guard let request, request.tab == tab else { return nil }
                        return request
                    }) { request in
                        withAnimation(scrollAnimation) {
                            proxy.scrollTo(request.id, anchor: .center)
                        }
                        highlightCoordinator.consumeScrollRequest(request)
                    }
            }
            // The page is one scroll view across the panel, so its scrollbar sits at the panel's edge. It caps
            // its own column and starts it the inset from the panel's leading edge, never centred, so a
            // full-screen panel's spare width gathers on the right; the title starts there too. Measured here,
            // at the panel's width, and handed to both.
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.settingsPageInset, isWidePanel ? SettingsTheme.pageInsetWide : SettingsTheme.pageInset)
            .onGeometryChange(for: Bool.self) { $0.size.width >= SettingsTheme.widePanelWidth } action: { isWidePanel = $0 }
        }
        .onPreferenceChange(SettingsPageTitleKey.self) { pageTitle = $0 }
    }
}

struct SettingsView: View {
    // Land on the product's core pane, not a generic one — "Watch Your Agents".
    @State private var selectedTab: SettingsTab = .agentStatus
    @State private var searchText: String = ""
    /// The tab last left on each list: where Back and the Settings row return to. Two slots, because a
    /// search jumps between lists keystroke by keystroke and one slot would end up holding a jump.
    @State private var lastProductTab: SettingsTab?
    @State private var lastSettingsTab: SettingsTab?
    @FocusState private var sidebarHasFocus: Bool
    @StateObject private var highlightCoordinator = SettingsHighlightCoordinator.shared
    /// View › Hide Sidebar: whether the sidebar shows at all, never which list it shows.
    @Default(.brainShowsSidebar) private var showsSidebar
    /// A snapshot's window can never take focus, so its board asks for the suggestions outright.
    private var snapshotShowsSuggestions = false
    /// A snapshot's board with no sidebar, which leaves the setting alone.
    private var snapshotHidesSidebar = false

    var body: some View {
        BrainShell(showsSidebar: showsSidebar && !snapshotHidesSidebar) {
            sidebar
        } headerAccessory: {
            SettingsAppearanceToggle()
        } detail: {
            detailView(for: resolvedSelection)
        }
        .environmentObject(highlightCoordinator)
        // The single place tab selection reacts to a navigation request — search-bar picks
        // and external deep links (the notch caffeinate indicator) both flow through here.
        // The scroll itself is handled per-tab by SettingsForm once the target tab's form
        // exists; this only makes sure that tab is frontmost. The sidebar follows the tab.
        .onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { $0 }) { request in
            selectedTab = request.tab
            // A query left typed would keep the flat list, which has no row for this tab.
            if !filteredTabs.contains(request.tab) { searchText = "" }
        }
        .settingsDesignSystem()
        // Unbounded above: the window can go full screen, and SwiftUI's size bridge clamps the window
        // to this (docs/REGRESSIONS.md, entry 17).
        .frame(minWidth: SettingsTheme.windowMinWidth, maxWidth: .infinity, minHeight: SettingsTheme.windowMinHeight, maxHeight: .infinity)
        .onChange(of: searchText) { old, newValue in
            // Where the query started is where the user was. The jumps below are not.
            if old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { remember(resolvedSelection) }
            let matches = tabsMatchingSearch(newValue)
            guard let firstMatch = matches.first else { return }
            if !matches.contains(resolvedSelection) {
                selectedTab = firstMatch
            }
        }
        .onChange(of: selectedTab) { old, _ in
            if !isSearching { remember(old) }
        }
    }

    private var resolvedSelection: SettingsTab {
        availableTabs.contains(selectedTab) ? selectedTab : (availableTabs.first ?? .general)
    }

    private func remember(_ tab: SettingsTab) {
        if tab.group == .settings { lastSettingsTab = tab } else { lastProductTab = tab }
    }

    private var filteredTabs: [SettingsTab] {
        tabsMatchingSearch(searchText)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// No mode flag: the list on screen is whichever one the selected tab is on, so a deep link or a
    /// search moves the sidebar with no path of its own.
    private var showsSettingsList: Bool { resolvedSelection.group == .settings }

    private var listedTabs: [SettingsTab] {
        if isSearching { return filteredTabs }
        return availableTabs.filter { $0.group == (showsSettingsList ? .settings : .product) }
    }

    @ViewBuilder
    private var sidebar: some View {
        SettingsSidebarSearchBar(
            text: $searchText,
            suggestions: searchSuggestions,
            showsSuggestionsUnfocused: snapshotShowsSuggestions,
            onSuggestionSelected: handleSearchSuggestionSelection
        )
        // A custom list, not `List(selection:)`: on macOS that draws its own selection, and
        // `listRowBackground` does not replace it.
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: SettingsTheme.sidebarRowGap) {
                    if showsSettingsList && !isSearching {
                        SettingsSidebarRow(String(localized: "Back"), systemImage: "chevron.left") { showProductList() }
                    }
                    ForEach(listedTabs) { tabRow($0).id($0) }
                }
                // On a background, not the stack: an outer `focusEffectDisabled` beats anything inside
                // it, so the rows would lose their ring under Full Keyboard Access.
                .background {
                    Color.clear
                        .focusable()
                        .focused($sidebarHasFocus)
                        .focusEffectDisabled()
                        .accessibilityHidden(true)
                }
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    moveSelection(by: press.key == .upArrow ? -1 : 1)
                    return .handled
                }
                // Back and the Settings row by key: they are the only way across, and not in the arrow order.
                .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                    guard !isSearching, showsSettingsList == (press.key == .leftArrow) else { return .ignored }
                    if showsSettingsList { showProductList() } else { showSettingsList() }
                    return .handled
                }
            }
            // Arrow keys can reach a row off screen, and a custom list does not follow its selection.
            .onChange(of: resolvedSelection) { _, tab in proxy.scrollTo(tab) }
            // A query changes the list under the selected row, so it can scroll away with no change of tab.
            .onChange(of: listedTabs, initial: true) { _, _ in proxy.scrollTo(resolvedSelection) }
        }
        if !showsSettingsList && !isSearching {
            VStack(spacing: SettingsTheme.sidebarRowGap) {
                SettingsSidebarRow(SettingsTabGroup.settings.title ?? "", systemImage: "gearshape") { showSettingsList() }
                tabRow(.about)
            }
        }
    }

    private func showProductList() {
        selectedTab = lastProductTab ?? .agentStatus
        sidebarHasFocus = true
    }

    private func showSettingsList() {
        selectedTab = lastSettingsTab ?? .general
        sidebarHasFocus = true
    }

    private func tabRow(_ tab: SettingsTab) -> some View {
        // The badge reads its own state, throttled and only while Brain is on screen; this view observes nothing new.
        SettingsSidebarRow(tab.title, systemImage: tab.systemImage, isSelected: tab == resolvedSelection,
                           badge: SidebarBadge(tab)) {
            selectedTab = tab
            sidebarHasFocus = true
        }
    }

    /// About is a foot row, as Settings is, so it is not in this order. From a tab outside it (About, or
    /// one a query has dropped) the arrows enter the list at its near end rather than doing nothing.
    private func moveSelection(by offset: Int) {
        let tabs = listedTabs
        guard let index = tabs.firstIndex(of: resolvedSelection) else {
            selectedTab = (offset < 0 ? tabs.last : tabs.first) ?? selectedTab
            return
        }
        guard tabs.indices.contains(index + offset) else { return }
        selectedTab = tabs[index + offset]
    }

    private var availableTabs: [SettingsTab] {
        SettingsTab.sidebarOrder
    }

    private func tabsMatchingSearch(_ query: String) -> [SettingsTab] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return availableTabs }

        let entryMatches = searchEntries(matching: trimmed)
        let matchingTabs = Set(entryMatches.map(\.tab))

        return availableTabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(trimmed) || matchingTabs.contains(tab)
        }
    }

    /// Every match, best first. It used to stop at eight in index order, so "color" never reached
    /// Notch fill color behind seven Devices and HUD rows; the list scrolls past eight instead.
    private var searchSuggestions: [SettingsSearchEntry] {
        searchEntries(matching: searchText).filter { $0.tab != .downloads }
    }

    private func handleSearchSuggestionSelection(_ suggestion: SettingsSearchEntry) {
        guard suggestion.tab != .downloads else { return }
        // Tab selection happens via the body-level onReceive of pendingScrollRequest, the
        // single switch point shared with external deep links (e.g. the notch caffeinate
        // indicator) — not here, or the two paths drift.
        highlightCoordinator.focus(on: suggestion)
    }

    private struct SettingsSidebarSearchBar: View {
        @Binding var text: String
        let suggestions: [SettingsSearchEntry]
        /// Only a snapshot's board: its window can never take focus.
        var showsSuggestionsUnfocused = false
        let onSuggestionSelected: (SettingsSearchEntry) -> Void

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @FocusState private var isFocused: Bool
        @State private var hoveredSuggestionID: SettingsSearchEntry.ID?

        var body: some View {
            VStack(spacing: 6) {
                searchField
                if showSuggestions {
                    suggestionList
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: SettingsTheme.quickAnimation), value: showSuggestions)
            // New matches sit at new heights: the old rows' measures say nothing about them.
            .onChange(of: suggestions.map(\.id)) { _, _ in rowBottoms = [:] }
        }

        private var showSuggestions: Bool {
            (isFocused || showsSuggestionsUnfocused) && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !suggestions.isEmpty
        }

        private var searchField: some View {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SettingsTheme.inkSecondary)

                TextField("Search Brain", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(triggerFirstSuggestion)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SettingsTheme.inkSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: SettingsTheme.fieldRadius, style: .continuous)
                    .fill(SettingsTheme.card)
            )
            .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.fieldRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsTheme.fieldRadius, style: .continuous)
                    .stroke(SettingsTheme.line)
            )
        }

        /// The list's tallest: past it the list scrolls rather than growing down the sidebar.
        private static let maxListHeight: CGFloat = 344
        /// One-line rows are about 47 pt, so seven fill `maxListHeight`, and more matches than this always scroll.
        private static let rowsThatFit = 7
        /// The rows' own space, where each measures its bottom edge.
        private static let rowSpace = "suggestionRows"
        /// The scroll view's own space, where the rows' foot shows whether more rows sit below.
        private static let scrollSpace = "suggestionScroll"
        /// Each row's bottom edge in the list, measured, since a title takes one line or two.
        @State private var rowBottoms: [SettingsSearchEntry.ID: CGFloat] = [:]
        /// Where the rows end, below the top of the scroll view as it is scrolled.
        @State private var rowsFoot: CGFloat = 0

        /// Decided from what is known now, so an unmeasured list is never taller than `maxListHeight`: more matches than
        /// fit, or a last row not yet measured, scroll; otherwise the list scrolls only if its measured rows run past it.
        private var listScrolls: Bool {
            guard suggestions.count <= Self.rowsThatFit, let last = suggestions.last,
                  let bottom = rowBottoms[last.id] else { return true }
            return bottom > Self.maxListHeight
        }

        /// Whole rows only: the measured bottoms trim the scroll view to the lowest one under `maxListHeight`, so the last
        /// row it shows is never cut; `maxListHeight` while nothing is measured.
        private var listHeight: CGFloat {
            suggestions.compactMap { rowBottoms[$0.id] }.filter { $0 <= Self.maxListHeight }.max() ?? Self.maxListHeight
        }

        private var suggestionList: some View {
            Group {
                if listScrolls {
                    ScrollView {
                        suggestionRows
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.scrollSpace)).maxY } action: {
                                rowsFoot = $0
                            }
                    }
                    .coordinateSpace(.named(Self.scrollSpace))
                    .frame(height: listHeight)
                    // While rows sit below the foot, a short fade says there is more; it goes once the last row is in.
                    .overlay(alignment: .bottom) {
                        if rowsFoot > listHeight + SettingsTheme.hairline {
                            LinearGradient(colors: [SettingsTheme.card.opacity(0), SettingsTheme.card],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: SettingsTheme.suggestionFade)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                } else {
                    suggestionRows
                }
            }
            .background(
                RoundedRectangle(cornerRadius: SettingsTheme.fieldRadius, style: .continuous)
                    .fill(SettingsTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsTheme.fieldRadius, style: .continuous)
                    .stroke(SettingsTheme.line)
            )
            .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.fieldRadius, style: .continuous))
            .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .move(edge: .top)))
        }

        private var suggestionRows: some View {
            VStack(spacing: 0) {
                ForEach(suggestions) { suggestion in
                    Button {
                        selectSuggestion(suggestion)
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(SettingsTheme.card)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Image(systemName: suggestion.tab.systemImage)
                                        .font(SettingsTheme.bodyStrong)
                                        .foregroundStyle(SettingsTheme.ink)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(SettingsTheme.body)
                                    .foregroundStyle(SettingsTheme.ink)
                                    .lineLimit(2)
                                Text(suggestion.tab.title)
                                    .font(SettingsTheme.description)
                                    .foregroundStyle(SettingsTheme.inkSecondary)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background(rowBackground(for: suggestion))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredSuggestionID = hovering ? suggestion.id : (hoveredSuggestionID == suggestion.id ? nil : hoveredSuggestionID)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.rowSpace)).maxY } action: {
                        rowBottoms[suggestion.id] = $0
                    }

                    if suggestion.id != suggestions.last?.id {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .coordinateSpace(.named(Self.rowSpace))
        }

        private func rowBackground(for suggestion: SettingsSearchEntry) -> some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hoveredSuggestionID == suggestion.id ? SettingsTheme.hover : Color.clear)
        }

        private func selectSuggestion(_ suggestion: SettingsSearchEntry) {
            onSuggestionSelected(suggestion)
            isFocused = false
        }

        private func triggerFirstSuggestion() {
            guard let first = suggestions.first else { return }
            selectSuggestion(first)
        }
    }

    private func searchEntries(matching query: String) -> [SettingsSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let candidates = settingsSearchIndex.filter { availableTabs.contains($0.tab) }
        return SettingsSearchRanking.ranked(candidates, query: trimmed, title: \.title, keywords: \.keywords)
            .map(landingOnABuiltRow)
    }

    /// Brain › Tasks builds a source's row only while the source is connected. An entry for that row
    /// lands on Add a source until then, instead of scrolling to a row that was never built.
    private func landingOnABuiltRow(_ entry: SettingsSearchEntry) -> SettingsSearchEntry {
        // Agents builds its other rows only while monitoring is on: until then they land on its switch.
        if entry.tab == .agentStatus, !Defaults[.enableAgentStatusFeature] {
            var landed = entry
            landed.highlightID = SettingsDeepLink.agentMonitoringHighlightID
            return landed
        }
        // Stats builds its other rows only while stats monitoring is on: until then they land on its switch.
        if entry.tab == .stats, !Defaults[.enableStatsFeature] {
            var landed = entry
            landed.highlightID = SettingsDeepLink.statsMonitoringHighlightID
            return landed
        }
        guard let id = entry.highlightID,
              let source = SettingsDeepLink.taskSourceRows.first(where: { $0.value == id })?.key,
              !source.isConnected else { return entry }
        var landed = entry
        landed.highlightID = SettingsDeepLink.tasksAddSourceHighlightID
        return landed
    }

    private var settingsSearchIndex: [SettingsSearchEntry] {
        [
            // General
            SettingsSearchEntry(tab: .general, title: "Menubar icon", keywords: ["menu bar", "status bar", "icon"], highlightID: SettingsTab.general.highlightID(for: "Menubar icon")),
            SettingsSearchEntry(tab: .general, title: "Launch at login", keywords: ["autostart", "startup"], highlightID: SettingsTab.general.highlightID(for: "Launch at login")),
            SettingsSearchEntry(tab: .general, title: "Quit Kannu", keywords: ["quit", "exit", "close", "stop", "shut down", "terminate"], highlightID: SettingsTab.general.highlightID(for: "Quit Kannu")),
            SettingsSearchEntry(tab: .general, title: "Where Kannu appears", keywords: ["display", "displays", "monitor", "external", "built-in", "all displays", "multi-display", "screen", "placement", "switch", "move", "second screen"], highlightID: SettingsTab.general.highlightID(for: "Where Kannu appears")),
            SettingsSearchEntry(tab: .general, title: "Display", keywords: ["preferred screen", "display picker", "specific display", "choose display"], highlightID: SettingsTab.general.highlightID(for: "Display")),
            SettingsSearchEntry(tab: .general, title: "Screenshots & recordings", keywords: ["privacy", "screenshot", "recording", "capture", "hide", "notch", "screen sharing"], highlightID: SettingsTab.general.highlightID(for: "Screenshots & recordings")),
            SettingsSearchEntry(tab: .general, title: "Enable gestures", keywords: ["gestures", "trackpad"], highlightID: SettingsTab.general.highlightID(for: "Enable gestures")),
            SettingsSearchEntry(tab: .general, title: "Close gesture", keywords: ["pinch", "swipe"], highlightID: SettingsTab.general.highlightID(for: "Close gesture")),
            SettingsSearchEntry(tab: .general, title: "Reverse swipe gestures", keywords: ["reverse", "swipe", "media"], highlightID: SettingsTab.general.highlightID(for: "Reverse swipe gestures")),
            SettingsSearchEntry(tab: .general, title: "Reverse scroll gestures", keywords: ["reverse", "scroll", "open", "close"], highlightID: SettingsTab.general.highlightID(for: "Reverse scroll gestures")),
            SettingsSearchEntry(tab: .general, title: "Extend hover area", keywords: ["hover", "cursor"], highlightID: SettingsTab.general.highlightID(for: "Extend hover area")),
            SettingsSearchEntry(tab: .general, title: "Enable haptics", keywords: ["haptic", "feedback"], highlightID: SettingsTab.general.highlightID(for: "Enable haptics")),
            SettingsSearchEntry(tab: .general, title: "Open notch on hover", keywords: ["hover to open", "auto open"], highlightID: SettingsTab.general.highlightID(for: "Open notch on hover")),
            SettingsSearchEntry(tab: .general, title: "Minimum hover duration", keywords: ["hover", "delay", "dwell", "slide in", "hidden island", "external display"], highlightID: SettingsTab.general.highlightID(for: "Minimum hover duration")),
            SettingsSearchEntry(tab: .general, title: "External display style", keywords: ["dynamic island", "pill", "external display", "non-notch", "floating", "capsule"], highlightID: SettingsTab.general.highlightID(for: "External display style")),
            SettingsSearchEntry(tab: .general, title: "Always show on non-notch displays", keywords: ["always show", "hide", "hover", "external", "non-notch", "auto hide", "slide"], highlightID: SettingsTab.general.highlightID(for: "Always show on non-notch displays")),
            SettingsSearchEntry(tab: .general, title: "Notch display height", keywords: ["display height", "menu bar size"], highlightID: SettingsTab.general.highlightID(for: "Notch display height")),
            SettingsSearchEntry(tab: .general, title: "Permissions", keywords: ["permission", "privacy", "allow", "accessibility", "bluetooth", "location", "downloads", "warp", "notes", "automation"], highlightID: SettingsTab.general.highlightID(for: "Permissions")),

            // Live Activities
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Screen Recording Detection", keywords: ["screen recording", "indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Screen Recording Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show Recording Indicator", keywords: ["recording indicator", "red dot"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Recording Indicator")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Focus Detection", keywords: ["focus", "do not disturb", "dnd"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Focus Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show Focus Indicator", keywords: ["focus icon", "moon"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Focus Indicator")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show Focus Label", keywords: ["focus label", "text"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Focus Label")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Camera Detection", keywords: ["camera", "privacy indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Camera Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Microphone Detection", keywords: ["microphone", "privacy"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Microphone Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable music live activity", keywords: ["music", "now playing"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable music live activity")),

            // Battery (Charge)
            SettingsSearchEntry(tab: .battery, title: "Show battery indicator", keywords: ["battery hud", "charge"], highlightID: SettingsTab.battery.highlightID(for: "Show battery indicator")),
            SettingsSearchEntry(tab: .battery, title: "Show battery percentage", keywords: ["battery percent"], highlightID: SettingsTab.battery.highlightID(for: "Show battery percentage")),
            SettingsSearchEntry(tab: .battery, title: "Show power status notifications", keywords: ["notifications", "power"], highlightID: SettingsTab.battery.highlightID(for: "Show power status notifications")),
            SettingsSearchEntry(tab: .battery, title: "Show power status icons", keywords: ["power icons", "charging icon"], highlightID: SettingsTab.battery.highlightID(for: "Show power status icons")),
            SettingsSearchEntry(tab: .battery, title: "Play low battery alert sound", keywords: ["low battery", "alert", "sound"], highlightID: SettingsTab.battery.highlightID(for: "Play low battery alert sound")),
            SettingsSearchEntry(tab: .battery, title: "Charging HUD", keywords: ["battery", "charging", "temporary activity"], highlightID: SettingsTab.battery.highlightID(for: "Charging HUD")),
            SettingsSearchEntry(tab: .battery, title: "Low battery HUD", keywords: ["battery", "low", "temporary activity"], highlightID: SettingsTab.battery.highlightID(for: "Low battery HUD")),
            SettingsSearchEntry(tab: .battery, title: "Fully charged HUD", keywords: ["battery", "full", "temporary activity"], highlightID: SettingsTab.battery.highlightID(for: "Fully charged HUD")),
            SettingsSearchEntry(tab: .battery, title: "Charging duration", keywords: ["charging", "duration", "seconds"], highlightID: SettingsTab.battery.highlightID(for: "Charging duration")),
            SettingsSearchEntry(tab: .battery, title: "Low battery duration", keywords: ["low battery", "duration", "seconds"], highlightID: SettingsTab.battery.highlightID(for: "Low battery duration")),
            SettingsSearchEntry(tab: .battery, title: "Full battery duration", keywords: ["full battery", "duration", "seconds"], highlightID: SettingsTab.battery.highlightID(for: "Full battery duration")),
            SettingsSearchEntry(tab: .battery, title: "Test charging HUD", keywords: ["battery", "test", "charging", "preview"], highlightID: SettingsTab.battery.highlightID(for: "Test charging HUD")),
            SettingsSearchEntry(tab: .battery, title: "Test low battery HUD", keywords: ["battery", "test", "low", "preview"], highlightID: SettingsTab.battery.highlightID(for: "Test low battery HUD")),
            SettingsSearchEntry(tab: .battery, title: "Test full battery HUD", keywords: ["battery", "test", "full", "preview"], highlightID: SettingsTab.battery.highlightID(for: "Test full battery HUD")),
            SettingsSearchEntry(tab: .battery, title: "Low battery style", keywords: ["battery", "style", "compact", "standard"], highlightID: SettingsTab.battery.highlightID(for: "Low battery style")),
            SettingsSearchEntry(tab: .battery, title: "Low battery threshold", keywords: ["battery", "threshold", "percent"], highlightID: SettingsTab.battery.highlightID(for: "Low battery threshold")),
            SettingsSearchEntry(tab: .battery, title: "Full battery style", keywords: ["battery", "style", "compact", "standard"], highlightID: SettingsTab.battery.highlightID(for: "Full battery style")),
            SettingsSearchEntry(tab: .battery, title: "Full charge threshold", keywords: ["battery", "threshold", "full"], highlightID: SettingsTab.battery.highlightID(for: "Full charge threshold")),

            // HUDs
            SettingsSearchEntry(tab: .devices, title: "Show Bluetooth device connections", keywords: ["bluetooth", "hud"], highlightID: SettingsTab.devices.highlightID(for: "Show Bluetooth device connections")),
            SettingsSearchEntry(tab: .devices, title: "Use circular battery indicator", keywords: ["battery", "circular"], highlightID: SettingsTab.devices.highlightID(for: "Use circular battery indicator")),
            SettingsSearchEntry(tab: .devices, title: "Show battery percentage text in HUD", keywords: ["battery text"], highlightID: SettingsTab.devices.highlightID(for: "Show battery percentage text in HUD")),
            SettingsSearchEntry(tab: .devices, title: "Scroll device name in HUD", keywords: ["marquee", "device name"], highlightID: SettingsTab.devices.highlightID(for: "Scroll device name in HUD")),
            SettingsSearchEntry(tab: .devices, title: "Use 3D Bluetooth HUD icon", keywords: ["bluetooth", "3d", "animation", "mov"], highlightID: SettingsTab.devices.highlightID(for: "Use 3D Bluetooth HUD icon")),
            SettingsSearchEntry(tab: .devices, title: "Color-coded battery display", keywords: ["color", "battery"], highlightID: SettingsTab.devices.highlightID(for: "Color-coded battery display")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Color-coded volume display", keywords: ["volume", "color"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Color-coded volume display")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Smooth color transitions", keywords: ["gradient", "smooth"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Smooth color transitions")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Show percentages beside progress bars", keywords: ["percentages", "progress"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Show percentages beside progress bars")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "HUD style", keywords: ["inline", "compact", "controls"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "HUD style")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Progressbar style", keywords: ["progress", "style"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Progressbar style")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable glowing effect", keywords: ["glow", "indicator"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable glowing effect")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Use accent color", keywords: ["accent", "color"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Use accent color")),

            // Custom OSD
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable Custom OSD", keywords: ["osd", "on-screen display", "custom osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable Custom OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Volume OSD", keywords: ["volume", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Brightness OSD", keywords: ["brightness", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Keyboard Backlight OSD", keywords: ["keyboard", "backlight", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Keyboard Backlight OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Material", keywords: ["material", "frosted", "liquid", "glass", "solid", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Material")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Icon & Progress Color", keywords: ["color", "icon", "white", "black", "gray", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Icon & Progress Color")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Volume step", keywords: ["volume", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume step")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Volume fine step", keywords: ["volume", "fine", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume fine step")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Brightness step", keywords: ["brightness", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness step")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Brightness fine step", keywords: ["brightness", "fine", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness fine step")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Third-party DDC app integration", keywords: ["ddc", "third party", "external", "display", "betterdisplay", "lunar"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Third-party DDC app integration")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Third-party DDC provider", keywords: ["provider", "betterdisplay", "lunar", "integration", "refresh detection"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Third-party DDC provider")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable external volume control listener", keywords: ["external volume", "ddc volume", "betterdisplay volume", "lunar volume", "disable native volume"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable external volume control listener")),

            // Media
            SettingsSearchEntry(tab: .media, title: "Music Source", keywords: ["media source", "controller"], highlightID: SettingsTab.media.highlightID(for: "Music Source")),
            SettingsSearchEntry(tab: .media, title: "Skip buttons", keywords: ["skip", "controls", "±10"], highlightID: SettingsTab.media.highlightID(for: "Skip buttons")),
            SettingsSearchEntry(tab: .media, title: "Sneak Peek Style", keywords: ["sneak peek", "preview"], highlightID: SettingsTab.media.highlightID(for: "Sneak Peek Style")),
            SettingsSearchEntry(tab: .media, title: "Enable lyrics", keywords: ["lyrics", "song text"], highlightID: SettingsTab.media.highlightID(for: "Enable lyrics")),
            SettingsSearchEntry(tab: .media, title: "Show live canvas in Dynamic Island", keywords: ["canvas", "live canvas", "album art", "dynamic island", "spotify canvas"], highlightID: SettingsTab.media.highlightID(for: "Show live canvas in Dynamic Island")),
            SettingsSearchEntry(tab: .media, title: "Auto-hide inactive notch media player", keywords: ["auto hide", "inactive", "placeholder", "notch media"], highlightID: SettingsTab.media.highlightID(for: "Auto-hide inactive notch media player")),
            SettingsSearchEntry(tab: .media, title: "Show Change Media Output control", keywords: ["airplay", "route picker", "media output"], highlightID: SettingsTab.media.highlightID(for: "Show Change Media Output control")),
            SettingsSearchEntry(tab: .media, title: "Enable album art parallax", keywords: ["parallax", "lock screen", "album art"], highlightID: SettingsTab.media.highlightID(for: "Enable album art parallax")),
            SettingsSearchEntry(tab: .media, title: "Enable album art parallax effect", keywords: ["parallax", "parallax effect", "album art"], highlightID: SettingsTab.media.highlightID(for: "Enable album art parallax effect")),
            SettingsSearchEntry(tab: .media, title: "Hide in fullscreen", keywords: ["fullscreen", "hide notch", "hide dynamicisland", "video", "movie"], highlightID: SettingsTab.media.highlightID(for: "Hide DynamicIsland Options")),
            // The Accessibility row is built only while the grant is missing, so its entry lands
            // on the always-visible picker right above it (the #90 rule: never target a row that
            // is sometimes not built).
            SettingsSearchEntry(tab: .media, title: "Accessibility access", keywords: ["accessibility", "fullscreen", "permission", "menu bar"], highlightID: SettingsTab.media.highlightID(for: "Hide DynamicIsland Options")),

            // Shelf
            SettingsSearchEntry(tab: .shelf, title: "Enable shelf", keywords: ["shelf", "dock"], highlightID: SettingsTab.shelf.highlightID(for: "Enable shelf")),
            SettingsSearchEntry(tab: .shelf, title: "Open shelf tab by default if items added", keywords: ["auto open", "shelf tab"], highlightID: SettingsTab.shelf.highlightID(for: "Open shelf tab by default if items added")),
            SettingsSearchEntry(tab: .shelf, title: "Expanded drag detection area", keywords: ["shelf", "drag"], highlightID: SettingsTab.shelf.highlightID(for: "Expanded drag detection area")),
            SettingsSearchEntry(tab: .shelf, title: "Copy items on drag", keywords: ["shelf", "drag", "copy"], highlightID: SettingsTab.shelf.highlightID(for: "Copy items on drag")),
            SettingsSearchEntry(tab: .shelf, title: "Remove from shelf after dragging", keywords: ["shelf", "drag", "remove"], highlightID: SettingsTab.shelf.highlightID(for: "Remove from shelf after dragging")),
            SettingsSearchEntry(tab: .shelf, title: "Quick Share Service", keywords: ["shelf", "share", "airdrop", "localsend"], highlightID: SettingsTab.shelf.highlightID(for: "Quick Share Service")),
            SettingsSearchEntry(tab: .shelf, title: "LocalSend Device Picker Style", keywords: ["localsend", "glass", "picker", "material"], highlightID: SettingsTab.shelf.highlightID(for: "Device Picker Style")),

            // Appearance
            SettingsSearchEntry(tab: .appearance, title: "Main screen style", keywords: ["dynamic island", "pill", "non-notch", "display style", "notch style"], highlightID: SettingsTab.appearance.highlightID(for: "Main screen style")),
            SettingsSearchEntry(tab: .appearance, title: "Brain icon in notch", keywords: ["brain", "settings", "gear", "settings button", "toolbar"], highlightID: SettingsTab.appearance.highlightID(for: "Brain icon in notch")),
            SettingsSearchEntry(tab: .appearance, title: "Enable window shadow", keywords: ["shadow", "appearance"], highlightID: SettingsTab.appearance.highlightID(for: "Enable window shadow")),
            SettingsSearchEntry(tab: .appearance, title: "Corner radius scaling", keywords: ["corner radius", "shape"], highlightID: SettingsTab.appearance.highlightID(for: "Corner radius scaling")),
            SettingsSearchEntry(tab: .appearance, title: "Use simpler close animation", keywords: ["close animation", "notch"], highlightID: SettingsTab.appearance.highlightID(for: "Use simpler close animation")),
            SettingsSearchEntry(tab: .appearance, title: "Notch Width", keywords: ["expanded notch", "width", "resize"], highlightID: SettingsTab.appearance.highlightID(for: "Expanded notch width")),
            SettingsSearchEntry(tab: .appearance, title: "Enable colored spectrograms", keywords: ["spectrogram", "audio"], highlightID: SettingsTab.appearance.highlightID(for: "Enable colored spectrograms")),
            SettingsSearchEntry(tab: .appearance, title: "Enable blur effect behind album art", keywords: ["blur", "album art"], highlightID: SettingsTab.appearance.highlightID(for: "Enable blur effect behind album art")),
            SettingsSearchEntry(tab: .appearance, title: "Slider color", keywords: ["slider", "accent"], highlightID: SettingsTab.appearance.highlightID(for: "Slider color")),
            SettingsSearchEntry(tab: .appearance, title: "Idle Animation", keywords: ["face animation", "idle", "cool face"], highlightID: SettingsTab.appearance.highlightID(for: "Idle Animation")),
            SettingsSearchEntry(tab: .appearance, title: "App icon", keywords: ["app icon", "custom icon"], highlightID: SettingsTab.appearance.highlightID(for: "App icon")),
            SettingsSearchEntry(tab: .appearance, title: "Notch fill color", keywords: ["notch color", "background", "fill", "appearance"], highlightID: SettingsTab.appearance.highlightID(for: "Notch fill color")),
            SettingsSearchEntry(tab: .appearance, title: "Notch skin", keywords: ["notch skin", "background", "wallpaper", "custom skin"], highlightID: SettingsTab.appearance.highlightID(for: "Notch skin")),
            SettingsSearchEntry(tab: .appearance, title: "Skin scrim opacity", keywords: ["scrim", "overlay", "darken", "notch skin"], highlightID: SettingsTab.appearance.highlightID(for: "Skin scrim opacity")),
            SettingsSearchEntry(tab: .appearance, title: "Brain appearance", keywords: ["dark mode", "light mode", "moon", "theme", "appearance"], highlightID: SettingsTab.appearance.highlightID(for: "Brain appearance")),

            // Lock Screen
            SettingsSearchEntry(tab: .lockScreen, title: "Preview lock screen widgets", keywords: ["preview", "lock screen", "widgets"], highlightID: SettingsTab.lockScreen.highlightID(for: "Preview lock screen widgets")),
            SettingsSearchEntry(tab: .lockScreen, title: "Enable lock screen live activity", keywords: ["lock screen", "live activity"], highlightID: SettingsTab.lockScreen.highlightID(for: "Enable lock screen live activity")),
            SettingsSearchEntry(tab: .lockScreen, title: "Material", keywords: ["glass", "frosted", "liquid"], highlightID: SettingsTab.lockScreen.highlightID(for: "Material")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen media panel", keywords: ["media panel", "lock screen media"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen media panel")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show media app icon", keywords: ["app icon", "media"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show media app icon")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show panel border", keywords: ["panel border"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show panel border")),
            SettingsSearchEntry(tab: .lockScreen, title: "Enable media panel blur", keywords: ["blur", "media panel"], highlightID: SettingsTab.lockScreen.highlightID(for: "Enable media panel blur")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen timer", keywords: ["timer widget", "lock screen timer"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen timer")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer surface", keywords: ["timer glass", "classic", "blur"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer surface")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer glass material", keywords: ["frosted", "liquid", "timer material"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer glass material")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer liquid mode", keywords: ["timer", "standard", "custom"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer liquid mode")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer widget variant", keywords: ["timer variant", "liquid"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer widget variant")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen weather", keywords: ["weather widget"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen weather")),
            SettingsSearchEntry(tab: .lockScreen, title: "Layout", keywords: ["inline", "circular", "weather layout"], highlightID: SettingsTab.lockScreen.highlightID(for: "Layout")),
            SettingsSearchEntry(tab: .lockScreen, title: "Weather data provider", keywords: ["wttr", "open meteo"], highlightID: SettingsTab.lockScreen.highlightID(for: "Weather data provider")),
            SettingsSearchEntry(tab: .lockScreen, title: "Temperature unit", keywords: ["celsius", "fahrenheit"], highlightID: SettingsTab.lockScreen.highlightID(for: "Temperature unit")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show location label", keywords: ["location", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show location label")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show charging status", keywords: ["charging", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show charging status")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show charging percentage", keywords: ["charging percentage"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show charging percentage")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show battery indicator", keywords: ["battery gauge", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show battery indicator")),
            SettingsSearchEntry(tab: .lockScreen, title: "Use MacBook icon when on battery", keywords: ["laptop icon", "battery"], highlightID: SettingsTab.lockScreen.highlightID(for: "Use MacBook icon when on battery")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show Bluetooth battery", keywords: ["bluetooth", "gauge"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show Bluetooth battery")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show AQI widget", keywords: ["air quality", "aqi"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show AQI widget")),
            SettingsSearchEntry(tab: .lockScreen, title: "Air quality scale", keywords: ["aqi", "scale"], highlightID: SettingsTab.lockScreen.highlightID(for: "Air quality scale")),
            SettingsSearchEntry(tab: .lockScreen, title: "Use colored gauges", keywords: ["gauge tint", "monochrome"], highlightID: SettingsTab.lockScreen.highlightID(for: "Use colored gauges")),

            // Extensions
            SettingsSearchEntry(tab: .extensions, title: "Enable third-party extensions", keywords: ["extensions", "authorization", "third party"], highlightID: SettingsTab.extensions.highlightID(for: "Enable third-party extensions")),
            SettingsSearchEntry(tab: .extensions, title: "Allow extension live activities", keywords: ["extensions", "live activities", "permissions"], highlightID: SettingsTab.extensions.highlightID(for: "Allow extension live activities")),
            SettingsSearchEntry(tab: .extensions, title: "Allow extension lock screen widgets", keywords: ["extensions", "lock screen", "widgets"], highlightID: SettingsTab.extensions.highlightID(for: "Allow extension lock screen widgets")),
            SettingsSearchEntry(tab: .extensions, title: "Enable extension diagnostics logging", keywords: ["extensions", "diagnostics", "logging"], highlightID: SettingsTab.extensions.highlightID(for: "Enable extension diagnostics logging")),
            SettingsSearchEntry(tab: .extensions, title: "Manage app permissions", keywords: ["extensions", "permissions", "apps"], highlightID: SettingsTab.extensions.highlightID(for: "App permissions list")),

            // Shortcuts
            SettingsSearchEntry(tab: .shortcuts, title: "Enable global keyboard shortcuts", keywords: ["keyboard", "shortcut"], highlightID: SettingsTab.shortcuts.highlightID(for: "Enable global keyboard shortcuts")),

            // Notes
            SettingsSearchEntry(tab: .notes, title: "Sync with Apple Notes", keywords: ["apple notes", "notes app", "icloud", "two-way", "sync"], highlightID: SettingsTab.notes.highlightID(for: "Sync with Apple Notes")),
            SettingsSearchEntry(tab: .notes, title: "Notes to sync", keywords: ["kannu folder", "whole account", "all notes", "import", "scope"], highlightID: SettingsTab.notes.highlightID(for: "Sync with Apple Notes")),

            // Timer
            SettingsSearchEntry(tab: .timer, title: "Enable timer feature", keywords: ["timer", "enable"], highlightID: SettingsTab.timer.highlightID(for: "Enable timer feature")),
            SettingsSearchEntry(tab: .timer, title: "Mirror macOS Clock timers", keywords: ["system timer", "clock app"], highlightID: SettingsTab.timer.highlightID(for: "Mirror macOS Clock timers")),
            SettingsSearchEntry(tab: .timer, title: "Show lock screen timer widget", keywords: ["lock screen", "timer widget"], highlightID: SettingsTab.timer.highlightID(for: "Show lock screen timer widget")),
            SettingsSearchEntry(tab: .timer, title: "Timer surface", keywords: ["timer glass", "classic", "blur"], highlightID: SettingsTab.timer.highlightID(for: "Timer surface")),
            SettingsSearchEntry(tab: .timer, title: "Timer glass material", keywords: ["frosted", "liquid", "timer material"], highlightID: SettingsTab.timer.highlightID(for: "Timer glass material")),
            SettingsSearchEntry(tab: .timer, title: "Timer liquid mode", keywords: ["timer", "standard", "custom"], highlightID: SettingsTab.timer.highlightID(for: "Timer liquid mode")),
            SettingsSearchEntry(tab: .timer, title: "Timer widget variant", keywords: ["timer variant", "liquid"], highlightID: SettingsTab.timer.highlightID(for: "Timer widget variant")),
            SettingsSearchEntry(tab: .timer, title: "Timer tint", keywords: ["timer colour", "preset"], highlightID: SettingsTab.timer.highlightID(for: "Timer tint")),
            SettingsSearchEntry(tab: .timer, title: "Solid colour", keywords: ["timer colour", "custom"], highlightID: SettingsTab.timer.highlightID(for: "Solid colour")),
            SettingsSearchEntry(tab: .timer, title: "Progress style", keywords: ["progress", "bar", "ring"], highlightID: SettingsTab.timer.highlightID(for: "Progress style")),
            SettingsSearchEntry(tab: .timer, title: "Timer Presets", keywords: ["preset", "accent colour", "timer"], highlightID: SettingsTab.timer.highlightID(for: "Timer Presets")),

            // Tasks. A source page's rows exist only while it is open, so their entries land on the
            // source's row on the overview, which opens it (the Advanced precedent, docs/SETTINGS.md).
            SettingsSearchEntry(tab: .tasks, title: "Sources", keywords: ["tasks", "sources", "jira", "gitlab", "integrations", "connect", "issues"], highlightID: SettingsDeepLink.tasksSourcesHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Add a source", keywords: ["tasks", "sources", "add", "connect", "integrations", "jira", "gitlab", "github", "linear", "todoist", "reminders"], highlightID: SettingsDeepLink.tasksAddSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "GitHub", keywords: ["github", "github enterprise", "issues", "pull requests", "connect", "personal access token", "integration"], highlightID: SettingsDeepLink.tasksGitHubSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Linear", keywords: ["linear", "issues", "cycles", "api key", "connect", "integration"], highlightID: SettingsDeepLink.tasksLinearSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Todoist", keywords: ["todoist", "tasks", "projects", "filter", "api token", "connect", "integration"], highlightID: SettingsDeepLink.tasksTodoistSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Apple Reminders", keywords: ["reminders", "apple reminders", "lists", "to do", "integration", "connect"], highlightID: SettingsDeepLink.tasksAppleRemindersSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Local tasks", keywords: ["tasks", "local", "my tasks", "own tasks", "add"], highlightID: SettingsDeepLink.tasksSourcesHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Local tasks colour", keywords: ["tasks", "local", "colour", "color", "tint", "glass", "integration"], highlightID: SettingsDeepLink.tasksSourcesHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Jira Cloud", keywords: ["jira", "atlassian", "connect", "disconnect", "api token", "issues", "integration"], highlightID: SettingsDeepLink.tasksJiraSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Sync Jira", keywords: ["jira", "sync", "issues", "fetch", "pause sync"], highlightID: SettingsDeepLink.tasksJiraSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Jira colour", keywords: ["jira", "tasks", "colour", "color", "tint", "glass", "integration"], highlightID: SettingsDeepLink.tasksJiraSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Refresh Jira issues", keywords: ["jira", "refresh", "reload", "synced", "rate limited", "offline"], highlightID: SettingsDeepLink.tasksJiraSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Issue filter (JQL)", keywords: ["jira", "jql", "filter", "query", "advanced", "issues"], highlightID: SettingsDeepLink.tasksJiraSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "GitLab", keywords: ["gitlab", "connect", "disconnect", "personal access token", "self-managed", "issues", "merge requests", "integration"], highlightID: SettingsDeepLink.tasksGitLabSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Sync GitLab", keywords: ["gitlab", "sync", "issues", "fetch", "pause sync"], highlightID: SettingsDeepLink.tasksGitLabSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "GitLab colour", keywords: ["gitlab", "tasks", "colour", "color", "tint", "glass", "integration"], highlightID: SettingsDeepLink.tasksGitLabSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Include merge requests", keywords: ["gitlab", "merge requests", "mr", "review", "reviewer", "pull requests"], highlightID: SettingsDeepLink.tasksGitLabSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Refresh GitLab items", keywords: ["gitlab", "refresh", "reload", "synced", "rate limited", "offline"], highlightID: SettingsDeepLink.tasksGitLabSourceHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Enable tasks", keywords: ["tasks", "todo", "to-do", "estimate", "time tracking", "actual time"], highlightID: SettingsTab.tasks.highlightID(for: "Enable tasks")),
            SettingsSearchEntry(tab: .tasks, title: "Default session length", keywords: ["tasks", "session", "length", "minutes", "pomodoro", "timer"], highlightID: SettingsTab.tasks.highlightID(for: "Default session length")),
            SettingsSearchEntry(tab: .tasks, title: "Sound when the estimate is reached", keywords: ["tasks", "sound", "estimate", "alarm", "chime", "overtime"], highlightID: SettingsTab.tasks.highlightID(for: "Sound when the estimate is reached")),
            SettingsSearchEntry(tab: .tasks, title: "Time to log", keywords: ["tasks", "log time", "log work", "worklog", "time tracking", "spent", "timesheet", "jira", "gitlab"], highlightID: SettingsTab.tasks.highlightID(for: "Time to log")),
            // All tasks' rows, and a task's own page, exist only while open, so their entries land on
            // the overview's All tasks row, which opens it.
            SettingsSearchEntry(tab: .tasks, title: "All tasks", keywords: ["tasks", "task list", "list", "to do", "in progress", "open tasks", "my tasks", "order", "priority", "move to top", "up next", "tracked", "actual time", "start", "time a task"], highlightID: SettingsDeepLink.tasksListHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Find a task", keywords: ["tasks", "find", "search", "look up", "key", "title"], highlightID: SettingsDeepLink.tasksListHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Task filters", keywords: ["tasks", "filter", "source", "project", "status", "to do", "in progress", "local", "jira", "gitlab"], highlightID: SettingsDeepLink.tasksListHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Add a task", keywords: ["tasks", "add", "new task", "todo", "estimate", "tags", "reminder"], highlightID: SettingsDeepLink.tasksListHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Task tags", keywords: ["tasks", "tags", "labels", "hashtag"], highlightID: SettingsDeepLink.tasksListHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Tag colours", keywords: ["tasks", "tags", "colour", "color", "tint", "glass", "labels", "hashtag"], highlightID: SettingsDeepLink.tasksListHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Schedule a task", keywords: ["tasks", "schedule", "reminder", "notification", "remind me", "due"], highlightID: SettingsDeepLink.tasksListHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Recently closed tasks", keywords: ["tasks", "done", "finished", "completed", "closed", "reopen"], highlightID: SettingsDeepLink.tasksListHighlightID),
            SettingsSearchEntry(tab: .tasks, title: "Archived tasks", keywords: ["tasks", "archive", "archived", "hidden", "restore", "delete", "clear"], highlightID: SettingsDeepLink.tasksListHighlightID),

            // Stats
            SettingsSearchEntry(tab: .stats, title: "Enable system stats monitoring", keywords: ["stats", "monitoring"], highlightID: SettingsTab.stats.highlightID(for: "Enable system stats monitoring")),
            SettingsSearchEntry(tab: .llmUsage, title: "Enable LLM Usage Monitor", keywords: ["llm", "usage", "ai", "monitor"], highlightID: SettingsTab.llmUsage.highlightID(for: "Enable LLM Usage Monitor")),
            SettingsSearchEntry(tab: .llmUsage, title: "Claude Provider", keywords: ["llm", "claude", "provider", "toggle", "usage", "rate", "limit", "quota", "5h", "7d", "weekly", "session"], highlightID: SettingsTab.llmUsage.highlightID(for: "Claude Provider")),
            SettingsSearchEntry(tab: .llmUsage, title: "Codex Provider", keywords: ["llm", "codex", "provider", "toggle"], highlightID: SettingsTab.llmUsage.highlightID(for: "Codex Provider")),
            SettingsSearchEntry(tab: .llmUsage, title: "Cursor Provider", keywords: ["llm", "cursor", "provider", "toggle"], highlightID: SettingsTab.llmUsage.highlightID(for: "Cursor Provider")),
            SettingsSearchEntry(tab: .llmUsage, title: "Check Codex and Cursor limits in the background", keywords: ["usage", "background", "codex", "cursor", "quota", "limit"], highlightID: SettingsTab.llmUsage.highlightID(for: "Check Codex and Cursor limits in the background")),
            SettingsSearchEntry(tab: .agentStatus, title: "Remind me when an agent is still waiting", keywords: ["remind", "reminder", "waiting", "yellow", "push", "approval", "nudge"], highlightID: SettingsTab.agentStatus.highlightID(for: "Remind me when an agent is still waiting")),
            SettingsSearchEntry(tab: .agentStatus, title: "Open the exact terminal tab", keywords: ["terminal", "iterm", "tmux", "tab", "click", "open", "pane"], highlightID: SettingsTab.agentStatus.highlightID(for: "Open the exact terminal tab")),
            SettingsSearchEntry(tab: .agentStatus, title: "Push when a usage limit is almost reached", keywords: ["push", "usage", "limit", "quota", "mobile", "ntfy", "pushover", "webhook"], highlightID: SettingsTab.agentStatus.highlightID(for: "Push when a usage limit is almost reached")),
            SettingsSearchEntry(tab: .llmUsage, title: "Antigravity Provider", keywords: ["antigravity", "gemini", "provider", "usage", "sessions"], highlightID: SettingsTab.llmUsage.highlightID(for: "Antigravity Provider")),
            SettingsSearchEntry(tab: .stats, title: "Stop monitoring after closing the notch", keywords: ["stats", "auto stop"], highlightID: SettingsTab.stats.highlightID(for: "Stop monitoring after closing the notch")),
            SettingsSearchEntry(tab: .stats, title: "CPU Usage", keywords: ["cpu", "graph"], highlightID: SettingsTab.stats.highlightID(for: "CPU Usage")),
            SettingsSearchEntry(tab: .stats, title: "Temperature unit", keywords: ["cpu", "temperature", "celsius", "fahrenheit"], highlightID: SettingsTab.stats.highlightID(for: "Temperature unit")),
            SettingsSearchEntry(tab: .stats, title: "Memory Usage", keywords: ["memory", "ram"], highlightID: SettingsTab.stats.highlightID(for: "Memory Usage")),
            SettingsSearchEntry(tab: .stats, title: "GPU Usage", keywords: ["gpu", "graphics"], highlightID: SettingsTab.stats.highlightID(for: "GPU Usage")),
            SettingsSearchEntry(tab: .stats, title: "Network Activity", keywords: ["network", "graph"], highlightID: SettingsTab.stats.highlightID(for: "Network Activity")),
            SettingsSearchEntry(tab: .stats, title: "Disk I/O", keywords: ["disk", "io"], highlightID: SettingsTab.stats.highlightID(for: "Disk I/O")),

            // Clipboard
            SettingsSearchEntry(tab: .clipboard, title: "Enable Clipboard Manager", keywords: ["clipboard", "manager"], highlightID: SettingsTab.clipboard.highlightID(for: "Enable Clipboard Manager")),
            SettingsSearchEntry(tab: .clipboard, title: "Show Clipboard Icon", keywords: ["icon", "clipboard"], highlightID: SettingsTab.clipboard.highlightID(for: "Show Clipboard Icon")),
            SettingsSearchEntry(tab: .clipboard, title: "Display Mode", keywords: ["list", "grid", "clipboard"], highlightID: SettingsTab.clipboard.highlightID(for: "Display Mode")),
            SettingsSearchEntry(tab: .clipboard, title: "History Size", keywords: ["history", "clipboard"], highlightID: SettingsTab.clipboard.highlightID(for: "History Size")),

            // Screen Assistant
            SettingsSearchEntry(tab: .screenAssistant, title: "Enable Screen Assistant", keywords: ["screen assistant", "ai"], highlightID: SettingsTab.screenAssistant.highlightID(for: "Enable Screen Assistant")),
            SettingsSearchEntry(tab: .screenAssistant, title: "Display Mode", keywords: ["screen assistant", "mode"], highlightID: SettingsTab.screenAssistant.highlightID(for: "Display Mode")),

            // Agent Status
            SettingsSearchEntry(tab: .agentStatus, title: "Enable Agent Monitoring", keywords: ["agent", "cursor", "claude", "codex", "status", "traffic", "light", "ai", "notch", "monitoring"], highlightID: SettingsTab.agentStatus.highlightID(for: "Enable Agent Monitoring")),
            SettingsSearchEntry(tab: .agentStatus, title: "Smart caffeinate", keywords: ["caffeinate", "awake", "sleep", "smart", "coffee", "keep awake", "assertion", "insomnia"], highlightID: SettingsDeepLink.smartCaffeinateHighlightID),
            SettingsSearchEntry(tab: .agentStatus, title: "Traffic light style", keywords: ["traffic", "light", "style", "classic", "minimal", "dots", "notch", "agent", "indicator"], highlightID: SettingsTab.agentStatus.highlightID(for: "Traffic light style")),
            SettingsSearchEntry(tab: .agentStatus, title: "Active color", keywords: ["active", "green", "color", "traffic", "light", "palette", "agent"], highlightID: SettingsTab.agentStatus.highlightID(for: "Active color")),
            SettingsSearchEntry(tab: .agentStatus, title: "Awaiting input color", keywords: ["awaiting", "yellow", "color", "traffic", "light", "palette", "agent"], highlightID: SettingsTab.agentStatus.highlightID(for: "Awaiting input color")),
            SettingsSearchEntry(tab: .agentStatus, title: "Stopped color", keywords: ["stopped", "red", "color", "traffic", "light", "palette", "agent"], highlightID: SettingsTab.agentStatus.highlightID(for: "Stopped color")),
            SettingsSearchEntry(tab: .agentStatus, title: "Show a red light when no agents are running", keywords: ["red", "light", "idle", "no agents", "stopped", "indicator", "always"], highlightID: SettingsTab.agentStatus.highlightID(for: "Show a red light when no agents are running")),
            SettingsSearchEntry(tab: .agentStatus, title: "Reset traffic light colors", keywords: ["reset", "color", "traffic", "light", "default"], highlightID: SettingsTab.agentStatus.highlightID(for: "Reset traffic light colors")),
            SettingsSearchEntry(tab: .agentStatus, title: "Editor Hooks", keywords: ["agent", "cursor", "vscode", "copilot", "copilot cli", "codex", "claude", "antigravity", "gemini", "gemini cli", "qwen", "opencode", "plugin", "hook", "install", "integration"], highlightID: SettingsTab.agentStatus.highlightID(for: "Cursor Hook")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Connect ADR", keywords: ["adr", "uber", "security", "discovery", "sensor", "connect", "install", "uv", "pipx"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Connect ADR")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Security findings", keywords: ["security", "agent security", "finding", "mcp", "unpinned", "plaintext", "undeclared", "acknowledge", "snooze", "shield"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Security findings")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Snapshot folder", keywords: ["snapshot", "folder", "directory", "adr", "discovery", "output"], highlightID: SettingsTab.agentSecurity.highlightID(for: "ADR advanced")),
            SettingsSearchEntry(tab: .agentSecurity, title: "ADR tools folder", keywords: ["adr", "tools", "folder", "path", "uv", "pipx", "sensor", "discovery", "install", "not found"], highlightID: SettingsTab.agentSecurity.highlightID(for: "ADR advanced")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Let Kannu run scans", keywords: ["scan", "adr", "discovery", "automatic", "daily", "schedule"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Let Kannu run scans")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Scan now", keywords: ["scan", "adr", "discovery", "run", "now"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Scan now")),
            SettingsSearchEntry(tab: .agentSecurity, title: "ADR scan policy", keywords: ["policy", "tenant", "domains", "approved", "forbidden", "adr", "file", "draft", "prompt"], highlightID: SettingsTab.agentSecurity.highlightID(for: "ADR advanced")),
            SettingsSearchEntry(tab: .agentSecurity, title: "High-severity alerts in the notch", keywords: ["alert", "notch", "pill", "shield", "security", "high", "acknowledge", "glyph"], highlightID: SettingsTab.agentSecurity.highlightID(for: "High-severity alerts in the notch")),
            SettingsSearchEntry(tab: .agentStatus, title: "Push high security findings", keywords: ["push", "security", "finding", "high", "mobile", "ntfy", "pushover", "webhook"], highlightID: SettingsTab.agentStatus.highlightID(for: "Push high security findings")),
            SettingsSearchEntry(tab: .agentStatus, title: "Push medium security findings", keywords: ["push", "security", "finding", "medium", "mobile"], highlightID: SettingsTab.agentStatus.highlightID(for: "Push medium security findings")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Look for hidden text in what agents read", keywords: ["hidden", "invisible", "unicode", "tag", "ascii smuggling", "zero-width", "bidi", "trojan source", "variation selector", "prompt injection"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Look for hidden text in what agents read")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Look for secrets in prompts and tool calls", keywords: ["secret", "api key", "token", "private key", "leak", "credential", "aws", "github"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Look for secrets in prompts and tool calls")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Watch for agents touching sensitive files", keywords: ["sensitive", "ssh", "keychain", "credentials", "env", "launch agent", "zshrc", "browser", "password", "history"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Watch for agents touching sensitive files")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Notice new MCP servers", keywords: ["mcp", "server", "new", "added", "config", "supply chain", "tool"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Notice new MCP servers")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Policy rules", keywords: ["policy", "agent policy", "block", "ssh", "forbid", "deny", "command", "tool", "rules", "json", "edit", "editor", "modify", "add rule", "remove rule"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Policy rules")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Get a policy", keywords: ["policy", "import", "draft", "prompt", "upload", "copy", "agent policy"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Get a policy")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Block matching tool calls", keywords: ["policy", "block", "deny", "enforce", "refuse", "ssh", "claude", "cursor", "antigravity"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Block matching tool calls")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Tell the agent when hidden text is found", keywords: ["hidden", "invisible", "unicode", "agent", "warn", "context", "note"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Tell the agent when hidden text is found")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Analyze chats with ADR Detection", keywords: ["adr", "detection", "analyze", "analysis", "session", "transcript", "malicious", "prompt injection"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Analyze chats with ADR Detection")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Detection checkout", keywords: ["adr", "detection", "checkout", "uv", "clone"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Detection checkout")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Reasoning model", keywords: ["adr", "detection", "model", "claude", "sonnet"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Reasoning model")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Use an Anthropic API key", keywords: ["adr", "detection", "anthropic", "api key", "quota"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Use an Anthropic API key")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Triage with OpenAI first", keywords: ["adr", "detection", "openai", "triage", "gpt"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Triage with OpenAI first")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Messages sent", keywords: ["adr", "detection", "messages", "cap", "transcript"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Messages sent")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Transcript budget", keywords: ["adr", "detection", "budget", "characters", "size", "truncate", "trim", "tokens"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Transcript budget")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Context servers", keywords: ["adr", "detection", "context", "mcp", "threat intelligence", "source code", "policy store"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Context servers")),
            SettingsSearchEntry(tab: .agentSecurity, title: "Confirm before every analysis", keywords: ["adr", "detection", "confirm", "consent"], highlightID: SettingsTab.agentSecurity.highlightID(for: "Confirm before every analysis")),
            SettingsSearchEntry(tab: .agentStatus, title: "Mobile notifications", keywords: ["mobile", "push", "ntfy", "pushover", "webhook", "iphone", "android"], highlightID: SettingsTab.agentStatus.highlightID(for: "Mobile notifications")),
            SettingsSearchEntry(tab: .agentStatus, title: "Send test notification", keywords: ["test", "mobile", "push", "notification"], highlightID: SettingsTab.agentStatus.highlightID(for: "Send test notification")),
            SettingsSearchEntry(tab: .about, title: "Watch for freezes", keywords: ["freeze", "frozen", "hang", "stuck", "unresponsive", "beachball", "spinning", "crash", "report", "diagnostics", "developer"], highlightID: SettingsTab.about.highlightID(for: "Watch for freezes")),
            SettingsSearchEntry(tab: .about, title: "Terms of Use", keywords: ["terms", "legal", "agreement", "warranty", "liability", "accept"], highlightID: SettingsTab.about.highlightID(for: "Terms of Use")),
            SettingsSearchEntry(tab: .about, title: "License", keywords: ["license", "licence", "gpl", "legal", "warranty", "acknowledgements", "notice"], highlightID: SettingsTab.about.highlightID(for: "License")),
            SettingsSearchEntry(tab: .about, title: "Report a Problem", keywords: ["report", "problem", "bug", "crash", "issue", "github", "feedback", "diagnostics"], highlightID: SettingsTab.about.highlightID(for: "Report a Problem")),
            SettingsSearchEntry(tab: .about, title: "Copy Latest Report", keywords: ["copy", "crash", "report", "diagnostics", "clipboard", "paste", "log"], highlightID: SettingsTab.about.highlightID(for: "Copy Latest Report")),
        ]
    }

    @ViewBuilder
    private func detailView(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            SettingsForm(tab: .general) {
                GeneralSettings()
            }
        case .liveActivities:
            SettingsForm(tab: .liveActivities) {
                LiveActivitiesSettings()
            }
        case .appearance:
            SettingsForm(tab: .appearance) {
                Appearance()
            }
        case .lockScreen:
            SettingsForm(tab: .lockScreen) {
                LockScreenSettings()
            }
        case .media:
            SettingsForm(tab: .media) {
                Media()
            }
        case .devices:
            SettingsForm(tab: .devices) {
                DevicesSettingsView()
            }
        case .extensions:
            SettingsForm(tab: .extensions) {
                ExtensionsSettingsView()
            }
        case .timer:
            SettingsForm(tab: .timer, actions: AnyView(TimerHeaderActions())) {
                TimerSettings()
            }
        case .hudAndOSD:
            SettingsForm(tab: .hudAndOSD) {
                HUDAndOSDSettingsView()
            }
        case .battery:
            SettingsForm(tab: .battery) {
                Charge()
            }
        case .stats:
            SettingsForm(tab: .stats) {
                StatsSettings()
            }
        case .clipboard:
            SettingsForm(tab: .clipboard, actions: AnyView(ClipboardHeaderActions())) {
                ClipboardSettings()
            }
        case .screenAssistant:
            SettingsForm(tab: .screenAssistant) {
                ScreenAssistantSettings()
            }
        case .agentStatus:
            SettingsForm(tab: .agentStatus, actions: AnyView(AgentsHeaderActions())) {
                AgentStatusSettings()
            }
        case .agentSecurity:
            SettingsForm(tab: .agentSecurity, actions: AnyView(SecurityHeaderActions())) {
                AgentSecuritySettings()
            }
        case .downloads:
            SettingsForm(tab: .downloads) {
                Downloads()
            }
        case .shelf:
            SettingsForm(tab: .shelf) {
                Shelf()
            }
        case .shortcuts:
            SettingsForm(tab: .shortcuts) {
                Shortcuts()
            }
        case .notes:
            SettingsForm(tab: .notes) {
                NotesSettingsView()
            }
        case .tasks:
            SettingsForm(tab: .tasks) {
                TasksSettings()
            }
        case .llmUsage:
            SettingsForm(tab: .llmUsage, actions: AnyView(UsageHeaderActions())) {
                UsageSettings()
            }
        case .about:
            SettingsForm(tab: .about) {
                About()
            }
        }
    }
}

#if DEBUG
extension SettingsView {
    /// DEBUG snapshot harness: each tab exactly as the window builds it (`detailView(for:)`).
    static func snapshotTabs(filter: Set<String>?) -> [(String, AnyView)] {
        SettingsTab.allCases
            .filter { filter?.contains($0.rawValue) ?? true }
            .map { tab in (tab.rawValue, AnyView(SettingsView().detailView(for: tab))) }
    }
}

extension SettingsView {
    /// DEBUG snapshot harness: the whole window on a given tab, with a query typed if there is one.
    init(snapshotTab: SettingsTab, search: String = "", showsSuggestions: Bool = false, hidesSidebar: Bool = false) {
        self.init()
        _selectedTab = State(initialValue: snapshotTab)
        _searchText = State(initialValue: search)
        snapshotShowsSuggestions = showsSuggestions
        snapshotHidesSidebar = hidesSidebar
    }
}

extension SettingsView {
    /// DEBUG snapshot harness: Brain › Tasks' All tasks under its large title, as the window builds it.
    /// `SettingsForm` is private to this file.
    static func snapshotPageTitle(_ page: some View) -> AnyView {
        AnyView(SettingsForm(tab: .tasks) { page.settingsPageTitle(TasksSettings.title(of: .allTasks)) })
    }

    /// DEBUG snapshot harness: the shortcut recorder rows, shown only once global shortcuts are on.
    static func snapshotShortcutRows() -> AnyView {
        AnyView(SettingsPage { Shortcuts().shortcutsSection })
    }

    /// DEBUG snapshot harness: the Controls tab's Custom OSD, Vertical Bar and Circular sections, which
    /// show only when that style's card is selected (the harness must not change the user's choice).
    static func snapshotControlsStyles() -> AnyView {
        let controls = HUDAndOSDSettingsView()
        return AnyView(SettingsPage {
            if #available(macOS 15.0, *) {
                CustomOSDSettings()
            }
            controls.verticalHUDSections
            controls.circularHUDSections
        })
    }
}
#endif
