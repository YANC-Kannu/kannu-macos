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

/// Brain › Tasks, a product page (docs/SETTINGS.md, "Product pages"): the list leads, with what needs you above it
/// (`TasksOverview`), and the settings follow: the Tasks switches, then where tasks come from — Local tasks, Jira
/// Cloud, GitLab and the rest, each with how many it holds and a › to its page — and the tags' colours. Below the first
/// page, a source's page holds its connection, then its projects (or its tasks, with one project or none); a project's
/// page its tasks; a task's page everything about it (`TaskDetailPage`).
///
/// Brain has no navigation stack, so going in is an in-tab view swap on `path`: empty is the first page, opening a page
/// appends it, and the back row atop every page goes up one level and names where it goes ("‹ GitLab"); going back
/// scrolls to the row that was opened. A task opened from the list is `[.task(id)]`, and while the panel holds the list
/// and a task's page side by side (`ListDetailLayout`) that path is drawn with the page beside the list instead of in
/// its place (layout-proposal D1). One path, drawn two ways, so a resize converts nothing. Search lands on the first
/// page's rows (docs/SETTINGS.md, "Section rules"), so any Tasks search or deep link returns there, at both widths.
///
/// What the first page shows from `TasksManager` comes through one throttled copy, `TasksPageData`, followed only while
/// Brain is on screen (docs/SETTINGS.md, "Live data"); a press calls the manager. The pages below the first follow the
/// manager, as they always did: they edit a task or a source in place, and the manager publishes only on an edit, a
/// timer's start or stop, or a sync, which runs only when asked (`SourceSync`). Task titles are the user's own text and
/// render verbatim. With tasks off nothing here touches `TasksManager`, so the tab never reads the task file. None of
/// the Tasks pages reads the Keychain: a sync does, off the main actor, in `TasksManager`.
struct TasksSettings: View {
    @Default(.enableTasks) private var enableTasks
    @Default(.tasksDefaultSessionMinutes) private var defaultSessionMinutes
    @ObservedObject private var visibility = BrainVisibility.shared

    // On the tab, not on a row: a row goes with its page when the path changes, and the task rows
    // are lazy, built only while in view, so a row may not exist when these change.
    @State private var sheet: TaskSheet?
    @State private var pendingDelete: TaskItem?
    /// New Task's draft, kept between sheets so Cancel loses nothing. A box in `@State`, deliberately
    /// not `@StateObject`: this tab must not observe it, so typing redraws the sheet alone
    /// (`NewTaskSheet` observes it). A throwaway box made on a re-init is harmless; `@State` keeps
    /// the first.
    @State private var newTask = NewTaskDraft()
    /// The source whose Disconnect… was clicked, while its dialog asks what to keep.
    @State private var confirmsDisconnect: TaskSource?
    /// The pages opened below the first; empty is the first page.
    @State private var path: [TasksPage] = []
    /// The list's Find field, and which of its tabs it shows. Here, not on the list, so they survive a look at a task
    /// and back.
    @State private var query = ""
    @State private var listTab = TasksListTab.active
    /// The row to bring into view once the next page has appeared: the one that opened the page
    /// just left, or the row a search or deep link names.
    @State private var returnTo: AnyHashable?
    /// What the first page shows from the manager, the list and the settings alike: a copy, never the manager itself.
    /// Read as the page appears and as Brain comes back on screen, then followed at most twice a second while it is on
    /// screen, and assigned only when it changed. Off screen it stays as it was (docs/SETTINGS.md, "Live data").
    @State private var tasks = TasksPageData()
    /// Whether the panel holds the list and a task's page side by side (`ListDetailLayout`). A flag, not the panel's
    /// width, so a resize redraws the page only when it crosses.
    @State private var showsPageBeside = false
    @ObservedObject private var highlights = SettingsHighlightCoordinator.shared

    private func highlightID(_ title: String) -> String { "tasks-\(title)" }

    #if DEBUG
    /// DEBUG snapshot boards only (`DebugSnapshots`): the path and the tab a board opens on.
    static var snapshotPath: [TasksPage] = []
    static var snapshotTab = TasksListTab.active
    #endif

    /// The page in the tab's place: the last of `path`, but a task opened from the list while its page fits beside it.
    private var pageInPlace: TasksPage? {
        guard enableTasks, let page = path.last else { return nil }
        return taskBeside == nil ? page : nil
    }

    /// The task whose page shows beside the list: one opened from the list, while the panel holds both.
    private var taskBeside: UUID? {
        guard enableTasks, showsPageBeside, path.count == 1, case .task(let id)? = path.first else { return nil }
        return id
    }

