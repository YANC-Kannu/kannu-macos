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

import XCTest

/// Brain › Tasks is a product page with live data, and Brain's content is built once and outlives its window
/// (docs/REGRESSIONS.md, entry 22). Its first page keeps Agents' live-data contract (docs/SETTINGS.md, "Live data") and
/// lays a task's page beside the list or in its place by one width function (layout-proposal D1). Each rule is read
/// from the source and checked against planted offenders, as `ClipboardPageLiveDataRulesTests` does for Clipboard.
final class TasksPageLiveDataRulesTests: XCTestCase {

    private static let settingsPath = "Kannu/components/Settings/TasksSettings.swift"
    private static let overviewPath = "Kannu/components/Settings/TasksOverview.swift"
    private static let rowsPath = "Kannu/components/Settings/TaskRowList.swift"
    private static let taskPagePath = "Kannu/components/Settings/TaskDetailPage.swift"
    private static let viewPath = "Kannu/components/Settings/SettingsView.swift"

    /// The braces after a signature, matched by depth; the reader `ClosedNotchTimerRulesTests` already shares.
    private static func body(after signature: String, in code: String) -> String {
        ClosedNotchTimerRulesTests.body(after: signature, in: code) ?? ""
    }

    /// The tab and its first page's sections, without the sheets after them: a sheet is a window of its own, not the
    /// page, and New Task's bell reads the manager as it draws.
    private static func pagePart(of settings: String) -> String {
        let code = SettingsDesignSystemRulesTests.code(settings)
        guard let sheets = code.range(of: "enum TaskSheet: Identifiable") else { return code }
        return String(code[..<sheets.lowerBound])
    }

    // MARK: - Clause 1: throttled and scoped

    /// The page's subscription: whatever the manager changes, at most twice a second.
    private static let managerFeed = #"TasksManager\.shared\.objectWillChange\s*\.throttle\(for: \.milliseconds\(500\), scheduler: RunLoop\.main, latest: true\)\s*\.values"#
    /// The header's: whether the task list has been read, passed on only when that changes.
    private static let readyFeed = #"TasksManager\.shared\.\$loadState\.map\(\{ \$0 == \.ready \}\)\.removeDuplicates\(\)\.values"#
    /// All the first page and its header may name on the manager: the two subscriptions, the reads as the page appears
    /// (`isReady` there and at New task's press) and the calls a press makes. Anything else there is state, which only
    /// the copy reads, so a value the manager gains later is caught too.
    private static let allowedManagerNames: Set<String> = [
        "objectWillChange", "$loadState", "isReady", "checkReminderPermission", "refreshArchive", "delete", "disconnect",
        "setEstimate", "addManualTime", "setEndTime", "setSchedule", "discardInterruptedSession", "retryRemovingToken",
        "syncIfStale", "setTagColor",
    ]

