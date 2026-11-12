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

/// Brain › Timer is a product page with live data: a running timer publishes three changes a second, and Brain's content
/// is built once and outlives its window (docs/REGRESSIONS.md, entry 22). So it keeps Agents' live-data contract
/// (docs/SETTINGS.md, "Live data"), its time moves only with the manager's own tick, and it starts, pauses and stops a
/// timer only on a press. Read from the source, clause by clause, each rule checked against planted offenders, as
/// `UsagePageLiveDataRulesTests` does for Usage.
final class TimerPageLiveDataRulesTests: XCTestCase {

    private static let overviewPath = "Kannu/components/Settings/TimerOverview.swift"
    private static let sheetPath = "Kannu/components/Settings/TimerPresetSheet.swift"
    private static let settingsPath = "Kannu/components/Settings/TimerSettings.swift"
    private static let viewPath = "Kannu/components/Settings/SettingsView.swift"

    // MARK: - Clause 1: throttled and scoped

    /// The page's subscription: the manager's changes, at most twice a second.
    private static let pageFeed = #"TimerManager\.shared\.objectWillChange\s*\.throttle\(for: \.milliseconds\(500\), scheduler: RunLoop\.main, latest: true\)\s*\.values"#
    /// The header's: whether a timer runs, passed on only when that changes.
    private static let headerFeed = #"TimerManager\.shared\.\$isTimerActive\s*\.removeDuplicates\(\)\s*\.values"#
    /// What the manager knows about the running timer, read through the shared manager or a local name for it.
    private static let stateRead = #"(?<![\w.])(?:TimerManager\.shared|manager|timerManager)\.(?:isTimerActive|timerName|totalDuration|remainingTime|elapsedTime|isPaused|isFinished|isOvertime|lastUpdated|activePresetId|activePreset|sessionTint|sessionTaskKey|sessionTaskID|activeSource|progress|sessionAccent|formattedRemainingTime|formattedElapsedTime|formattedTotalDuration|isExternalTimerActive|hasManualTimerRunning|allowsManualInteraction|isRunning|statusText|timerColor|currentColor|timerNSColor)\b"#
    /// The manager reached any way but the two feeds, the one copy or a start: a local name for it, a sink, a read.
    private static let otherReach = #"TimerManager\.shared(?!\.objectWillChange\b|\.\$isTimerActive\b|\.startTimer\(|\))"#
    /// The places that may read it: the copy's `init`, and what three presses call, which read it at the press: Pause or
    /// Resume, Stop, and Start timer's check that no timer runs.
    private static let readers = ["init(_ timerManager: TimerManager) {", "private static func togglePause() {",
                                  "private static func stop() {", "private static func timerRunsNow() -> Bool {"]

    /// Two subscriptions, each to what it needs, and nothing else of the manager: no observer, no `onReceive`, no sink,
    /// no local name for it. Its state is read in one copy, `TimerPageData`'s `init`, assigned only when it changed, and
    /// at a press, never in `body`.
    static func followProblems(in overview: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(overview)
        var problems: [String] = []
        if SettingsDesignSystemRulesTests.matches(of: pageFeed, in: code).count != 1 {
            problems.append("the timer does not come through one subscription throttled to 500 ms")
        }
        if SettingsDesignSystemRulesTests.matches(of: headerFeed, in: code).count != 1 {
            problems.append("the header's running state does not come through one subscription that drops repeats")
        }
        if code.components(separatedBy: "TimerManager.shared.$").count - 1 != 1
            || code.components(separatedBy: "TimerManager.shared.objectWillChange").count - 1 != 1 {
            problems.append("the manager is followed outside the two subscriptions")
        }
        if !SettingsDesignSystemRulesTests.matches(of: #"@(?:ObservedObject|StateObject|EnvironmentObject)[^\n]*TimerManager"#, in: code).isEmpty {
            problems.append("the page observes TimerManager whole")
        }
        if code.range(of: #"\.onReceive\([^\n]*TimerManager|TimerManager[^\n]*\.sink"#, options: .regularExpression) != nil {
            problems.append("TimerManager is followed outside the page's tasks")
        }
        if code.components(separatedBy: "TimerPageData(TimerManager.shared)").count - 1 != 1 {
            problems.append("the page copies the manager in more than one place")
        }
        // Assigned only on a change: a copy that always assigns redraws on every trailing emission of the throttle.
        let copy = AgentsPageLiveDataRulesTests.body(after: "private func copyFromManager() {", in: code) ?? ""
        if !copy.contains("if latest != data { data = latest }") || code.components(separatedBy: "data = latest").count - 1 != 1 {
            problems.append("the copy is assigned whether or not it changed")
        }
        var outside = code
        for reader in readers {
            guard let inside = AgentsPageLiveDataRulesTests.body(after: reader, in: outside),
                  let range = outside.range(of: inside) else {
                problems.append("\(reader) is gone")
                continue
            }
            outside.removeSubrange(range)
        }
        for read in SettingsDesignSystemRulesTests.matches(of: stateRead, in: outside) {
            problems.append("the page reads \(read) outside its copy and its presses")
        }
        if !SettingsDesignSystemRulesTests.matches(of: otherReach, in: outside).isEmpty {
            problems.append("the page reaches the manager outside its feeds, its copy and its starts")
        }
        return problems
    }

