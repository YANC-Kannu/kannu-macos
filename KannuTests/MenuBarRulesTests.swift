//
//  MenuBarRulesTests.swift
//  KannuTests
//
//  Copyright (C) 2026 Kannu contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import XCTest

/// The menu bar around Brain (Stage 6): Go lists the product pages in the sidebar's order, ⌘1 onward; View acts on
/// Brain's window; File's New Task opens Tasks' own sheet. Every item that opens Brain waits for the Terms of Use, as
/// Brain… does. The views are not in the logic target, so this reads the source, the `LaunchGateRulesTests` way.
final class MenuBarRulesTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // KannuTests/
        .deletingLastPathComponent()   // repo root

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private static func code(_ text: String) -> String {
        SettingsDesignSystemRulesTests.code(text)
    }

    /// From `var commands` to the class after the App struct: the commands, their helper and their views.
    private static func commands(in app: String) -> String {
        guard let start = app.range(of: "var commands: some Commands {"),
              let end = app.range(of: "final class FirstMouseHostingView", range: start.upperBound..<app.endIndex) else { return "" }
        return String(app[start.lowerBound..<end.lowerBound])
    }

    /// A member's body: from its declaration to the closing brace at its own indent.
    private static func body(of declaration: String, in text: String) -> String {
        guard let start = text.range(of: declaration),
              let end = text.range(of: "\n    }\n", range: start.upperBound..<text.endIndex) else { return "" }
        return String(text[start.lowerBound..<end.upperBound])
    }

    private static func count(_ needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private static func isBefore(_ first: String, _ second: String, in text: String) -> Bool {
        guard let a = text.range(of: first), let b = text.range(of: second) else { return false }
        return a.lowerBound < b.lowerBound
    }

    // MARK: - The three menus

    static func menuProblems(in commands: String) -> [String] {
        let menus = [
            // Go: one item per product page, from the sidebar's own order, ⌘1 to ⌘9 at most.
            "CommandMenu(String(localized: \"Go\"))",
            "ForEach(Array(SettingsTab.productPages.enumerated()), id: \\.element) { index, tab in",
            "Button(tab.title) { openBrain(on: tab) }",
            ".keyboardShortcut(Self.goShortcut(index))",
            "guard (0..<9).contains(index) else { return nil }",
            "return KeyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)",
            // File: New Task, off while Tasks is off.
            "CommandGroup(replacing: .newItem)",
            "NewTaskCommand { openBrain(on: .tasks, newTask: true) }",
            ".keyboardShortcut(\"n\", modifiers: .command)",
            ".disabled(!enableTasks)",
            // View: the sidebar, the moon's three choices, full screen.
            "CommandGroup(replacing: .sidebar)",
            "BrainViewCommands()",
            ".keyboardShortcut(\"s\", modifiers: [.control, .command])",
            "Picker(String(localized: \"Appearance\"), selection: $appearance)",
            "visibility.isFullScreen ? String(localized: \"Exit Full Screen\") : String(localized: \"Enter Full Screen\")",
            ".keyboardShortcut(\"f\", modifiers: [.control, .command])",
        ].filter { !commands.contains($0) }
        var problems = menus.map { "missing: \($0)" }
        // View's three items act on Brain's window, so each is off while it is not on screen.
        let view = code(body(of: "private struct BrainViewCommands: View {", in: commands))
        if count(".disabled(!visibility.isOnScreen)", in: view) != 3 {
            problems.append("a View item acts while Brain is not on screen")
        }
        return problems
    }

    func testTheMenusHoldWhatThePlanNames() throws {
        let commands = Self.commands(in: try Self.read("Kannu/KannuApp.swift"))
        XCTAssertFalse(commands.isEmpty, "the commands went away — this pin is vacuous")
        XCTAssertEqual(Self.menuProblems(in: commands), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("ForEach(Array(SettingsTab.productPages.enumerated())", "ForEach(Array(SettingsTab.allCases.enumerated())"),
            ("Button(tab.title) { openBrain(on: tab) }", "Button(tab.title) { SettingsWindowController.shared.showWindow() }"),
            ("guard (0..<9).contains(index) else { return nil }\n", ""),
            (".disabled(!enableTasks)", ""),
            ("CommandGroup(replacing: .sidebar)", "CommandGroup(after: .sidebar)"),
            ("        .disabled(!visibility.isOnScreen)\n        Divider()", "        Divider()"),
        ], in: commands, by: Self.menuProblems)
    }

    // MARK: - Nothing runs before the terms

    /// Brain… and `openBrain` are the only two ways the menus open Brain, and each checks the terms first. The one other
    /// touch of the window is full screen's, whose item is off unless Brain is on screen, which it never is before.
    static func gateProblems(in commands: String) -> [String] {
        var problems: [String] = []
        let code = Self.code(commands)
        if count("SettingsWindowController.shared.showWindow()", in: code) != 2 {
            problems.append("a menu opens Brain without the terms check")
        }
        if count("guard appDelegate.launchContinued else {", in: code) != 2 {
            problems.append("an item that opens Brain does not wait for the terms")
        }
        if count("SettingsWindowController.shared", in: code) != 4 {
            problems.append("a menu builds Brain's window, which must wait for the terms")
        }
        let open = body(of: "private func openBrain(", in: code)
        if !isBefore("guard appDelegate.launchContinued else {", "SettingsWindowController.shared.showWindow()", in: open)
            || !open.contains("TermsGateWindowController.shared.bringToFront()") {
            problems.append("openBrain opens Brain before the terms are accepted")
        }
        // Menu keys reach the menu bar under a sheet; a page switched under it would close it and lose its typing. The
        // window is read only once the terms are accepted.
        let sheetCheck = "if SettingsWindowController.shared.window?.attachedSheet != nil {"
        if !isBefore("guard appDelegate.launchContinued else {", sheetCheck, in: open)
            || !isBefore(sheetCheck, "SettingsWindowController.shared.showWindow()", in: open) {
            problems.append("a Go item or New Task switches the page under a sheet")
        }
        // The request reaches the content once it is back in the window.
        if !isBefore("SettingsWindowController.shared.showWindow()", "SettingsHighlightCoordinator.shared.requestPage(tab)", in: open)
            || !isBefore("requestPage(tab)", "SettingsHighlightCoordinator.shared.pendingNewTask = true", in: open) {
            problems.append("openBrain asks for a page before Brain's content is in the window")
        }
        return problems
    }

    func testEveryItemThatOpensBrainWaitsForTheTerms() throws {
        let commands = Self.commands(in: try Self.read("Kannu/KannuApp.swift"))
        XCTAssertEqual(Self.gateProblems(in: commands), [])
        // `openBrain`'s guard: the comment after it is its own, so Brain…'s guard is left alone.
        let guarded = """
                guard appDelegate.launchContinued else {
                    TermsGateWindowController.shared.bringToFront()
                    return
                }
                // A sheet over Brain
        """
        SettingsDesignSystemRulesTests.assertCaught([
            (guarded, "        // A sheet over Brain"),
            ("Button(tab.title) { openBrain(on: tab) }", "Button(tab.title) { SettingsWindowController.shared.showWindow() }"),
            ("visibility.isFullScreen ?", "SettingsWindowController.shared.window?.styleMask.contains(.fullScreen) == true ?"),
            ("        SettingsWindowController.shared.showWindow()\n        SettingsHighlightCoordinator.shared.requestPage(tab)",
             "        SettingsHighlightCoordinator.shared.requestPage(tab)\n        SettingsWindowController.shared.showWindow()"),
            ("        if SettingsWindowController.shared.window?.attachedSheet != nil {\n            NSSound.beep()\n            return\n        }\n", ""),
        ], in: commands, by: Self.gateProblems)
    }

    // MARK: - The full-screen item's title

    /// Every way a transition ends updates `BrainVisibility`, so View's item never keeps the wrong title.
    static func fullScreenTitleProblems(in controller: String) -> [String] {
        let code = Self.code(controller)
        return ["func windowDidEnterFullScreen(", "func windowDidExitFullScreen(",
                "func windowDidFailToEnterFullScreen(", "func windowDidFailToExitFullScreen("]
            .filter { !body(of: $0, in: code).contains("BrainVisibility.shared.update(for: window)") }
            .map { "\($0) leaves the full-screen title as it was" }
    }

    func testEveryFullScreenOutcomeUpdatesTheTitle() throws {
        let controller = try Self.read("Kannu/components/Settings/SettingsWindowController.swift")
        XCTAssertEqual(Self.fullScreenTitleProblems(in: controller), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("        finishPendingClose()\n        // An occlusion change during the attempt may have read it as full screen.\n        BrainVisibility.shared.update(for: window)\n",
             "        finishPendingClose()\n"),
            ("        finishPendingClose()\n        // View's menu item says Enter Full Screen again.\n        if let window { BrainVisibility.shared.update(for: window) }\n",
             "        finishPendingClose()\n"),
        ], in: controller, by: Self.fullScreenTitleProblems)
    }

    // MARK: - One full-screen item

    /// AppKit adds its own Enter Full Screen once launching ends unless an item sends `toggleFullScreen:`, which a SwiftUI
    /// command cannot. Told no before it asks, View's item is the only one.
    static func fullScreenItemProblems(in app: String) -> [String] {
        let will = body(of: "func applicationWillFinishLaunching(_ notification: Notification) {", in: code(app))
        return will.contains("UserDefaults.standard.register(defaults: [\"NSFullScreenMenuItemEverywhere\": false])")
            ? [] : ["AppKit adds a second Enter Full Screen beside View's"]
    }

    func testAppKitAddsNoSecondFullScreenItem() throws {
        let app = try Self.read("Kannu/KannuApp.swift")
        XCTAssertEqual(Self.fullScreenItemProblems(in: app), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("        UserDefaults.standard.register(defaults: [\"NSFullScreenMenuItemEverywhere\": false])\n", ""),
            ("\"NSFullScreenMenuItemEverywhere\": false", "\"NSFullScreenMenuItemEverywhere\": true"),
        ], in: app, by: Self.fullScreenItemProblems)
    }

    // MARK: - New Task

    /// ⌘N has one owner, the menu, and Tasks takes the request once, with the filter of the list on screen.
    static func newTaskProblems(tasks: String, shortcutOwners: [String]) -> [String] {
        var problems: [String] = []
        let code = Self.code(tasks)
        let taken = body(of: ".onChange(of: highlights.pendingNewTask, initial: true) { _, asked in", in: code + "\n    }\n")
        if taken.isEmpty || !isBefore("highlights.pendingNewTask = false", "openNewTask()", in: taken) {
            problems.append("New Task's request is not taken once")
        }
        let open = body(of: "private func openNewTask() {", in: code)
        if !open.contains("guard enableTasks, sheet == nil else { return }")
            || !open.contains("sheet = .newTask(listFilter: newTaskListFilter)") {
            problems.append("New Task no longer opens as its shortcut did")
        }
        // From a Brain whose list is still loading the request would be taken and dropped; the sheet waits instead.
        if open.contains("isReady") {
            problems.append("New Task waits for the task list, so the first ⌘N after launch opens nothing")
        }
        if shortcutOwners != ["Kannu/KannuApp.swift"] {
            problems.append("⌘N has more than one owner: \(shortcutOwners)")
        }
        return problems
    }

    /// Every app file that binds ⌘N.
    private static func shortcutOwners(replacing path: String? = nil, with text: String? = nil) throws -> [String] {
        let root = repoRoot.appendingPathComponent("Kannu")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 100, "the scan found no sources — check the root, not the rule")
        return try files.compactMap { url -> String? in
            let relative = url.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
            let source = relative == path ? (text ?? "") : try String(contentsOf: url, encoding: .utf8)
            return code(source).contains(".keyboardShortcut(\"n\", modifiers: .command)") ? relative : nil
        }.sorted()
    }

    func testNewTaskHasOneShortcutAndOneRequest() throws {
        let tasksPath = "Kannu/components/Settings/TasksSettings.swift"
        let tasks = try Self.read(tasksPath)
        XCTAssertEqual(Self.newTaskProblems(tasks: tasks, shortcutOwners: try Self.shortcutOwners()), [])
        let owners = try Self.shortcutOwners()
        SettingsDesignSystemRulesTests.assertCaught([
            ("            highlights.pendingNewTask = false\n", ""),
            ("guard enableTasks, sheet == nil else { return }", "guard enableTasks else { return }"),
            ("guard enableTasks, sheet == nil else { return }", "guard enableTasks, sheet == nil, TasksManager.shared.isReady else { return }"),
        ], in: tasks) { Self.newTaskProblems(tasks: $0, shortcutOwners: owners) }
        // The old hidden button back: a second owner.
        let hidden = tasks.replacingOccurrences(of: "    private func openNewTask() {",
                                                with: "    var shortcut: some View { Button(\"New Task\") {}.keyboardShortcut(\"n\", modifiers: .command) }\n    private func openNewTask() {")
        XCTAssertNotEqual(hidden, tasks)
        XCTAssertFalse(Self.newTaskProblems(tasks: hidden, shortcutOwners: try Self.shortcutOwners(replacing: tasksPath, with: hidden)).isEmpty)
    }

    // MARK: - Go is a sidebar row's click

    /// A Go item opens a page through the switch point a search pick uses, with no row: nothing pulses, and the Tasks
    /// tab, which goes back to its overview on a Tasks highlight, keeps its place. Its pages come from the sidebar's
    /// own list, so the two cannot disagree.
    static func pageProblems(view: String, shell: String) -> [String] {
        var problems: [String] = []
        let code = Self.code(view)
        let request = body(of: "func requestPage(_ tab: SettingsTab) {", in: code)
        if !request.contains("pendingScrollRequest = ScrollRequest(id: tab.rawValue, tab: tab)") || request.contains("activateHighlight") {
            problems.append("a Go item does not open its page as a sidebar row does")
        }
        if !code.contains("static var productPages: [SettingsTab] { sidebarOrder.filter { $0.group == .product } }")
            || !code.contains("private var availableTabs: [SettingsTab] {\n        SettingsTab.sidebarOrder\n    }") {
            problems.append("Go's pages are not the sidebar's")
        }
        if !code.contains("BrainShell(showsSidebar: showsSidebar && !snapshotHidesSidebar) {")
            || !Self.code(shell).contains("if showsSidebar {") {
            problems.append("View › Hide Sidebar does not reach the shell")
        }
        return problems
    }

    func testGoOpensAPageAsItsSidebarRowDoes() throws {
        let view = try Self.read("Kannu/components/Settings/SettingsView.swift")
        let shell = try Self.read("Kannu/components/Settings/DesignSystem/BrainShell.swift")
        XCTAssertEqual(Self.pageProblems(view: view, shell: shell), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("        pendingScrollRequest = ScrollRequest(id: tab.rawValue, tab: tab)\n",
             "        pendingScrollRequest = ScrollRequest(id: tab.rawValue, tab: tab)\n        activateHighlight(id: tab.rawValue)\n"),
            ("sidebarOrder.filter { $0.group == .product }", "[.agentStatus, .agentSecurity, .llmUsage]"),
            ("BrainShell(showsSidebar: showsSidebar && !snapshotHidesSidebar) {", "BrainShell {"),
        ], in: view) { Self.pageProblems(view: $0, shell: shell) }
        SettingsDesignSystemRulesTests.assertCaught([("if showsSidebar {", "if true {")], in: shell) { Self.pageProblems(view: view, shell: $0) }
    }

    // MARK: - The boards

    /// No PNG shows the menu bar, so the snapshot run writes it out; and the two new states have boards.
    func testTheBoardsDrawTheMenusAndTheirStates() throws {
        let snapshots = Self.code(try Self.read("Kannu/helpers/DebugSnapshot.swift"))
        for needle in ["writeMenuReport(into: request.directory)",
                       "(\"shellNoSidebar\", AnyView(SettingsView(snapshotTab: .agentStatus, hidesSidebar: true)))",
                       "SettingsHighlightCoordinator.shared.requestPage(.llmUsage)"] {
            XCTAssertTrue(snapshots.contains(needle), "missing: \(needle)")
        }
    }
}