    /// Each name used on `TasksManager.shared` that is not on that list.
    static func managerNamesPastTheCopy(in code: String) -> [String] {
        SettingsDesignSystemRulesTests.matches(of: #"\bTasksManager\.shared\.\$?\w+"#, in: code)
            .map { String($0.dropFirst("TasksManager.shared.".count)) }
            .filter { !Self.allowedManagerNames.contains($0) }
    }

    /// One subscription for the page and one for its header, and nothing else of the manager: no observer, no
    /// `onReceive`, no sink, no kept reference, its state read in one place into a copy assigned only when it changed,
    /// whose equality is the compiler's, so it covers every field. The list draws its rows from the copy
    /// (`TaskRowCards`, which observes nothing), never through `TaskRowList`, which follows the manager for the pages
    /// below the first. Time to log's cards, the notch popover's own, follow the manager: they are built only while an
    /// entry waits, which the copy says.
    static func followProblems(settings: String, overview: String, rows: String) -> [String] {
        let page = pagePart(of: settings)
        let overviewCode = SettingsDesignSystemRulesTests.code(overview)
        var problems: [String] = []
        if SettingsDesignSystemRulesTests.matches(of: managerFeed, in: page).count != 1
            || !SettingsDesignSystemRulesTests.matches(of: managerFeed, in: overviewCode).isEmpty {
            problems.append("the manager is not followed through the page's one subscription throttled to 500 ms")
        }
        if SettingsDesignSystemRulesTests.matches(of: readyFeed, in: overviewCode).count != 1 {
            problems.append("the header's verb does not follow the task list through one subscription that drops repeats")
        }
        let subscriptions = [page, overviewCode].reduce(0) {
            $0 + $1.components(separatedBy: "TasksManager.shared.$").count - 1
                + $1.components(separatedBy: "TasksManager.shared.objectWillChange").count - 1
        }
        if subscriptions != 2 { problems.append("the manager is followed outside the two subscriptions") }
        for (name, code) in [("the page", page), ("the overview", overviewCode)] {
            if !SettingsDesignSystemRulesTests.matches(of: #"@(?:ObservedObject|StateObject|EnvironmentObject)[^\n]*\bTasksManager\b"#, in: code).isEmpty {
                problems.append("\(name) observe the whole manager")
            }
            if code.range(of: #"\.onReceive\([^\n]*\bTasksManager\b|\bTasksManager\b[^\n]*\.sink"#, options: .regularExpression) != nil {
                problems.append("\(name) follow the manager outside the throttled task")
            }
            if code.range(of: #"=\s*TasksManager\.shared\s*\n"#, options: .regularExpression) != nil {
                problems.append("\(name) keep a reference to the manager, which reads past the copy")
            }
            let pastTheCopy = Self.managerNamesPastTheCopy(in: code)
            if !pastTheCopy.isEmpty {
                problems.append("\(name) read the manager's state past the copy: \(pastTheCopy.joined(separator: ", "))")
            }
        }
        let reader = body(after: "private func copyFromStore()", in: page)
        if page.components(separatedBy: "TasksPageData(TasksManager.shared)").count - 1 != 1
            || overviewCode.contains("TasksPageData(TasksManager.shared)")
            || !reader.contains("TasksPageData(TasksManager.shared)")
            || !reader.contains("if latest != tasks { tasks = latest }") {
            problems.append("the manager is not read in one place, into a copy assigned only when it changed")
        }
        if !overviewCode.contains("struct TasksPageData: Equatable {") || overviewCode.contains("static func == (lhs: TasksPageData") {
            problems.append("the copy's equality is not the compiler's, so it can leave a field out")
        }
        let cards = body(after: "struct TaskRowCards: View", in: SettingsDesignSystemRulesTests.code(rows))
        if cards.isEmpty || cards.range(of: #"@(?:ObservedObject|StateObject|EnvironmentObject)"#, options: .regularExpression) != nil {
            problems.append("the rows the list draws observe something of their own")
        }
        if !overviewCode.contains("TaskRowCards(") || overviewCode.contains("TaskRowList(") {
            problems.append("the list does not draw its rows from the copy")
        }
        if overviewCode.components(separatedBy: "TimeToLogSection()").count - 1 != 1
            || !body(after: "if data.openDraftCount > 0", in: overviewCode).contains("TimeToLogSection()") {
            problems.append("Time to log's cards, which follow the manager, are built while no entry waits")
        }
        return problems
    }

    func testTheManagerComesThroughOneThrottledCopy() throws {
        let settings = try Self.source(Self.settingsPath)
        let overview = try Self.source(Self.overviewPath)
        let rows = try Self.source(Self.rowsPath)
        XCTAssertEqual(Self.followProblems(settings: settings, overview: overview, rows: rows), [])
        SettingsDesignSystemRulesTests.assertCaught([
            (".throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n                .values", ".values"),
            (".milliseconds(500)", ".milliseconds(50)"),
            ("    @ObservedObject private var visibility = BrainVisibility.shared",
             "    @ObservedObject private var manager = TasksManager.shared\n    @ObservedObject private var visibility = BrainVisibility.shared"),
            ("if latest != tasks { tasks = latest }", "tasks = latest"),
            ("TasksOverview(data: tasks,", "TasksOverview(data: TasksPageData(TasksManager.shared),"),
            // A value the manager does not show yet, read past the copy: the allowlist catches what a list of names would miss.
            ("let counts = TaskFacets.sourceCounts(data.active)", "let counts = TaskFacets.sourceCounts(TasksManager.shared.activeTasks)"),
            ("let state = data.syncStates[source] ?? .idle", "let state = TasksManager.shared.syncState(source)"),
            ("        .settingsPageTitle(", "        .onReceive(TasksManager.shared.objectWillChange) { _ in }\n        .settingsPageTitle("),
        ], in: settings) { Self.followProblems(settings: $0, overview: overview, rows: rows) }
        SettingsDesignSystemRulesTests.assertCaught([
            (".removeDuplicates().values", ".values"),
            ("let base = data.tasks(on: tab)", "let base = TasksManager.shared.activeTasks"),
            ("    @Default(.enableTasks) private var enabled\n    @Default(.enableTimerFeature) private var timerOn",
             "    @Default(.enableTasks) private var enabled\n    @StateObject private var manager = TasksManager.shared\n    @Default(.enableTimerFeature) private var timerOn"),
            ("struct TasksPageData: Equatable {", "struct TasksPageData: Equatable {\n    static func == (lhs: TasksPageData, rhs: TasksPageData) -> Bool { lhs.tasks == rhs.tasks }"),
            ("            TaskRowCards(\n", "            TaskRowList(filter: filter, context: context)\n            TaskRowCards(\n"),
            ("                if data.openDraftCount > 0 {\n                    TimeToLogSection()\n                }\n",
             "                TimeToLogSection()\n"),
        ], in: overview) { Self.followProblems(settings: settings, overview: $0, rows: rows) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("    let doneTicks: TaskDoneTicks\n    let isReady: Bool",
             "    let doneTicks: TaskDoneTicks\n    @ObservedObject private var manager = TasksManager.shared\n    let isReady: Bool"),
        ], in: rows) { Self.followProblems(settings: settings, overview: overview, rows: $0) }
    }

