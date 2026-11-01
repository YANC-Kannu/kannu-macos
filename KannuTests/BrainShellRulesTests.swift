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

/// What `docs/SETTINGS.md`, "The shell and navigation", says, held against the sources: the shell
/// knows no page, the selected tab is the only navigation state, and every tab stays reachable. The
/// views are not in this logic target. Every scanner reads code with its comments blanked and is
/// proved against planted offenders or against a broken copy of the real source.
final class BrainShellRulesTests: XCTestCase {

    private static let settingsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Kannu/components/Settings", isDirectory: true)

    private static func code(_ path: String) throws -> String {
        SettingsDesignSystemRulesTests.code(try String(contentsOf: settingsDirectory.appendingPathComponent(path), encoding: .utf8))
    }

    private static func view() throws -> String { try code("SettingsView.swift") }

    /// `struct SettingsView` without the search bar nested in it, whose own state is its own.
    private static func navigation(in view: String) throws -> String {
        let start = try XCTUnwrap(view.range(of: "struct SettingsView: View {"))
        let end = try XCTUnwrap(view.range(of: "private struct SettingsSidebarSearchBar", range: start.upperBound..<view.endIndex))
        return String(view[start.lowerBound..<end.lowerBound])
    }

    private static func assertCaught(_ edits: [(from: String, to: String)], in source: String, by problems: (String) -> [String],
                                     file: StaticString = #filePath, line: UInt = #line) {
        SettingsDesignSystemRulesTests.assertCaught(edits, in: source, by: problems, file: file, line: line)
    }

    // MARK: - The shell knows no page

    private static func pageKnowledge(in code: String) -> [String] {
        ["SettingsTab", "Defaults", "Manager"].filter { code.contains($0) }
    }

    func testTheShellAndItsRowsKnowNoPage() throws {
        for name in ["BrainShell.swift", "SettingsSidebarRow.swift"] {
            XCTAssertEqual(Self.pageKnowledge(in: try Self.code("DesignSystem/" + name)), [], name)
        }

        XCTAssertEqual(Self.pageKnowledge(in: "let tab: SettingsTab"), ["SettingsTab"])
        XCTAssertEqual(Self.pageKnowledge(in: "@Default(.a) var a\nDefaults[.b]"), ["Defaults"])
        XCTAssertEqual(Self.pageKnowledge(in: "TasksManager.shared"), ["Manager"])
        XCTAssertEqual(Self.pageKnowledge(in: SettingsDesignSystemRulesTests.code("// a SettingsTab in a comment")), [])
    }

    // MARK: - What the shell replaced stays gone

    private static func replacedChrome(in code: String) -> [String] {
        ["NavigationSplitView", ".toolbar", "glassEffect", ".ultraThinMaterial"].filter { code.contains($0) }
    }

    func testTheSplitViewAndItsGlassAreGone() throws {
        XCTAssertEqual(Self.replacedChrome(in: try Self.view()), [])

        XCTAssertEqual(Self.replacedChrome(in: "NavigationSplitView {}\n.toolbar(removing: .sidebarToggle)"), ["NavigationSplitView", ".toolbar"])
        XCTAssertEqual(Self.replacedChrome(in: ".glassEffect(.clear)\n.fill(.ultraThinMaterial)"), ["glassEffect", ".ultraThinMaterial"])
    }

    // MARK: - One piece of navigation state

    private static let stateNames = #"@State private var (\w+)"#

