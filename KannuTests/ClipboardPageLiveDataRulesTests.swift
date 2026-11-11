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

/// Brain › Clipboard is a product page with live data, and Brain's content is built once and outlives its window
/// (docs/REGRESSIONS.md, entry 22). The page before this one observed the clipboard manager whole, so every copy redrew
/// it, Brain open or not. It keeps Agents' live-data contract (docs/SETTINGS.md, "Live data"), starts no work of its
/// own, and its boards never touch the manager. Each rule is read from the source and checked against planted
/// offenders, as `SecurityPageLiveDataRulesTests` does for Security.
final class ClipboardPageLiveDataRulesTests: XCTestCase {

    private static let overviewPath = "Kannu/components/Settings/ClipboardOverview.swift"
    private static let settingsPath = "Kannu/components/Settings/ClipboardSettings.swift"
    private static let viewPath = "Kannu/components/Settings/SettingsView.swift"
    private static let boardsPath = "Kannu/helpers/DebugSnapshot.swift"

    /// The braces after a signature, matched by depth; the reader `ClosedNotchTimerRulesTests` already shares.
    private static func body(after signature: String, in code: String) -> String {
        ClosedNotchTimerRulesTests.body(after: signature, in: code) ?? ""
    }

    // MARK: - Clause 1: throttled and scoped

    /// The page's subscription: whatever the manager changes, at most twice a second.
    private static let managerFeed = #"ClipboardManager\.shared\.objectWillChange\s*\.throttle\(for: \.milliseconds\(500\), scheduler: RunLoop\.main, latest: true\)\s*\.values"#
    /// The header's: whether History and the pinned items are empty, passed on only when that changes.
    private static let emptinessFeed = #"ClipboardManager\.shared\.\$clipboardHistory\.map\(\\\.isEmpty\)\s*\.combineLatest\(ClipboardManager\.shared\.\$pinnedItems\.map\(\\\.isEmpty\)\)\s*\.removeDuplicates\(by: ==\)\s*\.values"#
    /// All the page may name on the manager: the calls a press or the switch makes, and the two subscriptions. Anything
    /// else there is state, which only the copy reads, so a value the manager gains later is caught too. `pinnedItems`
    /// may only be emptied, as Clear Pinned Items does.
    private static let allowedManagerNames: Set<String> = [
        "copyToClipboard", "togglePin", "deleteItem", "clearHistory", "savePinnedItemsToDefaults", "startMonitoring",
        "stopMonitoring", "objectWillChange", "$clipboardHistory", "$pinnedItems",
    ]

