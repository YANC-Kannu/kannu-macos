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

    /// All of `struct SettingsView` but the search bar nested in it, whose own state is its own. The
    /// struct goes on past the bar, so stopping there would leave its last 400 lines unread.
    private static func navigation(in view: String) throws -> String {
        let start = try XCTUnwrap(view.range(of: "struct SettingsView: View {"))
        let bar = try XCTUnwrap(view.range(of: "private struct SettingsSidebarSearchBar", range: start.upperBound..<view.endIndex))
        let resume = try XCTUnwrap(view.range(of: "private func searchEntries(matching", range: bar.upperBound..<view.endIndex))
        let end = try XCTUnwrap(view.range(of: "#if DEBUG", range: resume.upperBound..<view.endIndex))
        return String(view[start.lowerBound..<bar.lowerBound]) + String(view[resume.lowerBound..<end.lowerBound])
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
        // The select, its list, the field, the slider, the stepper, the sheet and the date too: a page hands them their data.
        // The page, the section and the page's inset too: a page hands them its rows.
        for name in ["BrainShell.swift", "SettingsSidebarRow.swift", "SettingsSelect.swift", "SettingsSelectList.swift",
                     "SettingsField.swift", "SettingsSlider.swift", "SettingsStepper.swift", "SettingsSheet.swift",
                     "SettingsDateField.swift", "SettingsPage.swift", "SettingsSection.swift", "SettingsPageInsetKey.swift"] {
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
        for name in ["SettingsView.swift", "DesignSystem/BrainShell.swift"] {
            XCTAssertEqual(Self.replacedChrome(in: try Self.code(name)), [], name)
        }

        XCTAssertEqual(Self.replacedChrome(in: "NavigationSplitView {}\n.toolbar(removing: .sidebarToggle)"), ["NavigationSplitView", ".toolbar"])
        XCTAssertEqual(Self.replacedChrome(in: ".glassEffect(.clear)\n.fill(.ultraThinMaterial)"), ["glassEffect", ".ultraThinMaterial"])
    }

    // MARK: - One piece of navigation state

    private static let stateNames = #"@(?:State|AppStorage|SceneStorage|Default)\b[^\n]*?\bvar \w+"#

    private static func stateProblems(in navigation: String) -> [String] {
        var problems: [String] = []
        let tabs = SettingsDesignSystemRulesTests.matches(of: #"@State private var \w+: SettingsTab ="#, in: navigation)
        if tabs != ["@State private var selectedTab: SettingsTab ="] { problems.append("selectedTab is not the only tab that is set: \(tabs)") }
        // A mode flag of any type would be a second answer to "which list is on screen".
        let names = SettingsDesignSystemRulesTests.matches(of: stateNames, in: navigation).compactMap { $0.components(separatedBy: " var ").last }
        if names != ["selectedTab", "searchText", "lastProductTab", "lastSettingsTab"] { problems.append("new state beside the selected tab: \(names)") }
        if !navigation.contains("private var showsSettingsList: Bool { resolvedSelection.group == .settings }") {
            problems.append("the list on screen no longer follows the selected tab")
        }
        return problems
    }

    /// Every write of the return tabs. Back and the Settings row read them; only `remember` writes them,
    /// and a search's jumps never reach it: one of them is not where the user was.
    private static func returnTabProblems(in navigation: String) -> [String] {
        var problems = ["if tab.group == .settings { lastSettingsTab = tab } else { lastProductTab = tab }",
                        ".onChange(of: selectedTab) { old, _ in\n            if !isSearching { remember(old) }",
                        "if old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { remember(resolvedSelection) }"]
            .filter { !navigation.contains($0) }
        for slot in ["lastProductTab =", "lastSettingsTab ="] {
            let writes = navigation.components(separatedBy: slot).count - 1
            if writes != 1 { problems.append("\(slot) appears \(writes) times") }
        }
        return problems
    }

    func testTheSelectedTabIsTheOnlyNavigationState() throws {
        let navigation = try Self.navigation(in: try Self.view())
        XCTAssertEqual(Self.stateProblems(in: navigation), [])
        XCTAssertEqual(Self.returnTabProblems(in: navigation), [])

        Self.assertCaught([("@State private var selectedTab: SettingsTab = .agentStatus", "@State private var selectedTab: SettingsTab = .agentStatus\n@State private var mode: SettingsTab = .general"),
                           ("@State private var searchText: String = \"\"", "@State private var searchText: String = \"\"\n@State private var showsSettings = false"),
                           ("resolvedSelection.group == .settings }", "isShowingSettings }"),
                           // Below the search bar, which is as far as this rule used to read.
                           ("private func detailView(for tab: SettingsTab)", "@State private var showsSettings = false\nprivate func detailView(for tab: SettingsTab)"),
                           // A wrapper or a spelling other than `@State private var`.
                           ("@State private var searchText: String = \"\"", "@State private var searchText: String = \"\"\n@AppStorage(\"m\") var showsSettings = false"),
                           ("@State private var searchText: String = \"\"", "@State var mode = 0\n@State private var searchText: String = \"\"")],
                          in: navigation, by: Self.stateProblems)
        Self.assertCaught([("{ lastSettingsTab = tab } else { lastProductTab = tab }", "{ } else { }"),
                           // The bug this replaced: every keystroke that changes list overwrites the return tab.
                           ("if !isSearching { remember(old) }", "remember(old)"),
                           ("if old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { remember(resolvedSelection) }", ""),
                           ("selectedTab = lastProductTab ?? .agentStatus", "selectedTab = lastProductTab ?? .agentStatus\nlastProductTab = nil"),
                           ("private func detailView(for tab: SettingsTab)", "lastSettingsTab = .general\nprivate func detailView(for tab: SettingsTab)")],
                          in: navigation, by: Self.returnTabProblems)
    }

    private static func returnProblems(in navigation: String) -> [String] {
        ["selectedTab = lastProductTab ?? .agentStatus", "selectedTab = lastSettingsTab ?? .general"].filter { !navigation.contains($0) }
    }

    func testBackAndTheSettingsRowReturnToWhereTheUserWas() throws {
        let navigation = try Self.navigation(in: try Self.view())
        XCTAssertEqual(Self.returnProblems(in: navigation), [])
        Self.assertCaught([("selectedTab = lastProductTab ?? .agentStatus", "selectedTab = .agentStatus"),
                           ("selectedTab = lastSettingsTab ?? .general", "selectedTab = .general")],
                          in: navigation, by: Self.returnProblems)
    }

    /// Search picks and deep links share one switch point, so the sidebar follows them with no path of
    /// its own. A query left typed gives way when its flat list has no row for the tab.
    private static func hasTheSwitchPoint(in code: String) -> Bool {
        !SettingsDesignSystemRulesTests.matches(of: #"\.onReceive\(highlightCoordinator\.\$pendingScrollRequest\.compactMap \{ \$0 \}\) \{ request in\s*selectedTab = request\.tab\s*if !filteredTabs\.contains\(request\.tab\) \{ searchText = "" \}\s*\}"#, in: code).isEmpty
    }

    func testADeepLinkOrASearchMovesTheTabInOnePlace() throws {
        let navigation = try Self.navigation(in: try Self.view())
        XCTAssertTrue(Self.hasTheSwitchPoint(in: navigation))
        XCTAssertEqual(navigation.components(separatedBy: "selectedTab = request.tab").count - 1, 1)

        let switchPoint = ".onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { $0 }) { request in\n    selectedTab = request.tab\n    if !filteredTabs.contains(request.tab) { searchText = \"\" }\n}"
        XCTAssertTrue(Self.hasTheSwitchPoint(in: switchPoint))
        XCTAssertFalse(Self.hasTheSwitchPoint(in: ".onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { $0 }) { request in\n    selectedTab = request.tab\n}"))
        XCTAssertFalse(Self.hasTheSwitchPoint(in: ".onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { $0 }) { request in\n    log(request)\n}"))
        XCTAssertFalse(Self.hasTheSwitchPoint(in: "selectedTab = request.tab"))
    }

    // MARK: - Every tab stays reachable

    /// A query shows one flat list and neither Back nor the Settings row; with no query the sidebar shows
    /// the selected tab's list. `tabRow(.about)` is the only way to About but a search.
    private static func listProblems(in navigation: String) -> [String] {
        ["if isSearching { return filteredTabs }",
         "availableTabs.filter { $0.group == (showsSettingsList ? .settings : .product) }",
         "if showsSettingsList && !isSearching {",
         "if !showsSettingsList && !isSearching {",
         "tabRow(.about)",
         "ForEach(listedTabs)"].filter { !navigation.contains($0) }
    }

    func testEachListShowsWhatTheDocSays() throws {
        let navigation = try Self.navigation(in: try Self.view())
        XCTAssertEqual(Self.listProblems(in: navigation), [])
        Self.assertCaught([("if isSearching { return filteredTabs }", ""),
                           ("tabRow(.about)", ""),
                           ("if showsSettingsList && !isSearching {", "if showsSettingsList {"),
                           ("if !showsSettingsList && !isSearching {", "if !showsSettingsList {"),
                           ("(showsSettingsList ? .settings : .product)", "(.product)"),
                           ("ForEach(listedTabs)", "ForEach(availableTabs)")],
                          in: navigation, by: Self.listProblems)
    }

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
        // The newline, or `listedTabs + [.about]` would pass: About is a foot row, not in the arrow order.
        var problems = [".onKeyPress(keys: [.upArrow, .downArrow])", ".onKeyPress(keys: [.leftArrow, .rightArrow])", "let tabs = listedTabs\n",
                        "selectedTab = (offset < 0 ? tabs.last : tabs.first) ?? selectedTab"]
            .filter { !navigation.contains($0) }
        // On a background: an outer `focusEffectDisabled` beats the rows' own, and takes their ring.
        let focusStop = #"\.background \{\s*Color\.clear\s*\.focusable\(\)\s*\.focused\(\$sidebarHasFocus\)\s*\.focusEffectDisabled\(\)"#
        if SettingsDesignSystemRulesTests.matches(of: focusStop, in: navigation).isEmpty { problems.append("the focus stop is not a background of its own") }
        // A row, Back and the Settings row each hand the keyboard to the list. Arrow keys stay dead after any that does not.
        let focusing = navigation.components(separatedBy: "sidebarHasFocus = true").count - 1
        if focusing != 3 { problems.append("\(focusing) rows hand the keyboard to the list") }
        return problems
    }

    func testTheSidebarTakesArrowKeys() throws {
        let navigation = try Self.navigation(in: try Self.view())
        XCTAssertEqual(Self.keyboardProblems(in: navigation), [])
        Self.assertCaught([(".onKeyPress(keys: [.upArrow, .downArrow])", ".onKeyPress(keys: [.upArrow])"),
                           (".onKeyPress(keys: [.leftArrow, .rightArrow])", ".onKeyPress(keys: [.leftArrow])"),
                           ("let tabs = listedTabs\n", "let tabs = listedTabs + [.about]\n"),
                           ("selectedTab = (offset < 0 ? tabs.last : tabs.first) ?? selectedTab", ""),
                           ("Color.clear", "Group"), (".focusable()", ""), (".focused($sidebarHasFocus)", ""), (".focusEffectDisabled()", ""),
                           ("selectedTab = lastProductTab ?? .agentStatus\n        sidebarHasFocus = true",
                            "selectedTab = lastProductTab ?? .agentStatus")],
                          in: navigation, by: Self.keyboardProblems)
    }

    /// Spelled out in full: `SettingsForm` has its own `proxy.scrollTo`, so finding the bare call in
    /// this file would prove nothing. A query moves the list under the selected row with no change of tab.
    private static func followsItsSelection(in navigation: String) -> Bool {
        navigation.contains(".onChange(of: resolvedSelection) { _, tab in proxy.scrollTo(tab) }")
            && navigation.contains(".onChange(of: listedTabs, initial: true) { _, _ in proxy.scrollTo(resolvedSelection) }")
    }

    func testTheSidebarFollowsItsSelection() throws {
        let navigation = try Self.navigation(in: try Self.view())
        XCTAssertTrue(Self.followsItsSelection(in: navigation))
        XCTAssertFalse(Self.followsItsSelection(in: "withAnimation { proxy.scrollTo(request.id, anchor: .center) }"))
        XCTAssertFalse(Self.followsItsSelection(in: navigation.replacingOccurrences(of: ".onChange(of: listedTabs, initial: true)", with: ".onAppear")))
    }

    // MARK: - Reduce Motion

    private static func motionProblems(in view: String) -> [String] {
        ["withAnimation(scrollAnimation)",
         "return reduceMotion ? nil : .easeInOut(duration: 0.45)",
         ".animation(reduceMotion ? nil : .easeInOut(duration: SettingsTheme.quickAnimation), value: showSuggestions)",
         ".transition(reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .move(edge: .top)))"]
            .filter { !view.contains($0) }
    }

    func testTheSidebarAndTheDeepLinkScrollRespectReduceMotion() throws {
        let view = try Self.view()
        XCTAssertEqual(Self.motionProblems(in: view), [])
        Self.assertCaught([("reduceMotion ? nil : .easeInOut(duration: 0.45)", ".easeInOut(duration: 0.45)"),
                           ("withAnimation(scrollAnimation)", "withAnimation(.easeInOut(duration: 0.45))"),
                           ("reduceMotion ? nil : .easeInOut(duration: SettingsTheme.quickAnimation)", ".easeInOut(duration: SettingsTheme.quickAnimation)"),
                           ("reduceMotion ? AnyTransition.opacity : ", "")],
                          in: view, by: Self.motionProblems)
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

    // MARK: - The window's width and title bar

    /// In `SettingsForm`, which every page goes through, so no page can miss it. Capped first, then held
    /// the page inset from the panel's leading edge, then measured: the width flag must read the
    /// panel-wide frame, because above the cap it would see at most 720 pt and never reach
    /// `widePanelWidth`. Centred, a full-screen page floats in a blank panel; with the cap outside the
    /// padding, the inset would come out of the page's 720 pt.
    private static func pageCapProblems(in view: String) -> [String] {
        guard let start = view.range(of: "private struct SettingsForm<Content: View>: View {"),
              let end = view.range(of: "struct SettingsView: View {", range: start.upperBound..<view.endIndex) else {
            return ["SettingsForm cannot be found"]
        }
        let leading = #"\.frame\(maxWidth: SettingsTheme\.pageMaxWidth\)\s*"#
            + #"\.padding\(\.horizontal, \(isWidePanel \? SettingsTheme\.pageInsetWide : SettingsTheme\.pageInset\) - SettingsTheme\.formMargin\)\s*"#
            + #"\.frame\(maxWidth: \.infinity, alignment: \.leading\)\s*"#
            + #"\.onGeometryChange\(for: Bool\.self\) \{ \$0\.size\.width >= SettingsTheme\.widePanelWidth \} action: \{ isWidePanel = \$0 \}"#
        let found = SettingsDesignSystemRulesTests.matches(of: leading, in: String(view[start.upperBound..<end.lowerBound])).count
        return found == 1 ? [] : ["a page is not capped, held to the leading edge and measured at the panel's width"]
    }

    private static let pageCap = ".frame(maxWidth: SettingsTheme.pageMaxWidth)"
    private static let pageInset = ".padding(.horizontal, (isWidePanel ? SettingsTheme.pageInsetWide : SettingsTheme.pageInset) - SettingsTheme.formMargin)"
    private static let pageLeading = ".frame(maxWidth: .infinity, alignment: .leading)"
    private static let pageMeasure = ".onGeometryChange(for: Bool.self) { $0.size.width >= SettingsTheme.widePanelWidth } action: { isWidePanel = $0 }"

    func testAPageIsCappedAndLeading() throws {
        let view = try Self.view()
        XCTAssertEqual(Self.pageCapProblems(in: view), [])
        let line = "\n            "
        Self.assertCaught([(Self.pageCap, ""),
                           (Self.pageLeading, ".frame(maxWidth: .infinity)"),
                           (line + Self.pageInset, ""),
                           (" - SettingsTheme.formMargin)", ")"),
                           ("isWidePanel ? SettingsTheme.pageInsetWide : SettingsTheme.pageInset", "isWidePanel ? SettingsTheme.pageInset : SettingsTheme.pageInset"),
                           ("action: { isWidePanel = $0 }", "action: { _ in }"),
                           (Self.pageCap + line + Self.pageInset, Self.pageInset + line + Self.pageCap),
                           (Self.pageCap + line + Self.pageInset + line + Self.pageLeading + line + Self.pageMeasure,
                            Self.pageMeasure + line + Self.pageCap + line + Self.pageInset + line + Self.pageLeading)],
                          in: view, by: Self.pageCapProblems)
        // On the root instead: the panel's scrollbar would move, and a page outside the root would miss it.
        let chain = [Self.pageCap, Self.pageInset, Self.pageLeading, Self.pageMeasure].joined(separator: "\n")
        XCTAssertEqual(Self.pageCapProblems(in: "private struct SettingsForm<Content: View>: View {\n}\nstruct SettingsView: View {\n\(chain)\n}"),
                       ["a page is not capped, held to the leading edge and measured at the panel's width"])
        XCTAssertEqual(Self.pageCapProblems(in: "private struct SettingsForm<Content: View>: View {\n\(chain)\n}\nstruct SettingsView: View {\n}"), [])
    }

    /// A transparent title bar with the row still below the safe area would leave a blank strip above
    /// it, and the moon a row below the traffic lights.
    private static func titleRowProblems(shell: String, controller: String) -> [String] {
        var problems = [".ignoresSafeArea(.container, edges: .top)"].filter { !shell.contains($0) }
        problems += ["window.titlebarAppearsTransparent = true", "window.titleVisibility = .hidden", "window.titlebarSeparatorStyle = .none"]
            .filter { !controller.contains($0) }
        return problems
    }

    func testTheTitleRowLiesUnderTheTitleBar() throws {
        let shell = try Self.code("DesignSystem/BrainShell.swift")
        let controller = try Self.code("SettingsWindowController.swift")
        XCTAssertEqual(Self.titleRowProblems(shell: shell, controller: controller), [])
        Self.assertCaught([(".ignoresSafeArea(.container, edges: .top)", "")], in: shell) { Self.titleRowProblems(shell: $0, controller: controller) }
        Self.assertCaught([("titlebarAppearsTransparent = true", "titlebarAppearsTransparent = false"),
                           ("titleVisibility = .hidden", "titleVisibility = .visible"),
                           ("titlebarSeparatorStyle = .none", "titlebarSeparatorStyle = .line")],
                          in: controller) { Self.titleRowProblems(shell: shell, controller: $0) }
    }

    // MARK: - The boards

    /// Each board is the only headless view of its state. `allTasks` goes through `SettingsForm`, or it
    /// has no title to show or to clip by. The deep link's row is below the fold, or a dead `scrollTo`
    /// draws the same picture, and the run scrolls at once, or an animated scroll never moves.
    private static func boardProblems(in snapshots: String) -> [String] {
        ["(\"shell\", AnyView(", "(\"shellSettings\", AnyView(", "(\"shellWide\", AnyView(", "(\"shellDeepLink\", AnyView(",
         "(\"shellSearch\", AnyView(", "(\"shellSearchList\", AnyView(",
         "SettingsView.snapshotPageTitle(Form {",
         "SettingsTab.general.highlightID(for: \"Always show on non-notch displays\")",
         "SettingsHighlightCoordinator.snapshotScrollsAtOnce = true",
         "width: size.width, into: request.directory, fixedHeight: size.height",
         "return NSSize(width: SettingsTheme.windowDefaultWidth, height: SettingsTheme.windowDefaultHeight)",
         "return NSSize(width: 1440, height: 900)",
         "return NSSize(width: SettingsTheme.windowMinWidth, height: SettingsTheme.windowMinHeight)",
         // A page at the narrowest panel the window can have, or a clipped row goes unseen. A bare
         // `Form` gets what `SettingsForm`'s padding leaves of it.
         "SettingsTheme.windowMinWidth - SettingsTheme.sidebarWidth - SettingsTheme.panelInset",
         "narrowestPanel - 2 * (SettingsTheme.pageInset - SettingsTheme.formMargin)",
         "Set(SettingsTab.allCases.map(\\.rawValue) + [\"allTasks\"])",
         ": throughTheForm.contains(name) ? narrowestPanel : narrowestPage",
         "document.frame.height + hosting.bounds.height - scroll.frame.height"].filter { !snapshots.contains($0) }
    }

    func testTheBoardsDrawTheWholeWindow() throws {
        let root = Self.settingsDirectory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("helpers/DebugSnapshot.swift")
        let snapshots = SettingsDesignSystemRulesTests.code(try String(contentsOf: root, encoding: .utf8))
        XCTAssertEqual(Self.boardProblems(in: snapshots), [])
        Self.assertCaught(Self.boardProblems(in: "").map { (from: $0, to: "") }, in: snapshots, by: Self.boardProblems)
    }
}