    /// The first page's: a page opened from it takes its place, or, a task, shows beside the list while there is room.
    private var firstPageContext: TasksPageContext {
        context { path = [$0] }
    }

    /// A page below the first's: opening goes one level in.
    private var innerPageContext: TasksPageContext {
        context { path.append($0) }
    }

    private func context(open: @escaping (TasksPage) -> Void) -> TasksPageContext {
        TasksPageContext(
            sheet: $sheet,
            pendingDelete: $pendingDelete,
            confirmsDisconnect: $confirmsDisconnect,
            open: open,
            connect: { sheet = .connect($0) },
            refresh: { copyFromStore() }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            if let page = pageInPlace {
                SettingsPage {
                    // The back row bare on the panel, a gap above the page's first card (the design review's
                    // finding 24).
                    VStack(alignment: .leading, spacing: SettingsTheme.sectionLabelGap) {
                        backRow(from: page)
                        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {
                            pageContent(page)
                        }
                    }
                }
                // The page just built has appeared: the row it should show, in view. Inside `.id(path)`, so it runs
                // again for each page, also between two pages below the first.
                .onAppear { scrollToReturnTarget(proxy) }
                // A page opens at its top.
                .id(path)
            } else {
                firstPageAndTask
                    .onAppear { scrollToReturnTarget(proxy) }
            }
        }
        // D1: the panel's width decides where a task's page goes, from this one measurement (`ListDetailLayout`).
        .settingsListDetailFits($showsPageBeside)
        .settingsPageTitle(pageInPlace.map(Self.title) ?? Self.overviewTitle)
        .onReceive(NotificationCenter.default.publisher(for: .tasksNewTaskRequested)) { _ in
            // The header's New task, ⌘N, or the empty list's. Read at the press.
            guard enableTasks, sheet == nil, TasksManager.shared.isReady else { return }
            sheet = .newTask(listFilter: newTaskListFilter)
        }
        .onAppear {
            #if DEBUG
            if !Self.snapshotPath.isEmpty || Self.snapshotTab != .active {
                path = Self.snapshotPath
                listTab = Self.snapshotTab
            }
            #endif
            guard enableTasks else { return }
            // As the list did as it opened: macOS's answer may have changed, and Done and Archived count their days
            // from now, not from the last sync.
            TasksManager.shared.checkReminderPermission()
            TasksManager.shared.refreshArchive()
            // One read, not a subscription: the page opens on what the manager holds, and the subscription below takes
            // over once Brain is on screen.
            copyFromStore()
        }
        .task(id: visibility.isOnScreen && enableTasks) {
            guard visibility.isOnScreen && enableTasks else { return }
            // Back on screen: what changed while Brain was not, which `objectWillChange` will not send again.
            copyFromStore()
            // `objectWillChange` comes before a change; read through the run loop, the copy comes after it.
            for await _ in TasksManager.shared.objectWillChange
                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
                .values {
                copyFromStore()
            }
        }
        // Search and deep links land on the first page's rows, never inside a page below it. `initial`: the link may
        // arrive before this tab is built. The list's own link (the notch's "Show all in Brain", a reminder's click)
        // shows Active. A page in the list's place closes, and the first page, built anew, scrolls to the row again,
        // since Settings scrolled before it existed; a task's page beside the list stays, the first page being on
        // screen beside it (the header's gear among such links).
        .onChange(of: highlights.activeHighlightID, initial: true) { _, id in
            guard let id, id.hasPrefix(highlightID("")) else { return }
            if id == SettingsDeepLink.tasksListOpenID { listTab = .active }
            guard pageInPlace != nil else { return }
            path = []
            returnTo = id
        }
        // Tasks off: every reminder, waiting or on screen, is taken back, and the tree closes.
        // `TaskReminders` only — this never builds `TasksManager`.
        .onChange(of: enableTasks) { _, isOn in
            path = []
            if !isOn { TaskReminders.withdrawAll() }
        }
        // Widening past the width with a task open in the list's place builds the list anew, at its top: it scrolls to
        // the task's row, now selected beside the page.
        .onChange(of: showsPageBeside) { _, beside in
            if beside, let id = taskBeside { returnTo = id }
        }
        // A sheet writes through the manager; as it closes, the page reads it again at once, as after a press.
        .sheet(item: $sheet, onDismiss: copyFromStore) { sheet in
            switch sheet {
            case .connect(.jira):
                JiraConnectSheet()
            case .connect(.gitlab):
                GitLabConnectSheet()
            case .connect(let source):
                SourceConnectSheet(source: source)
            case .tags(let taskID, let title, let current, let existing):
                TaskTagsSheet(taskID: taskID, title: title, current: current, existing: existing)
            case .newTask(let listFilter):
                NewTaskSheet(newTask: newTask, listFilter: listFilter) { openTask($0) }
            default:
                TaskValueSheet(sheet: sheet) { value in apply(value, from: sheet) }
            }
        }
        .alert(
            Text(verbatim: String(localized: "Delete “\(pendingDelete?.title ?? "")”?")),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { task in
            Button("Delete", role: .destructive) {
                TasksManager.shared.delete(task.id)
                copyFromStore()
                // Its page, if open, has nothing left to show.
                path.removeAll { $0 == .task(task.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its recorded time is deleted too.")
        }
        .confirmationDialog(
            Text(verbatim: String(localized: "Disconnect \(confirmsDisconnect?.name ?? "")?")),
            isPresented: Binding(get: { confirmsDisconnect != nil }, set: { if !$0 { confirmsDisconnect = nil } }),
            titleVisibility: .visible,
            presenting: confirmsDisconnect
        ) { source in
            Button(String(localized: "Keep \(source.name) Tasks")) { disconnect(source, removeTasks: false) }
            Button(String(localized: "Remove \(source.name) Tasks"), role: .destructive) { disconnect(source, removeTasks: true) }
            Button("Cancel", role: .cancel) {}
        } message: { source in
            Text(verbatim: source.usesToken
                 ? String(localized: "Kannu forgets the token. Keep the \(source.name) tasks and their time, or remove them.")
                 : String(localized: "Kannu stops reading \(source.name). Keep its tasks and their time, or remove them."))
        }
    }

    /// After the page just built has appeared: the row it should show, in view, the one that opened the page left or the
    /// one a search names. After this update, so the row exists.
    private func scrollToReturnTarget(_ proxy: ScrollViewProxy) {
        guard let target = returnTo else { return }
        returnTo = nil
        DispatchQueue.main.async { proxy.scrollTo(target, anchor: .center) }
    }

    /// The one place the first page reads the manager's state: a fresh copy, assigned only when it changed. Never with
    /// tasks off, which would build the task list.
    private func copyFromStore() {
        guard enableTasks else { return }
        let latest = TasksPageData(TasksManager.shared)
        if latest != tasks { tasks = latest }
    }

    /// A task's page, from New Task: from the first page it takes the list's place, or shows beside it; from a page
    /// below the first, one level in.
    private func openTask(_ id: UUID) {
        if pageInPlace == nil {
            path = [.task(id)]
        } else {
            path.append(.task(id))
        }
    }

    /// What the list on screen shows, so a new task it would hide opens on its own page (`NewTaskSheet`): the first
    /// page's list while it shows open tasks, Local tasks' own; nil where no list of open tasks shows.
    private var newTaskListFilter: TaskFilter? {
        switch pageInPlace {
        case nil:
            return listTab == .active ? TaskFilter(tag: Defaults[.tasksListTagFilter], query: query) : nil
        case .source(.local)?:
            return TaskFilter(source: .local)
        default:
            return nil
        }
    }

    // MARK: - The first page, and a task beside it

    private var firstPage: some View {
        SettingsProductPage(settingsTitle: String(localized: "Tasks settings")) {
            TasksOverview(data: tasks, tab: $listTab, query: $query, selected: taskBeside,
                          live: visibility.isOnScreen, context: firstPageContext)
        } settings: {
            optionsSection
            if enableTasks {
                TaskSourcesSection(data: tasks, context: firstPageContext)
                TaskTagColorsSection(data: tasks, context: firstPageContext)
            }
        }
    }

    /// The first page, and while the panel holds both (layout-proposal D1) a task's page beside it, laid out by
    /// `SettingsListDetail`: the list in its own column, the page an inset after it, as wide as a settings column. The
    /// first page is that stack's first child either way, so crossing the width keeps it, scrolled where it was.
    private var firstPageAndTask: some View {
        SettingsListDetail(showsBeside: showsListAndPage) {
            firstPage
        } beside: {
            taskPageBeside
        }
    }

    /// Wide enough for a task's page beside the list, with tasks on.
    private var showsListAndPage: Bool {
        enableTasks && showsPageBeside
    }

    /// The task's page beside the list, or, while none is open, what its place says.
    @ViewBuilder
    private var taskPageBeside: some View {
        if let id = taskBeside {
            SettingsPage {
                TaskDetailPage(taskID: id, context: firstPageContext)
            }
            // A task's page opens at its top.
            .id(id)
        } else {
            SettingsPage {
                SettingsSection {
                    TasksMessage(title: String(localized: "No task selected"),
                                 message: String(localized: "Click › on a task to see it here.")) {
                        EmptyView()
                    }
                }
            }
        }
    }

    // MARK: - The pages below the first

    /// Up one level, to the page it names, which scrolls to the row that opened this one.
    private func backRow(from page: TasksPage) -> some View {
        let parent = path.dropLast().last.map(Self.title) ?? Self.overviewTitle
        return TasksBackRow(parent: parent) { returnTo = Self.scrollTarget(of: path.removeLast()) }
    }

    @ViewBuilder
    private func pageContent(_ page: TasksPage) -> some View {
        switch page {
        case .source(let source):
            TaskSourcePage(source: source, context: innerPageContext)
        case .project(let source, let project):
            TaskProjectPage(source: source, project: project, context: innerPageContext)
        case .task(let id):
            TaskDetailPage(taskID: id, context: innerPageContext)
        }
    }

    private static var overviewTitle: String { String(localized: "Tasks") }

    /// What a page is called, in its back row's child and in the page's large title.
    static func title(of page: TasksPage) -> String {
        switch page {
        case .source(let source): return source.title
        case .project(_, let project): return TaskFacets.projectShortName(project)
        case .task: return String(localized: "Task")
        }
    }

    /// The row that opened a page: a source by its highlight id, a project by its page, a task by its id.
    private static func scrollTarget(of page: TasksPage) -> AnyHashable {
        switch page {
        case .source(let source): return SettingsDeepLink.taskSourceRows[source] ?? SettingsDeepLink.tasksSourcesHighlightID
        case .project: return page
        case .task(let id): return id
        }
    }

    // MARK: - The settings

    /// The Tasks switches, the settings' first section and always built: the header's gear lands on its first row.
    private var optionsSection: some View {
        SettingsSection {
            SettingsRow("Enable tasks", description: "Plan your work and time it.") {
                Defaults.Toggle(key: .enableTasks) {
                    Text("Enable tasks")
                }
            }
            .settingsHighlight(id: SettingsDeepLink.tasksEnableHighlightID)

            SettingsStepperRow(
                "Default session length",
                description: "Timer length when a task has no estimate.",
                value: $defaultSessionMinutes,
                in: 5...240,
                step: 5,
                valueText: Text("\(defaultSessionMinutes) min")
            )
            .settingsHighlight(id: highlightID("Default session length"))

            SettingsRow("Sound when the estimate is reached", description: "Play the timer sound at the estimate.") {
                Defaults.Toggle(key: .tasksSoundAtEstimate) {
                    Text("Sound when the estimate is reached")
                }
            }
            .settingsHighlight(id: highlightID("Sound when the estimate is reached"))
        } header: {
            SettingsSectionHeader("Tasks")
        } footer: {
            SettingsFooter("Tasks and their time stay on this Mac.")
        }
    }

    /// Disconnect, from the dialog: the source's page, if open, leaves with its tasks.
    private func disconnect(_ source: TaskSource, removeTasks: Bool) {
        TasksManager.shared.disconnect(source, removeTasks: removeTasks)
        copyFromStore()
        path.removeAll { page in
            switch page {
            case .source(let shown), .project(let shown, _): return shown == source
            case .task: return false
            }
        }
    }

    private func apply(_ value: TaskValueSheet.Value, from sheet: TaskSheet) {
        switch (sheet, value) {
        case (.estimate(let taskID, _, _), .duration(let seconds)):
            TasksManager.shared.setEstimate(seconds, for: taskID)
        case (.addTime(let taskID, _), .duration(let seconds)):
            if let seconds { TasksManager.shared.addManualTime(seconds, to: taskID) }
        case (.endTime(let taskID, let segmentID, _, _, _), .date(let end)):
            TasksManager.shared.setEndTime(end, segmentID: segmentID, taskID: taskID)
        case (.schedule(let taskID, _, _), .date(let date)):
            TasksManager.shared.setSchedule(date, for: taskID)
        case (.schedule(let taskID, _, _), .cleared):
            TasksManager.shared.setSchedule(nil, for: taskID)
        default:
            break
        }
        copyFromStore()
    }
}

/// A page of Brain › Tasks below the first.
enum TasksPage: Hashable {
    /// A source's connection, then its projects — or its tasks, with one project or none.
    case source(TaskSource)
    /// One project's tasks: a key as `TaskFacets.project` gives it, or `TaskFacets.noProject`.
    case project(TaskSource, String)
    /// One task, opened from any list: beside the first page's list while there is room for both.
    case task(UUID)
}

/// What a page needs from the tab. The sheets (New Task's draft with them) and the alerts live on
/// the tab, because a row goes with its page when the path changes and the task rows are lazy;
/// `open` goes one level in, or, from the first page, takes its place.
struct TasksPageContext {
    let sheet: Binding<TaskSheet?>
    let pendingDelete: Binding<TaskItem?>
    let confirmsDisconnect: Binding<TaskSource?>
    let open: (TasksPage) -> Void
    /// Connect…: the source's own sheet (a token, or Apple Reminders' permission).
    let connect: (TaskSource) -> Void
    /// After a press: the first page reads the manager again at once, outside its throttle, so a second click never
    /// waits for the copy. A page below the first follows the manager and needs nothing.
    var refresh: () -> Void = {}
}

/// Atop every page below the first, bare on the panel: up one level, naming where it goes ("‹ GitLab"). The one
/// sanctioned lone leading button in Brain (docs/SETTINGS.md): it is navigation, not an action on a row. Flush, so its
/// chevron starts on the page's column.
struct TasksBackRow: View {
    let parent: String
    let back: () -> Void

    var body: some View {
        Button(action: back) {
            HStack(spacing: SettingsMetrics.iconGap) {
                Image(systemName: "chevron.left")
                Text(verbatim: parent)
            }
        }
        .buttonStyle(SettingsButtonStyle(.quiet, flush: true))
        .accessibilityLabel(Text(verbatim: String(localized: "Back to \(parent)")))
    }
}

/// "40 open ›": a row's way into its page.
struct TasksOpenButton: View {
    let text: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsMetrics.iconGap) {
                Text(verbatim: text)
                Image(systemName: "chevron.right")
            }
        }
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }
}

/// The settings' Sources: Local tasks, then each connected source with how many tasks it holds and a › to its page,
/// where its connection and settings are; then "Add a source", a Connect menu of the sources not connected. A source
/// not connected has no row of its own: its search entries land on Add a source (`SettingsView.landingOnABuiltRow`),
/// and tasks it kept from before stay in the list.
///
/// Status comes from the page's copy (`TasksPageData`) and the Defaults display copies, never from the Keychain
/// (`TaskSourceStatus`). A source's row appearing asks for a sync only when the last one is stale; a problem shows here
/// as "Needs attention" and in full on the source's page. Each row registers its own deep link, literally
/// (`highlighted(_:for:)`), so search and the inventory test find it.
private struct TaskSourcesSection: View {
    let data: TasksPageData
    let context: TasksPageContext

