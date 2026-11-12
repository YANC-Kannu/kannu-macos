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

/// The open notch's text is Geist, through `SettingsTheme.font(size:weight:)` (docs/SETTINGS.md, "The notch"). The
/// system fonts left are pinned per file with why, read the way `SettingsLayoutRulesTests` reads Brain's
/// (`systemFontLines`), plus a font handed over as an argument (`font: .caption2`), which the notch's views take and
/// Brain's never do. Remove a survivor and lower its pin; add one and say why here.
final class NotchFontRulesTests: XCTestCase {
    private static let components = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Kannu/components", isDirectory: true)

    /// `Notch/` holds the open notch's header, its tabs and two of its popovers. The Agents tab lives in `AgentStatus/`.
    private static func notchSources() throws -> [String: String] {
        let folder = components.appendingPathComponent("Notch", isDirectory: true)
        var sources: [String: String] = [:]
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" {
            sources[file.lastPathComponent] = try String(contentsOf: file, encoding: .utf8)
        }
        let agents = components.appendingPathComponent("AgentStatus/NotchAgentStatusView.swift")
        sources[agents.lastPathComponent] = try String(contentsOf: agents, encoding: .utf8)
        return sources
    }

    /// A symbol's size is not type: `.system` sizes it. A symbol inside text under the token takes Geist's face, which
    /// it reads as regular for Medium, so one under a medium font has its own. Geist Mono ships Regular only, so
    /// monospaced text keeps the system's. An AppKit field or measure draws in AppKit.
    private static let pinned: [String: Int] = [
        "ClipboardHistoryPopover.swift": 6,  // symbols
        "DurationDigitField.swift": 1,       // the digit field's AppKit font, monospaced
        "KannuHeader.swift": 1,              // the header's buttons: their symbols scale from it (.imageScale)
        "NotchAgentStatusView.swift": 4,     // symbols
        "NotchEyeRevealView.swift": 1,       // a symbol
        // 8 symbols; the music title, artist and lyrics, whose title measures its width with an AppKit text style
        // (`MusicTitleMarqueeView`); and 2 weights: one on the artist, one over the theme's font on the time labels
        "NotchHomeView.swift": 13,
        // 20 symbols, two of them beside medium text (the back chevron, Open in Notes); the character count, monospaced
        "NotchNotesView.swift": 21,
        "NotchStatsView.swift": 7,           // 3 symbols; 4 weights over the theme's font, which pick Geist's faces
        // 6 symbols; the three timer readouts, monospaced black; the running timer's name and its rename field, 20 pt
        // in a 24 pt line that Geist's 26 pt line overfills (three lines); the status badge's AppKit measure; a weight
        // over the theme's font
        "NotchTimerView.swift": 14,
        "TaskSourceMenu.swift": 1,           // a symbol
        "TasksPopover.swift": 3,             // a symbol; the key and the tracked clock, monospaced
        "TimerRailIcon.swift": 1,            // a symbol
        // 15 symbols; `SideChip`, a tag chip in a row's 16 pt caption line, where Geist's 10 pt line by AppKit's ruler
        // is 13 against the system's 12 (`TimerComposerMetricsTests`); a preset's length, monospaced
        "TimerSideColumn.swift": 17,
        "TimerTaskForm.swift": 9,            // symbols, one beside medium text (Add a reminder's bell)
        "TimerTaskSuggestions.swift": 1,     // a symbol
    ]

    static func systemFontLines(in source: String) -> Int {
        let code = SettingsDesignSystemRulesTests.code(source, blankingStrings: true)
        let styles = "largeTitle|title2|title3|title|headline|subheadline|body|callout|footnote|caption2|caption|system"
        let arguments = code.components(separatedBy: "\n").filter {
            $0.range(of: #"\bfont\s*:\s*\.(?:"# + styles + #")\b"#, options: .regularExpression) != nil
        }
        return SettingsLayoutRulesTests.systemFontLines(in: source).count + arguments.count
    }

    func testTheNotchsTextIsGeist() throws {
        let sources = try Self.notchSources()
        XCTAssertNotNil(sources["NotchLLMUsageView.swift"], "the walk no longer reaches Notch/")
        var found: [String: Int] = [:]
        for (file, source) in sources where Self.systemFontLines(in: source) > 0 {
            found[file] = Self.systemFontLines(in: source)
        }
        XCTAssertEqual(found, Self.pinned, "text in the notch takes SettingsTheme.font(size:weight:); a survivor is pinned with why")

        XCTAssertEqual(Self.systemFontLines(in: ".font(.caption)"), 1)
        XCTAssertEqual(Self.systemFontLines(in: "AgentChatNameLabel(text: name, font: .caption2)"), 1)
        XCTAssertEqual(Self.systemFontLines(in: "HoverRevealText(title, font: .system(size: 12, weight: .semibold), isActive: true)"), 1)
        for clean in [".font(SettingsTheme.font(size: 11, weight: .medium))", "// .font(.caption)", "Text(\"font: .caption\")",
                      "statusText(for: session, font: SettingsTheme.font(size: 10))"] {
            XCTAssertEqual(Self.systemFontLines(in: clean), 0, clean)
        }

        // A real file: the tooltip's bubble back on the system's caption.
        let tooltip = try XCTUnwrap(sources["HoverTooltip.swift"])
        let bubble = try XCTUnwrap(tooltip.range(of: ".font(SettingsTheme.font(size: 10))"), "the tooltip has no bubble font to plant on")
        XCTAssertEqual(Self.systemFontLines(in: tooltip.replacingCharacters(in: bubble, with: ".font(.caption2)")),
                       (Self.pinned["HoverTooltip.swift"] ?? 0) + 1)
    }
}
