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

/// A name typed in the timer tab becomes a task, the bar's typed search, the running task's form,
/// and a countdown that follows its estimate (David, 2026-10-23). Views and managers outside the
/// logic target, so the wiring is read from the source (the `TimerSideColumnRulesTests` idiom):
///
/// - the session knows its task (`sessionTaskID`), set and cleared with it; a name or length
///   update touches only its own session, and a new length never rings or sends an event; the tick
///   never rings for a session an estimate edit already finished;
/// - only a session `start(_:)` sized from the estimate follows it (`trackedAtStart`); a block (a
///   preset, a typed length) never does, rings like a preset, and is named and keyed like a task;
///   only the user's estimate edit retargets, and a rename renames the running session;
/// - a typed start waits for the task file like a reminder's Start, after it in each place, and
///   "Show local" turns on only where a task is added;
/// - a preset with a form open starts what the form shows, never `start(_:)`; a picked task never
///   falls back to making or reusing one;
/// - `NotchTimerView` builds the task list, offers the typed search and draws a pick only behind
///   `isTasksPageAvailable`, clears the stored name explicitly on every start, and closes the
///   running task's form when its session ends, is replaced, or runs out;
/// - the form's typed search covers its rows first and then lies over them, Escape and Return
///   close it before they leave or add, and a pick opens the task's edit;
/// - the closed notch drops its finished label when a session leaves overtime;
/// - paused in overtime, every timer surface still offers Resume.
///
/// Each detector has a planted-offender test, so a scanner that stops matching fails instead of
/// passing vacuously.
final class TimerTaskSessionRulesTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    static let timerPath = "Kannu/managers/TimerManager.swift"
    static let managerPath = "Kannu/managers/Tasks/TasksManager.swift"
    static let formPath = "Kannu/components/Notch/TimerTaskForm.swift"
    static let notchPath = "Kannu/components/Notch/NotchTimerView.swift"
    static let activityPath = "Kannu/components/Timer/TimerLiveActivity.swift"
    static let resumePaths = [
        "Kannu/components/Notch/NotchTimerView.swift",
        "Kannu/components/Timer/TimerControlOverlay.swift",
        "Kannu/components/LockScreen/LockScreenTimerWidget.swift",
        "Kannu/components/Timer/TimerPopover.swift",
    ]

    // MARK: - The rules, on the real sources

    func testTheSessionKnowsItsTaskAndANewLengthNeverRings() throws {
        XCTAssertEqual(Self.timerProblems(try Self.code(Self.timerPath)), [])
    }

    func testOnlyASessionSizedFromTheEstimateFollowsIt() throws {
        XCTAssertEqual(Self.followProblems(try Self.code(Self.managerPath)), [])
    }

    func testATypedStartWaitsForTheFileAndShowsLocalOnlyWhenItAdds() throws {
        XCTAssertEqual(Self.typedStartProblems(try Self.code(Self.managerPath)), [])
    }

    func testAPresetWithAFormOpenStartsWhatTheFormShows() throws {
        XCTAssertEqual(Self.formStartProblems(try Self.code(Self.formPath)), [])
    }

    func testTheTimerTabGatesTheTaskListAndClearsWhatItStarted() throws {
        XCTAssertEqual(Self.notchProblems(try Self.code(Self.notchPath)), [])
    }

    func testTheFormsTypedSearchCoversThenLiesOverAndClosesFirst() throws {
        XCTAssertEqual(Self.formListProblems(try Self.code(Self.formPath)), [])
    }

    func testTheClosedNotchDropsItsFinishedLabelLeavingOvertime() throws {
        XCTAssertEqual(Self.activityProblems(try Self.code(Self.activityPath)), [])
    }

    func testPausedInOvertimeEverySurfaceOffersResume() throws {
        for path in Self.resumePaths {
            XCTAssertEqual(Self.resumeProblems(try Self.code(path)), [], path)
        }
    }

    /// The title key and the "starts with" group fold with no locale (`TaskItem.nameKey`,
    /// `TaskSearch`), so reuse and the typed search never depend on the Mac's language.
    func testTitleFoldingIgnoresTheLocale() throws {
        for path in ["Kannu/managers/Tasks/TaskModels.swift", "Kannu/managers/Tasks/TaskSearch.swift"] {
            XCTAssertEqual(Self.foldingProblems(try Self.code(path)), [], path)
        }
    }

    /// A covered duration box is disabled for real: SwiftUI's `.disabled` does not reach the
    /// AppKit field by itself, so the representable mirrors it.
    func testACoveredDurationBoxIsDisabled() throws {
        XCTAssertEqual(Self.digitFieldProblems(try Self.code("Kannu/components/Notch/DurationDigitField.swift")), [])
    }

    // MARK: - Planted offenders

    func testTheTimerScannerCatchesAPlantedOffender() {
        let planted = """
        func startTimer(duration: TimeInterval) { sessionTaskID = taskID }
        func adoptExternalTimer() { sessionTaskID = nil }
        private func resetTimer() { sessionTint = nil }
        func updateSessionName(_ name: String, session: UUID) { timerName = name }
        func updateSessionLength(_ length: Int, session: UUID) { guard session == sessionID else { return }; playTimerSound() }
        } else if self.remainingTime == 0 {
        """
        XCTAssertEqual(Self.timerProblems(planted), [
            "resetTimer does not clear sessionTaskID",
            "updateSessionName does not check its session",
            "updateSessionLength plays the sound or sends an event",
            "the tick can ring for a session an estimate edit finished",
        ])
    }

    func testTheFollowScannerCatchesAPlantedOffender() {
        let planted = """
        func start(_ taskID: UUID) -> Bool { pendingLink = (timer.sessionID, taskID, tracked); startTimer(taskID: task.id) }
        func startBlock(_ taskID: UUID) -> Bool {
            timer.startTimer(name: TimerSessionName.resolved(typed: task.title, fallback: f), playsSoundOnFinish: Defaults[.tasksSoundAtEstimate],
                             taskKey: TaskDetailSummary.shortKey(for: task), taskID: task.id)
            pendingLink = (timer.sessionID, taskID, tracked)
        }
        func renameTask(_ taskID: UUID, to title: String) -> Bool { if title != task.title { update(taskID) { $0.title = title } } }
        func setEstimate(_ seconds: Int?, for taskID: UUID) { update(taskID) { } }
        func merge() { refreshTimedLength(id) }
        private func refreshTimedLength(_ taskID: UUID) { }
        """
        XCTAssertEqual(Self.followProblems(planted), [
            "startBlock follows the estimate or rings at it",
            "only setEstimate may retarget the countdown",
            "a renamed task leaves its running session's name",
        ])
    }

    func testTheTypedStartScannerCatchesAPlantedOffender() {
        let planted = """
        func startBlock(_ taskID: UUID) -> Bool { showLocalTasks() }
        func startTyped(_ typed: String) { switch loadState { case .loading: pendingTypedStart = (typed) } }
        private func startTypedNow(_ typed: String) -> Bool { showLocalTasks(); if let added = addTask(title: typed, estimateSeconds: nil) { } }
        func addTask(from draft: TaskFormDraft) -> UUID? { forgetFormDraft(editing: nil) }
        func startFromReminder(_ taskID: UUID) { pendingReminderStart?.completion() }
        private func load() async { loadState = .failed(reason); if let pending = pendingReminderStart { pending.completion() } }
        private func apply(_ loaded: TasksFile) { if let pending = pendingReminderStart { pending.completion() } }
        """
        XCTAssertEqual(Self.typedStartProblems(planted), [
            "a reminder's Start does not drop a waiting typed start",
            "a load failure leaves a waiting typed start unanswered",
            "the file being read never runs a waiting typed start",
            "Show local turns on for a reuse or a pick",
            "Add no longer shows local tasks",
        ])
    }

    func testTheFormStartScannerCatchesAPlantedOffender() {
        let planted = """
        @MainActor static func startFromForm(_ mode: TimerTaskFormMode) -> TimerFormStart {
            manager.addTask(from: draft); manager.start(id); return .started
        }
        @MainActor static func startNamed(typed: String, pick: TimerSessionPick?) {
            if let taskID = pick?.taskID {
                manager.startTyped(typed, reuse: false)
                return
            }
        }
        """
        XCTAssertEqual(Self.formStartProblems(planted), [
            "a preset with a form open skips the shared add, the shared save, or the block",
            "an untouched edit form does not time the task it shows",
            "a preset with a form open starts through start(_:), which follows the estimate",
            "an unreadable estimate or a gone task is not answered",
            "a held preset does not move focus to the estimate",
            "a picked task can fall back to making or reusing one",
        ])
    }

    func testTheNotchScannerCatchesAPlantedOffender() {
        let planted = """
        .onAppear { TimerTaskForm.prepareForTypedStart() }
        private func warmTasks(ifNamed text: String) { TimerTaskForm.prepareForTypedStart() }
        private func startSession() { TimerTaskForm.startNamed(typed: typed); pendingSessionName = "" }
        private func taskStarted() { pendingSessionName = "" }
        private var wantsSuggestions: Bool { sessionPick == nil }
        TimerTaskSuggestions(typed: pendingSessionName)
        TimerTaskPickDot(taskID: taskID)
        private func pickLost() { sessionPick = nil }
        """
        XCTAssertEqual(Self.notchProblems(planted), [
            "the task list is built without isTasksPageAvailable, or outside warmTasks",
            "a typed start skips isTasksPageAvailable",
            "an edit whose task is gone falls through to the bar",
            "the typed search shows with tasks off",
            "a pick is drawn with tasks off",
            "startSession leaves the stored name or the pick behind",
            "taskStarted leaves the stored name or the pick behind",
            "a lost pick does not give the bar back what was typed",
            "the running task's form outlives its session",
            "the bar's keys do not close the typed search first",
        ])
    }

    func testTheFormListScannerCatchesAPlantedOffender() {
        let planted = """
        GoldenRow(spacing: M.taskFormRowSpacing) {
        }
        .overlay(alignment: .top) { TimerTaskSuggestions() }
        .coveredBySuggestions(showsTitleSuggestions)
        .zIndex(2)
        private var wantsTitleSuggestions: Bool { focused == .title }
        private func exitTitle() { dismiss() }
        private func submitTitle() { submit() }
        private func pickTitleSuggestion(_ row: Row) { close() }
        """
        XCTAssertEqual(Self.formListProblems(planted), [
            "the list is covered with the rows (cover first, then the overlay)",
            "the reminder row is not covered",
            "an edit's title offers the typed search",
            "Escape or Return leaves before closing the list",
            "a picked task does not open its edit",
            "the list does not start closed on the opening title",
        ])
    }

    func testTheActivityScannerCatchesAPlantedOffender() {
        let planted = """
        .onChange(of: timerManager.isFinished) { _, finished in if finished { showTransientLabel = true } }
        .onChange(of: timerManager.isOvertime) { _, overtime in if overtime { } else { hideFinishLabel() } }
        private func hideFinishLabel() { showTransientLabel = false }
        """
        XCTAssertEqual(Self.activityProblems(planted), [
            "leaving the finish leaves the closed notch's label pinned",
            "hideFinishLabel acts after a stop",
        ])
    }

    func testTheFoldingScannerCatchesAPlantedOffender() {
        XCTAssertEqual(Self.foldingProblems("text.folding(options: [.caseInsensitive], locale: .current)"),
                       ["a title is folded with a locale"])
        XCTAssertEqual(Self.foldingProblems("let x = 1"), ["no title folding found: the scan is vacuous"])
    }

    func testTheDigitFieldScannerCatchesAPlantedOffender() {
        XCTAssertEqual(Self.digitFieldProblems("func updateNSView(_ field: DigitTextField, context: Context) { field.ink = ink }"),
                       ["a covered duration box stays enabled"])
    }

    func testTheResumeScannerCatchesAPlantedOffender() {
        XCTAssertEqual(Self.resumeProblems("HStack { if !timerManager.isOvertime { PauseButton() } }"),
                       ["paused in overtime hides Resume"])
    }

    // MARK: - Detectors

    static func timerProblems(_ source: String) -> [String] {
        var problems: [String] = []
        if !(body(of: "func startTimer(", in: source)?.contains("sessionTaskID = taskID") ?? false) {
            problems.append("startTimer does not set sessionTaskID")
        }
        for name in ["func adoptExternalTimer(", "private func resetTimer("]
        where !(body(of: name, in: source)?.contains("sessionTaskID = nil") ?? false) {
            problems.append("\(name.replacingOccurrences(of: "private func ", with: "").replacingOccurrences(of: "func ", with: "").dropLast()) does not clear sessionTaskID")
        }
        for name in ["func updateSessionName(", "func updateSessionLength("]
        where !(body(of: name, in: source)?.contains("session == sessionID") ?? false) {
            problems.append("\(name.dropFirst(5).dropLast()) does not check its session")
        }
        if let length = body(of: "func updateSessionLength(", in: source),
           length.contains("playTimerSound") || length.contains("emit(") {
            problems.append("updateSessionLength plays the sound or sends an event")
        }
        if !source.contains("self.remainingTime == 0, !self.isFinished") {
            problems.append("the tick can ring for a session an estimate edit finished")
        }
        return problems
    }

    static func followProblems(_ source: String) -> [String] {
        var problems: [String] = []
        let start = body(of: "func start(_ taskID: UUID)", in: source) ?? ""
        if !(start.contains("pendingLink = (timer.sessionID, taskID, tracked)") && start.contains("taskID: task.id")) {
            problems.append("start(_:) does not record what it sized the session from")
        }
        let block = body(of: "func startBlock(", in: source) ?? ""
        if !block.contains("pendingLink = (timer.sessionID, taskID, nil)") || block.contains("tasksSoundAtEstimate") {
            problems.append("startBlock follows the estimate or rings at it")
        }
        if !(block.contains("TimerSessionName.resolved(typed: task.title") && block.contains("taskKey: TaskDetailSummary.shortKey(for: task)")
             && block.contains("taskID: task.id")) {
            problems.append("startBlock is not named, keyed and tied to its task like start(_:)")
        }
        let calls = source.components(separatedBy: "refreshTimedLength(").count - 1
        let estimate = body(of: "func setEstimate(", in: source) ?? ""
        // The declaration and the one call in setEstimate.
        if calls != 2 || !estimate.contains("refreshTimedLength(taskID)") {
            problems.append("only setEstimate may retarget the countdown")
        }
        let rename = body(of: "func renameTask(", in: source) ?? ""
        let renamed = rename.range(of: "if title != task.title").map { rename[$0.upperBound...].contains("refreshTimedName(taskID)") } ?? false
        if !renamed { problems.append("a renamed task leaves its running session's name") }
        return problems
    }

    static func typedStartProblems(_ source: String) -> [String] {
        var problems: [String] = []
        let typed = body(of: "func startTyped(", in: source) ?? ""
        if !(typed.contains(".loading") && typed.contains("pendingTypedStart = (")) {
            problems.append("a typed start before the file is read is not kept")
        }
        if !(body(of: "func startFromReminder(", in: source)?.contains("pendingTypedStart = nil") ?? false) {
            problems.append("a reminder's Start does not drop a waiting typed start")
        }
        if !after("typed.otherwise()", "pending.completion()", in: body(of: "private func load(", in: source) ?? "") {
            problems.append("a load failure leaves a waiting typed start unanswered")
        }
        if !after("startTypedNow(typed.typed", "pending.completion()", in: body(of: "private func apply(", in: source) ?? "") {
            problems.append("the file being read never runs a waiting typed start")
        }
        let now = body(of: "private func startTypedNow(", in: source) ?? ""
        let showsOnlyOnAdd = now.components(separatedBy: "showLocalTasks()").count == 2
            && after("showLocalTasks()", "addTask(title: typed", in: now)
        if !showsOnlyOnAdd || (body(of: "func startBlock(", in: source)?.contains("showLocalTasks()") ?? true) {
            problems.append("Show local turns on for a reuse or a pick")
        }
        if !(body(of: "func addTask(from draft: TaskFormDraft)", in: source)?.contains("showLocalTasks()") ?? false) {
            problems.append("Add no longer shows local tasks")
        }
        return problems
    }

    static func formStartProblems(_ source: String) -> [String] {
        var problems: [String] = []
        let start = body(of: "static func startFromForm(", in: source) ?? ""
        if !(start.contains("addTask(from:") && start.contains("applyEdits(") && start.contains("startBlock(")) {
            problems.append("a preset with a form open skips the shared add, the shared save, or the block")
        }
        if !start.contains("TaskFormDraft(editing: task)") {
            problems.append("an untouched edit form does not time the task it shows")
        }
        if start.contains(".start(") {
            problems.append("a preset with a form open starts through start(_:), which follows the estimate")
        }
        if !(start.contains("manager.requestEstimateFocus()") && start.contains("return .held") && start.contains("return .gone")) {
            problems.append("an unreadable estimate or a gone task is not answered")
        }
        if !source.contains(".onChange(of: manager.estimateFocusRequests)") {
            problems.append("a held preset does not move focus to the estimate")
        }
        let named = body(of: "static func startNamed(", in: source) ?? ""
        let pickBranch = named.range(of: "if let taskID = pick?.taskID {").flatMap { open -> Substring? in
            named.range(of: "return", range: open.upperBound..<named.endIndex).map { named[open.upperBound..<$0.lowerBound] }
        } ?? ""
        if !(pickBranch.contains("startBlock(") && pickBranch.contains("otherwise()")) || pickBranch.contains("startTyped(") {
            problems.append("a picked task can fall back to making or reusing one")
        }
        return problems
    }

    static func notchProblems(_ source: String) -> [String] {
        var problems: [String] = []
        let warm = body(of: "private func warmTasks(", in: source) ?? ""
        if source.components(separatedBy: "TimerTaskForm.prepareForTypedStart()").count != 2
            || !warm.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("guard isTasksPageAvailable") {
            problems.append("the task list is built without isTasksPageAvailable, or outside warmTasks")
        }
        let session = body(of: "private func startSession(", in: source) ?? ""
        if !after("TimerTaskForm.startNamed(", "if isTasksPageAvailable", in: session) {
            problems.append("a typed start skips isTasksPageAvailable")
        }
        let gone = session.range(of: "case .gone:").map { session[$0.upperBound...].prefix(160) } ?? ""
        if !gone.contains("return") {
            problems.append("an edit whose task is gone falls through to the bar")
        }
        let wants = body(of: "private var wantsSuggestions: Bool", in: source) ?? ""
        if !wants.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("isTasksPageAvailable &&")
            || source.components(separatedBy: "TimerTaskSuggestions(").count != 2
            || !source.contains("if wantsSuggestions {\n                TimerTaskSuggestions(") {
            problems.append("the typed search shows with tasks off")
        }
        if !source.contains("if isTasksPageAvailable, let sessionPick {")
            || !source.contains("if isTasksPageAvailable, let taskID = sessionPick?.taskID {\n                TimerTaskPickInfo(") {
            problems.append("a pick is drawn with tasks off")
        }
        for name in ["private func startSession(", "private func taskStarted("] {
            let text = body(of: name, in: source) ?? ""
            if !(text.contains("timerManager.typedSessionName = \"\"") && text.contains("sessionPick = nil")) {
                problems.append("\(name.dropFirst(13).dropLast()) leaves the stored name or the pick behind")
            }
        }
        let lost = body(of: "private func pickLost(", in: source) ?? ""
        if !(lost.contains("sessionPick = nil") && lost.contains("pendingSessionName = pick.typed")) {
            problems.append("a lost pick does not give the bar back what was typed")
        }
        let changes = SwiftModifierScan.modifiers(".onChange", in: source)
        let closesOnReplace = changes.contains { $0.hasPrefix(".onChange(of: timerManager.sessionTaskID)") && $0.contains("taskForm = nil") }
        let closesOnFinish = changes.contains { $0.hasPrefix(".onChange(of: timerManager.isFinished)") && $0.contains("taskForm = nil") }
        let shown = body(of: "private var shownTaskForm: TimerTaskFormMode?", in: source) ?? ""
        if !(closesOnReplace && closesOnFinish && source.contains("if let taskForm = shownTaskForm")
             && shown.contains("runningTaskID.map(TimerTaskFormMode.edit) == taskForm")) {
            problems.append("the running task's form outlives its session")
        }
        let field = body(of: "private var sessionNameField: some View", in: source) ?? ""
        if !(field.contains(".onSubmit(submitName)") && field.contains(".onExitCommand { suggestions.close(on: pendingSessionName) }")
             && field.contains("suggestionListKeys(isActive: showsSuggestions")
             && source.contains(".offset(y: -TimerComposerMetrics.nameFieldSpacing)")) {
            problems.append("the bar's keys do not close the typed search first")
        }
        return problems
    }

    static func formListProblems(_ source: String) -> [String] {
        var problems: [String] = []
        let row = source.range(of: "GoldenRow(spacing: M.taskFormRowSpacing) {").map { source[$0.upperBound...] } ?? ""
        let cover = row.range(of: ".coveredBySuggestions(showsTitleSuggestions)")?.lowerBound
        let overlay = row.range(of: ".overlay(alignment: .top)")?.lowerBound
        let lift = row.range(of: ".zIndex(2)")?.lowerBound
        if !(cover != nil && overlay != nil && lift != nil && cover! < overlay! && overlay! < lift!) {
            problems.append("the list is covered with the rows (cover first, then the overlay)")
        }
        if !source.contains(".coveredBySuggestions(showsTitleSuggestions)\n            .frame(height: M.taskFormRowHeight)\n            .zIndex(1)") {
            problems.append("the reminder row is not covered")
        }
        if !(body(of: "private var wantsTitleSuggestions: Bool", in: source)?.contains("draft.isNew") ?? false) {
            problems.append("an edit's title offers the typed search")
        }
        let exit = body(of: "private func exitTitle(", in: source) ?? ""
        let submit = body(of: "private func submitTitle(", in: source) ?? ""
        if !(exit.contains("titleSuggestions.close(on:") && exit.contains("dismiss()")
             && submit.contains("titleSuggestions.highlightedRow") && submit.contains("submit()")) {
            problems.append("Escape or Return leaves before closing the list")
        }
        let pick = body(of: "private func pickTitleSuggestion(", in: source) ?? ""
        if !(pick.contains("open(.edit(") && pick.contains("typedSessionName = \"\"")) {
            problems.append("a picked task does not open its edit")
        }
        if !source.contains("TaskSuggestionState(closedOn: opening.title)") {
            problems.append("the list does not start closed on the opening title")
        }
        return problems
    }

    static func activityProblems(_ source: String) -> [String] {
        var problems: [String] = []
        let changes = SwiftModifierScan.modifiers(".onChange", in: source)
        for flag in ["isFinished", "isOvertime"] {
            let observers = changes.filter { $0.hasPrefix(".onChange(of: timerManager.\(flag))") }
            if observers.isEmpty || observers.contains(where: { !$0.contains("hideFinishLabel()") }) {
                problems.append("leaving the finish leaves the closed notch's label pinned")
                break
            }
        }
        if !(body(of: "private func hideFinishLabel(", in: source)?.contains("guard timerManager.isTimerActive") ?? false) {
            problems.append("hideFinishLabel acts after a stop")
        }
        return problems
    }

    static func foldingProblems(_ source: String) -> [String] {
        let calls = source.components(separatedBy: ".folding(options:").dropFirst()
        if calls.isEmpty { return ["no title folding found: the scan is vacuous"] }
        let localized = calls.contains { call in
            let line = call.prefix { $0 != "\n" }
            return !line.contains("locale: nil")
        }
        return localized ? ["a title is folded with a locale"] : []
    }

    static func digitFieldProblems(_ source: String) -> [String] {
        let update = body(of: "func updateNSView(", in: source) ?? ""
        return update.contains("context.environment.isEnabled") && update.contains("field.isEnabled = enabled")
            ? [] : ["a covered duration box stays enabled"]
    }

    static func resumeProblems(_ source: String) -> [String] {
        if source.contains("if !timerManager.isOvertime {") || !source.contains("!timerManager.isOvertime || timerManager.isPaused") {
            return ["paused in overtime hides Resume"]
        }
        return []
    }

    // MARK: - Scanning

    private static func code(_ path: String) throws -> String {
        let text = try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The balanced braces after the first `opener`: a function's or property's body.
    static func body(of opener: String, in text: String) -> String? {
        guard let range = text.range(of: opener),
              let open = text[range.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        repeat {
            if text[index] == "{" { depth += 1 } else if text[index] == "}" { depth -= 1 }
            index = text.index(after: index)
        } while index < text.endIndex && depth > 0
        return String(text[text.index(after: open)..<text.index(before: index)])
    }

    /// Whether `later` appears, and after the first `earlier`.
    private static func after(_ later: String, _ earlier: String, in text: String) -> Bool {
        guard let first = text.range(of: earlier), let second = text.range(of: later) else { return false }
        return first.lowerBound < second.lowerBound
    }
}