    /// Each name used on `ClipboardManager.shared` that is not on that list, read with comments blanked.
    static func managerNamesPastTheCopy(in code: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\bClipboardManager\.shared\.(\$?\w+)(\.removeAll\(\))?"#) else {
            return ["the manager's names cannot be read"]
        }
        let text = code as NSString
        return regex.matches(in: code, range: NSRange(location: 0, length: text.length)).compactMap { match in
            let name = text.substring(with: match.range(at: 1))
            if name == "pinnedItems", match.range(at: 2).location != NSNotFound { return nil }
            return Self.allowedManagerNames.contains(name) ? nil : name
        }
    }

    /// Two subscriptions, the page's and the header's, and nothing else of the manager: no observer, no `onReceive`, no
    /// sink, no kept reference, and its state read in one place, a copy assigned only when it changed. The copy's
    /// equality covers what the page draws from it: the pins and History by id, since a copy never changes once
    /// captured, and whether the manager runs.
    static func followProblems(settings: String, overview: String) -> [String] {
        let settingsCode = SettingsDesignSystemRulesTests.code(settings)
        let overviewCode = SettingsDesignSystemRulesTests.code(overview)
        var problems: [String] = []
        if SettingsDesignSystemRulesTests.matches(of: managerFeed, in: settingsCode).count != 1
            || !SettingsDesignSystemRulesTests.matches(of: managerFeed, in: overviewCode).isEmpty {
            problems.append("the manager is not followed through the page's one subscription throttled to 500 ms")
        }
        if SettingsDesignSystemRulesTests.matches(of: emptinessFeed, in: overviewCode).count != 1 {
            problems.append("the header's clears do not come through one subscription that drops repeats")
        }
        // The page's `objectWillChange`, and the header's two `$` values combined into one.
        let subscriptions = [settingsCode, overviewCode].reduce(0) {
            $0 + $1.components(separatedBy: "ClipboardManager.shared.$").count - 1
                + $1.components(separatedBy: "ClipboardManager.shared.objectWillChange").count - 1
        }
        if subscriptions != 3 { problems.append("the manager is followed outside the two subscriptions") }
        for (name, code) in [("the settings", settingsCode), ("the overview", overviewCode)] {
            if !SettingsDesignSystemRulesTests.matches(of: #"@(?:ObservedObject|StateObject|EnvironmentObject)[^\n]*\bClipboardManager\b"#, in: code).isEmpty {
                problems.append("\(name) observe the whole manager")
            }
            if code.range(of: #"\.onReceive\([^\n]*\bClipboardManager\b|\bClipboardManager\b[^\n]*\.sink"#, options: .regularExpression) != nil {
                problems.append("\(name) follow the manager outside the throttled task")
            }
            if code.range(of: #"=\s*ClipboardManager\.shared\s*\n"#, options: .regularExpression) != nil {
                problems.append("\(name) keep a reference to the manager, which reads past the copy")
            }
            let pastTheCopy = Self.managerNamesPastTheCopy(in: code)
            if !pastTheCopy.isEmpty {
                problems.append("\(name) read the manager's state past the copy: \(pastTheCopy.joined(separator: ", "))")
            }
        }
        let reader = body(after: "private func copyFromStore()", in: settingsCode)
        if settingsCode.components(separatedBy: "ClipboardPageData(ClipboardManager.shared)").count - 1 != 1
            || overviewCode.contains("ClipboardPageData(ClipboardManager.shared)")
            || !reader.contains("ClipboardPageData(ClipboardManager.shared)")
            || !reader.contains("if latest != clipboard { clipboard = latest }") {
            problems.append("the manager is not read in one place, into a copy assigned only when it changed")
        }
        let copy = body(after: "init(_ manager: ClipboardManager)", in: overviewCode)
        for read in ["pinned = manager.pinnedItems", "history = manager.regularHistory", "isMonitoring = manager.isMonitoring"]
            where !copy.contains(read) {
            problems.append("the copy does not read \(read)")
        }
        let equality = body(after: "static func == (lhs: ClipboardPageData, rhs: ClipboardPageData) -> Bool", in: overviewCode)
        for compared in [#"lhs.pinned.map(\.id) == rhs.pinned.map(\.id)"#, #"lhs.history.map(\.id) == rhs.history.map(\.id)"#,
                         "lhs.isMonitoring == rhs.isMonitoring"] where !equality.contains(compared) {
            problems.append("the copy's equality leaves out \(compared), so the page would keep an old one")
        }
        return problems
    }

    func testTheManagerComesThroughOneThrottledCopy() throws {
        let settings = try Self.source(Self.settingsPath)
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.followProblems(settings: settings, overview: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            (".throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)\n                .values", ".values"),
            (".milliseconds(500)", ".milliseconds(50)"),
            ("    @ObservedObject private var visibility = BrainVisibility.shared",
             "    @ObservedObject private var clipboardManager = ClipboardManager.shared\n    @ObservedObject private var visibility = BrainVisibility.shared"),
            ("SettingsStatusText(clipboard.isMonitoring ?", "SettingsStatusText(ClipboardManager.shared.isMonitoring ?"),
            // A value the manager does not show yet, read past the copy: the allowlist catches what a list of names would miss.
            ("isReady: clipboard.isMonitoring)", "isReady: ClipboardManager.shared.lastCopiedItemDate != nil)"),
            ("ClipboardOverview(data: clipboard)", "ClipboardOverview(data: ClipboardPageData(ClipboardManager.shared))"),
            ("if latest != clipboard { clipboard = latest }", "clipboard = latest"),
            ("        .navigationTitle(\"Clipboard\")",
             "        .onReceive(ClipboardManager.shared.objectWillChange) { _ in }\n        .navigationTitle(\"Clipboard\")"),
        ], in: settings) { Self.followProblems(settings: $0, overview: overview) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("                .removeDuplicates(by: ==)\n", ""),
            ("ForEach(data.pinned) { item in", "ForEach(ClipboardManager.shared.pinnedItems) { item in"),
            ("Text(verbatim: data.history.count.formatted())", "Text(verbatim: ClipboardManager.shared.clipboardHistory.count.formatted())"),
            ("    @Default(.enableClipboardManager) private var enabled\n    /// History starts folded",
             "    @Default(.enableClipboardManager) private var enabled\n    @StateObject private var manager = ClipboardManager.shared\n    /// History starts folded"),
            ("history = manager.regularHistory", "history = manager.clipboardHistory.filter { _ in false }"),
            ("            && lhs.isMonitoring == rhs.isMonitoring", ""),
        ], in: overview) { Self.followProblems(settings: settings, overview: $0) }
    }

    // MARK: - Clause 2: stopped while Brain is not on screen

    /// A `Task` started inside a `.task` is not its child: it outlives the cancel, one more each time Brain comes back.
    private static let unstructuredTask = #"\bTask\s*(?:\{|\(|\.detached)"#

    /// Both subscriptions are the one `.task` of their file, keyed on Brain's visibility, each returning at once while it
    /// is false, with no `Task` inside, and each loop doing its one job: the page's takes a fresh copy, the header's
    /// passes the flags on. Back on screen, the page reads the manager once before it follows it, because
    /// `objectWillChange` will not send again what changed while Brain was away. `AgentsPageLiveDataRulesTests` holds
    /// the flag itself.
    static func offScreenProblems(settings: String, overview: String) -> [String] {
        var problems: [String] = []
        let opener = ".task(id: visibility.isOnScreen)"
        for (name, source, feed, job) in [("the page", settings, "ClipboardManager.shared.objectWillChange", "copyFromStore()"),
                                          ("the header", overview, "ClipboardManager.shared.$clipboardHistory", "hasHistory = !historyEmpty")] {
            let code = SettingsDesignSystemRulesTests.code(source)
            guard code.components(separatedBy: ".task").count - 1 == 1, code.components(separatedBy: opener).count - 1 == 1 else {
                problems.append("\(name) does not follow Brain's visibility")
                continue
            }
            let task = body(after: opener, in: code)
            guard let guardRange = task.range(of: "guard visibility.isOnScreen else { return }"),
                  let feedRange = task.range(of: feed), guardRange.lowerBound < feedRange.lowerBound else {
                problems.append("\(name) subscribes while Brain is off screen")
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
                      guardRange.lowerBound < read.lowerBound, read.lowerBound < feedRange.lowerBound else {
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
        let loop = "            for await _ in ClipboardManager.shared.objectWillChange\n"
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
            ("            guard visibility.isOnScreen else { return }\n            for await", "            for await"),
            ("                hasHistory = !historyEmpty\n", ""),
        ], in: overview) { Self.offScreenProblems(settings: settings, overview: $0) }
    }

    // MARK: - Clause 3: no work while nothing is on screen

    /// The page keeps no clock and nothing that moves on its own: a row says when it was copied by its date, and off
    /// screen the copy simply stays as it was. A "Copied" that clears itself would be a clock too.
    static func clockProblems(in source: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(source)
        return ["TimelineView", "Timer.", ".repeatForever", "ProgressView", "withAnimation", ".animation(", "asyncAfter"]
            .filter { code.contains($0) }
            .map { "the page keeps a clock or a motion of its own: \($0)" }
    }

    func testThePageKeepsNoClock() throws {
        let settings = try Self.source(Self.settingsPath)
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.clockProblems(in: settings), [])
        XCTAssertEqual(Self.clockProblems(in: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("                pinned\n", "                pinned\n                TimelineView(.periodic(from: .now, by: 60)) { _ in EmptyView() }\n"),
            ("                    ClipboardManager.shared.copyToClipboard(item)\n",
             "                    ClipboardManager.shared.copyToClipboard(item)\n                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {}\n"),
        ], in: overview, by: Self.clockProblems)
        SettingsDesignSystemRulesTests.assertCaught([
            ("        .navigationTitle(\"Clipboard\")", "        .animation(.default, value: clipboard)\n        .navigationTitle(\"Clipboard\")"),
        ], in: settings, by: Self.clockProblems)
    }

    // MARK: - No work of its own

    /// Each press, and nothing else, calls the manager once: Copy, Pin or Unpin, Delete, the two clears and Open history
    /// panel, each from its own button.
    private static let presses: [(button: String, method: String, call: String)] = [
        ("glyph(\"doc.on.doc\", String(localized: \"Copy\"))", "copyToClipboard", "ClipboardManager.shared.copyToClipboard(item)"),
        ("glyph(isPinned ? \"pin.slash\" : \"pin\"", "togglePin", "ClipboardManager.shared.togglePin(for: item)"),
        ("glyph(\"trash\", String(localized: \"Delete\"), role: .destructive)", "deleteItem", "ClipboardManager.shared.deleteItem(item)"),
        ("Button(\"Clear History\", role: .destructive)", "clearHistory", "ClipboardManager.shared.clearHistory()"),
        ("Button(\"Clear Pinned Items\", role: .destructive)", "pinnedItems.removeAll()", "ClipboardManager.shared.pinnedItems.removeAll()"),
        ("Button(\"Open history panel\")", "ClipboardPanelManager", "ClipboardPanelManager.shared.showClipboardPanel(trigger: \"brain\")"),
    ]

    /// The settings' calls, as they were before the page led with its product: the switch starts and stops the manager,
    /// and the page starts it as it appears while it is on (`startMonitoring` returns at once while it runs). A new one,
    /// anywhere on the page, fails here.
    private static let settingsWork = ["startMonitoring": 2, "stopMonitoring": 1, "ClipboardPanelManager": 0, "copyToClipboard": 0,
                                       "togglePin": 0, "deleteItem": 0, "clearHistory": 0, "removeAll": 0]

    /// The product starts and stops nothing, and each of its calls runs only on its press; the settings keep exactly
    /// the calls they had.
    static func workProblems(settings: String, overview: String) -> [String] {
        var problems: [String] = []
        let overviewCode = SettingsDesignSystemRulesTests.code(overview)
        for call in ["startMonitoring", "stopMonitoring"] where overviewCode.contains(call) {
            problems.append("the product starts or stops the manager: \(call)")
        }
        for press in presses {
            if overviewCode.components(separatedBy: press.method).count - 1 != 1
                || !body(after: press.button, in: overviewCode).contains(press.call) {
                problems.append("\(press.method) runs other than on its press")
            }
        }
        let settingsCode = SettingsDesignSystemRulesTests.code(settings)
        for (call, pinned) in settingsWork {
            let found = settingsCode.components(separatedBy: call).count - 1
            if found != pinned { problems.append("the settings call \(call) \(found) times, pinned at \(pinned)") }
        }
        if !body(after: ".onAppear", in: settingsCode).contains("if enableClipboardManager {\n                ClipboardManager.shared.startMonitoring()\n            }") {
            problems.append("the page starts the manager as it appears while it is off")
        }
        return problems
    }

    func testThePageStartsNoWorkOfItsOwn() throws {
        let settings = try Self.source(Self.settingsPath)
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.workProblems(settings: settings, overview: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("            showsHistory = false\n            #if DEBUG\n",
             "            showsHistory = false\n            ClipboardManager.shared.startMonitoring()\n            #if DEBUG\n"),
            ("            showsHistory = false\n            #if DEBUG\n",
             "            showsHistory = false\n            ClipboardManager.shared.clearHistory()\n            #if DEBUG\n"),
            ("                .buttonStyle(SettingsButtonStyle(.primary))\n",
             "                .buttonStyle(SettingsButtonStyle(.primary))\n                .onAppear { ClipboardPanelManager.shared.showClipboardPanel(trigger: \"visit\") }\n"),
            ("ClipboardManager.shared.deleteItem(item)", "ClipboardManager.shared.togglePin(for: item)"),
        ], in: overview) { Self.workProblems(settings: settings, overview: $0) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("            copyFromStore()\n        }\n        .task", "            copyFromStore()\n            ClipboardManager.shared.stopMonitoring()\n        }\n        .task"),
            ("            if enableClipboardManager {\n                ClipboardManager.shared.startMonitoring()\n            }\n",
             "            ClipboardManager.shared.startMonitoring()\n"),
            ("            copyFromStore()\n        }\n        .task", "            copyFromStore()\n            ClipboardManager.shared.clearHistory()\n        }\n        .task"),
        ], in: settings) { Self.workProblems(settings: $0, overview: overview) }
    }

    // MARK: - Boards draw fixtures, never the manager

    /// A board draws made-up copies and never touches the manager. Its first touch loads the saved history, and deletes
    /// every image file that history does not name, in a folder the installed app shares with the debug build; its start
    /// reads the real pasteboard twice a second. So with a fixture set, the settings' `onAppear` takes the fixture and
    /// returns before anything reads or starts the manager, both `.task`s return before they subscribe, and the boards
    /// make their copies without the manager and without writing an image.
    static func boardProblems(settings: String, overview: String, boards: String) -> [String] {
        var problems: [String] = []
        let settingsCode = SettingsDesignSystemRulesTests.code(settings)
        let appear = body(after: ".onAppear", in: settingsCode)
        let fixture = appear.range(of: "if let fixture = ClipboardOverview.snapshotFixture {\n                clipboard = fixture.data\n                return\n            }")
        let firstTouch = [appear.range(of: "ClipboardManager.shared"), appear.range(of: "copyFromStore()")]
            .compactMap { $0?.lowerBound }.min()
        if fixture == nil || firstTouch == nil || fixture!.upperBound > firstTouch! {
            problems.append("a board's settings reach the manager as they appear")
        }
        for (name, source) in [("the page", settingsCode), ("the header", SettingsDesignSystemRulesTests.code(overview))] {
            let task = body(after: ".task(id: visibility.isOnScreen)", in: source)
            guard let early = task.range(of: "if ClipboardOverview.snapshotFixture != nil { return }"),
                  let touch = task.range(of: "ClipboardManager.shared"), early.upperBound < touch.lowerBound else {
                problems.append("\(name) can subscribe to the manager on a board")
                continue
            }
        }
        let boardsCode = SettingsDesignSystemRulesTests.code(boards)
        for touch in ["ClipboardManager.shared", "ClipboardItem(imageData", "ClipboardItem(stringData", "ClipboardItem(fileURLs"]
            where boardsCode.contains(touch) {
            problems.append("the boards make their copies through \(touch)")
        }
        return problems
    }

    func testTheBoardsNeverTouchTheManager() throws {
        let settings = try Self.source(Self.settingsPath)
        let overview = try Self.source(Self.overviewPath)
        let boards = try Self.source(Self.boardsPath)
        XCTAssertEqual(Self.boardProblems(settings: settings, overview: overview, boards: boards), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("                clipboard = fixture.data\n                return\n", "                clipboard = fixture.data\n"),
            ("            #if DEBUG\n            if let fixture = ClipboardOverview.snapshotFixture {",
             "            ClipboardManager.shared.startMonitoring()\n            #if DEBUG\n            if let fixture = ClipboardOverview.snapshotFixture {"),
            ("            #if DEBUG\n            if ClipboardOverview.snapshotFixture != nil { return }\n            #endif\n            guard visibility.isOnScreen else { return }\n            // Back on screen",
             "            guard visibility.isOnScreen else { return }\n            // Back on screen"),
        ], in: settings) { Self.boardProblems(settings: $0, overview: overview, boards: boards) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("            if ClipboardOverview.snapshotFixture != nil { return }\n", ""),
        ], in: overview) { Self.boardProblems(settings: settings, overview: $0, boards: boards) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("        let clipboard = DebugSnapshotFixtures.clipboardOverview(pinned: 0, history: 4, now: Date())\n",
             "        let clipboard = DebugSnapshotFixtures.clipboardOverview(pinned: 0, history: 4, now: Date())\n        _ = ClipboardManager.shared.pinnedItems\n"),
            ("ClipboardItem(snapshot: content, type: type, copiedAt: now.addingTimeInterval(-ago))\n        }",
             "ClipboardItem(stringData: content, type: type)\n        }"),
        ], in: boards) { Self.boardProblems(settings: settings, overview: overview, boards: $0) }
    }

    // MARK: - The page and its header

    /// Clipboard leads with its overview and its settings follow; its header carries "…" and the verb; and History starts
    /// folded and folds again each time the page appears, Brain's reopening included (Brain's content outlives its
    /// window), so a copy shows only once History is opened on this visit. A board's fixture may open it after that.
    static func wiringProblems(settings: String, view: String, overview: String) -> [String] {
        var problems: [String] = []
        if !SettingsDesignSystemRulesTests.code(settings).contains(
            "SettingsProductPage(settingsTitle: String(localized: \"Clipboard settings\")) {\n            ClipboardOverview(data: clipboard)\n        } settings: {") {
            problems.append("Clipboard does not lead with its overview")
        }
        if !SettingsDesignSystemRulesTests.code(view).contains("SettingsForm(tab: .clipboard, actions: AnyView(ClipboardHeaderActions())) {") {
            problems.append("Clipboard's header has no actions")
        }
        let overviewCode = SettingsDesignSystemRulesTests.code(overview)
        if !overviewCode.contains("@State private var showsHistory = false")
            || !overviewCode.contains("DisclosureGroup(isExpanded: $showsHistory) {") {
            problems.append("History does not start folded")
        }
        let appear = body(after: ".onAppear", in: overviewCode)
        let fold = appear.range(of: "showsHistory = false")
        let fixture = appear.range(of: "#if DEBUG")
        if fold == nil || fixture == nil || fold!.lowerBound > fixture!.lowerBound {
            problems.append("History does not fold again each time the page appears")
        }
        return problems
    }

    func testClipboardIsAProductPageWithItsActions() throws {
        let settings = try Self.source(Self.settingsPath)
        let view = try Self.source(Self.viewPath)
        let overview = try Self.source(Self.overviewPath)
        XCTAssertEqual(Self.wiringProblems(settings: settings, view: view, overview: overview), [])
        SettingsDesignSystemRulesTests.assertCaught([("            ClipboardOverview(data: clipboard)\n", "")], in: settings) {
            Self.wiringProblems(settings: $0, view: view, overview: overview)
        }
        SettingsDesignSystemRulesTests.assertCaught([(", actions: AnyView(ClipboardHeaderActions())", "")], in: view) {
            Self.wiringProblems(settings: settings, view: $0, overview: overview)
        }
        SettingsDesignSystemRulesTests.assertCaught([
            ("@State private var showsHistory = false", "@State private var showsHistory = true"),
            // Opened once, History would stay open on every later visit, a reopened Brain on a shared screen included.
            ("            showsHistory = false\n            #if DEBUG\n", "            #if DEBUG\n"),
        ], in: overview) { Self.wiringProblems(settings: settings, view: view, overview: $0) }
    }

    // MARK: - Plumbing

    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
