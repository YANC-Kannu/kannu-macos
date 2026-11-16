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

/// The floating panels on Brain's theme (docs/SETTINGS.md, "The floating panels"): the clipboard panel and the LocalSend
/// picker. Each draws with the theme's colours and fonts, and what is left of the system's is pinned per file with why,
/// read the way `SettingsLayoutRulesTests` reads Brain's pages; remove a survivor and lower its pin. Each panel's
/// drawing holds no manager, so its boards draw fixtures and never build the clipboard manager or the LocalSend service.
/// Each rule is read from the source and checked against planted offenders.
final class FloatingPanelRulesTests: XCTestCase {
    private static let panelPath = "Kannu/components/Clipboard/ClipboardPanel.swift"
    private static let pickerPath = "Kannu/managers/LocalSendDevicePickerWindowManager.swift"
    private static let boardsPath = "Kannu/helpers/DebugSnapshot.swift"

    // MARK: - The theme

    /// A symbol's size is not type: `.system` sizes an SF Symbol, as in the notch (`NotchFontRulesTests`).
    private static let pinnedFonts: [String: Int] = [
        panelPath: 9,   // symbols
        pickerPath: 4,  // 3 symbols; the Standard backdrop's invisible text, the shape its glass takes
    ]

    /// What draws the window's own chrome, which this pass leaves alone.
    private static let pinnedColours: [String: Int] = [
        // The panel's shadow; the close button, drawn as the window's red traffic light, which Brain keeps native
        // (its white glyph and red fill).
        panelPath: 3,
        // The glass the user picked in Shelf › Device Picker Style: its edge, its shadow, and its two tints.
        pickerPath: 4,
    ]

    static func fontLines(in source: String) -> Int {
        NotchFontRulesTests.systemFontLines(in: source)
    }

    static func colourLines(in source: String) -> Int {
        SettingsLayoutRulesTests.rawColourLines(in: source).count
    }

    /// Each panel applies Brain's root itself, as a sheet does, and the picker's content is dark whatever the Mac's
    /// appearance, on glass made for light text.
    static func wiringProblems(panel: String, picker: String) -> [String] {
        var problems: [String] = []
        let panelCode = SettingsDesignSystemRulesTests.code(panel)
        if panelCode.components(separatedBy: ".settingsDesignSystem()").count - 1 != 1 {
            problems.append("the clipboard panel does not apply Brain's root once")
        }
        let pickerCode = SettingsDesignSystemRulesTests.code(picker)
        if !pickerCode.contains(".settingsDesignSystem()\n            .environment(\\.colorScheme, .dark)") {
            problems.append("the LocalSend picker's content does not apply Brain's root, dark")
        }
        return problems
    }

