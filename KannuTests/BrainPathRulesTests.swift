//
//  BrainPathRulesTests.swift
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

/// Text that sends the user to "Brain › <tab> › …" names a tab the sidebar has. CodeRabbit (#87)
/// found "Brain › Security findings", which is a section, not a tab; the security messages also
/// said "Brain › Agents ›" for rows that live in the Security tab. The settings tabs now sit
/// behind the sidebar's Settings row, so a path to one says "Brain › Settings › <tab>".
final class BrainPathRulesTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The sidebar's tab titles and the Settings row's, from `SettingsView`'s `title` switches.
    private static func titles() throws -> Set<String> {
        let settings = try source("Kannu/components/Settings/SettingsView.swift")
        let pattern = try NSRegularExpression(pattern: #"case \.\w+:\s+return String\(localized: "([^"]+)"\)"#)
        let range = NSRange(settings.startIndex..., in: settings)
        return Set(pattern.matches(in: settings, range: range).compactMap { match in
            Range(match.range(at: 1), in: settings).map { String(settings[$0]) }
        })
    }

    /// What a path may start with: the sidebar's product list, its foot, and the Settings row.
    private static let allowedHeads = ["Agents", "Security", "Usage", "Tasks", "Timer", "Notes", "Clipboard", "About", "Settings"]
    /// What may follow "Brain › Settings ›": the settings list, as `title` spells it.
    private static let fourteenTitles = ["General", "Appearance", "Live activities", "Lock screen", "Media", "Devices", "HUD and OSD",
                                         "Battery", "Stats", "Shelf", "Downloads", "Screen Assistant", "Shortcuts", "Extensions"]

    /// Every "Brain › a › b" in the text's string-bearing lines, as its segments. Comment lines are
    /// skipped. A segment ends at `›`, `.`, `,`, `)`, `"` or `\`, and only `›` lets the path go on.
    private static func paths(in text: String) -> [[String]] {
        let enders: Set<Character> = ["›", ".", ",", ")", "\"", "\\"]
        var found: [[String]] = []
        for line in text.split(separator: "\n") where line.contains("\"") && line.contains("Brain › ") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("*") else { continue }
            let string = String(line)
            var searchFrom = string.startIndex
            while let start = string.range(of: "Brain › ", range: searchFrom..<string.endIndex) {
                var path: [String] = []
                var index = start.upperBound
                while true {
                    let end = string[index...].firstIndex(where: { enders.contains($0) }) ?? string.endIndex
                    path.append(string[index..<end].trimmingCharacters(in: .whitespaces))
                    guard end < string.endIndex, string[end] == "›" else {
                        index = end
                        break
                    }
                    index = string.index(after: end)
                }
                found.append(path)
                searchFrom = index
            }
        }
        return found
    }

    /// The live check first: a head must be a title `SettingsView` has, so renaming a tab fails any
    /// path naming it. Then the levels, which a live list alone cannot see: "Brain › General" names a
    /// real title and leads nowhere, since General is behind the Settings row.
    private static func problems(paths: [[String]], titles: Set<String>) -> [String] {
        paths.compactMap { path -> String? in
            let shown = "Brain › " + path.joined(separator: " › ")
            guard let head = path.first else { return "\(shown) is empty" }
            if !titles.contains(head) { return "\(shown) names no tab of the sidebar" }
            if !allowedHeads.contains(head) { return "\(shown) starts at a tab behind the Settings row" }
            if head == "Settings", path.count > 1, !fourteenTitles.contains(path[1]) {
                return "\(shown): the settings list has no \(path[1])"
            }
            return nil
        }
    }

    /// The real tree, through the same pair of functions as the plants.
    private static func problemsInTheApp(titles: Set<String>) throws -> (paths: Int, problems: [String]) {
        let folder = root.appendingPathComponent("Kannu")
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var count = 0
        var found: [String] = []
        for file in files {
            let inFile = Self.paths(in: try String(contentsOf: file, encoding: .utf8))
            count += inFile.count
            found += Self.problems(paths: inFile, titles: titles).map { "\(file.lastPathComponent): \($0)" }
        }
        return (count, found)
    }

    func testEveryBrainPathLeadsToARowTheSidebarHas() throws {
        let titles = try Self.titles()
        XCTAssertTrue(titles.contains("Security") && titles.contains("Tasks"), "the titles were not read")
        XCTAssertTrue(Set(Self.allowedHeads + Self.fourteenTitles).isSubset(of: titles), "a list here names a title SettingsView no longer has")
        let scan = try Self.problemsInTheApp(titles: titles)
        XCTAssertGreaterThan(scan.paths, 0, "no Brain path found: the scan is vacuous")
        XCTAssertEqual(scan.problems, [])
    }

    func testTheScanReadsEveryLevelOfAPlantedPath() throws {
        let titles = try Self.titles()
        func problems(_ line: String) -> [String] { Self.problems(paths: Self.paths(in: line), titles: titles) }

        // Behind the Settings row, under the wrong list, or no title at all.
        XCTAssertEqual(problems(#"let a = "Brain › General › Permissions""#).count, 1)
        XCTAssertEqual(problems(#"let a = "Brain › Settings › Agents""#).count, 1)
        XCTAssertEqual(problems(#"let a = "Brain › Nowhere › Permissions""#).count, 1)
        XCTAssertEqual(problems(#"let a = "see Brain › General, then Brain › Media.""#).count, 2)

        // NotesSettings' shape, with its period, and PermissionsStepView's, with what follows.
        XCTAssertEqual(Self.paths(in: #"let a = "row in Brain › Settings › General.""#), [["Settings", "General"]])
        XCTAssertEqual(problems(#"let a = "row in Brain › Settings › General.""#), [])
        XCTAssertEqual(Self.paths(in: #"let a = "Brain › Settings › General › Permissions, or System Settings › Privacy""#),
                       [["Settings", "General", "Permissions"]])
        XCTAssertEqual(problems(#"let a = "Brain › Settings › General › Permissions, or System Settings › Privacy""#), [])
        XCTAssertEqual(problems(#"let a = "(Brain › Security › Analyze chats)""#), [])
        XCTAssertEqual(problems(#"let a = "Brain › Settings""#), [])

        // A comment line is prose, whatever it names.
        XCTAssertEqual(Self.paths(in: #"// says "Brain › General""#), [])
        XCTAssertEqual(Self.paths(in: #"* says "Brain › General""#), [])
    }

    func testTheSecurityMessagesNameTheSecurityTab() throws {
        XCTAssertTrue(try Self.source("Kannu/managers/AgentStatus/SecurityFindingsStore.swift")
            .contains("Session analysis is off (Brain › Security › Analyze chats with ADR Detection)."))
        XCTAssertTrue(try Self.source("Kannu/managers/AgentStatus/AgentSecurityFinding.swift")
            .contains("Details are in Brain › Security › Security findings."))
        XCTAssertTrue(try Self.source("Kannu/managers/AgentStatus/SecurityFindingGuide.swift")
            .contains("turn blocking off in Brain › Security › Agent policy."))
    }
}
