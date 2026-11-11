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

/// Brain › Agents is a product page with live data, and Brain's content is built once and outlives its window
/// (docs/REGRESSIONS.md, entry 22), so a page that observed the agent monitor would re-render at up to about 20 Hz for
/// the rest of the process, Brain open or not (entry 10: one such view cost 38 % CPU). The live-data contract
/// (docs/SETTINGS.md, "Live data") is read from the source, clause by clause, each rule checked against planted
/// offenders. `ClosedNotchObservationTests` cannot see this shape, a subscription inside a `.task`.
final class AgentsPageLiveDataRulesTests: XCTestCase {

    private static let overviewPath = "Kannu/components/Settings/AgentsOverview.swift"
    private static let settingsPath = "Kannu/components/Settings/AgentStatusSettings.swift"
    private static let controllerPath = "Kannu/components/Settings/SettingsWindowController.swift"
    private static let visibilityPath = "Kannu/components/Settings/BrainVisibility.swift"
    private static let productPagePath = "Kannu/components/Settings/DesignSystem/SettingsProductPage.swift"
    private static let notchPath = "Kannu/components/AgentStatus/NotchAgentStatusView.swift"
    private static let metricsPath = "Kannu/components/AgentStatus/AgentTurnMetricsView.swift"

    // MARK: - Clause 1: throttled and scoped

    private static let sessionsFeed = #"CursorAgentStatusMonitor\.shared\.\$sessions\s*\.throttle\(for: \.milliseconds\(500\), scheduler: RunLoop\.main, latest: true\)\s*\.values"#
    private static let findingsFeed = #"SecurityFindingsStore\.shared\.objectWillChange\s*\.throttle\(for: \.milliseconds\(500\), scheduler: RunLoop\.main, latest: true\)\s*\.values"#
    /// A `Task` started inside a `.task` is not its child: it outlives the cancel, one more each time Brain comes back.
    private static let unstructuredTask = #"\bTask\s*(?:\{|\(|\.detached)"#

    /// One subscription to the monitor's sessions, throttled to two updates a second, and nothing else of the monitor:
    /// no observer, no `onReceive`, no sink, and the list read once, on appearing, not in `body`.
    static func followProblems(in overview: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(overview)
        var problems: [String] = []
        if SettingsDesignSystemRulesTests.matches(of: sessionsFeed, in: code).count != 1 {
            problems.append("the sessions are not followed through one subscription throttled to 500 ms")
        }
        if code.components(separatedBy: "CursorAgentStatusMonitor.shared.$").count - 1 != 1 {
            problems.append("a second subscription to the monitor")
        }
        if !SettingsDesignSystemRulesTests.matches(of: #"@(?:ObservedObject|StateObject|EnvironmentObject)[^\n]*CursorAgentStatusMonitor"#, in: code).isEmpty {
            problems.append("the overview observes the whole monitor")
        }
        if code.range(of: #"\.onReceive\([^\n]*CursorAgentStatusMonitor|CursorAgentStatusMonitor[^\n]*\.sink"#, options: .regularExpression) != nil {
            problems.append("the monitor is followed outside the throttled task")
        }
        let reads = code.components(separatedBy: "CursorAgentStatusMonitor.shared.sessions").count - 1
        let appear = body(after: ".onAppear {", in: code) ?? ""
        if reads != 1 || !appear.contains("CursorAgentStatusMonitor.shared.sessions") {
            problems.append("the sessions are read somewhere other than once on appearing")
        }
        return problems
    }

    /// The style preview follows the light alone, never the whole monitor.
    static func previewProblems(in settings: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(settings)
        var problems: [String] = []
        if !SettingsDesignSystemRulesTests.matches(of: #"@(?:ObservedObject|StateObject|EnvironmentObject)[^\n]*CursorAgentStatusMonitor"#, in: code).isEmpty {
            problems.append("the Agents settings observe the whole monitor")
        }
        if code.components(separatedBy: "CursorAgentStatusMonitor.shared.$trafficLightState.removeDuplicates().values").count - 1 != 1
            || code.components(separatedBy: "CursorAgentStatusMonitor.shared.$").count - 1 != 1 {
            problems.append("the preview follows more of the monitor than its light")
        }
        return problems
    }