    // MARK: - Clause 2: stopped while Brain is not on screen

    /// A `Task` started inside a `.task` is not its child: it outlives the cancel, one more each time Brain comes back.
    private static let unstructuredTask = #"\bTask\s*(?:\{|\(|\.detached)"#

    /// Both subscriptions are the one `.task` of their part, keyed on Brain's visibility and the Tasks switch, each
    /// returning at once while either is false (with tasks off nothing touches the manager), with no `Task` inside, and
    /// each loop doing its one job. Back on screen, the page reads the manager once before it follows it, because
    /// `objectWillChange` will not send again what changed while Brain was away. `AgentsPageLiveDataRulesTests` holds
    /// the flag itself.
    static func offScreenProblems(settings: String, overview: String) -> [String] {
        var problems: [String] = []
        let parts = [
            ("the page", pagePart(of: settings), ".task(id: visibility.isOnScreen && enableTasks)",
             "guard visibility.isOnScreen && enableTasks else { return }", "TasksManager.shared.objectWillChange", "copyFromStore()"),
            ("the header", SettingsDesignSystemRulesTests.code(overview), ".task(id: visibility.isOnScreen && enabled)",
             "guard visibility.isOnScreen && enabled else { return }", "TasksManager.shared.$loadState", "ready = isReady"),
        ]
        for (name, code, opener, gate, feed, job) in parts {
            // The modifier, never a path's `.task(id)`: a `.task {` or a `.task(id:`.
            let modifiers = SettingsDesignSystemRulesTests.matches(of: #"\.task\s*(?:\{|\(id:)"#, in: code).count
            guard modifiers == 1, code.components(separatedBy: opener).count - 1 == 1 else {
                problems.append("\(name) does not follow Brain's visibility")
                continue
            }
            let task = body(after: opener, in: code)
            guard let gateRange = task.range(of: gate), let feedRange = task.range(of: feed),
                  gateRange.lowerBound < feedRange.lowerBound else {
                problems.append("\(name) subscribes while Brain is off screen or tasks are off")
                continue
            }
            if task.range(of: unstructuredTask, options: .regularExpression) != nil {
                problems.append("\(name) subscribes in a Task its .task cannot cancel")
            }
            if !body(after: ".values", in: task).contains(job) {
                problems.append("\(name)'s loop does not do its job: \(job)")
            }
            if name == "the page" {
                guard let read = task.range(of: "copyFromStore()"),
                      gateRange.lowerBound < read.lowerBound, read.lowerBound < feedRange.lowerBound else {
                    problems.append("the page does not read the manager as Brain comes back on screen")
                    continue
                }
            }
        }
        return problems
    }

    func testTheSubscriptionsStopWhileBrainIsOffScreen() throws {
        let settings = try Self.source(Self.settingsPath)
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.offScreenProblems(settings: settings, overview: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            (".task(id: visibility.isOnScreen && enableTasks) {", ".task {"),
            ("            guard visibility.isOnScreen && enableTasks else { return }\n", ""),
            ("            guard visibility.isOnScreen && enableTasks else { return }\n", "            guard visibility.isOnScreen else { return }\n"),
            ("            copyFromStore()\n            // `objectWillChange` comes before", "            // `objectWillChange` comes before"),
            ("            for await _ in TasksManager.shared.objectWillChange", "            Task { for await _ in TasksManager.shared.objectWillChange"),
            // A loop that follows and does nothing: the copy would never change after Brain comes back.
            ("                .values {\n                copyFromStore()\n            }", "                .values {\n            }"),
        ], in: settings) { Self.offScreenProblems(settings: $0, overview: overview) }
        SettingsDesignSystemRulesTests.assertCaught([
            (".task(id: visibility.isOnScreen && enabled) {", ".task {"),
            ("            guard visibility.isOnScreen && enabled else { return }\n", ""),
            ("                ready = isReady\n", ""),
        ], in: overview) { Self.offScreenProblems(settings: settings, overview: $0) }
    }

