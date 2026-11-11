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

/// Brain › Security is a product page with live data, and Brain's content is built once and outlives its window
/// (docs/REGRESSIONS.md, entry 22). The findings store republishes on every hook write while a session runs with
/// permission checks off, so a page that observed it would redraw at hook rate for the rest of the process, Brain open or
/// not (entry 10: one such view cost 38 % CPU); the page before this one did. It keeps Agents' live-data contract
/// (docs/SETTINGS.md, "Live data") and starts no work of its own, read from the source clause by clause, each rule
/// checked against planted offenders, as `AgentsPageLiveDataRulesTests` does for Agents.
final class SecurityPageLiveDataRulesTests: XCTestCase {

    private static let overviewPath = "Kannu/components/Settings/SecurityOverview.swift"
    private static let settingsPath = "Kannu/components/Settings/AgentSecuritySettings.swift"
    private static let viewPath = "Kannu/components/Settings/SettingsView.swift"

    // MARK: - Clause 1: throttled and scoped

    /// The page's subscription: whatever the store changes, at most twice a second.
    private static let findingsFeed = #"SecurityFindingsStore\.shared\.objectWillChange\s*\.throttle\(for: \.milliseconds\(500\), scheduler: RunLoop\.main, latest: true\)\s*\.values"#
    /// The header's: whether a scan runs, passed on only when that changes.
    private static let scanningFeed = #"SecurityFindingsStore\.shared\.\$isScanning\s*\.removeDuplicates\(\)\s*\.values"#
    /// All the page may name on the store: the methods a press calls, and the two subscriptions. Anything else there is
    /// state, which only the copy reads, so a value the store gains later is caught too. `agentPolicyImportError` may
    /// only be reset, as the policy's visit does.
    private static let allowedStoreNames: Set<String> = [
        "runScanNow", "copyAgentPrompt", "acknowledgeGroup", "snooze", "openChat", "clearAcknowledgements", "forgetAnalysis",
        "checkAgentPolicy", "importPolicyFile", "openAgentPolicyDraft", "copyPolicyDraftingPrompt", "copyADRPolicyDraftingPrompt",
        "directoryChanged", "objectWillChange", "$isScanning",
    ]