    private static func stateProblems(in navigation: String) -> [String] {
        var problems: [String] = []
        let tabs = SettingsDesignSystemRulesTests.matches(of: #"@State private var \w+: SettingsTab ="#, in: navigation)
        if tabs != ["@State private var selectedTab: SettingsTab ="] { problems.append("selectedTab is not the only tab that is set: \(tabs)") }
        // A mode flag of any type would be a second answer to "which list is on screen".
        let names = SettingsDesignSystemRulesTests.matches(of: stateNames, in: navigation).map { $0.replacingOccurrences(of: "@State private var ", with: "") }
        if names != ["selectedTab", "searchText", "tabOnOtherList"] { problems.append("new state beside the selected tab: \(names)") }
        if !navigation.contains("private var showsSettingsList: Bool { resolvedSelection.group == .settings }") {
            problems.append("the list on screen no longer follows the selected tab")
        }
        return problems
    }

    /// Every write of the return tab. Back and the Settings row read it; only a change of list writes it.
    private static func returnTabProblems(in navigation: String) -> [String] {
        let writes = navigation.components(separatedBy: "tabOnOtherList =").count - 1
        let inTheChange = navigation.contains(".onChange(of: selectedTab) { old, new in\n            if (old.group == .settings) != (new.group == .settings) { tabOnOtherList = old }")
        return writes == 1 && inTheChange ? [] : ["tabOnOtherList is written \(writes) times, in the change of list: \(inTheChange)"]
    }

    func testTheSelectedTabIsTheOnlyNavigationState() throws {
        let navigation = try Self.navigation(in: try Self.view())
        XCTAssertEqual(Self.stateProblems(in: navigation), [])
        XCTAssertEqual(Self.returnTabProblems(in: navigation), [])

        Self.assertCaught([("@State private var selectedTab: SettingsTab = .agentStatus", "@State private var selectedTab: SettingsTab = .agentStatus\n@State private var mode: SettingsTab = .general"),
                           ("@State private var searchText: String = \"\"", "@State private var searchText: String = \"\"\n@State private var showsSettings = false"),
                           ("resolvedSelection.group == .settings }", "isShowingSettings }")],
                          in: navigation, by: Self.stateProblems)
        Self.assertCaught([("{ tabOnOtherList = old }", "{ }"),
                           ("selectedTab = tabOnOtherList ?? .agentStatus", "selectedTab = tabOnOtherList ?? .agentStatus\ntabOnOtherList = nil"),
                           ("(old.group == .settings) != (new.group == .settings)", "old != new")],
                          in: navigation, by: Self.returnTabProblems)
    }

    private static func returnProblems(in navigation: String) -> [String] {
        ["selectedTab = tabOnOtherList ?? .agentStatus", "selectedTab = tabOnOtherList ?? .general"].filter { !navigation.contains($0) }
    }

    func testBackAndTheSettingsRowReturnToWhereTheUserWas() throws {
        let navigation = try Self.navigation(in: try Self.view())
        XCTAssertEqual(Self.returnProblems(in: navigation), [])
        Self.assertCaught([("selectedTab = tabOnOtherList ?? .agentStatus", "selectedTab = .agentStatus"),
                           ("selectedTab = tabOnOtherList ?? .general", "selectedTab = .general")],
                          in: navigation, by: Self.returnProblems)
    }

    /// Search picks and deep links share one switch point, so the sidebar follows them with no path of
    /// its own.
    private static func hasTheSwitchPoint(in code: String) -> Bool {
        !SettingsDesignSystemRulesTests.matches(of: #"\.onReceive\(highlightCoordinator\.\$pendingScrollRequest\.compactMap \{ \$0 \}\) \{ request in\s*selectedTab = request\.tab\s*\}"#, in: code).isEmpty
    }

    func testADeepLinkOrASearchMovesTheTabInOnePlace() throws {
        let navigation = try Self.navigation(in: try Self.view())
        XCTAssertTrue(Self.hasTheSwitchPoint(in: navigation))
        XCTAssertEqual(navigation.components(separatedBy: "selectedTab = request.tab").count - 1, 1)

        XCTAssertTrue(Self.hasTheSwitchPoint(in: ".onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { $0 }) { request in\n    selectedTab = request.tab\n}"))
        XCTAssertFalse(Self.hasTheSwitchPoint(in: ".onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { $0 }) { request in\n    log(request)\n}"))
        XCTAssertFalse(Self.hasTheSwitchPoint(in: "selectedTab = request.tab"))
    }

    // MARK: - Every tab stays reachable

    private static func formsIn(detailOf view: String) -> [String] {
        guard let start = view.range(of: "private func detailView(for tab: SettingsTab)"),
              let end = view.range(of: "#if DEBUG", range: start.upperBound..<view.endIndex) else { return [] }
        return SettingsDesignSystemRulesTests.matches(of: #"SettingsForm\(tab: \.\w+\)"#, in: String(view[start.upperBound..<end.lowerBound]))
    }

    func testEveryTabKeepsItsForm() throws {
        let forms = Self.formsIn(detailOf: try Self.view())
        XCTAssertEqual(forms.count, 22, "a page outside SettingsForm has no header, no scroll and no highlight")
        XCTAssertEqual(Set(forms).count, 22, "a tab shows another tab's page")

        XCTAssertEqual(Self.formsIn(detailOf: "private func detailView(for tab: SettingsTab) {\nSettingsForm(tab: .a)\nSettingsForm(tab: .b)\n}\n#if DEBUG\nSettingsForm(tab: .c)\n"),
                       ["SettingsForm(tab: .a)", "SettingsForm(tab: .b)"])
        XCTAssertEqual(Self.formsIn(detailOf: "SettingsForm(tab: .a)"), [])
    }

    // MARK: - The row and the keyboard

    private static func rowProblems(in row: String) -> [String] {
        [".accessibilityAddTraits(isSelected ? .isSelected : [])", ".buttonStyle(.plain)", ".accessibilityHidden(true)"].filter { !row.contains($0) }
    }

    func testARowSaysItIsSelectedAndKeepsOutOfTheRootsChrome() throws {
        let row = try Self.code("DesignSystem/SettingsSidebarRow.swift")
        XCTAssertEqual(Self.rowProblems(in: row), [])
        Self.assertCaught([(".accessibilityAddTraits(isSelected ? .isSelected : [])", ""), (".buttonStyle(.plain)", ""), (".accessibilityHidden(true)", "")],
                          in: row, by: Self.rowProblems)
    }

    private static func keyboardProblems(in navigation: String) -> [String] {
        var problems = [".focusable()", ".focused($sidebarHasFocus)", ".focusEffectDisabled()", ".onKeyPress(keys: [.upArrow, .downArrow])"]
            .filter { !navigation.contains($0) }
        // A row, Back and the Settings row each hand the keyboard to the list. Arrow keys stay dead after any that does not.
        let focusing = navigation.components(separatedBy: "sidebarHasFocus = true").count - 1
        if focusing != 3 { problems.append("\(focusing) rows hand the keyboard to the list") }
        return problems
    }

    func testTheSidebarTakesArrowKeys() throws {
        let navigation = try Self.navigation(in: try Self.view())
        XCTAssertEqual(Self.keyboardProblems(in: navigation), [])
        Self.assertCaught([(".onKeyPress(keys: [.upArrow, .downArrow])", ".onKeyPress(keys: [.upArrow])"), (".focusable()", ""),
                           (".focused($sidebarHasFocus)", ""), (".focusEffectDisabled()", ""),
                           ("selectedTab = tabOnOtherList ?? .agentStatus\n                            sidebarHasFocus = true",
                            "selectedTab = tabOnOtherList ?? .agentStatus")],
                          in: navigation, by: Self.keyboardProblems)
    }

    /// Spelled out in full: `SettingsForm` has its own `proxy.scrollTo`, so finding the bare call in
    /// this file would prove nothing.
    private static func followsItsSelection(in navigation: String) -> Bool {
        navigation.contains(".onChange(of: resolvedSelection) { _, tab in proxy.scrollTo(tab) }")
    }

    func testTheSidebarFollowsItsSelection() throws {
        let view = try Self.view()
        XCTAssertTrue(Self.followsItsSelection(in: try Self.navigation(in: view)))
        XCTAssertFalse(Self.followsItsSelection(in: "withAnimation { proxy.scrollTo(request.id, anchor: .center) }"))
    }

    // MARK: - The large title

    private static func titleProblems(form: String, tasks: String) -> [String] {
        var problems = ["SettingsPageHeader(title: pageTitle ?? tab.title)", ".onPreferenceChange(SettingsPageTitleKey.self)"].filter { !form.contains($0) }
        if !tasks.contains(".settingsPageTitle(enableTasks ? path.last.map(Self.title) ?? Self.overviewTitle : Self.overviewTitle)") {
            problems.append("Tasks no longer names its sub-pages")
        }
        return problems
    }

    func testAPageGetsItsTitleWithNoEditOfItsOwn() throws {
        let form = try Self.view()
        let tasks = try Self.code("TasksSettings.swift")
        XCTAssertEqual(Self.titleProblems(form: form, tasks: tasks), [])
        XCTAssertEqual(tasks.components(separatedBy: ".navigationTitle").count - 1, 0, "Tasks says its title once, through the preference")

        Self.assertCaught([("pageTitle ?? tab.title", "tab.title"), (".onPreferenceChange(SettingsPageTitleKey.self)", ".onPreferenceChange(OtherKey.self)")],
                          in: form) { Self.titleProblems(form: $0, tasks: tasks) }
        Self.assertCaught([("settingsPageTitle(enableTasks", "navigationTitle(enableTasks")], in: tasks) { Self.titleProblems(form: form, tasks: $0) }
    }

    // MARK: - The boards

    func testTheBoardsDrawTheWholeWindow() throws {
        let root = Self.settingsDirectory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("helpers/DebugSnapshot.swift")
        let snapshots = SettingsDesignSystemRulesTests.code(try String(contentsOf: root, encoding: .utf8))
        for board in ["\"shell\"", "\"shellSettings\"", "\"shellDeepLink\"", "\"shellSearch\"", "\"shellSearchList\""] {
            XCTAssertTrue(snapshots.contains(board), "\(board) is the only headless view of that state")
        }
        XCTAssertTrue(snapshots.contains("width: 700, into: request.directory, fixedHeight: 600"), "the whole window at today's size")
        XCTAssertTrue(snapshots.contains("document.frame.height + hosting.bounds.height - scroll.frame.height"),
                      "a page's header would clip its last rows")
    }
}