    // MARK: - Clause 3: no work while nothing is on screen

    /// The product keeps no clock and nothing that moves on its own: a closed task says when it closes by its date, and
    /// off screen the copy simply stays as it was. The two clocks a task has run only while Brain is on screen: the
    /// timed row's minute (`TaskRowCards`, its `live`) and a task's page's (`TaskDetailPage`, its `.task` keyed on Brain's
    /// visibility).
    static func clockProblems(overview: String, rows: String, taskPage: String) -> [String] {
        var problems: [String] = []
        let overviewCode = SettingsDesignSystemRulesTests.code(overview)
        for clock in ["TimelineView", "Timer.", ".repeatForever", "ProgressView", "withAnimation", ".animation(", "asyncAfter"]
            where overviewCode.contains(clock) {
            problems.append("the product keeps a clock or a motion of its own: \(clock)")
        }
        let rowsCode = SettingsDesignSystemRulesTests.code(rows)
        if rowsCode.components(separatedBy: "TimelineView").count - 1 != 1
            || SettingsDesignSystemRulesTests.matches(of: #"if isTimed && live \{\s*TimelineView\(\.everyMinute\)"#, in: rowsCode).count != 1 {
            problems.append("the timed row's minute runs while Brain is not on screen")
        }
        let pageCode = SettingsDesignSystemRulesTests.code(taskPage)
        if SettingsDesignSystemRulesTests.matches(of: #"\.task\(id: visibility\.isOnScreen\) \{\s*guard visibility\.isOnScreen else \{ return \}\s*while !Task\.isCancelled \{"#,
                                                   in: pageCode).count != 1 {
            problems.append("a task's page keeps its minute while Brain is not on screen")
        }
        return problems
    }

