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

/// Brain › Tasks' product, above its settings (docs/SETTINGS.md, "Product pages"): what needs you first, a session
/// Kannu stopped while timing and time waiting to be logged, then the list. The list shows the open tasks, the ones
/// closed lately or the archive (Active, Done, Archived), narrowed by Find, where `#tag` finds a tag (`TaskSearch`),
/// and by the Tag filter; each task is a soft card with its tags, and the open ones carry ✓ and ▶.
///
/// Nothing here observes `TasksManager`. `TasksSettings` copies what the first page shows into one value,
/// `TasksPageData`, at most twice a second while Brain is on screen, and hands it down; off screen the copy stays as it
/// was (docs/SETTINGS.md, "Live data"). A press calls the manager, then the page reads it again at once
/// (`TasksPageContext.refresh`). One part follows the manager itself: Time to log's cards are the notch popover's own
/// (`WorklogDraftCard`), and they are built only while an entry waits, which the copy says.
struct TasksOverview: View {
    let data: TasksPageData
    @Binding var tab: TasksListTab
    @Binding var query: String
    /// The task whose page shows beside the list, drawn selected; nil while a task's page takes the list's place.
    let selected: UUID?
    /// Brain is on screen: only then does the timed row keep its minute clock.
    let live: Bool
    let context: TasksPageContext
    @Default(.enableTasks) private var enabled
    @Default(.enableTimerFeature) private var timerOn
    @Default(.tasksListTagFilter) private var tagFilter

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
            if !enabled {
                // Nothing is listed while it is off, and the tab never builds the task list then.
                SettingsSection {
                    TasksMessage(title: String(localized: "Tasks is off"), message: nil) {
                        Button("Turn On") { enabled = true }
                    }
                }
            } else {
                interruptedSection
                if data.openDraftCount > 0 {
                    TimeToLogSection()
                }
                list
            }
        }
    }

    // MARK: - The list

    /// The list's own filter: Find and the Tag filter. Never the Source, Project or Status filter: a source and a
    /// project have their own pages, and the tabs split what is open from what is closed.
    private var filter: TaskFilter {
        TaskFilter(tag: tagFilter, query: query)
    }

    private var list: some View {
        let filter = filter
        let base = data.tasks(on: tab)
        let shown = base.filter { TaskFacets.matches($0, filter: filter) }
        return VStack(alignment: .leading, spacing: SettingsTheme.listRowGap) {
            controls
            notes
            // Above the rows, so a narrowed list never passes for the whole one: the list's one count.
            if filter.isNarrowing {
                SettingsSection {
                    SettingsActionRow("Filtered", description: String(localized: "\(shown.count) of \(base.count) tasks")) {
                        Button("Show All", action: showAll)
                    }
                }
            }
            if shown.isEmpty {
                emptyState(narrowed: filter.isNarrowing)
            } else {
                rows(shown)
            }
            // As a section draws its footer: secondary, in line with the rows' text.
            footer
                .foregroundStyle(SettingsTheme.inkSecondary)
                .padding(.horizontal, SettingsTheme.sectionPadding.leading)
        }
        .accessibilityElement(children: .contain)
    }

    /// The three tabs, then Find and the Tag filter. The tabs' row takes the list's deep link (the notch's "Show all in
    /// Brain" and a reminder's click), Find's row the list's search entries.
    private var controls: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.sectionLabelGap) {
            SettingsSelect("Tasks", selection: $tab, options: TasksListTab.allCases, optionTitle: \.title, style: .segmented)
                .settingsHighlight(id: SettingsDeepLink.tasksListOpenID)
            HStack(spacing: SettingsMetrics.rowContent) {
                TextField("Find", text: $query, prompt: Text("Title, key or #tag"))
                    .settingsField()
                SettingsSelect("Tag", selection: $tagFilter, options: tagChoices, optionTitle: Self.tagTitle)
            }
            .settingsHighlight(id: SettingsDeepLink.tasksListHighlightID)
        }
    }

    /// Every tag and label on any task Kannu holds, not what the list shows, so a choice never vanishes from its own
    /// list; a saved choice no task has any more still shows, so the button is never blank.
    private var tagChoices: [String] {
        var choices = [TaskFacets.anyTag] + data.filterTags.map { $0.lowercased() == tagFilter.lowercased() ? tagFilter : $0 }
        if tagFilter != TaskFacets.anyTag, !choices.contains(where: { $0.lowercased() == tagFilter.lowercased() }) {
            choices.append(tagFilter)
        }
        return choices
    }

    private static func tagTitle(_ tag: String) -> String {
        tag == TaskFacets.anyTag ? String(localized: "All tags") : "#\(tag)"
    }

    /// Show All: the Tag filter back to All and Find emptied, so the tab shows every task it holds.
    private func showAll() {
        tagFilter = TaskFacets.anyTag
        query = ""
    }

    /// What stops the list working as it should, each a row of one card above it, and only while it is true.
    @ViewBuilder
    private var notes: some View {
        let timingOff = tab == .active && !timerOn
        if data.loadFailure != nil || data.movedAsideFileName != nil || timingOff || data.remindersBlocked {
            SettingsSection {
                if let reason = data.loadFailure {
                    SettingsErrorText(String(localized: "Couldn't read the task list, so it can't change. \(reason)"))
                }
                if let name = data.movedAsideFileName {
                    SettingsNoteRow(
                        "A new task list was started",
                        description: String(localized: "The old file couldn't be read; it's kept as \(name)."),
                        tint: .orange
                    )
                }
                if timingOff {
                    SettingsNoteRow("Timing is off", description: "Turn on the timer in the Timer tab.")
                }
                if data.remindersBlocked {
                    SettingsActionRow("Notifications are off", description: "Reminders need notifications for Kannu.") {
                        Button(openNotificationSettingsTitle) { TaskReminders.openNotificationSettings() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rows(_ shown: [TaskItem]) -> some View {
        switch tab {
        case .active:
            TaskRowCards(
                rows: TaskListRows(shown, tagColors: data.tagColors, integrationColors: data.integrationColors,
                                   topTaskID: data.active.first?.id, timedTaskID: data.timing?.taskID,
                                   timingIsPaused: data.timing?.isPaused ?? false),
                tagColors: data.tagColors, doneTicks: data.doneTicks, isReady: data.isReady,
                canStart: timerOn && data.isReady, query: query, selected: selected, live: live, context: context
            )
        case .done, .archived:
            // Lazy, as the open rows: the archive only grows (docs/SETTINGS.md, "Pages and sections").
            LazyVStack(alignment: .leading, spacing: SettingsTheme.listRowGap) {
                ForEach(shown) { task in
                    TaskClosedCard(task: task, holdsTimeToLog: data.holdsTimeToLog.contains(task.id),
                                   isSelected: selected == task.id, context: context)
                        .id(task.id)
                }
            }
        }
    }

    /// The rows' place when the tab has nothing to list: what is empty, in one line, and on Active the page's verb.
    @ViewBuilder
    private func emptyState(narrowed: Bool) -> some View {
        if narrowed {
            SettingsSection {
                SettingsNoteRow("No tasks match", description: "Change the filters or Find, or show all tasks.")
            }
        } else if data.isReady {
            switch tab {
            case .active:
                SettingsSection {
                    TasksMessage(title: String(localized: "No open tasks"),
                                 message: String(localized: "Add one, or connect a source below.")) {
                        // The header's verb in the standard style, as Security's empty state draws its own.
                        Button("New task") { TasksHeaderActions.requestNewTask() }
                    }
                }
            case .done:
                SettingsSection {
                    SettingsNoteRow("Nothing closed lately", description: "Tasks you mark done, and tickets closed in Jira or GitLab, appear here.")
                }
            case .archived:
                SettingsSection {
                    SettingsNoteRow("The archive is empty", description: "Archived tasks keep their time here.")
                }
            }
        }
    }

    /// One line under the list: the rows' menu, otherwise unseen, or what becomes of a closed task.
    @ViewBuilder
    private var footer: some View {
        switch tab {
        case .active:
            SettingsFooter("Right-click a task for more, such as Move to Top.")
        case .done:
            SettingsFooter("Moved to the archive after \(TaskArchive.closedDays) days.")
        case .archived:
            SettingsFooter("Jira and GitLab tasks clear after \(TaskArchive.clearDays) days; yours stay.")
        }
    }

    // MARK: - Interrupted sessions

    /// Segments Kannu left open by a quit or a crash: an end time to set, or the session to discard.
    @ViewBuilder
    private var interruptedSection: some View {
        let interrupted = data.interrupted
        if !interrupted.isEmpty {
            SettingsSection {
                ForEach(interrupted) { entry in
                    LabeledContent {
                        HStack(spacing: SettingsMetrics.rowContent) {
                            Button("Set End Time") {
                                context.sheet.wrappedValue = .endTime(
                                    taskID: entry.task.id,
                                    segmentID: entry.segment.id,
                                    title: entry.task.title,
                                    start: entry.segment.start,
                                    nextSessionStart: entry.nextSessionStart
                                )
                            }
                            Button("Discard") {
                                TasksManager.shared.discardInterruptedSession(segmentID: entry.segment.id, taskID: entry.task.id)
                                context.refresh()
                            }
                        }
                    } label: {
                        SettingsRowLabel(
                            Text(verbatim: entry.task.title),
                            description: Text(verbatim: String(localized: "Timing since \(entry.segment.start.formatted(date: .abbreviated, time: .shortened))"))
                        )
                    }
                }
            } header: {
                SettingsSectionHeader("Interrupted sessions")
            } footer: {
                SettingsFooter("Kannu stopped while timing these. Set an end time or discard.")
            }
        }
    }
}

/// Which of its tasks Brain › Tasks' list shows. Not saved: like Find, it is the page's own state, kept while Brain is.
enum TasksListTab: String, CaseIterable, Identifiable {
    case active
    case done
    case archived

    var id: String { rawValue }

    /// Keys of their own, with the English as their value, as Stats' "Active" has: "Done" is also a sheet's button,
    /// which several languages say otherwise ("Fertig" on the button, "Erledigt" here).
    var title: String {
        switch self {
        case .active: return String(localized: "tasks_tab_active", defaultValue: "Active")
        case .done: return String(localized: "tasks_tab_done", defaultValue: "Done")
        case .archived: return String(localized: "tasks_tab_archived", defaultValue: "Archived")
        }
    }
}

// MARK: - The header

/// Tasks' header actions (docs/SETTINGS.md, "Product pages"): the gear, which goes to the first settings row, then
/// the page's one primary verb, New task, ⌘N, while tasks are on. Its press asks the page, which holds New Task's
/// sheet, its draft and the path, to open it: the header and the page are siblings under `SettingsForm`, and the
/// root may hold no state of its own.
struct TasksHeaderActions: View {
    @ObservedObject private var visibility = BrainVisibility.shared
    @Default(.enableTasks) private var enabled
    /// Whether the task list has been read, followed only while Brain is on screen.
    @State private var ready = false

    /// New Task, from the header or the empty list. `TasksSettings` answers it.
    static func requestNewTask() {
        NotificationCenter.default.post(name: .tasksNewTaskRequested, object: nil)
    }

    var body: some View {
        HStack(spacing: SettingsMetrics.rowContent) {
            Button {
                // The first settings row, which is always built.
                SettingsHighlightCoordinator.shared.requestAgentStatusNavigation(highlightID: SettingsDeepLink.tasksEnableHighlightID)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(SettingsButtonStyle(.quiet))
            .help(String(localized: "Tasks settings"))
            .accessibilityLabel(String(localized: "Tasks settings"))
            if enabled {
                Button("New task") { Self.requestNewTask() }
                    .buttonStyle(SettingsButtonStyle(.primary))
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!ready)
            }
        }
        // One read as it appears, so a board and a first open draw the verb as it is; the subscription takes over once
        // Brain is on screen. Never with tasks off: that would build the task list.
        .onAppear {
            if enabled { ready = TasksManager.shared.isReady }
        }
        // One value, passed on only when it changes; `$loadState` sends the current one as it subscribes.
        .task(id: visibility.isOnScreen && enabled) {
            guard visibility.isOnScreen && enabled else { return }
            for await isReady in TasksManager.shared.$loadState.map({ $0 == .ready }).removeDuplicates().values {
                ready = isReady
            }
        }
    }
}

extension Notification.Name {
    /// The Tasks header's New task, and the empty list's: `TasksSettings` opens New Task.
    static let tasksNewTaskRequested = Notification.Name("TasksNewTaskRequested")
}

// MARK: - A closed task, and the card in the rows' place

/// A task on Done or Archived: its title over its key, where it stands and what becomes of it, then its one action
/// (Reopen, Archive or Restore) and a › to its page; the rest is in its right-click menu, which opens with Show
/// Details, as the open rows' does (docs/SETTINGS.md, "Section rules").
private struct TaskClosedCard: View {
    let task: TaskItem
    /// An archived Jira or GitLab task kept until its time is logged.
    let holdsTimeToLog: Bool
    let isSelected: Bool
    let context: TasksPageContext

    var body: some View {
        LabeledContent {
            HStack(spacing: SettingsMetrics.rowContent) {
                switch task.visibility {
                case .done:
                    Button("Reopen") { press { $0.reopen(task.id) } }
                case .gone:
                    // A task its source no longer lists comes back only with the source: it can be archived now.
                    Button("Archive") { press { $0.archive(task.id) } }
                case .archived, .active:
                    Button("Restore") { press { $0.reopen(task.id) } }
                }
                Button {
                    context.open(.task(task.id))
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(SettingsButtonStyle(.quiet))
                .accessibilityLabel("Show Details")
            }
        } label: {
            SettingsRowLabel(Text(verbatim: task.title), description: Text(verbatim: line))
                .lineLimit(2)
        }
        .taskCard(selected: isSelected, label: task.title)
        .contextMenu {
            Button("Show Details") { context.open(.task(task.id)) }
            Divider()
            if task.visibility == .done {
                Button("Archive") { press { $0.archive(task.id) } }
            }
            if task.source == .local {
                Button("Delete", role: .destructive) { context.pendingDelete.wrappedValue = task }
            } else if let link = taskOpenLink(for: task, manager: TasksManager.shared) {
                Button(link.title) { NSWorkspace.shared.open(link.url) }
            }
        }
    }

    /// "PROJ-123 · Done · 2h recorded · archives in 3d", read as the page draws, with no clock.
    private var line: String {
        let now = Date()
        let tracked = WorkDuration.format(TaskTimeMath.trackedSeconds(task.segments, now: now))
        var parts = [TaskDetailSummary.shortKey(for: task)]
        switch task.visibility {
        case .done, .gone:
            parts.append(task.visibility == .done
                ? String(localized: "Done · \(tracked) recorded")
                : String(localized: "No longer listed by its source · \(tracked) recorded"))
            let days = TaskArchive.daysUntilArchive(task, now: now) ?? TaskArchive.closedDays
            parts.append(days == 0 ? String(localized: "archiving now") : String(localized: "archives in \(days)d"))
        case .archived, .active:
            if task.source == .local {
                parts.append(String(localized: "Archived · \(tracked) recorded"))
            } else if holdsTimeToLog {
                parts.append(String(localized: "Archived · kept until its time is logged"))
            } else if let days = TaskArchive.daysUntilClear(task, now: now) {
                parts.append(days == 0 ? String(localized: "Archived · clearing now") : String(localized: "Archived · clears in \(days)d"))
            } else {
                // Still open on its server: clearing it would only bring it back as new.
                parts.append(String(localized: "Archived · kept while still open in its source"))
            }
        }
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// A press calls the manager, then the page reads it again at once, so a second click never waits for the copy.
    private func press(_ action: (TasksManager) -> Void) {
        action(TasksManager.shared)
        context.refresh()
    }
}

/// The rows' place when there is nothing to list, the page's while tasks are off, and a task's place beside the list
/// before one is open: the status, at most one line that teaches, and at most one action (docs/SETTINGS.md, "Product
/// pages"). It sits in a section's card, whose padding is the hero's, so it is as tall as the hero less that padding.
struct TasksMessage<Action: View>: View {
    let title: String
    let message: String?
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: SettingsMetrics.cardPadding) {
            Image(systemName: SettingsTab.tasks.systemImage)
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

/// What Brain › Tasks' first page shows from `TasksManager`, copied in one value, so one throttled subscription carries
/// it and the page redraws only when it changed (docs/SETTINGS.md, "Live data"). The list, what needs you above it and
/// the settings below all read it; nothing on the first page reads the manager's state another way, but Time to log's
/// cards (`TasksOverview`).
struct TasksPageData: Equatable {
    /// Every task Kannu holds, in the user's order.
    var tasks: [TaskItem] = []
    /// What each tab starts from: the open tasks of every connected source in the task order (`activeTasks`), the ones
    /// closed lately and the archive.
    var active: [TaskItem] = []
    var closed: [TaskItem] = []
    var archived: [TaskItem] = []
    var tagColors: [String: TaskColor] = [:]
    var integrationColors: [TaskSource: TaskColor] = [:]
    var timing: TasksManager.Timing?
    var doneTicks = TaskDoneTicks()
    var isReady = false
    /// Why the task file could not be read; nil while it reads or once it has.
    var loadFailure: String?
    var movedAsideFileName: String?
    var remindersBlocked = false
    /// The archived tasks kept until their time is logged (`TaskArchive.holdsTimeToLog`).
    var holdsTimeToLog: Set<UUID> = []
    /// How many Time to log entries wait.
    var openDraftCount = 0
    /// Every source in the manager's order, where each one's sync stands, and those whose token could not be removed.
    var sources: [TaskSource] = []
    var syncStates: [TaskSource: SourceSyncState] = [:]
    var tokenRemovalFailed: Set<TaskSource> = []
    /// The connected sources, what each one's row says and which sync: the Defaults display copies, read with the rest.
    /// A change there publishes through the manager, and the page redraws only when the copy changed, so they are in it.
    var connected: [TaskSource] = []
    var sourceStatus: [TaskSource: String] = [:]
    var syncOn: Set<TaskSource> = []
    /// What the page works out from every task, here once a copy rather than in `body` once a keystroke in Find: the
    /// interrupted sessions, the Tag filter's choices (tags and labels), Tag colours' tags (the user's own) and each
    /// source's open count.
    var interrupted: [TasksManager.InterruptedSession] = []
    var filterTags: [String] = []
    var ownTags: [String] = []
    var sourceCounts: [TaskSource: Int] = [:]

    init() {}

    /// The manager as it is now.
    @MainActor
    init(_ manager: TasksManager) {
        tasks = manager.tasks
        active = manager.activeTasks
        closed = manager.recentlyClosedTasks
        archived = manager.archivedTasks
        tagColors = manager.tagColors
        integrationColors = manager.integrationColors
        timing = manager.timing
        doneTicks = manager.doneTicks
        isReady = manager.isReady
        if case .failed(let reason) = manager.loadState { loadFailure = reason }
        movedAsideFileName = manager.movedAsideFileName
        remindersBlocked = manager.remindersBlocked
        holdsTimeToLog = Set(archived.filter { TaskArchive.holdsTimeToLog($0, drafts: manager.drafts) }.map(\.id))
        openDraftCount = manager.openDrafts.count
        sources = manager.syncs.map { $0.source }
        syncStates = Dictionary(uniqueKeysWithValues: sources.map { ($0, manager.syncState($0)) })
        tokenRemovalFailed = Set(sources.filter { manager.tokenRemovalFailed($0) })
        connected = sources.filter { $0.isConnected }
        sourceStatus = Dictionary(uniqueKeysWithValues: connected.map { ($0, TaskSourceStatus.text(for: $0)) })
        syncOn = Set(connected.filter { $0.isSyncOn })
        interrupted = manager.interruptedSessions
        filterTags = TaskFacets.filterTags(in: tasks)
        ownTags = TaskFacets.tags(in: tasks)
        sourceCounts = TaskFacets.sourceCounts(active)
    }

    /// The tasks a tab starts from, before Find and the Tag filter.
    func tasks(on tab: TasksListTab) -> [TaskItem] {
        switch tab {
        case .active: return active
        case .done: return closed
        case .archived: return archived
        }
    }
}