    var body: some View {
        let counts = data.sourceCounts
        let connected = data.connected
        let addable = data.sources.filter { !connected.contains($0) }
        SettingsSection {
            LabeledContent {
                openButton(count: counts[.local] ?? 0, page: .source(.local))
            } label: {
                SettingsRowLabel("Local tasks", description: "Tasks you add here or in the notch.")
            }
            .settingsHighlight(id: SettingsDeepLink.tasksSourcesHighlightID)

            ForEach(connected, id: \.self) { source in
                highlighted(sourceRow(source, count: counts[source] ?? 0), for: source)
            }

            ForEach(addable.filter { data.tokenRemovalFailed.contains($0) }, id: \.self) { source in
                SettingsErrorText(String(localized: "Couldn't remove the \(source.name) token from your Keychain."))
                SettingsActionRow(
                    "Saved token",
                    description: String(localized: "Or delete com.kannu.app.secure-secrets (\(TaskSourceStatus.keychainItem(for: source))) in Keychain Access.")
                ) {
                    Button("Remove Token") {
                        TasksManager.shared.retryRemovingToken(source)
                        context.refresh()
                    }
                }
            }

            if !addable.isEmpty {
                LabeledContent {
                    Menu {
                        ForEach(addable, id: \.self) { source in
                            Button(source.title) { context.connect(source) }
                        }
                    } label: {
                        // Our button takes the native indicator away, so the label draws its own chevron.
                        HStack(spacing: SettingsMetrics.iconGap) {
                            Text("Connect…")
                            Image(systemName: "chevron.down")
                                .accessibilityHidden(true)
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(SettingsButtonStyle())
                    .menuIndicator(.hidden)
                    .fixedSize()
                } label: {
                    SettingsRowLabel("Add a source", description: Text(verbatim: addable.map(\.title).formatted(.list(type: .or))))
                }
                .settingsHighlight(id: SettingsDeepLink.tasksAddSourceHighlightID)
            }
        } header: {
            SettingsSectionHeader("Sources")
        } footer: {
            SettingsFooterStack {
                SettingsFooter("Tokens stay in your Keychain. Kannu writes nothing until you choose Log.")
                SettingsFooter("Make tokens just for Kannu, with an expiry date.")
            }
        }
    }

    private func openButton(count: Int, page: TasksPage) -> some View {
        TasksOpenButton(
            text: String(localized: "\(count) open"),
            accessibilityLabel: String(localized: "Open \(TasksSettings.title(of: page))")
        ) { context.open(page) }
    }

    /// A connected source: who it is connected as, or "Needs attention", and its open count.
    private func sourceRow(_ source: TaskSource, count: Int) -> some View {
        let state = data.syncStates[source] ?? .idle
        let problem = TaskSourceStatus.problem(state, source: source)
        let status = problem != nil || state == .needsKeychainApproval
            ? String(localized: "Needs attention")
            : data.sourceStatus[source] ?? ""
        return LabeledContent {
            openButton(count: count, page: .source(source))
        } label: {
            VStack(alignment: .leading, spacing: SettingsMetrics.labelStack) {
                Text(verbatim: source.title)
                SettingsStatusText(status, isReady: data.syncOn.contains(source) && problem == nil)
            }
        }
        // A sync of its own only when the last is stale, as the page opens: never on a scroll, which a plain page has
        // none of.
        .onAppear { TasksManager.shared.syncIfStale(source) }
    }

    /// Each source's row with its own deep link, written out so it is found by search and pinned by
    /// `SettingsHighlightInventoryTests`.
    @ViewBuilder
    private func highlighted(_ row: some View, for source: TaskSource) -> some View {
        switch source {
        case .local: row
        case .jira: row.settingsHighlight(id: SettingsDeepLink.tasksJiraSourceHighlightID)
        case .gitlab: row.settingsHighlight(id: SettingsDeepLink.tasksGitLabSourceHighlightID)
        case .github: row.settingsHighlight(id: SettingsDeepLink.tasksGitHubSourceHighlightID)
        case .linear: row.settingsHighlight(id: SettingsDeepLink.tasksLinearSourceHighlightID)
        case .todoist: row.settingsHighlight(id: SettingsDeepLink.tasksTodoistSourceHighlightID)
        case .appleReminders: row.settingsHighlight(id: SettingsDeepLink.tasksAppleRemindersSourceHighlightID)
        }
    }
}

/// Every tag on any task Kannu holds, done and archived ones too, with its colour, folded until opened. A colour is
/// the tag's, shared by every task carrying it (`TasksManager.setTagColor`). Our disclosure, as every group under
/// Settings now is (the design review's finding 13): the list moved up into the product, and this one is short.
private struct TaskTagColorsSection: View {
    let data: TasksPageData
    let context: TasksPageContext
    @State private var showsTagColors = false

    var body: some View {
        let tags = data.ownTags
        SettingsSection {
            DisclosureGroup(isExpanded: $showsTagColors) {
                if tags.isEmpty {
                    SettingsNoteRow("No tags yet", description: "Tags you add to tasks appear here.")
                }
                ForEach(tags, id: \.self) { tag in
                    let color = data.tagColors[TaskColoring.key(for: tag)] ?? .glass
                    LabeledContent {
                        TaskColorPickerButton(
                            selection: Binding(get: { color }, set: { picked in
                                TasksManager.shared.setTagColor(picked, for: tag)
                                context.refresh()
                            }),
                            accessibilityLabel: String(localized: "Colour of tag \(tag): \(color.localizedName)")
                        )
                        .disabled(!data.isReady)
                    } label: {
                        SettingsRowLabel(Text(verbatim: "#\(tag)"))
                    }
                }
            } label: {
                SettingsRowLabel("Tag colours", description: "A task takes its first tag's colour; untagged ones, their source's.")
            }
            .settingsHighlight(id: SettingsDeepLink.tasksTagColorsHighlightID)
        }
    }
}

/// What a task sheet edits.
enum TaskSheet: Identifiable {
    /// Right-click › Set Estimate: the task's estimate as `TaskFormDraft(editing:)` reads it.
    case estimate(taskID: UUID, title: String, draft: TaskFormDraft)
    case addTime(taskID: UUID, title: String)
    /// `nextSessionStart` is when the next session on the task began, if one has: the end may not
    /// pass it. The sheet caps it at now on its own render, so the clock stays live.
    case endTime(taskID: UUID, segmentID: UUID, title: String, start: Date, nextSessionStart: Date?)
    /// Add Tags on any task, served by `TaskTagsSheet`. `existing` are the tags in use on any task.
    case tags(taskID: UUID, title: String, current: [String], existing: [String])
    /// Schedule on a local task.
    case schedule(taskID: UUID, title: String, current: Date?)
    /// Connect… for a source: `JiraConnectSheet`, `GitLabConnectSheet`, or `SourceConnectSheet`.
    case connect(TaskSource)
    /// New Task, served by `NewTaskSheet`. `listFilter` is what the list on screen shows, so a task it would hide
    /// opens on its own page; nil where no list of open tasks shows.
    case newTask(listFilter: TaskFilter?)

    var id: String {
        switch self {
        case .newTask: return "new-task"
        case .connect(let source): return "connect-\(source.rawValue)"
        case .estimate(let taskID, _, _): return "estimate-\(taskID)"
        case .addTime(let taskID, _): return "add-time-\(taskID)"
        case .endTime(_, let segmentID, _, _, _): return "end-time-\(segmentID)"
        case .tags(let taskID, _, _, _): return "tags-\(taskID)"
        case .schedule(let taskID, _, _): return "schedule-\(taskID)"
        }
    }
}

/// The small sheet behind Set Estimate, Add Time, Set End Time and Schedule. Its confirm button says
/// what it does: Save, Add or Schedule. Set Estimate takes the typed estimate New Task and a task's
/// page take (`TaskEstimateField`), checked as it is typed. A sheet pads its own content; a Form row
/// never does.
private struct TaskValueSheet: View {
    enum Value {
        /// Nil removes an estimate.
        case duration(Int?)
        case date(Date)
        /// Clear Schedule.
        case cleared
    }

    let sheet: TaskSheet
    let onSave: (Value) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    /// Set Estimate's typed estimate (`TaskFormDraft`).
    @State private var estimate: TaskFormDraft
    @State private var date: Date
    @State private var problem: String?

    init(sheet: TaskSheet, onSave: @escaping (Value) -> Void) {
        self.sheet = sheet
        self.onSave = onSave
        if case .estimate(_, _, let draft) = sheet {
            _estimate = State(initialValue: draft)
        } else {
            _estimate = State(initialValue: TaskFormDraft())
        }
        switch sheet {
        case .endTime(_, _, _, let start, _):
            // Kannu never guesses the end: the picker starts where the session started.
            _date = State(initialValue: start)
        case .schedule(_, _, let current):
            _date = State(initialValue: current.flatMap { $0 > Date() ? $0 : nil } ?? Self.nextHour())
        default:
            _date = State(initialValue: Date())
        }
    }

    /// The next whole hour: a schedule's starting point.
    private static func nextHour(after now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? now.addingTimeInterval(3600)
    }

    var body: some View {
        SettingsSheet(heading, subtitle: Text(explanation)) {
            if let subject {
                Text(verbatim: subject)
                    .settingsDescriptionStyle()
            }
            field
            // Only for a reminder that would notify: a muted task's re-timed reminder stays muted
            // (`setSchedule`), as on the task page and in New Task. The bell cannot change while the
            // sheet is up, so a lookup at render is enough.
            if case .schedule(let taskID, _, _) = sheet,
               TasksManager.shared.tasks.first(where: { $0.id == taskID })?.notifiesForReminder ?? true {
                ReminderPermissionNote()
            }
            if let problem {
                SettingsErrorText(problem)
            }
        } buttons: {
            if case .estimate(_, _, let draft) = sheet, draft.estimateSeconds != nil {
                Button("Remove Estimate") {
                    onSave(.duration(nil))
                    dismiss()
                }
            }
            if case .schedule(_, _, .some) = sheet {
                Button("Clear Schedule") {
                    onSave(.cleared)
                    dismiss()
                }
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(primaryTitle) { save() }
                .buttonStyle(SettingsButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(isEstimate && estimate.estimateReading == .unreadable)
        }
        .onChange(of: estimate.estimateText) { _, _ in problem = nil }
        // macOS's answer may have changed since the list last asked: the note follows it.
        .onAppear {
            if case .schedule = sheet { TasksManager.shared.checkReminderPermission() }
        }
    }

    private var isEstimate: Bool {
        if case .estimate = sheet { return true }
        return false
    }

    @ViewBuilder
    private var field: some View {
        switch sheet {
        case .endTime(_, _, _, let start, let nextSessionStart):
            // Date() here, not a stored bound: the list may have rendered long before the click.
            LabeledContent("Stopped working at") {
                SettingsDateField("Stopped working at", selection: $date, in: start...max(start, min(nextSessionStart ?? .distantFuture, Date())))
            }
        case .schedule:
            LabeledContent("Remind me at") {
                SettingsDateField("Remind me at", selection: $date, in: Date()...)
            }
        case .estimate:
            TaskEstimateField(draft: $estimate, onSubmit: save)
        default:
            TextField("Length", text: $text, prompt: Text("1h 30m"))
                .onSubmit(save)
                .onChange(of: text) { _, _ in problem = nil }
                .settingsField()
        }
    }

    private var heading: LocalizedStringKey {
        switch sheet {
        case .estimate: return "Set Estimate"
        case .addTime: return "Add Time"
        case .endTime: return "Set End Time"
        case .tags: return "Tags"
        case .schedule: return "Schedule"
        case .connect: return "Connect"
        case .newTask: return "New Task"
        }
    }

    /// The task's own title, verbatim.
    private var subject: String? {
        switch sheet {
        case .tags, .connect, .newTask: return nil
        case .estimate(_, let title, _), .addTime(_, let title), .endTime(_, _, let title, _, _),
             .schedule(_, let title, _):
            return title
        }
    }

    private var explanation: LocalizedStringKey {
        switch sheet {
        case .estimate:
            return "Such as 1h 30m, 90m, 1.5h or 2d. Nothing, or 0, removes it."
        case .addTime:
            return "Time worked without the timer, ending now."
        case .endTime(_, _, _, _, .none):
            return "When did you stop working on it?"
        case .endTime:
            return "When did you stop? Not after a later session began."
        case .schedule:
            return "A reminder with a Start button."
        case .tags, .connect, .newTask:
            return ""
        }
    }

    private var primaryTitle: LocalizedStringKey {
        switch sheet {
        case .addTime, .newTask: return "Add"
        case .schedule: return "Schedule"
        case .estimate, .endTime, .tags, .connect: return "Save"
        }
    }

    private func save() {
        switch sheet {
        case .endTime, .schedule:
            onSave(.date(date))
            dismiss()
            return
        case .estimate:
            // The typed estimate's own reading: nothing or 0 removes it, as on a task's page.
            switch estimate.estimateReading {
            case .none: onSave(.duration(nil))
            case .length(let seconds): onSave(.duration(seconds))
            case .unreadable:
                problem = String(localized: "Type at least a minute, such as 1h 30m.")
                return
            }
            dismiss()
            return
        default:
            break
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = WorkDuration.parse(trimmed), seconds >= 60 else {
            problem = String(localized: "Type at least a minute, such as 1h 30m.")
            return
        }
        onSave(.duration(seconds))
        dismiss()
    }
}

/// The button to macOS's Notifications pane. One literal, for All tasks' note, a task page's
/// Notify, and the Schedule and New Task sheets (`BrainNamingRulesTests` allows it once: it means
/// the macOS pane, not Brain).
let openNotificationSettingsTitle: LocalizedStringKey = "Open Notification Settings"

/// "Notifications are off" with a way to turn them on, while macOS blocks Kannu's notifications:
/// in the Schedule and New Task sheets, so the user hears before setting a reminder that cannot
/// notify (`notificationsDenied`, macOS's answer, not whether any reminder waits yet).
struct ReminderPermissionNote: View {
    @ObservedObject private var manager = TasksManager.shared

    var body: some View {
        if manager.notificationsDenied {
            HStack(spacing: SettingsMetrics.rowContent) {
                Text("Notifications are off for Kannu.")
                    .settingsDescriptionStyle(tint: .orange)
                Button(openNotificationSettingsTitle) { TaskReminders.openNotificationSettings() }
            }
        }
    }
}

#if DEBUG
extension TasksSettings {
    /// DEBUG snapshot harness: Set End Time, the value sheet that shows the date field and, unlike Schedule, runs no
    /// permission check. The sheet's type is private to this file.
    static func snapshotEndTimeSheet() -> AnyView {
        AnyView(TaskValueSheet(sheet: .endTime(taskID: DebugSnapshotFixtures.localTaskID, segmentID: UUID(),
                                               title: "Write the release notes",
                                               start: Date().addingTimeInterval(-3 * 3600), nextSessionStart: nil),
                               onSave: { _ in }))
    }
}
#endif