    func testThePageKeepsNoClockOffScreen() throws {
        let overview = try Self.source(Self.overviewPath)
        let rows = try Self.source(Self.rowsPath)
        let taskPage = try Self.source(Self.taskPagePath)
        XCTAssertEqual(Self.clockProblems(overview: overview, rows: rows, taskPage: taskPage), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("            controls\n", "            controls\n            TimelineView(.periodic(from: .now, by: 60)) { _ in EmptyView() }\n"),
            ("                    Button(\"Reopen\") { press { $0.reopen(task.id) } }\n",
             "                    Button(\"Reopen\") { withAnimation { press { $0.reopen(task.id) } } }\n"),
        ], in: overview) { Self.clockProblems(overview: $0, rows: rows, taskPage: taskPage) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("if isTimed && live {", "if isTimed {"),
        ], in: rows) { Self.clockProblems(overview: overview, rows: $0, taskPage: taskPage) }
        SettingsDesignSystemRulesTests.assertCaught([
            (".task(id: visibility.isOnScreen) {", ".task {"),
            ("                guard visibility.isOnScreen else { return }\n", ""),
        ], in: taskPage) { Self.clockProblems(overview: overview, rows: rows, taskPage: $0) }
    }

    // MARK: - D1: a task's page beside the list, or in its place

    /// One width function decides (`ListDetailLayout`, tested in `ListDetailLayoutTests`), read from one measurement of
    /// the page into a flag; the page beside the list only for a task opened from it (a path of one task); the list a
    /// column of the function's width with the inset on each side, and the task's page an inset after it, with no
    /// inset of its own. None of the ways D1 rules out: `minWidth:` (the size bridge would clamp the window to it),
    /// `ViewThatFits` (it builds every layout it tries), `.inspector`. A search or deep link returns to the first page at
    /// either width, and scrolls a first page built anew to its row.
    static func layoutProblems(settings: String, overview: String) -> [String] {
        let page = pagePart(of: settings)
        var problems: [String] = []
        let measure = #"\.onGeometryChange\(for: Bool\.self\) \{ geometry in\s*ListDetailLayout\.showsPageBeside\(panelWidth: geometry\.size\.width, inset: inset, pageWidth: SettingsTheme\.pageMaxWidth\)\s*\} action: \{ showsPageBeside = \$0 \}"#
        if SettingsDesignSystemRulesTests.matches(of: measure, in: page).count != 1
            || page.components(separatedBy: "ListDetailLayout.showsPageBeside(").count - 1 != 1 {
            problems.append("the page does not choose its layout by the width function, from one measurement")
        }
        if !page.contains("guard enableTasks, showsPageBeside, path.count == 1, case .task(let id)? = path.first else { return nil }") {
            problems.append("a page other than a task opened from the list shows beside it")
        }
        if !page.contains(".frame(width: inset + ListDetailLayout.listWidth + inset)")
            || !page.contains(".environment(\\.settingsPageInset, 0)") {
            problems.append("the list and the task's page are not laid out by the function's widths")
        }
        for (name, code) in [("the page", page), ("the overview", SettingsDesignSystemRulesTests.code(overview))] {
            for banned in ["minWidth:", "ViewThatFits", ".inspector("] where code.contains(banned) {
                problems.append("\(name) lays out with \(banned), which D1 rules out")
            }
        }
        let landing = body(after: ".onChange(of: highlights.activeHighlightID, initial: true)", in: page)
        guard let rebuilt = landing.range(of: "let rebuildsFirstPage = pageInPlace != nil"),
              let cleared = landing.range(of: "path = []"), rebuilt.lowerBound < cleared.lowerBound,
              landing.contains("if rebuildsFirstPage { returnTo = id }") else {
            problems.append("a search or deep link does not return to the first page at both widths")
            return problems
        }
        return problems
    }

    func testATasksPageIsBesideTheListOrInItsPlaceByOneWidthFunction() throws {
        let settings = try Self.source(Self.settingsPath)
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.layoutProblems(settings: settings, overview: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("pageWidth: SettingsTheme.pageMaxWidth)", "pageWidth: 600)"),
            ("guard enableTasks, showsPageBeside, path.count == 1,", "guard enableTasks, showsPageBeside,"),
            (".frame(width: inset + ListDetailLayout.listWidth + inset)", ".frame(minWidth: inset + ListDetailLayout.listWidth + inset)"),
            ("            .environment(\\.settingsPageInset, 0)\n", ""),
            ("                } else if enableTasks && showsPageBeside {\n                    listAndPage\n",
             "                } else if enableTasks && showsPageBeside {\n                    ViewThatFits { listAndPage; firstPage }\n"),
            ("            path = []\n            if id == SettingsDeepLink.tasksListOpenID", "            if id == SettingsDeepLink.tasksListOpenID"),
            ("            if rebuildsFirstPage { returnTo = id }\n", "            returnTo = id\n"),
        ], in: settings) { Self.layoutProblems(settings: $0, overview: overview) }
    }

    // MARK: - The page and its header

    /// Tasks leads with its overview and its settings follow, the switch first, where the gear lands; its header carries
    /// the gear and New task, the page's one verb, with ⌘N; the hidden ⌘N button the page used to carry is gone; and the
    /// verb's press reaches the page, which opens New Task.
    static func wiringProblems(settings: String, view: String, overview: String) -> [String] {
        var problems: [String] = []
        let page = pagePart(of: settings)
        if SettingsDesignSystemRulesTests.matches(of: #"SettingsProductPage\(settingsTitle: String\(localized: "Tasks settings"\)\) \{\s*TasksOverview\("#, in: page).count != 1 {
            problems.append("Tasks does not lead with its overview")
        }
        let settingsBlock = body(after: "} settings:", in: page)
        if !settingsBlock.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("optionsSection") {
            problems.append("the settings do not start with the Tasks switch, where the gear lands")
        }
        if !body(after: "private var optionsSection: some View", in: page).contains(".settingsHighlight(id: SettingsDeepLink.tasksEnableHighlightID)") {
            problems.append("the Tasks switch does not carry the gear's landing")
        }
        if !SettingsDesignSystemRulesTests.code(view).contains("SettingsForm(tab: .tasks, actions: AnyView(TasksHeaderActions())) {") {
            problems.append("Tasks' header has no actions")
        }
        let header = body(after: "struct TasksHeaderActions: View", in: SettingsDesignSystemRulesTests.code(overview))
        if SettingsDesignSystemRulesTests.matches(of: #"Button\("New task"\) \{ Self\.requestNewTask\(\) \}\s*\.buttonStyle\(SettingsButtonStyle\(\.primary\)\)\s*\.keyboardShortcut\("n", modifiers: \.command\)"#,
                                                   in: header).count != 1 {
            problems.append("New task is not the header's primary verb with ⌘N")
        }
        if !header.contains("requestAgentStatusNavigation(highlightID: SettingsDeepLink.tasksEnableHighlightID)") {
            problems.append("the gear does not go to the first settings row")
        }
        if page.contains(".keyboardShortcut(") || page.contains(".opacity(0)") {
            problems.append("the page keeps a hidden ⌘N button of its own beside the header's verb")
        }
        if !body(after: ".onReceive(NotificationCenter.default.publisher(for: .tasksNewTaskRequested))", in: page)
            .contains("sheet = .newTask(listFilter: newTaskListFilter)") {
            problems.append("New task's press does not open New Task")
        }
        return problems
    }

    func testTasksIsAProductPageWithItsVerb() throws {
        let settings = try Self.source(Self.settingsPath)
        let view = try Self.source(Self.viewPath)
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.wiringProblems(settings: settings, view: view, overview: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("            TasksOverview(data: tasks,", "            EmptyView()\n            TasksOverview(data: tasks,"),
            ("            optionsSection\n            if enableTasks {", "            if enableTasks {"),
            ("            .settingsHighlight(id: SettingsDeepLink.tasksEnableHighlightID)\n", "\n"),
            ("        .settingsPageTitle(", "        .background { Button(\"New Task\") {}.keyboardShortcut(\"n\", modifiers: .command).opacity(0) }\n        .settingsPageTitle("),
            ("sheet = .newTask(listFilter: newTaskListFilter)", "sheet = nil"),
        ], in: settings) { Self.wiringProblems(settings: $0, view: view, overview: overview) }
        SettingsDesignSystemRulesTests.assertCaught([(", actions: AnyView(TasksHeaderActions())", "")], in: view) {
            Self.wiringProblems(settings: settings, view: $0, overview: overview)
        }
        SettingsDesignSystemRulesTests.assertCaught([
            ("                    .keyboardShortcut(\"n\", modifiers: .command)\n", ""),
            ("                    .buttonStyle(SettingsButtonStyle(.primary))\n                    .keyboardShortcut",
             "                    .keyboardShortcut"),
            ("highlightID: SettingsDeepLink.tasksEnableHighlightID)", "highlightID: SettingsDeepLink.tasksSourcesHighlightID)"),
        ], in: overview) { Self.wiringProblems(settings: settings, view: view, overview: $0) }
    }

    // MARK: - Plumbing

    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