    func testThePanelsTakeTheTheme() throws {
        let panel = try Self.source(Self.panelPath)
        let picker = try Self.source(Self.pickerPath)
        XCTAssertEqual([Self.panelPath: Self.fontLines(in: panel), Self.pickerPath: Self.fontLines(in: picker)], Self.pinnedFonts,
                       "a panel's text takes SettingsTheme's fonts; a survivor is pinned with why")
        XCTAssertEqual([Self.panelPath: Self.colourLines(in: panel), Self.pickerPath: Self.colourLines(in: picker)],
                       Self.pinnedColours, "a panel's colours come from SettingsTheme; a survivor is pinned with why")
        XCTAssertEqual(Self.wiringProblems(panel: panel, picker: picker), [])

        // Planted: the title back on the system's font and in a raw colour; a tile's name in white.
        let title = ".font(SettingsTheme.sheetTitle)\n                    .foregroundStyle(SettingsTheme.ink)"
        XCTAssertTrue(panel.contains(title), "the panel has no title to plant on")
        let plantedPanel = panel.replacingOccurrences(of: title, with: ".font(.system(size: 14, weight: .semibold))\n"
                                                      + "                    .foregroundStyle(.primary)\n                    .foregroundColor(.black)")
        XCTAssertEqual(Self.fontLines(in: plantedPanel), Self.fontLines(in: panel) + 1)
        XCTAssertEqual(Self.colourLines(in: plantedPanel), Self.colourLines(in: panel) + 1)
        let name = ".foregroundStyle(isRejected ? SettingsTheme.destructive : SettingsTheme.ink)"
        XCTAssertTrue(picker.contains(name), "the picker has no tile name to plant on")
        XCTAssertEqual(Self.colourLines(in: picker.replacingOccurrences(of: name, with: ".foregroundStyle(isRejected ? .red : .white)")),
                       Self.colourLines(in: picker) + 1)
        SettingsDesignSystemRulesTests.assertCaught([
            ("        .settingsDesignSystem()\n    }\n}", "    }\n}"),
            ("        .settingsDesignSystem()\n    }\n}", "        .settingsDesignSystem()\n        .settingsDesignSystem()\n    }\n}"),
        ], in: panel) { Self.wiringProblems(panel: $0, picker: picker) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("            .environment(\\.colorScheme, .dark)\n", ""),
        ], in: picker) { Self.wiringProblems(panel: panel, picker: $0) }
    }

    // MARK: - Boards draw fixtures, never a manager

    /// What a panel's drawing may call on the clipboard manager: a press's action, never its state. `pinnedItems` only
    /// to empty it, as Clear Favorites does.
    private static let clipboardPresses: Set<String> = ["clearHistory", "savePinnedItemsToDefaults", "pinItem", "unpinItem",
                                                        "copyToClipboard", "deleteItem"]

    /// From each panel's content view to the end of its file: no observed or kept manager, nothing of the clipboard
    /// manager's but its presses, no LocalSend service and no Defaults. The panel's tab button of old observed the
    /// manager for its counts, so the drawing does not build it.
    static func drawingProblems(panel: String, picker: String) -> [String] {
        var problems: [String] = []
        let panelCode = SettingsDesignSystemRulesTests.code(panel)
        if let start = panelCode.range(of: "struct ClipboardPanelContent: View {") {
            let drawing = String(panelCode[start.lowerBound...])
            if drawing.range(of: #"@(?:ObservedObject|StateObject|EnvironmentObject)[^\n]*\bClipboardManager\b"#,
                             options: .regularExpression) != nil
                || drawing.range(of: #"=\s*ClipboardManager\.shared\s*\n"#, options: .regularExpression) != nil
                || drawing.contains("ClipboardTabButton(") {
                problems.append("the clipboard panel's drawing holds the manager")
            }
            let reads = SettingsDesignSystemRulesTests.matches(of: #"\bClipboardManager\.shared\.\$?\w+(?:\.removeAll\(\))?"#,
                                                                in: drawing)
                .map { $0.replacingOccurrences(of: "ClipboardManager.shared.", with: "") }
                .filter { !clipboardPresses.contains($0) && $0 != "pinnedItems.removeAll()" }
            if !reads.isEmpty {
                problems.append("the clipboard panel's drawing reads the manager: \(reads.joined(separator: ", "))")
            }
        } else {
            problems.append("the clipboard panel has no content view of its own")
        }
        let pickerCode = SettingsDesignSystemRulesTests.code(picker)
        if let start = pickerCode.range(of: "struct LocalSendDevicePickerContent: View {") {
            let drawing = String(pickerCode[start.lowerBound...])
            for name in ["LocalSendService", "@Default(", "Defaults["] where drawing.contains(name) {
                problems.append("the LocalSend picker's drawing reaches \(name)")
            }
        } else {
            problems.append("the LocalSend picker has no content view of its own")
        }
        return problems
    }

    /// The boards draw each panel's content, never the views that hold a manager, and name neither manager.
    static func boardProblems(in boards: String) -> [String] {
        let code = SettingsDesignSystemRulesTests.code(boards)
        var problems = ["ClipboardPanelView", "ClipboardManager", "LocalSendDevicePickerView", "LocalSendService"]
            .filter { code.range(of: #"\b"# + $0 + #"\b"#, options: .regularExpression) != nil }
            .map { "the boards reach a panel's manager through \($0)" }
        for content in ["ClipboardPanelContent(", "LocalSendDevicePickerContent("] where !code.contains(content) {
            problems.append("no board draws \(content)")
        }
        return problems
    }

    func testTheBoardsNeverTouchAManager() throws {
        let panel = try Self.source(Self.panelPath)
        let picker = try Self.source(Self.pickerPath)
        let boards = try Self.source(Self.boardsPath)
        XCTAssertEqual(Self.drawingProblems(panel: panel, picker: picker), [])
        XCTAssertEqual(Self.boardProblems(in: boards), [])
        SettingsDesignSystemRulesTests.assertCaught([
            ("    @State private var searchText = \"\"\n    @State private var hoveredItemId: UUID?\n",
             "    @State private var searchText = \"\"\n    @State private var hoveredItemId: UUID?\n"
             + "    @ObservedObject var clipboardManager = ClipboardManager.shared\n"),
            ("isPinned: pinned.contains(where: { $0.id == item.id })",
             "isPinned: ClipboardManager.shared.pinnedItems.contains(where: { $0.id == item.id })"),
            ("let count = tab == .history ? historyCount : pinnedCount",
             "let count = tab == .history ? ClipboardManager.shared.regularHistory.count : pinnedCount"),
        ], in: panel) { Self.drawingProblems(panel: $0, picker: picker) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("    @State private var hoveredDeviceID: String?\n",
             "    @State private var hoveredDeviceID: String?\n    @Default(.localSendDevicePickerGlassMode) private var storedMode\n"),
            ("                Button(\"Scan Again\") {\n                    onRefresh()",
             "                Button(\"Scan Again\") {\n                    LocalSendService.shared.refreshDeviceScan()"),
        ], in: picker) { Self.drawingProblems(panel: panel, picker: $0) }
        SettingsDesignSystemRulesTests.assertCaught([
            ("(\"clipboardPanelEmpty\", ClipboardPanelContent(history: [], pinned: [], historyIsEmpty: true, onClose: {})),",
             "(\"clipboardPanelEmpty\", ClipboardPanelView(onClose: {})),"),
            ("        let devices = DebugSnapshotFixtures.localSendDevices\n",
             "        let devices = LocalSendService.shared.devices\n"),
        ], in: boards, by: Self.boardProblems)
    }

    // MARK: - Plumbing

    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
