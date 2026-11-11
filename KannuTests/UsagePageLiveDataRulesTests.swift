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

/// Brain › Usage is a product page with live data, and Brain's content is built once and outlives its window
/// (docs/REGRESSIONS.md, entry 22), so it keeps Agents' live-data contract (docs/SETTINGS.md, "Live data"). What it
/// shows comes from reads that are a danger zone of their own (entry 8), so the page must never start one: Refresh, on a
/// press, is the one way in. Read from the source, clause by clause, each rule checked against planted offenders, as
/// `AgentsPageLiveDataRulesTests` does for Agents.
final class UsagePageLiveDataRulesTests: XCTestCase {

    private static let overviewPath = "Kannu/components/Settings/UsageOverview.swift"
    private static let settingsPath = "Kannu/components/Settings/UsageSettings.swift"
    private static let viewPath = "Kannu/components/Settings/SettingsView.swift"

    // MARK: - Clause 1: throttled and scoped

    /// The page's subscription: the readings, their outlooks and the providers' results, at most twice a second.
    private static let usageFeed = #"UsageAlertManager\.shared\.\$readings\s*\.combineLatest\(UsageAlertManager\.shared\.\$outlooks, LLMUsageManager\.shared\.\$results\)\s*\.throttle\(for: \.milliseconds\(500\), scheduler: RunLoop\.main, latest: true\)\s*\.values"#
    /// The header's: whether a refresh runs, passed on only when that changes.
    private static let refreshFeed = #"LLMUsageManager\.shared\.\$isRefreshing\s*\.combineLatest\(CursorAgentStatusMonitor\.shared\.\$isRefreshingClaudeUsage, \{ \$0 \|\| \$1 \}\)\s*\.removeDuplicates\(\)\s*\.values"#
    private static let stores = ["UsageAlertManager", "LLMUsageManager", "CursorAgentStatusMonitor"]

    /// Two subscriptions, each to the values it needs, and nothing else of the stores: no observer, no `onReceive`, no
    /// sink, and their values read once, on appearing, not in `body`.
    static func followProblems(in overview: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(overview)
        var problems: [String] = []
        if SettingsDesignSystemRulesTests.matches(of: usageFeed, in: code).count != 1 {
            problems.append("the readings, outlooks and models do not come through one subscription throttled to 500 ms")
        }
        if SettingsDesignSystemRulesTests.matches(of: refreshFeed, in: code).count != 1 {
            problems.append("the refresh state does not come through one subscription that drops repeats")
        }
        // Five values in all, each one of the two feeds' own.
        if stores.reduce(0, { $0 + code.components(separatedBy: "\($1).shared.$").count - 1 }) != 5 {
            problems.append("a store is followed outside the two subscriptions")
        }
        for store in stores {
            if !SettingsDesignSystemRulesTests.matches(of: #"@(?:ObservedObject|StateObject|EnvironmentObject)[^\n]*"# + store, in: code).isEmpty {
                problems.append("the page observes \(store) whole")
            }
            if code.range(of: #"\.onReceive\([^\n]*"# + store + "|" + store + #"[^\n]*\.sink"#, options: .regularExpression) != nil {
                problems.append("\(store) is followed outside the page's tasks")
            }
        }
        let appear = AgentsPageLiveDataRulesTests.body(after: ".onAppear {", in: code) ?? ""
        for read in ["UsageAlertManager.shared.readings", "UsageAlertManager.shared.outlooks", "LLMUsageManager.shared.results"] {
            if code.components(separatedBy: read).count - 1 != 1 || !appear.contains(read) {
                problems.append("\(read) is read somewhere other than once on appearing")
            }
        }
        return problems
    }