    /// Each name used on `SecurityFindingsStore.shared` that is not on that list, read with comments blanked.
    static func storeNamesPastTheCopy(in code: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"SecurityFindingsStore\.shared\.(\$?\w+)(\s*=\s*nil\b)?"#) else {
            return ["the store's names cannot be read"]
        }
        let text = code as NSString
        return regex.matches(in: code, range: NSRange(location: 0, length: text.length)).compactMap { match in
            let name = text.substring(with: match.range(at: 1))
            if name == "agentPolicyImportError", match.range(at: 2).location != NSNotFound { return nil }
            return Self.allowedStoreNames.contains(name) ? nil : name
        }
    }

    /// Two subscriptions, the page's and the header's, and nothing else of the store: no observer, no `onReceive`, no
    /// sink, no kept reference, and its state read in one place, a copy assigned only when it changed.
    static func followProblems(settings: String, overview: String) -> [String] {
        let settingsCode = SettingsDesignSystemRulesTests.code(settings)
        let overviewCode = SettingsDesignSystemRulesTests.code(overview)
        var problems: [String] = []
        if SettingsDesignSystemRulesTests.matches(of: findingsFeed, in: settingsCode).count != 1
            || !SettingsDesignSystemRulesTests.matches(of: findingsFeed, in: overviewCode).isEmpty {
            problems.append("the store is not followed through the page's one subscription throttled to 500 ms")
        }
        if SettingsDesignSystemRulesTests.matches(of: scanningFeed, in: overviewCode).count != 1 {
            problems.append("the header's scan does not come through one subscription that drops repeats")
        }
        let subscriptions = [settingsCode, overviewCode].reduce(0) {
            $0 + $1.components(separatedBy: "SecurityFindingsStore.shared.$").count - 1
                + $1.components(separatedBy: "SecurityFindingsStore.shared.objectWillChange").count - 1
        }
        if subscriptions != 2 { problems.append("the store is followed outside the two subscriptions") }
        for (name, code) in [("the settings", settingsCode), ("the overview", overviewCode)] {
            if !SettingsDesignSystemRulesTests.matches(of: #"@(?:ObservedObject|StateObject|EnvironmentObject)[^\n]*SecurityFindingsStore"#, in: code).isEmpty {
                problems.append("\(name) observe the whole store")
            }
            if code.range(of: #"\.onReceive\([^\n]*SecurityFindingsStore|SecurityFindingsStore[^\n]*\.sink"#, options: .regularExpression) != nil {
                problems.append("\(name) follow the store outside the throttled task")
            }
            if code.range(of: #"=\s*SecurityFindingsStore\.shared\s*\n"#, options: .regularExpression) != nil {
                problems.append("\(name) keep a reference to the store, which reads past the copy")
            }
            let pastTheCopy = Self.storeNamesPastTheCopy(in: code)
            if !pastTheCopy.isEmpty {
                problems.append("\(name) read the store's state past the copy: \(pastTheCopy.joined(separator: ", "))")
            }
        }
        let reader = AgentsPageLiveDataRulesTests.body(after: "private func copyFromStore() {", in: settingsCode) ?? ""
        if settingsCode.components(separatedBy: "SecurityPageData(SecurityFindingsStore.shared)").count - 1 != 1
            || overviewCode.contains("SecurityPageData(SecurityFindingsStore.shared)")
            || !reader.contains("SecurityPageData(SecurityFindingsStore.shared)")
            || !reader.contains("if latest != security { security = latest }") {
            problems.append("the store is not read in one place, into a copy assigned only when it changed")
        }
        return problems
    }

    func testTheStoreComesThroughOneThrottledCopy() throws {
        let settings = try Self.source(Self.settingsPath)
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.followProblems(settings: settings, overview: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            (".throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n                .values", ".values"),
            (".milliseconds(500)", ".milliseconds(50)"),
            ("    @ObservedObject private var visibility = BrainVisibility.shared",
             "    @ObservedObject private var findingsStore = SecurityFindingsStore.shared\n    @ObservedObject private var visibility = BrainVisibility.shared"),
            ("Button(security.isScanning ? \"Scanning…\" : \"Scan now\")", "Button(SecurityFindingsStore.shared.isScanning ? \"Scanning…\" : \"Scan now\")"),
            ("if let importError = security.policyImportError {", "if let importError = SecurityFindingsStore.shared.agentPolicyImportError {"),
            // A value the store does not have yet, read past the copy: the allowlist catches what a list of names would miss.
            ("if let error = security.lastScanError {", "if let error = SecurityFindingsStore.shared.lastScanWarning {"),
            ("SecurityOverview(data: security)", "SecurityOverview(data: SecurityPageData(SecurityFindingsStore.shared))"),
            ("if latest != security { security = latest }", "security = latest"),
            ("        .navigationTitle(\"Security\")",
             "        .onReceive(SecurityFindingsStore.shared.objectWillChange) { _ in }\n        .navigationTitle(\"Security\")"),
        ], in: settings) { Self.followProblems(settings: $0, overview: overview) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("SecurityFindingsStore.shared.$isScanning\n                .removeDuplicates()\n                .values", "SecurityFindingsStore.shared.$isScanning.values"),
            ("openChat: data.hasChat(for: finding)", "openChat: SecurityFindingsStore.shared.hasChat(for: finding)"),
            ("SecurityCountStrip(groups: data.groups)", "SecurityCountStrip(groups: SecurityFindingsStore.shared.groupRanking)"),
            ("    @Default(.adrDetectionEnabled) private var detectionEnabled",
             "    @Default(.adrDetectionEnabled) private var detectionEnabled\n    @StateObject private var store = SecurityFindingsStore.shared"),
        ], in: overview) { Self.followProblems(settings: settings, overview: $0) }
    }

    // MARK: - Clause 2: stopped while Brain is not on screen

    /// A `Task` started inside a `.task` is not its child: it outlives the cancel, one more each time Brain comes back.
    private static let unstructuredTask = #"\bTask\s*(?:\{|\(|\.detached)"#

    /// Both subscriptions are the one `.task` of their file, keyed on Brain's visibility, each returning at once while it
    /// is false, with no `Task` inside, and each loop doing its one job: the page's takes a fresh copy, the header's passes
    /// the flag on. Back on screen, the page reads the store once before it follows it, because `objectWillChange` will
    /// not send again what changed while Brain was away. `AgentsPageLiveDataRulesTests` holds the flag itself.
    static func offScreenProblems(settings: String, overview: String) -> [String] {
        var problems: [String] = []
        let opener = ".task(id: visibility.isOnScreen) {"
        for (name, source, feed, job) in [("the page", settings, "SecurityFindingsStore.shared.objectWillChange", "copyFromStore()"),
                                          ("the header", overview, "SecurityFindingsStore.shared.$isScanning", "scanning = busy")] {
            let code = SettingsDesignSystemRulesTests.code(source)
            guard code.components(separatedBy: ".task").count - 1 == 1, code.components(separatedBy: opener).count - 1 == 1,
                  let task = AgentsPageLiveDataRulesTests.body(after: opener, in: code) else {
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
            if !(AgentsPageLiveDataRulesTests.body(after: ".values {", in: task) ?? "").contains(job) {
                problems.append("\(name)'s loop does not do its job: \(job)")
            }
            if name == "the page" {
                guard let read = task.range(of: "copyFromStore()"),
                      guardRange.lowerBound < read.lowerBound, read.lowerBound < feedRange.lowerBound else {
                    problems.append("the page does not read the store as Brain comes back on screen")
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
        let loop = "            for await _ in SecurityFindingsStore.shared.objectWillChange\n"
            + "                .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n"
            + "                .values {\n                copyFromStore()\n            }\n"
        SettingsDesignSystemRulesTests.assertCaught([
            (".task(id: visibility.isOnScreen) {", ".task {"),
            ("            guard visibility.isOnScreen else { return }\n            // Back on screen", "            // Back on screen"),
            ("            copyFromStore()\n            // `objectWillChange` comes before", "            // `objectWillChange` comes before"),
            (loop, "            Task {\n" + loop + "            }\n"),
            // A loop that follows and does nothing: the copy would never change after Brain comes back.
            ("                .values {\n                copyFromStore()\n            }", "                .values {\n            }"),
        ], in: settings) { Self.offScreenProblems(settings: $0, overview: overview) }
        SettingsDesignSystemRulesTests.assertCaught([
            (".task(id: visibility.isOnScreen) {", ".task {"),
            ("            guard visibility.isOnScreen else { return }\n            for await busy", "            for await busy"),
            ("                .values {\n                scanning = busy\n            }", "                .values {\n            }"),
        ], in: overview) { Self.offScreenProblems(settings: settings, overview: $0) }
    }

    // MARK: - Clause 3: no work while nothing is on screen

    /// The page keeps no clock and nothing that moves on its own: a scan is told by its time of day, and off screen the
    /// copy simply stays as it was.
    static func clockProblems(in source: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(source)
        return ["TimelineView", "Timer.", ".repeatForever", "ClaudeTurnTokenFollower", "ProgressView", "withAnimation", ".animation("]
            .filter { code.contains($0) }
            .map { "the page keeps a clock or a motion of its own: \($0)" }
    }

    func testThePageKeepsNoClock() throws {
        let settings = try Self.source(Self.settingsPath)
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.clockProblems(in: settings), [])
        XCTAssertEqual(Self.clockProblems(in: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("            .disabled(scanning)", "            .disabled(scanning)\n            if scanning { ProgressView() }"),
            ("                findings\n", "                findings\n                TimelineView(.periodic(from: .now, by: 60)) { _ in EmptyView() }\n"),
        ], in: overview, by: Self.clockProblems)
        SettingsDesignSystemRulesTests.assertCaught([
            ("        .navigationTitle(\"Security\")", "        .animation(.default, value: security)\n        .navigationTitle(\"Security\")"),
        ], in: settings, by: Self.clockProblems)
    }

    // MARK: - No work of its own

    /// What starts work: a scan, ADR's tool check (it spawns processes), the Detection checkout's check, a policy read
    /// or import, an analysis, a snapshot read, a process.
    private static let work = ["runScanNow", "checkAgain", "checkDetection", "checkAgentPolicy", "runAnalysis", "reloadNewestSnapshot",
                               "directoryChanged", "importPolicyFile", "openAgentPolicyDraft", "Process("]

    /// The settings' calls, as they were before the page led with its findings: each on a press, or once a visit (ADR's
    /// tools while never looked for, the Detection checkout while analysis is on and never checked, the policy). A new
    /// one, anywhere on the page, fails here.
    private static let settingsWork = ["runScanNow": 1, "checkAgain": 4, "checkDetection": 7, "checkAgentPolicy": 3, "runAnalysis": 0,
                                       "reloadNewestSnapshot": 0, "directoryChanged": 1, "importPolicyFile": 1,
                                       "openAgentPolicyDraft": 1, "Process(": 0]

    /// The product shows what the store holds and starts nothing but its verb's scan, on Scan now's press; Connect ADR
    /// only goes to ADR's row. The settings keep exactly the work they had, their own Scan now a press too.
    static func workProblems(settings: String, overview: String) -> [String] {
        var problems: [String] = []
        let overviewCode = SettingsDesignSystemRulesTests.code(overview)
        let press = AgentsPageLiveDataRulesTests.body(after: "Button(\"Scan now\") {", in: overviewCode) ?? ""
        if overviewCode.components(separatedBy: "runScanNow").count - 1 != 1
            || !press.contains("SecurityFindingsStore.shared.runScanNow(reason: \"manual\")") {
            problems.append("the product scans other than on Scan now's press")
        }
        for call in work.dropFirst() where overviewCode.contains(call) {
            problems.append("the product starts work of its own: \(call)")
        }
        let connect = AgentsPageLiveDataRulesTests.body(after: "Button(\"Connect ADR\") {", in: overviewCode) ?? ""
        if !connect.contains("requestAgentStatusNavigation(highlightID: SettingsDeepLink.securityConnectADRHighlightID)") {
            problems.append("Connect ADR does not go to ADR's row")
        }
        let settingsCode = SettingsDesignSystemRulesTests.code(settings)
        for (call, pinned) in settingsWork {
            let found = settingsCode.components(separatedBy: call).count - 1
            if found != pinned { problems.append("the settings call \(call) \(found) times, pinned at \(pinned)") }
        }
        let row = AgentsPageLiveDataRulesTests.body(after: "Button(security.isScanning ? \"Scanning…\" : \"Scan now\") {", in: settingsCode) ?? ""
        if !row.contains("SecurityFindingsStore.shared.runScanNow(reason: \"manual\")") {
            problems.append("the settings scan other than on Scan now's press")
        }
        return problems
    }

    func testThePageStartsNoWorkOfItsOwn() throws {
        let settings = try Self.source(Self.settingsPath)
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.workProblems(settings: settings, overview: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("            .disabled(scanning)", "            .disabled(scanning)\n            .onAppear { SecurityFindingsStore.shared.runScanNow(reason: \"visit\") }"),
            ("                findings\n", "                findings\n                    .onAppear { ADRConnection.shared.checkAgain() }\n"),
            ("                SecurityFindingsStore.shared.runScanNow(reason: \"manual\")", "                SecurityFindingsStore.shared.checkAgentPolicy()"),
            ("highlightID: SettingsDeepLink.securityConnectADRHighlightID)\n", "highlightID: SettingsDeepLink.securityConnectADRHighlightID)\n                ADRConnection.shared.checkAgain()\n"),
        ], in: overview) { Self.workProblems(settings: settings, overview: $0) }
        let appear = "            copyFromStore()\n        }\n        .task"
        SettingsDesignSystemRulesTests.assertCaught([
            (appear, "            copyFromStore()\n            adr.checkAgain()\n        }\n        .task"),
            (appear, "            copyFromStore()\n            SecurityFindingsStore.shared.runScanNow(reason: \"visit\")\n        }\n        .task"),
            ("                        SecurityFindingsStore.shared.runScanNow(reason: \"manual\")\n", ""),
        ], in: settings) { Self.workProblems(settings: $0, overview: overview) }
    }

    // MARK: - The page, its header and its list

    /// Security leads with its overview and its settings follow; its header carries the gear and the verb; and the
    /// findings stay the lazy list child 4-1 made them, since they can run to hundreds and no search lands on one.
    static func wiringProblems(settings: String, view: String, overview: String) -> [String] {
        var problems: [String] = []
        if !SettingsDesignSystemRulesTests.code(settings).contains(
            "SettingsProductPage(settingsTitle: String(localized: \"Security settings\")) {\n            SecurityOverview(data: security)\n        } settings: {") {
            problems.append("Security does not lead with its overview")
        }
        if !SettingsDesignSystemRulesTests.code(view).contains("SettingsForm(tab: .agentSecurity, actions: AnyView(SecurityHeaderActions())) {") {
            problems.append("Security's header has no actions")
        }
        let lazyList = #"LazyVStack\([^\n]*\{\s*ForEach\(visible, id: \\\.group\.id\)"#
        if SettingsDesignSystemRulesTests.matches(of: lazyList, in: SettingsDesignSystemRulesTests.code(overview)).count != 1 {
            problems.append("the findings list is not lazy")
        }
        return problems
    }

    func testSecurityIsAProductPageWithItsActions() throws {
        let settings = try Self.source(Self.settingsPath)
        let view = try Self.source(Self.viewPath)
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.wiringProblems(settings: settings, view: view, overview: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([("            SecurityOverview(data: security)\n", "")], in: settings) {
            Self.wiringProblems(settings: $0, view: view, overview: overview)
        }
        SettingsDesignSystemRulesTests.assertCaught([(", actions: AnyView(SecurityHeaderActions())", "")], in: view) {
            Self.wiringProblems(settings: settings, view: $0, overview: overview)
        }
        SettingsDesignSystemRulesTests.assertCaught([
            ("LazyVStack(alignment: .leading, spacing: SettingsTheme.sectionRowGap) {", "VStack(alignment: .leading, spacing: SettingsTheme.sectionRowGap) {"),
        ], in: overview) { Self.wiringProblems(settings: settings, view: view, overview: $0) }
    }

    // MARK: - Plumbing

    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
