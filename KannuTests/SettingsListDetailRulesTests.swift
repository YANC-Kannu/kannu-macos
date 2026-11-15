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

/// D1's layout (layout-proposal, David 2026-11-06), which Brain › Tasks and Brain › Notes share in one place: the panel
/// measured once, through the width function (`ListDetailLayout`, tested in `ListDetailLayoutTests`), into a flag
/// (`SettingsListDetailFits`); the list first, a column of the function's width with the page inset on each side, and
/// the item's page after it, with no inset of its own (`SettingsListDetail`); and none of the ways D1 rules out:
/// `minWidth:` (the size bridge would clamp the window to it), `ViewThatFits` (it builds every layout it tries),
/// `.inspector`. Each page's rule test holds that it uses these, once (`TasksPageLiveDataRulesTests`,
/// `NotesPageLiveDataRulesTests`).
final class SettingsListDetailRulesTests: XCTestCase {

    private static let layoutPath = "Kannu/components/Settings/DesignSystem/SettingsListDetail.swift"
    private static let fitsPath = "Kannu/components/Settings/DesignSystem/SettingsListDetailFits.swift"

    static func layoutProblems(layout: String, fits: String) -> [String] {
        let layoutCode = SettingsDesignSystemRulesTests.code(layout)
        let fitsCode = SettingsDesignSystemRulesTests.code(fits)
        var problems: [String] = []
        let measure = #"\.onGeometryChange\(for: Bool\.self\) \{ geometry in\s*ListDetailLayout\.showsPageBeside\(panelWidth: geometry\.size\.width, inset: inset, pageWidth: SettingsTheme\.pageMaxWidth\)\s*\} action: \{ fits = \$0 \}"#
        if SettingsDesignSystemRulesTests.matches(of: measure, in: fitsCode).count != 1
            || (layoutCode + fitsCode).components(separatedBy: "ListDetailLayout.showsPageBeside(").count - 1 != 1 {
            problems.append("the layout is not chosen by the width function, from one measurement")
        }
        let column = #"first\(\)\s*\.frame\(width: showsBeside \? inset \+ ListDetailLayout\.listWidth \+ inset : nil\)"#
        let told = #"\s*\.environment\(\\\.settingsInListColumn, showsBeside\)"#
        let columns = #"HStack\(alignment: \.top, spacing: 0\) \{\s*"# + column + "(?:" + told + ")?"
            + #"\s*if showsBeside \{\s*beside\(\)\s*\.environment\(\\\.settingsPageInset, 0\)\s*\.frame\(maxWidth: \.infinity, alignment: \.leading\)"#
        if SettingsDesignSystemRulesTests.matches(of: columns, in: layoutCode).count != 1 {
            problems.append("the list and the item's page are not laid out by the function's widths, the list first")
        }
        // The list's column says it is one, so a row it cannot hold stacks there rather than running past it (Time to
        // log's card, which `testARowTooWideForTheListsColumnStacksThere` holds).
        if SettingsDesignSystemRulesTests.matches(of: column + told, in: layoutCode).count != 1 {
            problems.append("the list's column is not told it is one, so a row too wide for it is clipped there")
        }
        for (name, code) in [("the layout", layoutCode), ("the measurement", fitsCode)] {
            for banned in ["minWidth:", "ViewThatFits", ".inspector("] where code.contains(banned) {
                problems.append("\(name) uses \(banned), which D1 rules out")
            }
        }
        return problems
    }