    func testTheStoresComeThroughThrottledScopedSubscriptions() throws {
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.followProblems(in: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            (".throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n                .values", ".values"),
            (".milliseconds(500)", ".milliseconds(50)"),
            ("{ $0 || $1 })\n                .removeDuplicates()\n                .values", "{ $0 || $1 })\n                .values"),
            ("    @State private var data = UsageOverviewData()",
             "    @State private var data = UsageOverviewData()\n    @ObservedObject private var usage = UsageAlertManager.shared"),
            ("        .onAppear {\n            #if DEBUG", "        .onReceive(LLMUsageManager.shared.$results) { _ in }\n        .onAppear {\n            #if DEBUG"),
            ("data.readings.filter", "UsageAlertManager.shared.readings.filter"),
        ], in: overview, by: Self.followProblems)
    }

    // MARK: - Clause 2: stopped while Brain is not on screen

    /// A `Task` started inside a `.task` is not its child: it outlives the cancel, one more each time Brain comes back.
    private static let unstructuredTask = #"\bTask\s*(?:\{|\(|\.detached)"#

    /// Both subscriptions are `.task`s keyed on Brain's visibility, each returning at once while it is false, with no
    /// `Task` inside. `AgentsPageLiveDataRulesTests` holds the flag itself.
    static func offScreenProblems(in overview: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(overview)
        var problems: [String] = []
        let opener = ".task(id: visibility.isOnScreen) {"
        if code.components(separatedBy: ".task").count - 1 != 2 || code.components(separatedBy: opener).count - 1 != 2 {
            problems.append("a subscription is not keyed on Brain's visibility")
        }
        for (index, part) in code.components(separatedBy: opener).dropFirst().enumerated() {
            let task = AgentsPageLiveDataRulesTests.body(after: "", in: "{" + part) ?? ""
            guard let guardRange = task.range(of: "guard visibility.isOnScreen else { return }"),
                  let feed = task.range(of: ".shared.$"), guardRange.lowerBound < feed.lowerBound else {
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
        let refreshLoop = "            for await busy in LLMUsageManager.shared.$isRefreshing\n"
            + "                .combineLatest(CursorAgentStatusMonitor.shared.$isRefreshingClaudeUsage, { $0 || $1 })\n"
            + "                .removeDuplicates()\n"
            + "                .values {\n                refreshing = busy\n            }\n"
        SettingsDesignSystemRulesTests.assertCaught([
            (".task(id: visibility.isOnScreen) {", ".task {"),
            ("            guard visibility.isOnScreen else { return }\n            for await (readings", "            for await (readings"),
            ("            guard visibility.isOnScreen else { return }\n            for await busy", "            for await busy"),
            (refreshLoop, "            Task {\n" + refreshLoop + "            }\n"),
        ], in: overview, by: Self.offScreenProblems)
    }

    // MARK: - Clause 3: no work while nothing is on screen

    /// The page keeps no clock and nothing that moves on its own: resets and readings are told by the time of day, and a
    /// window past its reset is left out as the page draws. A `Text` with a relative or timer style is a clock too: it
    /// redraws every second. Off screen, the copy simply stays as it was.
    static func clockProblems(in overview: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(overview)
        var problems = ["TimelineView", "Timer.", ".repeatForever", "ClaudeTurnTokenFollower", "ProgressView", "withAnimation", ".animation("]
            .filter { code.contains($0) }
            .map { "the page keeps a clock or a motion of its own: \($0)" }
        if code.range(of: #"style:\s*\.(?:relative|timer|offset)\b"#, options: .regularExpression) != nil {
            problems.append("the page keeps a clock of its own: a Text that counts")
        }
        return problems
    }

    func testThePageKeepsNoClock() throws {
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.clockProblems(in: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("            if providers.isEmpty {", "            TimelineView(.periodic(from: .now, by: 60)) { _ in EmptyView() }\n            if providers.isEmpty {"),
            ("            .disabled(refreshing || providers.isEmpty || !usageStoreRuns)",
             "            .disabled(refreshing || providers.isEmpty || !usageStoreRuns)\n            if refreshing { ProgressView() }"),
            ("            if providers.isEmpty {", "            Text(Date(), style: .relative)\n            if providers.isEmpty {"),
            ("            if providers.isEmpty {", "            Text(Date(), style: .timer)\n            if providers.isEmpty {"),
        ], in: overview, by: Self.clockProblems)
    }

    // MARK: - Nothing stale on the page

    /// A window past its reset or expiry never shows: each card keeps the live ones only (`isLive`, the rule the notch's
    /// bars and the alerts use), since the store drops them only while it runs. While Agent Status is off, which stops
    /// the store, its off state stands in place of the cards and Refresh is off: nothing a refresh read would show.
    static func staleProblems(in overview: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(overview)
        var problems: [String] = []
        if !code.contains("let live = readings.filter { $0.isLive(now: now) }") || !code.contains("ForEach(live, id: \\.id)")
            || code.contains("ForEach(readings,") {
            problems.append("a card can show a window past its reset")
        }
        if SettingsDesignSystemRulesTests.matches(of: #"if usageStoreRuns \{\s*VStack"#, in: code).count != 1
            || !code.contains("UsageMessageCard(title: \"Agent Status is off\", message: nil)") {
            problems.append("the cards show while Agent Status is off")
        }
        if !code.contains(".disabled(refreshing || providers.isEmpty || !usageStoreRuns)") {
            problems.append("Refresh runs while Agent Status is off")
        }
        if code.components(separatedBy: "return agentStatusOn").count - 1 != 2 {
            problems.append("the page and its header do not both follow Agent Status")
        }
        return problems
    }

    func testNothingStaleShows() throws {
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.staleProblems(in: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("ForEach(live, id: \\.id)", "ForEach(readings, id: \\.id)"),
            ("let live = readings.filter { $0.isLive(now: now) }", "let live = readings"),
            ("                if usageStoreRuns {", "                if true {"),
            ("|| !usageStoreRuns)", ")"),
            ("        return agentStatusOn\n", "        return true\n"),
        ], in: overview, by: Self.staleProblems)
    }

    // MARK: - No read of its own

    /// The page shows what the stores hold and starts no read, spawn or sign-in of its own (docs/REGRESSIONS.md,
    /// entry 8). Refresh, on a press, is the one way in, through the notch's paths unchanged: its Refresh usage, and,
    /// while Claude is on and no status holds the automatic refresh, Claude's `/usage` as that refresh runs it, never the
    /// ↻'s press that may start a browser sign-in. The status is read at the press, never followed. A fixed list of
    /// other reads is banned from the page and its settings, and the settings may not make Refresh's two calls either.
    static func readProblems(overview: String, settings: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(overview)
        var problems: [String] = []
        let refresh = AgentsPageLiveDataRulesTests.body(after: #"Button("Refresh") {"#, in: code) ?? ""
        let calls = ["LLMUsageManager.shared.refreshRequestedByUser()", "CursorAgentStatusMonitor.shared.refreshClaudeUsageFromCLI(manual: false)"]
        for call in calls where code.components(separatedBy: call).count - 1 != 1 || !refresh.contains(call) {
            problems.append("\(call) runs somewhere other than once, on Refresh's press")
        }
        if code.components(separatedBy: "refreshClaudeUsageFromCLI(").count - 1 != 1 {
            problems.append("Claude's /usage runs another way")
        }
        // Claude's run sits in one `if` with both conditions: Claude is on, and no status holds the automatic refresh.
        let guarded = "if providers.contains(.claude), CursorAgentStatusMonitor.shared.claudeRefreshStatus?.holdsAutomaticRefresh != true {"
        if let condition = refresh.range(of: guarded),
           let call = refresh.range(of: calls[1], range: condition.upperBound..<refresh.endIndex) {
            if refresh[condition.upperBound..<call.lowerBound].firstIndex(of: "}") != nil {
                problems.append("Claude's /usage runs outside its guard")
            }
        } else {
            problems.append("Claude's /usage is not guarded by Claude being on and by the automatic refresh's hold")
        }
        if code.components(separatedBy: "claudeRefreshStatus").count - 1 != 1 {
            problems.append("Claude's status is read somewhere other than once, at the press")
        }
        let banned = ["refreshAll(", "refreshClaudeUsageIfStale(", "resolveQuotaAction(", "fetchSnapshot(", "fetchLimits(",
                      "QuotaClient", "ClaudeUsageRefresh", "Process(", "cancelClaudeSignIn(", "openClaudeSignInInTerminal("]
        let settingsBanned = banned + ["refreshRequestedByUser(", "refreshClaudeUsageFromCLI("]
        for (name, source, reads) in [("the page", code, banned), ("its settings", SettingsDesignSystemRulesTests.code(settings), settingsBanned)] {
            for read in reads where source.contains(read) {
                problems.append("\(name) starts a read of its own: \(read)")
            }
        }
        return problems
    }

    func testThePageStartsNoReadOfItsOwn() throws {
        let overview = try Self.source(Self.overviewPath)
        let settings = try Self.source(Self.settingsPath)
        XCTAssertEqual(Self.readProblems(overview: overview, settings: settings), [])
        let appearRead = "            data = UsageOverviewData(readings: UsageAlertManager.shared.readings"
        SettingsDesignSystemRulesTests.assertCaught([
            (appearRead, "            LLMUsageManager.shared.refreshRequestedByUser()\n" + appearRead),
            (appearRead, "            LLMUsageManager.shared.refreshAll()\n" + appearRead),
            (appearRead, "            CursorAgentStatusMonitor.shared.refreshClaudeUsageIfStale()\n" + appearRead),
            ("refreshClaudeUsageFromCLI(manual: false)", "refreshClaudeUsageFromCLI()"),
            // A press that would clear the notch's sign-in line, or the status followed instead of read at the press.
            (", CursorAgentStatusMonitor.shared.claudeRefreshStatus?.holdsAutomaticRefresh != true {", " {"),
            ("    @State private var data = UsageOverviewData()",
             "    @State private var data = UsageOverviewData()\n    @State private var claudeStatus = CursorAgentStatusMonitor.shared.claudeRefreshStatus"),
            // Claude's run while Claude is off.
            ("if providers.contains(.claude), CursorAgentStatusMonitor", "if CursorAgentStatusMonitor"),
        ], in: overview) { Self.readProblems(overview: $0, settings: settings) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("        .navigationTitle(\"Usage\")", "        .onAppear { LLMUsageManager.shared.refreshAll() }\n        .navigationTitle(\"Usage\")"),
            ("        .navigationTitle(\"Usage\")", "        .onAppear { LLMUsageManager.shared.refreshRequestedByUser() }\n        .navigationTitle(\"Usage\")"),
            ("        .navigationTitle(\"Usage\")",
             "        .onAppear { CursorAgentStatusMonitor.shared.refreshClaudeUsageFromCLI(manual: false) }\n        .navigationTitle(\"Usage\")"),
        ], in: settings) { Self.readProblems(overview: overview, settings: $0) }
    }

    // MARK: - The page and its header

    /// Usage is a product page that leads with its overview, and its header carries the gear and Refresh.
    static func wiringProblems(settings: String, view: String) -> [String] {
        var problems: [String] = []
        if !SettingsDesignSystemRulesTests.code(settings)
            .contains("SettingsProductPage(settingsTitle: String(localized: \"Usage settings\")) {\n            UsageOverview()\n        } settings: {") {
            problems.append("Usage does not lead with its overview")
        }
        if !SettingsDesignSystemRulesTests.code(view).contains("SettingsForm(tab: .llmUsage, actions: AnyView(UsageHeaderActions())) {") {
            problems.append("Usage's header has no actions")
        }
        return problems
    }

    func testUsageIsAProductPageWithItsActions() throws {
        let settings = try Self.source(Self.settingsPath)
        let view = try Self.source(Self.viewPath)
        XCTAssertEqual(Self.wiringProblems(settings: settings, view: view), [])
        SettingsDesignSystemRulesTests.assertCaught([("            UsageOverview()\n", "")], in: settings) {
            Self.wiringProblems(settings: $0, view: view)
        }
        SettingsDesignSystemRulesTests.assertCaught([(", actions: AnyView(UsageHeaderActions())", "")], in: view) {
            Self.wiringProblems(settings: settings, view: $0)
        }
    }

    // MARK: - Plumbing

    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