    func testTheTimerComesThroughThrottledScopedSubscriptions() throws {
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.followProblems(in: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            (".throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n                .values", ".values"),
            (".milliseconds(500)", ".milliseconds(50)"),
            (".removeDuplicates()\n                .values", ".values"),
            ("    @State private var data = TimerPageData()",
             "    @State private var data = TimerPageData()\n    @ObservedObject private var timer = TimerManager.shared"),
            ("        .onAppear {\n            #if DEBUG", "        .onReceive(TimerManager.shared.$remainingTime) { _ in }\n        .onAppear {\n            #if DEBUG"),
            ("Text(verbatim: data.time)", "Text(verbatim: TimerManager.shared.formattedRemainingTime())"),
            ("isRunning: data.isActive && data.presetID == preset.id", "isRunning: TimerManager.shared.activePresetId == preset.id"),
            // A second copy, made in `body`, and a local name for the manager read there.
            ("                    TimerRunningCard(data: data, refresh: { copyFromManager() })",
             "                    TimerRunningCard(data: TimerPageData(TimerManager.shared), refresh: { copyFromManager() })"),
            ("        Button {\n            TimerManager.shared.startTimer(",
             "        let manager = TimerManager.shared\n        let _ = manager.remainingTime\n        Button {\n            TimerManager.shared.startTimer("),
            // A name the state list does not know, and a sink through it.
            ("    var body: some View {\n        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {",
             "    var body: some View {\n        let m = TimerManager.shared\n        let _ = m.objectWillChange.sink { _ in }\n        VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {"),
            // A copy assigned every time.
            ("if latest != data { data = latest }", "data = latest"),
        ], in: overview, by: Self.followProblems)
    }

    // MARK: - Clause 2: stopped while Brain is not on screen

    /// A `Task` started inside a `.task` is not its child: it outlives the cancel, one more each time Brain comes back.
    private static let unstructuredTask = #"\bTask\s*(?:\{|\(|\.detached)"#

    /// Both subscriptions are `.task`s keyed on Brain's visibility, each returning at once while it is false, before it
    /// reads or follows the manager, with no `Task` inside. `AgentsPageLiveDataRulesTests` holds the flag itself.
    static func offScreenProblems(in overview: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(overview)
        var problems: [String] = []
        let opener = ".task(id: visibility.isOnScreen) {"
        // Openers only: `data.taskKey` is not a task.
        if SettingsDesignSystemRulesTests.matches(of: #"\.task\s*[({]"#, in: code).count != 2
            || code.components(separatedBy: opener).count - 1 != 2 {
            problems.append("a subscription is not keyed on Brain's visibility")
        }
        for (index, part) in code.components(separatedBy: opener).dropFirst().enumerated() {
            let task = AgentsPageLiveDataRulesTests.body(after: "", in: "{" + part) ?? ""
            guard let guardRange = task.range(of: "guard visibility.isOnScreen else { return }"),
                  let read = task.range(of: #"TimerManager\.shared|copyFromManager\(\)"#, options: .regularExpression),
                  guardRange.lowerBound < read.lowerBound else {
                problems.append("subscription \(index + 1) runs while Brain is off screen")
                continue
            }
        }
        if code.range(of: unstructuredTask, options: .regularExpression) != nil {
            problems.append("a Task outlives its .task")
        }
        return problems
    }

    func testTheSubscriptionsStopWhileBrainIsOffScreen() throws {
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.offScreenProblems(in: overview), [])
        let headerLoop = "            for await active in TimerManager.shared.$isTimerActive\n"
            + "                .removeDuplicates()\n"
            + "                .values {\n                running = active\n            }\n"
        SettingsDesignSystemRulesTests.assertCaught([
            (".task(id: visibility.isOnScreen) {", ".task {"),
            ("            guard visibility.isOnScreen else { return }\n            // Back on screen", "            // Back on screen"),
            ("            guard visibility.isOnScreen else { return }\n            for await active", "            for await active"),
            (headerLoop, "            Task {\n" + headerLoop + "            }\n"),
            // The read on returning, moved ahead of the check.
            ("            guard visibility.isOnScreen else { return }\n            // Back on screen: what changed while Brain was not, which `objectWillChange` will not send again.\n            copyFromManager()\n",
             "            copyFromManager()\n            guard visibility.isOnScreen else { return }\n"),
        ], in: overview, by: Self.offScreenProblems)
    }

    // MARK: - Clause 3: no clock of its own

    /// What keeps time by itself, on the page, in its sheet or in its settings: a clock here would be a second one that
    /// could disagree with the notch's, and would tick on while a timer stood paused. A `Text` with a relative or timer
    /// style, or a `timerInterval`, is a clock too.
    private static let clocks = ["TimelineView", "Timer.scheduledTimer", "Timer.publish", "Timer(timeInterval:", "Timer(fire:",
                                 "Timer.init(", ".repeatForever", "phaseAnimator", "keyframeAnimator", ".symbolEffect(", "DispatchSource",
                                 "asyncAfter", "Task.sleep", "ClaudeTurnTokenFollower", "timerInterval:"]
    /// What moves by itself on the page and in its sheet. The settings keep the one bounded ease they had.
    private static let motions = ["withAnimation", ".animation(", ".contentTransition(", "ProgressView"]

    static func clockProblems(overview: String, sheet: String, settings: String) -> [String] {
        var problems: [String] = []
        for (name, source, banned) in [("the page", overview, clocks + motions), ("its sheet", sheet, clocks + motions),
                                       ("its settings", settings, clocks)] {
            let code = SettingsDesignSystemRulesTests.code(source)
            problems += banned.filter { code.contains($0) }.map { "\(name) keeps a clock or a motion of its own: \($0)" }
            if code.range(of: #"style:\s*\.(?:relative|timer|offset)\b"#, options: .regularExpression) != nil {
                problems.append("\(name) keeps a clock of its own: a Text that counts")
            }
        }
        return problems
    }

    func testThePageKeepsNoClockOfItsOwn() throws {
        let overview = try Self.source(Self.overviewPath)
        let sheet = try Self.source(Self.sheetPath)
        let settings = try Self.source(Self.settingsPath)
        XCTAssertEqual(Self.clockProblems(overview: overview, sheet: sheet, settings: settings), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("            if !isOn {", "            TimelineView(.periodic(from: .now, by: 1)) { _ in EmptyView() }\n            if !isOn {"),
            ("            if !isOn {", "            Text(Date(), style: .timer)\n            if !isOn {"),
            ("            if !isOn {", "            Text(timerInterval: Date()...Date())\n            if !isOn {"),
            ("                        .monospacedDigit()", "                        .monospacedDigit()\n                        .contentTransition(.numericText())"),
            ("    private func copyFromManager() {", "    private func copyFromManager() {\n        withAnimation {}"),
            ("                Circle()\n                    .fill(data.accent ?? SettingsTheme.accent)",
             "                Circle()\n                    .phaseAnimator([0, 1]) { dot, _ in dot }\n                    .fill(data.accent ?? SettingsTheme.accent)"),
        ], in: overview) { Self.clockProblems(overview: $0, sheet: sheet, settings: settings) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("            SettingsColorPickerRow(", "            TimelineView(.periodic(from: .now, by: 1)) { _ in EmptyView() }\n            SettingsColorPickerRow("),
            ("if isNew { nameFocused = true }", "if isNew { withAnimation { nameFocused = true } }"),
        ], in: sheet) { Self.clockProblems(overview: overview, sheet: $0, settings: settings) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("            timerFeatureSection\n", "            timerFeatureSection\n            Text(Date(), style: .relative)\n"),
            ("        .navigationTitle(\"Timer\")", "        .onAppear { _ = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in } }\n        .navigationTitle(\"Timer\")"),
        ], in: settings) { Self.clockProblems(overview: overview, sheet: sheet, settings: $0) }
    }

    // MARK: - Clause 4: only on a press

    /// What changes the timer, every one of `TimerManager`'s own calls that the notch's popover makes, and nothing else.
    private static let mutators = ["startTimer(", "pauseTimer(", "resumeTimer(", "stopTimer(", "togglePause(", "stop("]
    private static let banned = ["forceStopTimer(", "startDemoTimer(", "adoptExternalTimer(", "endExternalTimer(", "updateSessionLength(",
                                 "updateSessionName(", "updateSessionTint(", "completeExternalTimer("]
    /// Every hook that runs without a press.
    private static let hooks = [".onAppear {", ".onDisappear {", ".task(id: visibility.isOnScreen) {", ".onChange(of:", ".onReceive("]

    /// Start timer and a tile start a timer, Pause or Resume and Stop act on it, each in its own button's action and
    /// nowhere else: never as the page appears or goes, follows the manager or sees a change. Each press reads the timer
    /// again at once. Start timer is off while a timer runs, as the popover hides its own start then; a 0:00 preset does
    /// not start; Pause or Resume shows unless the timer runs in overtime.
    static func pressProblems(in overview: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(overview)
        var problems: [String] = []
        let start = "TimerManager.shared.startTimer("
        if code.components(separatedBy: "startTimer(").count - 1 != 2 {
            problems.append("a timer starts somewhere other than Start timer and a tile")
        }
        if !(AgentsPageLiveDataRulesTests.body(after: #"Button("Start timer") {"#, in: code) ?? "").contains(start) {
            problems.append("Start timer's press does not start the timer")
        }
        let tile = AgentsPageLiveDataRulesTests.body(after: "private struct TimerPresetTile: View {", in: code) ?? ""
        let tilePress = AgentsPageLiveDataRulesTests.body(after: "Button {", in: tile) ?? ""
        if !tilePress.contains(start) {
            problems.append("a tile's press does not start its preset")
        }
        for (call, count) in [("Self.togglePause()", 1), ("Self.stop()", 1), ("pauseTimer()", 1), ("resumeTimer()", 1), ("stopTimer()", 1)]
            where code.components(separatedBy: call).count - 1 != count {
            problems.append("\(call) is called somewhere other than its one button")
        }
        let toggle = AgentsPageLiveDataRulesTests.body(after: "private static func togglePause() {", in: code) ?? ""
        if !toggle.contains("manager.isPaused ? manager.resumeTimer() : manager.pauseTimer()") {
            problems.append("Pause or Resume does not act on the manager as it is at the press")
        }
        // Each press reads the timer again at once, so the card never shows the old state for the throttle's half second.
        let card = AgentsPageLiveDataRulesTests.body(after: "private struct TimerRunningCard: View {", in: code) ?? ""
        let cardPresses = bodies(after: "Button {", in: card)
        if cardPresses.count != 2 || cardPresses.contains(where: { !$0.contains("refresh()") }) || !tilePress.contains("refresh()")
            || code.components(separatedBy: "refresh: { copyFromManager() }").count - 1 != 2 {
            problems.append("a press does not read the timer again at once")
        }
        if !(AgentsPageLiveDataRulesTests.body(after: "if data.offersPause {", in: card) ?? "").contains("Self.togglePause()") {
            problems.append("Pause or Resume does not follow offersPause, which keeps Resume while paused in overtime")
        }
        for hook in hooks.flatMap({ bodies(after: $0, in: code) }) {
            for mutator in mutators where hook.contains(mutator) {
                problems.append("the page calls \(mutator) without a press")
            }
        }
        for call in banned where code.contains(call) {
            problems.append("the page calls \(call), which the popover's buttons never do")
        }
        // Start timer's own chain, from its button to the header's task: never moved onto the gear.
        if let button = code.range(of: #"Button("Start timer") {"#),
           let task = code.range(of: ".task(id: visibility.isOnScreen)", range: button.upperBound..<code.endIndex) {
            if !code[button.lowerBound..<task.lowerBound].contains(".disabled(isRunning || !isOn || customTimerDuration <= 0)") {
                problems.append("Start timer is on while a timer runs, while the timer is off, or at 0:00")
            }
        } else {
            problems.append("Start timer is gone")
        }
        if !tile.contains(".disabled(preset.duration <= 0)") {
            problems.append("a 0:00 preset starts")
        }
        return problems
    }

    func testTheTimerStartsPausesAndStopsOnlyOnAPress() throws {
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.pressProblems(in: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("            // One read, not a subscription", "            TimerManager.shared.startTimer(duration: 60)\n            // One read, not a subscription"),
            ("            // Back on screen", "            TimerManager.shared.stopTimer()\n            // Back on screen"),
            ("            // Back on screen", "            Self.togglePause()\n            // Back on screen"),
            (".onChange(of: storedPresets) { _, _ in copyFromManager() }", ".onChange(of: storedPresets) { _, _ in TimerManager.shared.stopTimer() }"),
            ("        manager.stopTimer()", "        manager.forceStopTimer()"),
            ("        manager.isPaused ? manager.resumeTimer() : manager.pauseTimer()", "        manager.pauseTimer()"),
            (".disabled(isRunning || !isOn || customTimerDuration <= 0)", ".disabled(!isOn || customTimerDuration <= 0)"),
            (".disabled(preset.duration <= 0)", ".disabled(false)"),
            ("                TimerManager.shared.startTimer(duration: length, name: name, fallbackName: name)", ""),
            ("                            Self.togglePause()\n                            refresh()\n", "                            Self.togglePause()\n"),
            ("                        Self.stop()\n                        refresh()\n", "                        Self.stop()\n"),
            ("fallbackName: preset.name)\n            refresh()", "fallbackName: preset.name)"),
            ("if data.offersPause {", "if true {"),
        ], in: overview, by: Self.pressProblems)
        // Start timer's off switch moved onto the gear: gone from its own chain, though still in the file.
        let off = ".disabled(isRunning || !isOn || customTimerDuration <= 0)\n"
        let moved = overview
            .replacingOccurrences(of: "            .buttonStyle(SettingsButtonStyle(.primary))\n            " + off,
                                  with: "            .buttonStyle(SettingsButtonStyle(.primary))\n")
            .replacingOccurrences(of: "            .accessibilityLabel(String(localized: \"Timer settings\"))\n",
                                  with: "            .accessibilityLabel(String(localized: \"Timer settings\"))\n            " + off)
        XCTAssertEqual(moved.components(separatedBy: off).count - 1, 1, "the plant must move the switch, not drop or copy it")
        XCTAssertFalse(Self.pressProblems(in: moved).isEmpty, "the rule misses Start timer's off switch moved onto the gear")
    }

    // MARK: - The page, its header and its presets' sheet

    /// Timer is a product page that leads with its overview, its header carries the gear and Start timer, and its presets
    /// are edited in their sheet, never inline in the settings (the design review's finding 25).
    static func wiringProblems(overview: String, settings: String, view: String) -> [String] {
        var problems: [String] = []
        let settingsCode = SettingsDesignSystemRulesTests.code(settings)
        if !settingsCode.contains("SettingsProductPage(settingsTitle: String(localized: \"Timer settings\")) {\n            TimerOverview()\n        } settings: {") {
            problems.append("Timer does not lead with its overview")
        }
        if !SettingsDesignSystemRulesTests.code(view).contains("SettingsForm(tab: .timer, actions: AnyView(TimerHeaderActions())) {") {
            problems.append("Timer's header has no actions")
        }
        if settingsCode.contains(".timerPresets") {
            problems.append("the settings edit the presets inline")
        }
        let sheet = AgentsPageLiveDataRulesTests.body(after: ".sheet(item: $editing) {", in: SettingsDesignSystemRulesTests.code(overview)) ?? ""
        if !sheet.contains("TimerPresetSheet(target: target)") {
            problems.append("a preset is not edited in its sheet")
        }
        return problems
    }

    func testTimerIsAProductPageWithItsActionsAndItsPresetsSheet() throws {
        let overview = try Self.source(Self.overviewPath)
        let settings = try Self.source(Self.settingsPath)
        let view = try Self.source(Self.viewPath)
        XCTAssertEqual(Self.wiringProblems(overview: overview, settings: settings, view: view), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("            TimerOverview()\n", ""),
            ("    @Default(.enableTimerFeature) var enableTimerFeature\n",
             "    @Default(.enableTimerFeature) var enableTimerFeature\n    @Default(.timerPresets) private var timerPresets\n"),
        ], in: settings) { Self.wiringProblems(overview: overview, settings: $0, view: view) }
        SettingsDesignSystemRulesTests.assertCaught([(", actions: AnyView(TimerHeaderActions())", "")], in: view) {
            Self.wiringProblems(overview: overview, settings: settings, view: $0)
        }
        SettingsDesignSystemRulesTests.assertCaught([("            TimerPresetSheet(target: target)", "            EmptyView()")], in: overview) {
            Self.wiringProblems(overview: $0, settings: settings, view: view)
        }
    }

    // MARK: - Plumbing

    /// The braces' contents after every `opener` in `code`, in order.
    private static func bodies(after opener: String, in code: String) -> [String] {
        var found: [String] = []
        var rest = Substring(code)
        while let range = rest.range(of: opener) {
            found.append(AgentsPageLiveDataRulesTests.body(after: opener, in: String(rest[range.lowerBound...])) ?? "")
            rest = rest[range.upperBound...]
        }
        return found
    }

    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