    func testTheListAndAnItemsPageAreLaidOutByTheWidthFunction() throws {
        let layout = try Self.source(Self.layoutPath)
        let fits = try Self.source(Self.fitsPath)
        XCTAssertEqual(Self.layoutProblems(layout: layout, fits: fits), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("pageWidth: SettingsTheme.pageMaxWidth)", "pageWidth: 600)"),
            // A second measurement of its own.
            ("} action: { fits = $0 }", "} action: { fits = $0 || ListDetailLayout.showsPageBeside(panelWidth: 0, inset: 0, pageWidth: 0) }"),
            ("        content.onGeometryChange(", "        content.frame(minWidth: 1224).onGeometryChange("),
        ], in: fits) { Self.layoutProblems(layout: layout, fits: $0) }
        SettingsDesignSystemRulesTests.assertCaught([
            (".frame(width: showsBeside ? inset + ListDetailLayout.listWidth + inset : nil)",
             ".frame(minWidth: showsBeside ? inset + ListDetailLayout.listWidth + inset : 0)"),
            ("                .environment(\\.settingsInListColumn, showsBeside)\n", ""),
            (".environment(\\.settingsInListColumn, showsBeside)", ".environment(\\.settingsInListColumn, false)"),
            ("                    .environment(\\.settingsPageInset, 0)\n", ""),
            ("        HStack(alignment: .top, spacing: 0) {", "        ViewThatFits {\n        HStack(alignment: .top, spacing: 0) {"),
            ("                    .frame(maxWidth: .infinity, alignment: .leading)\n",
             "                    .frame(maxWidth: .infinity, alignment: .leading)\n                    .inspector(isPresented: .constant(true)) { EmptyView() }\n"),
        ], in: layout) { Self.layoutProblems(layout: $0, fits: fits) }
    }

    private static let timeToLogPath = "Kannu/components/Settings/TimeToLogSection.swift"

    /// Time to log's card is a row whose fields and answers fill a settings column, wider than the list's 360 pt, so in the
    /// list's column it stacks, as the notch draws it; the root's row everywhere else. One style at both widths, deciding
    /// inside, so crossing the width keeps the card and what is typed in it.
    static func stackingProblems(in section: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(section)
        var problems: [String] = []
        if !code.contains("@Environment(\\.settingsInListColumn) private var inListColumn")
            || SettingsDesignSystemRulesTests.matches(of: #"WorklogDraftCard\(draft: draft\)\s*\.labeledContentStyle\(WorklogCardStyle\(stacked: inListColumn\)\)"#, in: code).count != 1 {
            problems.append("Time to log's cards do not follow the list's column, so in it they run past its edge")
        }
        // A card built in two branches is two cards: crossing the width would rebuild it and lose what is typed.
        if code.components(separatedBy: "WorklogDraftCard(draft: draft)").count - 1 != 1 {
            problems.append("a draft's card is built in more than one place, so crossing the width rebuilds it")
        }
        let decides = #"if stacked \{\s*StackedCardStyle\(\)\.makeBody\(configuration: configuration\)\s*\} else \{\s*SettingsLabeledContentStyle\(\)\.makeBody\(configuration: configuration\)\s*\}"#
        if SettingsDesignSystemRulesTests.matches(of: decides, in: code).count != 1 {
            problems.append("the card is not the notch's stack in the column and the root's row elsewhere, in one style")
        }
        return problems
    }

    func testARowTooWideForTheListsColumnStacksThere() throws {
        let section = try Self.source(Self.timeToLogPath)
        XCTAssertEqual(Self.stackingProblems(in: section), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("\n                        .labeledContentStyle(WorklogCardStyle(stacked: inListColumn))", ""),
            ("WorklogCardStyle(stacked: inListColumn)", "WorklogCardStyle(stacked: false)"),
            ("@Environment(\\.settingsInListColumn) private var inListColumn", "@State private var inListColumn = false"),
            ("StackedCardStyle().makeBody(configuration: configuration)", "SettingsLabeledContentStyle().makeBody(configuration: configuration)"),
            // A card built in two branches is two cards: crossing the width would lose what is typed.
            ("                    WorklogDraftCard(draft: draft)\n                        .labeledContentStyle(WorklogCardStyle(stacked: inListColumn))\n",
             "                    if inListColumn {\n                        WorklogDraftCard(draft: draft).labeledContentStyle(StackedCardStyle())\n"
                + "                    } else {\n                        WorklogDraftCard(draft: draft)\n                    }\n"),
        ], in: section) { Self.stackingProblems(in: $0) }
    }

    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
