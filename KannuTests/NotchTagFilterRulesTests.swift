//
//  NotchTagFilterRulesTests.swift
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

/// The notch's Tag filter and tag chips (Brain redesign Stage 5, the notch). The views and
/// `TaskSourcePreferences` are not in the logic target, so the wiring is read from the source (the
/// `TimerSideColumnRulesTests` idiom); what the filter keeps is pure and tested in
/// `TaskSourceFilterTests`:
///
/// - `tasksNotchTagFilter` joins Show in notch: `TaskSourcePreferences` follows the key, counts it in
///   `isNarrowing` (the "Filtered" line, the filled glyph) and clears it in `showAll()`;
/// - a task added in the notch clears a Tag filter that would hide it: `TasksManager.showInNotch`,
///   which the popover's Add a task calls too (the task form's and a typed start's calls are pinned
///   in `TimerTaskSessionRulesTests`, Brain's New Task leaving it alone in `TaskFormWiringTests`);
/// - the rail and the popover list through the Tag filter, the timed task always passing;
/// - the typed search lists through Show in notch alone, never the Tag filter, so a task the tag
///   hides is still found by its name and never made twice;
/// - the Tag submenu's tags are passed in, so `TaskSourceMenu` never reads `TasksManager`;
/// - a rail row shows its tags beside the caption (`TaskTagChips`), the search's first, on a line one
///   chip tall, in the fonts `TimerComposerMetricsTests` measures against the 36 pt row;
/// - the caption wins (design review finding 7): whole, then the first tag (whole, or shortened to no
///   less than `sideTaskChipMinWidth`) and "+N" for the rest, else one "+N" for every tag beside a
///   caption that has the room first; and its overtime never shortens.
///
/// Each detector has a planted-offender test, so a scanner that stops matching fails instead of
/// passing vacuously.
final class NotchTagFilterRulesTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    static let settingsPath = "Kannu/managers/Tasks/TaskSourceSettings.swift"
    static let constantsPath = "Kannu/models/Constants.swift"
    static let managerPath = "Kannu/managers/Tasks/TasksManager.swift"
    static let popoverPath = "Kannu/components/Notch/TasksPopover.swift"
    static let columnPath = "Kannu/components/Notch/TimerSideColumn.swift"
    static let suggestionsPath = "Kannu/components/Notch/TimerTaskSuggestions.swift"
    static let menuPath = "Kannu/components/Notch/TaskSourceMenu.swift"
    static let chipsPath = "Kannu/components/Notch/TaskTagChips.swift"

    /// What the rail and the popover list through: Show in notch and the Tag filter, the timed task passing.
    static let listFilter =
        "TaskOrdering.viewFilter(hidden: preferences.hiddenInNotch, tag: preferences.tagFilter, alwaysListed: manager.timing?.taskID)"

    private static func read(_ path: String) throws -> String {
        code(try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8))
    }

    // MARK: - The rules, on the real sources

    func testTheTagFilterJoinsIsNarrowingAndShowAll() throws {
        XCTAssertEqual(Self.preferencesProblems(settings: try Self.read(Self.settingsPath),
                                                constants: try Self.read(Self.constantsPath)), [])
    }

    func testAddingATaskClearsATagFilterThatWouldHideIt() throws {
        XCTAssertEqual(Self.addProblems(manager: try Self.read(Self.managerPath), popover: try Self.read(Self.popoverPath)), [])
    }

    func testTheListsHonourTheTagFilterAndTheTimedTaskAlwaysShows() throws {
        for path in [Self.columnPath, Self.popoverPath] {
            XCTAssertEqual(Self.listProblems(in: try Self.read(path)), [], path)
        }
    }

    func testTheTypedSearchIgnoresTheTagFilter() throws {
        XCTAssertEqual(Self.suggestionProblems(in: try Self.read(Self.suggestionsPath)), [])
    }

    func testTheTagSubmenuHasItsTagsPassedIn() throws {
        XCTAssertEqual(Self.menuProblems(menu: try Self.read(Self.menuPath),
                                         callers: [try Self.read(Self.columnPath), try Self.read(Self.popoverPath)]), [])
    }

    func testARailRowShowsItsTagsBesideTheCaption() throws {
        XCTAssertEqual(Self.chipProblems(column: try Self.read(Self.columnPath), chips: try Self.read(Self.chipsPath)), [])
    }

    // MARK: - The scanners catch planted offenders

    func testThePreferencesScannerCatchesPlantedOffenders() {
        let settings = """
                + [Defaults.publisher(.tasksNotchTagFilter, options: [])]
            var isNarrowing: Bool { !hiddenInNotch.isEmpty || tagFilter != TaskFacets.anyTag }
            var tagBinding: Binding<String> {
                Binding(get: { Defaults[.tasksNotchTagFilter] }, set: { Defaults[.tasksNotchTagFilter] = $0 })
            }
            func showAll() {
                if Defaults[.tasksNotchTagFilter] != TaskFacets.anyTag { Defaults[.tasksNotchTagFilter] = TaskFacets.anyTag }
            }
            private func recompute() {
                let tag = Defaults[.tasksNotchTagFilter]
            }
            """
        let constants = "static let tasksNotchTagFilter = Key<String>(\"tasksNotchTagFilter\", default: TaskFacets.anyTag)"
        XCTAssertEqual(Self.preferencesProblems(settings: settings, constants: constants), [])
        XCTAssertEqual(Self.preferencesProblems(settings: settings, constants: ""), ["no tasksNotchTagFilter key that starts with no tag"])
        let cases = [
            ("+ [Defaults.publisher(.tasksNotchTagFilter, options: [])]", "", "TaskSourcePreferences does not follow tasksNotchTagFilter"),
            (" || tagFilter != TaskFacets.anyTag", "", "isNarrowing leaves out the Tag filter"),
            ("set: { Defaults[.tasksNotchTagFilter] = $0 }", "set: { _ in }", "the Tag submenu does not set tasksNotchTagFilter"),
            ("{ Defaults[.tasksNotchTagFilter] = TaskFacets.anyTag }", "{ }", "showAll() leaves the Tag filter on"),
            ("let tag = Defaults[.tasksNotchTagFilter]", "let tag = TaskFacets.anyTag", "recompute does not read tasksNotchTagFilter"),
        ]
        for (target, replacement, problem) in cases {
            XCTAssertEqual(Self.preferencesProblems(settings: Self.plant(target, replacement, in: settings), constants: constants), [problem])
        }
    }

    func testTheAddScannerCatchesPlantedOffenders() {
        let manager = """
            func showInNotch(_ id: UUID) {
                if !Defaults[.tasksPopoverShowLocal] { Defaults[.tasksPopoverShowLocal] = true }
                guard let task = tasks.first(where: { $0.id == id }) else { return }
                let tag = TaskOrdering.tagFilter(Defaults[.tasksNotchTagFilter], afterAdding: task)
                if tag != Defaults[.tasksNotchTagFilter] { Defaults[.tasksNotchTagFilter] = tag }
            }
            """
        let popover = """
            private func addTask() {
                if let id = manager.addTask(title: newTitle, estimateSeconds: nil) {
                    newTitle = ""
                    manager.showInNotch(id)
                }
            }
            """
        XCTAssertEqual(Self.addProblems(manager: manager, popover: popover), [])
        XCTAssertEqual(Self.addProblems(manager: Self.plant("{ Defaults[.tasksNotchTagFilter] = tag }", "{ }", in: manager), popover: popover),
                       ["showInNotch does not clear a Tag filter that would hide the task"])
        XCTAssertEqual(Self.addProblems(manager: Self.plant("{ Defaults[.tasksPopoverShowLocal] = true }", "{ }", in: manager), popover: popover),
                       ["showInNotch does not bring hidden local tasks back"])
        XCTAssertEqual(Self.addProblems(manager: manager, popover: Self.plant("manager.showInNotch(id)", "", in: popover)),
                       ["the popover's Add a task does not show its task"])
        XCTAssertEqual(Self.addProblems(manager: "", popover: popover).count, 2, "no showInNotch at all is vacuous")
    }

    func testTheListScannerCatchesPlantedOffenders() {
        XCTAssertEqual(Self.listProblems(in: "private var notchFilter: TaskOrdering.Listed { \(Self.listFilter) }"), [])
        let untagged = "TaskOrdering.viewFilter(hidden: preferences.hiddenInNotch, alwaysListed: manager.timing?.taskID)"
        let untimed = "TaskOrdering.viewFilter(hidden: preferences.hiddenInNotch, tag: preferences.tagFilter, alwaysListed: nil)"
        for planted in [untagged, untimed] {
            XCTAssertEqual(Self.listProblems(in: planted), ["the list does not honour the Tag filter with the timed task passing"])
        }
    }

    func testTheSuggestionScannerCatchesPlantedOffenders() {
        let good = """
            private var found: [TaskSuggestionState.Row] {
                let listed = TaskOrdering.active(manager.activeTasks, listed: TaskOrdering.viewFilter(
                    hidden: preferences.hiddenInNotch, alwaysListed: manager.timing?.taskID))
                return TaskSuggestionState.rows(for: TaskSearch.suggestions(listed, typed: typed), typed: typed)
            }
            """
        XCTAssertEqual(Self.suggestionProblems(in: good), [])
        XCTAssertEqual(Self.suggestionProblems(in: Self.plant("hidden: preferences.hiddenInNotch, ", "hidden: preferences.hiddenInNotch, tag: preferences.tagFilter, ", in: good)),
                       ["the typed search reads the Tag filter"])
        XCTAssertEqual(Self.suggestionProblems(in: Self.plant("hidden: preferences.hiddenInNotch, ", "hidden: [], tag: \"x\", ", in: good)),
                       ["the typed search no longer lists through Show in notch: the scan is vacuous", "the typed search reads the Tag filter"])
        XCTAssertEqual(Self.suggestionProblems(in: good + "\nlet picked = preferences.tagFilter"), ["the typed search reads the Tag filter"])
    }

    func testTheMenuScannerCatchesPlantedOffenders() {
        let menu = """
            let tags: [String]
            Picker("Tag", selection: preferences.tagBinding) { }
            """
        let caller = """
            private var tagChoices: [String] { TaskFacets.filterTags(in: shown) }
            TaskSourceMenu(openBrain: { $0.open() }, tags: tagChoices, style: .rail)
            """
        XCTAssertEqual(Self.menuProblems(menu: menu, callers: [caller]), [])
        XCTAssertEqual(Self.menuProblems(menu: menu + "\n@ObservedObject private var manager = TasksManager.shared", callers: [caller]),
                       ["the menu reads TasksManager"])
        XCTAssertEqual(Self.menuProblems(menu: Self.plant("let tags: [String]", "", in: menu), callers: [caller]),
                       ["the menu does not take its tags"])
        XCTAssertEqual(Self.menuProblems(menu: Self.plant("preferences.tagBinding", "$picked", in: menu), callers: [caller]),
                       ["no Tag submenu on the Tag filter"])
        XCTAssertEqual(Self.menuProblems(menu: menu, callers: [Self.plant("tags: tagChoices, ", "tags: [], ", in: caller)]),
                       ["a caller does not pass the tags filterTags offers"])
        XCTAssertEqual(Self.menuProblems(menu: menu, callers: [Self.plant("TaskFacets.filterTags(in: shown)", "TaskFacets.tags(in: shown)", in: caller)]),
                       ["a caller does not pass the tags filterTags offers"])
    }

    func testTheChipScannerCatchesPlantedOffenders() {
        let column = """
            private func row(_ task: TaskItem, tooltipEdge: HoverTooltipEdge) -> some View {
                HoverRevealText(task.title, font: SettingsTheme.font(size: 12, weight: .semibold), isActive: isHovered)
                TaskTagChips(tags: TaskSearch.chipTags(of: task, query: searchText), foundFirst: !TaskSearch.foundTags(of: task, query: searchText).isEmpty) {
                    HStack(spacing: 0) {
                        HoverRevealText(Text(verbatim: caption).font(SettingsTheme.font(size: 11, weight: .medium)), isActive: isHovered)
                        overText(progress.over)
                            .font(SettingsTheme.font(size: 11, weight: .medium))
                            .fixedSize()
                    }
                }
                .frame(height: M.sideTaskCaptionHeight)
                .frame(height: M.sideTaskRowHeight)
            }
            struct SideChip: View {
                var body: some View {
                    Text(verbatim: text)
                        .font(.system(size: 10, weight: .semibold, design: monospaced ? .monospaced : .default))
                        .padding(.vertical, 2)
                }
            }
            """
        let chips = """
            ViewThatFits(in: .horizontal) {
                besideWholeCaption(SideChip("#\\(first)"))
                besideWholeCaption(
                    SideChip("#\\(first)", truncates: true)
                        .frame(minWidth: M.sideTaskChipMinWidth, idealWidth: M.sideTaskChipMinWidth)
                )
                HStack(spacing: 4) {
                    caption.layoutPriority(1)
                    SideChip("+\\(tags.count)", tint: foundFirst ? .accentColor : nil)
                }
            }
            private func besideWholeCaption(_ chip: some View) -> some View {
                HStack(spacing: 4) {
                    caption.fixedSize()
                    HStack(spacing: 4) {
                        chip
                        if tags.count > 1 {
                            SideChip("+\\(tags.count - 1)")
                        }
                    }
                }
            }
            """
        XCTAssertEqual(Self.chipProblems(column: column, chips: chips), [])
        XCTAssertEqual(Self.chipProblems(column: Self.plant("chipTags(of: task, query: searchText)", "chipTags(of: task, query: \"\")", in: column), chips: chips),
                       ["a row does not show the tags the search finds first"])
        // The caption above the tags' line (5-2's tags-after-caption order no longer passes), or the line
        // not one chip tall, is not the caption and its tags on one line.
        let above = Self.plant("TaskTagChips(tags: TaskSearch.chipTags(of: task, query: searchText), foundFirst: !TaskSearch.foundTags(of: task, query: searchText).isEmpty) {\n", "VStack {\n",
                               in: Self.plant("    .frame(height: M.sideTaskCaptionHeight)\n",
                                              "    TaskTagChips(tags: TaskSearch.chipTags(of: task, query: searchText), foundFirst: !TaskSearch.foundTags(of: task, query: searchText).isEmpty) {}\n    .frame(height: M.sideTaskCaptionHeight)\n",
                                              in: column))
        XCTAssertEqual(Self.chipProblems(column: above, chips: chips), ["the tags are not beside the caption on a line one chip tall"])
        XCTAssertEqual(Self.chipProblems(column: Self.plant(".frame(height: M.sideTaskCaptionHeight)", "", in: column), chips: chips),
                       ["the tags are not beside the caption on a line one chip tall"])
        // The overtime back inside the clipped caption (5-2's shape), where a short line cut it, or free
        // to shorten.
        let concatenated = Self.plant("HoverRevealText(Text(verbatim: caption).font(",
                                      "HoverRevealText((Text(verbatim: caption) + overText(progress.over)).font(",
                                      in: Self.plant("overText(progress.over)", "Text(\"x\")", in: column))
        XCTAssertEqual(Self.chipProblems(column: concatenated, chips: chips),
                       ["the caption's overtime can shorten: it is not a text of its own at its full width"])
        XCTAssertEqual(Self.chipProblems(column: Self.plant("        .fixedSize()\n", "", in: column), chips: chips),
                       ["the caption's overtime can shorten: it is not a text of its own at its full width"])
        XCTAssertEqual(Self.chipProblems(column: Self.plant("size: 12, weight: .semibold", "size: 13, weight: .semibold", in: column), chips: chips),
                       ["the row's title font or its 36 pt height changed: TimerComposerMetricsTests measures them"])
        XCTAssertEqual(Self.chipProblems(column: Self.plant(".padding(.vertical, 2)", ".padding(.vertical, 3)", in: column), chips: chips),
                       ["SideChip's font or padding changed: TimerComposerMetricsTests measures them"])
        XCTAssertEqual(Self.chipProblems(column: column, chips: Self.plant("SideChip(\"+\\(tags.count - 1)\")", "", in: chips)),
                       ["the chips are not the first tag and +N for the rest, else one +N for every tag"])
        XCTAssertEqual(Self.chipProblems(column: column, chips: Self.plant("SideChip(\"+\\(tags.count)\",", "SideChip(\"+\\(tags.count - 1)\",", in: chips)),
                       ["the chips are not the first tag and +N for the rest, else one +N for every tag"])
        XCTAssertEqual(Self.chipProblems(column: column, chips: Self.plant(", tint: foundFirst ? .accentColor : nil", "", in: chips)),
                       ["a lone +N hides the tag the search found, untinted"])
        XCTAssertEqual(Self.chipProblems(column: Self.plant(", foundFirst: !TaskSearch.foundTags(of: task, query: searchText).isEmpty", "", in: column), chips: chips),
                       ["a row does not say when the search found its first tag"])
        XCTAssertEqual(Self.chipProblems(column: column, chips: Self.plant("SideChip(\"#\\(first)\", truncates: true)", "SideChip(\"#\\(first)\")", in: chips)),
                       ["a shortened chip does not truncate: it would draw whole over the caption"])
        // A tag that takes the caption's room: the caption shortened beside the chip, or not first beside +N.
        XCTAssertEqual(Self.chipProblems(column: column, chips: Self.plant("caption.fixedSize()", "caption", in: chips)),
                       ["the caption does not win: whole beside a chip, first to the room beside +N"])
        XCTAssertEqual(Self.chipProblems(column: column, chips: Self.plant("caption.layoutPriority(1)", "caption", in: chips)),
                       ["the caption does not win: whole beside a chip, first to the room beside +N"])
        XCTAssertEqual(Self.chipProblems(column: column, chips: Self.plant(".frame(minWidth: M.sideTaskChipMinWidth, idealWidth: M.sideTaskChipMinWidth)",
                                                                           "", in: chips)),
                       ["a shortened chip has no floor: it can shrink past reading"])
        XCTAssertEqual(Self.chipProblems(column: column, chips: Self.plant("ViewThatFits(in: .horizontal)", "HStack", in: chips)),
                       ["the line is not the first of its layouts that fits"])
    }

    // MARK: - Scanning

    /// `TaskSourcePreferences` follows `tasksNotchTagFilter` (a String key that starts with no tag),
    /// counts it in `isNarrowing`, sets it from the Tag submenu and clears it in `showAll()`.
    static func preferencesProblems(settings: String, constants: String) -> [String] {
        var problems: [String] = []
        if !constants.contains("static let tasksNotchTagFilter = Key<String>(\"tasksNotchTagFilter\", default: TaskFacets.anyTag)") {
            problems.append("no tasksNotchTagFilter key that starts with no tag")
        }
        if !settings.contains("Defaults.publisher(.tasksNotchTagFilter, options: [])") {
            problems.append("TaskSourcePreferences does not follow tasksNotchTagFilter")
        }
        if !settings.contains("var isNarrowing: Bool { !hiddenInNotch.isEmpty || tagFilter != TaskFacets.anyTag }") {
            problems.append("isNarrowing leaves out the Tag filter")
        }
        if !settings.contains("set: { Defaults[.tasksNotchTagFilter] = $0 }") {
            problems.append("the Tag submenu does not set tasksNotchTagFilter")
        }
        if !(body(of: "func showAll()", in: settings)?.contains("Defaults[.tasksNotchTagFilter] = TaskFacets.anyTag") ?? false) {
            problems.append("showAll() leaves the Tag filter on")
        }
        if !(body(of: "private func recompute()", in: settings)?.contains("Defaults[.tasksNotchTagFilter]") ?? false) {
            problems.append("recompute does not read tasksNotchTagFilter")
        }
        return problems
    }

    /// `showInNotch` brings hidden local tasks back and clears a Tag filter the task does not pass,
    /// through the pure rule; the popover's Add a task calls it.
    static func addProblems(manager: String, popover: String) -> [String] {
        var problems: [String] = []
        let show = body(of: "func showInNotch(_ id: UUID)", in: manager) ?? ""
        if !(show.contains("TaskOrdering.tagFilter(Defaults[.tasksNotchTagFilter], afterAdding: task)")
             && show.contains("Defaults[.tasksNotchTagFilter] = tag")) {
            problems.append("showInNotch does not clear a Tag filter that would hide the task")
        }
        if !show.contains("Defaults[.tasksPopoverShowLocal] = true") {
            problems.append("showInNotch does not bring hidden local tasks back")
        }
        if !(body(of: "private func addTask()", in: popover)?.contains("manager.showInNotch(id)") ?? false) {
            problems.append("the popover's Add a task does not show its task")
        }
        return problems
    }

    static func listProblems(in view: String) -> [String] {
        view.contains(listFilter) ? [] : ["the list does not honour the Tag filter with the timed task passing"]
    }

    /// The typed search's rows come through Show in notch, and nothing in its file reads the Tag filter.
    static func suggestionProblems(in suggestions: String) -> [String] {
        var problems: [String] = []
        let found = body(of: "private var found: [TaskSuggestionState.Row]", in: suggestions) ?? ""
        if !(found.contains("TaskOrdering.viewFilter(") && found.contains("hidden: preferences.hiddenInNotch")) {
            problems.append("the typed search no longer lists through Show in notch: the scan is vacuous")
        }
        if suggestions.contains("tagFilter") || found.contains("tag:") {
            problems.append("the typed search reads the Tag filter")
        }
        return problems
    }

    /// The menu takes its tags and offers them on the Tag filter, never reading `TasksManager`; each
    /// caller passes what `TaskFacets.filterTags` offers (labels too), not the own-tags-only `tags(in:)`.
    static func menuProblems(menu: String, callers: [String]) -> [String] {
        var problems: [String] = []
        if !menu.contains("let tags: [String]") { problems.append("the menu does not take its tags") }
        if !menu.contains("Picker(\"Tag\", selection: preferences.tagBinding)") { problems.append("no Tag submenu on the Tag filter") }
        if menu.contains("TasksManager") { problems.append("the menu reads TasksManager") }
        let passing = callers.filter {
            $0.contains("TaskSourceMenu(openBrain:") && $0.contains("tags: tagChoices") && $0.contains("TaskFacets.filterTags(in:")
        }
        if passing.count != callers.count { problems.append("a caller does not pass the tags filterTags offers") }
        return problems
    }

    /// A rail row passes its caption into `TaskTagChips`, with the tags the search finds first, on a line
    /// one chip tall, and the caption's overtime is a text of its own at its full width; the fonts and
    /// the chip's padding are the ones the metrics test measures. `TaskTagChips` lets the caption win
    /// (finding 7): the first of its layouts that fits is the whole caption, then the first tag with
    /// its `#`, whole or shortened to no less than `sideTaskChipMinWidth`, and "+N" for the rest; the
    /// last is one "+N" for every tag beside the caption, which takes the room first. All on `SideChip`.
    static func chipProblems(column: String, chips: String) -> [String] {
        var problems: [String] = []
        let row = body(of: "private func row(_ task: TaskItem", in: column) ?? ""
        if !row.contains("TaskTagChips(tags: TaskSearch.chipTags(of: task, query: searchText)") {
            problems.append("a row does not show the tags the search finds first")
        }
        if !row.contains("foundFirst: !TaskSearch.foundTags(of: task, query: searchText).isEmpty") {
            problems.append("a row does not say when the search found its first tag")
        }
        if let tags = row.range(of: "TaskTagChips("), let caption = row.range(of: ".font(SettingsTheme.font(size: 11, weight: .medium))"),
           let line = row.range(of: ".frame(height: M.sideTaskCaptionHeight)"),
           tags.lowerBound < caption.lowerBound, caption.lowerBound < line.lowerBound {
            // The caption goes into the tags' line.
        } else {
            problems.append("the tags are not beside the caption on a line one chip tall")
        }
        let overtime = #"overText\(progress\.over\)\s*\.font\(SettingsTheme\.font\(size: 11, weight: \.medium\)\)\s*\.fixedSize\(\)"#
        if row.range(of: overtime, options: .regularExpression) == nil {
            problems.append("the caption's overtime can shorten: it is not a text of its own at its full width")
        }
        if !(row.contains("font: SettingsTheme.font(size: 12, weight: .semibold)") && row.contains(".frame(height: M.sideTaskRowHeight)")) {
            problems.append("the row's title font or its 36 pt height changed: TimerComposerMetricsTests measures them")
        }
        let chip = body(of: "struct SideChip: View", in: column) ?? ""
        if !(chip.contains(".font(.system(size: 10, weight: .semibold, design: monospaced ? .monospaced : .default))")
             && chip.contains(".padding(.vertical, 2)")) {
            problems.append("SideChip's font or padding changed: TimerComposerMetricsTests measures them")
        }
        if !(chips.contains("SideChip(\"#\\(first)\")") && chips.contains("SideChip(\"+\\(tags.count - 1)\")")
             && chips.contains("SideChip(\"+\\(tags.count)\"")) {
            problems.append("the chips are not the first tag and +N for the rest, else one +N for every tag")
        }
        if !chips.contains("tint: foundFirst ? .accentColor : nil") {
            problems.append("a lone +N hides the tag the search found, untinted")
        }
        if !(chips.contains("caption.fixedSize()") && chips.contains("caption.layoutPriority(1)")) {
            problems.append("the caption does not win: whole beside a chip, first to the room beside +N")
        }
        if !chips.contains(".frame(minWidth: M.sideTaskChipMinWidth, idealWidth: M.sideTaskChipMinWidth)") {
            problems.append("a shortened chip has no floor: it can shrink past reading")
        }
        if !chips.contains("SideChip(\"#\\(first)\", truncates: true)") {
            problems.append("a shortened chip does not truncate: it would draw whole over the caption")
        }
        if !chips.contains("ViewThatFits(in: .horizontal)") {
            problems.append("the line is not the first of its layouts that fits")
        }
        return problems
    }

    /// The source without comment lines.
    static func code(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("*") && !trimmed.hasPrefix("/*")
            }
            .joined(separator: "\n")
    }

    /// The balanced `{ … }` after the first `opener`, or nil when there is none.
    static func body(of opener: String, in text: String) -> String? {
        guard let range = text.range(of: opener), let open = text[range.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        repeat {
            if text[index] == "{" { depth += 1 } else if text[index] == "}" { depth -= 1 }
            index = text.index(after: index)
        } while index < text.endIndex && depth > 0
        return String(text[open..<index])
    }

    /// `text` with `target` replaced, failing the test when the plant did not take.
    private static func plant(_ target: String, _ replacement: String, in text: String,
                              file: StaticString = #filePath, line: UInt = #line) -> String {
        let planted = text.replacingOccurrences(of: target, with: replacement)
        XCTAssertNotEqual(planted, text, "the plant did not take: \(target)", file: file, line: line)
        return planted
    }
}
