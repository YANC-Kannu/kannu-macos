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
    private static let settingsPath = "Kannu/components/Settings/TimerSettings.swift"
    private static let viewPath = "Kannu/components/Settings/SettingsView.swift"

    // MARK: - Clause 1: throttled and scoped

    /// The page's subscription: the manager's changes, at most twice a second.
    private static let pageFeed = #"TimerManager\.shared\.objectWillChange\s*\.throttle\(for: \.milliseconds\(500\), scheduler: RunLoop\.main, latest: true\)\s*\.values"#
    /// The header's: whether a timer runs, passed on only when that changes.
    private static let headerFeed = #"TimerManager\.shared\.\$isTimerActive\s*\.removeDuplicates\(\)\s*\.values"#
    /// What the manager knows about the running timer, read through the shared manager or a local name for it.
    private static let stateRead = #"(?<![\w.])(?:TimerManager\.shared|manager|timerManager)\.(?:isTimerActive|timerName|totalDuration|remainingTime|elapsedTime|isPaused|isFinished|isOvertime|lastUpdated|activePresetId|activePreset|sessionTint|sessionTaskKey|sessionTaskID|activeSource|progress|sessionAccent|formattedRemainingTime|formattedElapsedTime|formattedTotalDuration|isExternalTimerActive|hasManualTimerRunning|allowsManualInteraction|isRunning|statusText|timerColor|currentColor|timerNSColor)\b"#
    /// The places that may read it: the copy's `init`, and the two presses, which read it at the press.
    private static let readers = ["init(_ timerManager: TimerManager) {", "private static func togglePause() {",
                                  "private static func stop() {"]

    /// Two subscriptions, each to what it needs, and nothing else of the manager: no observer, no `onReceive`, no sink.
    /// The manager's state is read in one copy, `TimerPageData`'s `init`, and at a press, never in `body`.
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
            ("                    TimerRunningCard(data: data)", "                    TimerRunningCard(data: TimerPageData(TimerManager.shared))"),
            ("        Button {\n            TimerManager.shared.startTimer(",
             "        let manager = TimerManager.shared\n        let _ = manager.remainingTime\n        Button {\n            TimerManager.shared.startTimer("),
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

    /// The time moves with the manager's own one-second tick, through the subscription above, and nothing on the page
    /// moves by itself: a clock here would be a second one that could disagree with the notch's, and would tick on while
    /// a timer stood paused. A `Text` with a relative or timer style, or a `timerInterval`, is a clock too.
    static func clockProblems(in overview: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(overview)
        var problems = ["TimelineView", "Timer.scheduledTimer", "Timer.publish", ".repeatForever", "withAnimation", ".animation(",
                        "ProgressView", ".contentTransition(", "timerInterval:", "asyncAfter", "Task.sleep", "ClaudeTurnTokenFollower"]
            .filter { code.contains($0) }
            .map { "the page keeps a clock or a motion of its own: \($0)" }
        if code.range(of: #"style:\s*\.(?:relative|timer|offset)\b"#, options: .regularExpression) != nil {
            problems.append("the page keeps a clock of its own: a Text that counts")
        }
        return problems
    }

    func testThePageKeepsNoClockOfItsOwn() throws {
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.clockProblems(in: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("            if !isOn {", "            TimelineView(.periodic(from: .now, by: 1)) { _ in EmptyView() }\n            if !isOn {"),
            ("            if !isOn {", "            Text(Date(), style: .timer)\n            if !isOn {"),
            ("            if !isOn {", "            Text(timerInterval: Date()...Date())\n            if !isOn {"),
            ("                        .monospacedDigit()", "                        .monospacedDigit()\n                        .contentTransition(.numericText())"),
            ("    private func copyFromManager() {", "    private func copyFromManager() {\n        withAnimation {}"),
        ], in: overview, by: Self.clockProblems)
    }

    // MARK: - Clause 4: only on a press

    /// What changes the timer, every one of `TimerManager`'s own calls that the notch's popover makes, and nothing else.
    private static let mutators = ["startTimer(", "pauseTimer(", "resumeTimer(", "stopTimer(", "togglePause(", "stop("]
    private static let banned = ["forceStopTimer(", "startDemoTimer(", "adoptExternalTimer(", "endExternalTimer(", "updateSessionLength(",
                                 "updateSessionName(", "updateSessionTint(", "completeExternalTimer("]

    /// Start timer and a tile start a timer, Pause or Resume and Stop act on it, each in its own button's action and
    /// nowhere else: never as the page appears or follows the manager. Start timer is off while a timer runs, as the
    /// popover hides its own start then, and a 0:00 preset does not start.
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
        if !(AgentsPageLiveDataRulesTests.body(after: "Button {", in: tile) ?? "").contains(start) {
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
        var hooks: [String] = []
        for opener in [".onAppear {", ".task(id: visibility.isOnScreen) {"] {
            var rest = Substring(code)
            while let range = rest.range(of: opener) {
                hooks.append(AgentsPageLiveDataRulesTests.body(after: opener, in: String(rest[range.lowerBound...])) ?? "")
                rest = rest[range.upperBound...]
            }
        }
        for hook in hooks {
            for mutator in mutators where hook.contains(mutator) {
                problems.append("the page calls \(mutator) without a press")
            }
        }
        for call in banned where code.contains(call) {
            problems.append("the page calls \(call), which the popover's buttons never do")
        }
        if !code.contains(".disabled(isRunning || !isOn || customTimerDuration <= 0)") {
            problems.append("Start timer is on while a timer runs, while the timer is off, or at 0:00")
        }
        if !code.contains(".disabled(preset.duration <= 0)") {
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
            ("        manager.stopTimer()", "        manager.forceStopTimer()"),
            ("        manager.isPaused ? manager.resumeTimer() : manager.pauseTimer()", "        manager.pauseTimer()"),
            (".disabled(isRunning || !isOn || customTimerDuration <= 0)", ".disabled(!isOn || customTimerDuration <= 0)"),
            (".disabled(preset.duration <= 0)", ".disabled(false)"),
            ("                TimerManager.shared.startTimer(duration: length, name: name, fallbackName: name)", ""),
        ], in: overview, by: Self.pressProblems)
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

    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