    func testTheSessionsComeThroughOneThrottledScopedSubscription() throws {
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.followProblems(in: overview), [])
        let feed = ".throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n                .values"
        SettingsDesignSystemRulesTests.assertCaught([
            (feed, ".values"),
            (".milliseconds(500)", ".milliseconds(50)"),
            ("    @ObservedObject private var visibility = BrainVisibility.shared",
             "    @ObservedObject private var monitor = CursorAgentStatusMonitor.shared\n    @ObservedObject private var visibility = BrainVisibility.shared"),
            ("        .onAppear {", "        .onReceive(CursorAgentStatusMonitor.shared.$sessions) { sessions = $0 }\n        .onAppear {"),
            ("AgentTrafficLightMapper.latestSessions(sessions)", "AgentTrafficLightMapper.latestSessions(CursorAgentStatusMonitor.shared.sessions)"),
        ], in: overview, by: Self.followProblems)

        let settings = try Self.source(Self.settingsPath)
        XCTAssertEqual(Self.previewProblems(in: settings), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("    @ObservedObject private var visibility = BrainVisibility.shared",
             "    @ObservedObject private var monitor = CursorAgentStatusMonitor.shared"),
            ("$trafficLightState.removeDuplicates().values", "$sessions.map { _ in AgentTrafficLightState.executing }.values"),
        ], in: settings, by: Self.previewProblems)
    }

    // MARK: - Clause 2: stopped while Brain is not on screen

    /// Every subscription on the page starts only while Brain is on screen and ends when it is not: a `.task` keyed on
    /// the visibility flag, which returns at once while it is false, with no `Task` inside. The flag comes from the
    /// window's occlusion state, which covers closed, minimised, hidden, covered and another Space; a close alone would
    /// miss the last. Opening and closing set it too, since that change can come late, or not at all for a window never
    /// shown, and it is assigned in one place.
    static func offScreenProblems(overview: String, settings: String, controller: String, visibility: String) -> [String] {
        var problems: [String] = []
        for (name, source, feed) in [("the overview", overview, "$sessions"), ("the style preview", settings, "$trafficLightState")] {
            let code = SettingsDesignSystemRulesTests.code(source)
            guard let task = body(after: ".task(id: visibility.isOnScreen) {", in: code) else {
                problems.append("\(name) does not follow Brain's visibility")
                continue
            }
            guard let guardRange = task.range(of: "guard visibility.isOnScreen else { return }"),
                  let feedRange = task.range(of: feed), guardRange.lowerBound < feedRange.lowerBound else {
                problems.append("\(name) subscribes while Brain is off screen")
                continue
            }
            if task.range(of: unstructuredTask, options: .regularExpression) != nil {
                problems.append("\(name) subscribes in a Task its .task cannot cancel")
            }
        }
        let controllerCode = SettingsDesignSystemRulesTests.code(controller)
        for (writer, problem) in [("func windowDidChangeOcclusionState(", "the window does not say when it leaves the screen"),
                                  ("func showWindow() {", "opening does not say Brain is on screen"),
                                  ("private func relinquishFocus() {", "closing does not say Brain left the screen")]
            where !(body(after: writer, in: controllerCode) ?? "").contains("BrainVisibility.shared.update(for: window)") {
            problems.append(problem)
        }
        let flag = SettingsDesignSystemRulesTests.code(visibility)
        if !flag.contains("let onScreen = window.isVisible && window.occlusionState.contains(.visible)")
            || !flag.contains("if onScreen != isOnScreen { isOnScreen = onScreen }")
            || flag.components(separatedBy: "isOnScreen = ").count - 1 != 2 {
            problems.append("on screen is not read from the occlusion state, or is set elsewhere")
        }
        if !flag.contains("@Published private(set) var isOnScreen = false") {
            problems.append("something live could start before Brain is first on screen")
        }
        return problems
    }

    func testTheSubscriptionsStopWhileBrainIsOffScreen() throws {
        let overview = try Self.source(Self.overviewPath)
        let settings = try Self.source(Self.settingsPath)
        let controller = try Self.source(Self.controllerPath)
        let visibility = try Self.source(Self.visibilityPath)
        XCTAssertEqual(Self.offScreenProblems(overview: overview, settings: settings, controller: controller, visibility: visibility), [])

        let sessionsLoop = "            for await latest in CursorAgentStatusMonitor.shared.$sessions\n"
            + "                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n"
            + "                .values {\n                sessions = latest\n            }\n"
        SettingsDesignSystemRulesTests.assertCaught([
            (".task(id: visibility.isOnScreen) {", ".task {"),
            ("            guard visibility.isOnScreen else { return }\n", ""),
            (sessionsLoop, "            Task {\n" + sessionsLoop + "            }\n"),
        ], in: overview) { Self.offScreenProblems(overview: $0, settings: settings, controller: controller, visibility: visibility) }
        SettingsDesignSystemRulesTests.assertCaught([
            (".task(id: visibility.isOnScreen) {", ".task(id: style) {"),
            ("                guard visibility.isOnScreen else { return }\n", ""),
        ], in: settings) { Self.offScreenProblems(overview: overview, settings: $0, controller: controller, visibility: visibility) }
        let update = "        if let window { BrainVisibility.shared.update(for: window) }\n"
        let opened = "        // On screen from here: a window never shown may already count as visible, and then AppKit sends no change.\n"
        let closed = "        // Off screen from here, without waiting for AppKit's occlusion change, which can come late.\n"
        SettingsDesignSystemRulesTests.assertCaught([
            ("        BrainVisibility.shared.update(for: window)\n", ""),
            (opened + update, opened),
            (closed + update, closed),
        ], in: controller) { Self.offScreenProblems(overview: overview, settings: settings, controller: $0, visibility: visibility) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("window.isVisible && window.occlusionState.contains(.visible)", "window.isVisible"),
            ("var isOnScreen = false", "var isOnScreen = true"),
            ("isOnScreen = onScreen }", "isOnScreen = true }"),
            ("    private init() {}", "    private init() { isOnScreen = true }"),
        ], in: visibility) { Self.offScreenProblems(overview: overview, settings: settings, controller: controller, visibility: $0) }
    }

    // MARK: - Clause 3: no work while nothing is on screen

    /// While Brain is off screen the live leaves give way to a static copy: the metrics, which observe the token
    /// follower and tick once a second, drawn live by the hero and the rows only while `drawsLive`, and the status row,
    /// which observes the usage store. The findings store republishes on every hook write while a session runs with
    /// permission checks off, so it is never observed whole: Security's summary comes through one subscription
    /// throttled to 500 ms, inside the live row, and is assigned only on a change. Nothing else on the page observes
    /// those stores, and nothing on it keeps a clock.
    static func frozenProblems(in overview: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(overview)
        var problems: [String] = []
        if code.components(separatedBy: "AgentTurnMetricsView(").count - 1 != 1
            || SettingsDesignSystemRulesTests.matches(of: #"if live \{\s*AgentTurnMetricsView\("#, in: code).count != 1 {
            problems.append("the live metrics are drawn while Brain is off screen")
        }
        for leaf in ["AgentsHeroCard", "AgentsSessionRow"] {
            let calls = code.components(separatedBy: "\(leaf)(session:").count - 1
            let gated = SettingsDesignSystemRulesTests.matches(of: leaf + #"\(session: \w+, live: drawsLive\)"#, in: code).count
            if calls != 1 || gated != 1 { problems.append("\(leaf) draws live whatever Brain's visibility") }
        }
        if code.components(separatedBy: "AgentsLiveStatusRow(").count - 1 != 1
            || SettingsDesignSystemRulesTests.matches(of: #"if visibility\.isOnScreen \{\s*AgentsLiveStatusRow\("#, in: code).count != 1 {
            problems.append("the live status row is drawn while Brain is off screen")
        }
        if !code.contains("return visibility.isOnScreen") {
            problems.append("the live leaves do not follow Brain's visibility")
        }
        let liveRow = region(from: "private struct AgentsLiveStatusRow", to: "private struct AgentsStatusRow", in: code) ?? ""
        let usage = #"@ObservedObject[^\n]*UsageAlertManager"#
        if SettingsDesignSystemRulesTests.matches(of: usage, in: code).count != 1 || SettingsDesignSystemRulesTests.matches(of: usage, in: liveRow).count != 1 {
            problems.append("the usage store is observed outside the live status row")
        }
        if !SettingsDesignSystemRulesTests.matches(of: #"@(?:ObservedObject|StateObject|EnvironmentObject)[^\n]*SecurityFindingsStore"#, in: code).isEmpty
            || code.range(of: #"\.onReceive\([^\n]*SecurityFindingsStore|SecurityFindingsStore[^\n]*\.sink"#, options: .regularExpression) != nil {
            problems.append("the findings store is followed at its own rate")
        }
        if SettingsDesignSystemRulesTests.matches(of: findingsFeed, in: code).count != 1
            || SettingsDesignSystemRulesTests.matches(of: findingsFeed, in: liveRow).count != 1
            || !liveRow.contains("if latest != security { security = latest }")
            || liveRow.range(of: unstructuredTask, options: .regularExpression) != nil {
            problems.append("Security's summary does not come through one throttled subscription in the live row, assigned on a change")
        }
        for clock in ["TimelineView", "ClaudeTurnTokenFollower", "Timer.", ".repeatForever"] where code.contains(clock) {
            problems.append("the page keeps a clock or a follower of its own: \(clock)")
        }
        return problems
    }

    /// Brain's static hero lays out through `AgentTurnMetricsView.figureRow`, which the overview does not own, so that
    /// path is held to the same rule: no clock, no follower, no observed store.
    static func staticFigureProblems(in metrics: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(metrics)
        guard let row = region(from: "static func figureRow", to: "static func display", in: code) else {
            return ["the static figures are not where this rule reads them"]
        }
        return ["TimelineView", "ClaudeTurnTokenFollower", "follower", "Timer.", "@ObservedObject", ".repeatForever"]
            .filter { row.contains($0) }
            .map { "the static figures keep a clock or a follower: \($0)" }
    }

    func testNothingWorksWhileNothingIsOnScreen() throws {
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.frozenProblems(in: overview), [])
        let securityLoop = "                for await _ in SecurityFindingsStore.shared.objectWillChange\n"
            + "                    .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n"
            + "                    .values {\n"
            + "                    let latest = AgentsSecuritySummary(SecurityFindingsStore.shared.groupRanking)\n"
            + "                    if latest != security { security = latest }\n"
            + "                }\n"
        SettingsDesignSystemRulesTests.assertCaught([
            ("        if live {\n", "        if true {\n"),
            ("AgentsHeroCard(session: primary, live: drawsLive)", "AgentsHeroCard(session: primary, live: true)"),
            ("AgentsSessionRow(session: session, live: drawsLive)", "AgentsSessionRow(session: session, live: true)"),
            ("        if visibility.isOnScreen {\n            AgentsLiveStatusRow", "        if true {\n            AgentsLiveStatusRow"),
            ("        return visibility.isOnScreen", "        return true"),
            ("    @ObservedObject private var hookInstaller = AgentHookInstaller.shared\n    @Default",
             "    @ObservedObject private var hookInstaller = AgentHookInstaller.shared\n    @ObservedObject private var usage = UsageAlertManager.shared\n    @Default"),
            ("    @State private var security = AgentsSecuritySummary(toReview: 0, high: 0, pinnedTitle: nil)",
             "    @ObservedObject private var findings = SecurityFindingsStore.shared\n    @State private var security = AgentsSecuritySummary(toReview: 0, high: 0, pinnedTitle: nil)"),
            ("SecurityFindingsStore.shared.objectWillChange\n                    .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n                    .values",
             "SecurityFindingsStore.shared.objectWillChange.values"),
            ("if latest != security { security = latest }", "security = latest"),
            (securityLoop, "                Task {\n" + securityLoop + "                }\n"),
            ("    @State private var sessions: [AgentSessionStatus] = []",
             "    @State private var sessions: [AgentSessionStatus] = []\n    @ObservedObject private var follower = ClaudeTurnTokenFollower.shared"),
            ("            lead(primary: primary)\n", "            lead(primary: primary)\n            TimelineView(.periodic(from: .now, by: 1)) { _ in EmptyView() }\n"),
        ], in: overview, by: Self.frozenProblems)
        let metrics = try Self.source(Self.metricsPath)
        XCTAssertEqual(Self.staticFigureProblems(in: metrics), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("figure(runTime, label:", "figure(TimelineView(.periodic(from: .now, by: 1)) { _ in runTime }, label:"),
            ("            if let tokens {\n", "            if let tokens = ClaudeTurnTokenFollower.shared.latest {\n"),
        ], in: metrics, by: Self.staticFigureProblems)
    }

    // MARK: - A click resolves its target in the action

    /// Finding a session's target walks parent processes and asks `NSWorkspace`, so Brain never does it in `body`, for
    /// each row on every render: a click calls `AgentSessionOpener.open`, which resolves it then.
    static func clickProblems(in overview: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(overview)
        var problems: [String] = []
        if code.contains("AgentSessionOpener.target(") { problems.append("a target is resolved while drawing") }
        if SettingsDesignSystemRulesTests.matches(of: #"Button \{\s*_ = AgentSessionOpener\.open\(session\)"#, in: code).count != 2 {
            problems.append("the hero and the rows do not open their chat from the click")
        }
        return problems
    }

    func testAClickResolvesItsTargetInTheAction() throws {
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.clickProblems(in: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("Button {\n            _ = AgentSessionOpener.open(session)", "Button {\n            _ = AgentSessionOpener.target(for: session)"),
        ], in: overview, by: Self.clickProblems)
    }

    // MARK: - Tools are checked once per visit

    /// The detector checks files and Launch Services. The overview calls it from `onAppear`, once a visit (the header
    /// offers no install), and the notch from its empty state's; never from `body`, and nothing on the page checks a
    /// file of its own.
    static func detectionProblems(in sources: [String: String]) -> [String] {
        var problems: [String] = []
        for (path, source) in sources {
            let code = SettingsDesignSystemRulesTests.code(source)
            let calls = code.components(separatedBy: "AgentToolDetector.detect()").count - 1
            let inAppear = code.components(separatedBy: ".onAppear {").dropFirst()
                .compactMap { body(after: "", in: "{" + $0) }
                .reduce(0) { $0 + $1.components(separatedBy: "AgentToolDetector.detect()").count - 1 }
            if calls == 0 || calls != inAppear { problems.append("\(path) checks the tools outside onAppear") }
            if path == overviewPath, calls != 1 { problems.append("\(path) checks the tools more than once a visit") }
            if code.contains("fileExists(") { problems.append("\(path) checks a file of its own") }
        }
        return problems
    }

    /// While an agent works, every hover-open lands on Agent Status, so the notch checks only from its empty state,
    /// which shows while none does.
    static func notchDetectionProblems(in notch: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(notch)
        let emptyState = body(after: "private var emptyStateView: some View {", in: code) ?? ""
        guard code.components(separatedBy: "AgentToolDetector.detect()").count - 1 == 1,
              emptyState.contains("AgentToolDetector.detect()") else { return ["the notch checks its tools outside its empty state"] }
        return []
    }

    func testTheToolsAreCheckedOncePerVisit() throws {
        let sources = try Dictionary(uniqueKeysWithValues: [Self.overviewPath, Self.notchPath].map { ($0, try Self.source($0)) })
        XCTAssertEqual(Self.detectionProblems(in: sources), [])
        let overview = try XCTUnwrap(sources[Self.overviewPath])
        SettingsDesignSystemRulesTests.assertCaught([
            ("let watched = tools.filter(\\.detected)", "let watched = AgentToolDetector.detect().filter(\\.detected)"),
            ("let watched = tools.filter(\\.detected)", "let watched = tools.filter { FileManager.default.fileExists(atPath: $0.name) }"),
            ("            tools = AgentToolDetector.detect()\n", "            tools = AgentToolDetector.detect()\n            tools = AgentToolDetector.detect()\n"),
        ], in: overview) { Self.detectionProblems(in: [Self.overviewPath: $0]) }
        let notch = try XCTUnwrap(sources[Self.notchPath])
        XCTAssertEqual(Self.notchDetectionProblems(in: notch), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("        .ownsVerticalScroll()\n", "        .ownsVerticalScroll()\n        .onAppear { detectedTools = AgentToolDetector.detect() }\n"),
        ], in: notch, by: Self.notchDetectionProblems)
    }

    // MARK: - The product page's frame

    /// One scroll view across the panel, the product capped at `productMaxWidth` and the settings at `pageMaxWidth`,
    /// held the page inset from the leading edge; plain stacks, no hook and no animator (docs/SETTINGS.md, "Product
    /// pages"), as `SettingsPage`.
    static func productPageProblems(in page: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(page)
        var problems = [".frame(maxWidth: SettingsTheme.productMaxWidth, alignment: .leading)",
                        ".frame(maxWidth: SettingsTheme.pageMaxWidth, alignment: .leading)",
                        ".padding(.horizontal, inset)", "@Environment(\\.settingsPageInset) private var inset",
                        ".frame(maxWidth: .infinity, alignment: .leading)"].filter { !code.contains($0) }
        if code.components(separatedBy: "ScrollView {").count - 1 != 1 { problems.append("not one scroll view") }
        problems += [".onAppear", ".onDisappear", ".task", "withAnimation", ".animation(", "TimelineView", "Lazy", "List", "Form"]
            .filter { code.contains($0) }
        return problems
    }

    func testTheProductPageKeepsItsFrame() throws {
        let page = try Self.source(Self.productPagePath)
        XCTAssertEqual(Self.productPageProblems(in: page), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("VStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {\n                    settings",
             "LazyVStack(alignment: .leading, spacing: SettingsTheme.sectionGap) {\n                    settings"),
            (".frame(maxWidth: SettingsTheme.pageMaxWidth, alignment: .leading)", ".frame(maxWidth: SettingsTheme.productMaxWidth, alignment: .leading)"),
            (".padding(.horizontal, inset)", ".padding(.horizontal, SettingsTheme.pageInset)"),
            ("        ScrollView {", "        ScrollView {\n            EmptyView().onAppear {}"),
        ], in: page, by: Self.productPageProblems)
    }

    // MARK: - Plumbing

    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The braces' contents that start at `opener`'s own `{`: the first one after where `opener` begins. Usage's and
    /// Security's rules read their pages with it too (`UsagePageLiveDataRulesTests`,
    /// `SecurityPageLiveDataRulesTests`).
    static func body(after opener: String, in code: String) -> String? {
        guard let start = opener.isEmpty ? code.startIndex..<code.startIndex : code.range(of: opener),
              let open = code[start.lowerBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        for index in code[open...].indices {
            if code[index] == "{" { depth += 1 }
            if code[index] == "}" {
                depth -= 1
                if depth == 0 { return String(code[code.index(after: open)..<index]) }
            }
        }
        return nil
    }

    private static func region(from start: String, to end: String, in code: String) -> String? {
        guard let from = code.range(of: start), let to = code.range(of: end, range: from.upperBound..<code.endIndex) else { return nil }
        return String(code[from.lowerBound..<to.lowerBound])
    }

    func testTheHelpersReadBraces() {
        XCTAssertEqual(Self.body(after: ".task {", in: "x.task { a { b } c } d"), " a { b } c ")
        XCTAssertNil(Self.body(after: ".task {", in: "x.onAppear { a }"))
        XCTAssertEqual(Self.region(from: "struct A", to: "struct B", in: "struct A { } struct B { }"), "struct A { } ")
    }
}
