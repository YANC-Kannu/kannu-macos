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
/// said "Brain › Agents ›" for rows that live in the Agent Security tab.
final class BrainPathRulesTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The sidebar's tab and section titles, from `SettingsView`'s `title` switches.
    private static func titles() throws -> Set<String> {
        let settings = try source("Kannu/components/Settings/SettingsView.swift")
        let pattern = try NSRegularExpression(pattern: #"case \.\w+:\s+return String\(localized: "([^"]+)"\)"#)
        let range = NSRange(settings.startIndex..., in: settings)
        return Set(pattern.matches(in: settings, range: range).compactMap { match in
            Range(match.range(at: 1), in: settings).map { String(settings[$0]) }
        })
    }

    /// Every "Brain › <first>" in a string literal of the app's code (comment lines skipped).
    private static func pathHeads() throws -> [(file: String, head: String)] {
        let folder = root.appendingPathComponent("Kannu")
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        let pattern = try NSRegularExpression(pattern: #"Brain › ([^›".)\\]+?)\s*(?:›|\.|\)|"|\\)"#)
        var heads: [(String, String)] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n") where line.contains("\"") && line.contains("Brain › ") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("*") else { continue }
                let string = String(line)
                for match in pattern.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
                    if let range = Range(match.range(at: 1), in: string) {
                        heads.append((file.lastPathComponent, string[range].trimmingCharacters(in: .whitespaces)))
                    }
                }
            }
        }
        return heads
    }

    func testEveryBrainPathStartsAtATabTheSidebarHas() throws {
        let titles = try Self.titles()
        XCTAssertTrue(titles.contains("Agent Security") && titles.contains("Tasks"), "the titles were not read")
        let heads = try Self.pathHeads()
        XCTAssertFalse(heads.isEmpty, "no Brain path found: the scan is vacuous")
        for (file, head) in heads {
            XCTAssertTrue(titles.contains(head), "\(file): \"Brain › \(head)\" names no tab or section of the sidebar")
        }
    }

    func testTheSecurityMessagesNameTheAgentSecurityTab() throws {
        XCTAssertTrue(try Self.source("Kannu/managers/AgentStatus/SecurityFindingsStore.swift")
            .contains("Session analysis is off (Brain › Agent Security › Analyze chats with ADR Detection)."))
        XCTAssertTrue(try Self.source("Kannu/managers/AgentStatus/AgentSecurityFinding.swift")
            .contains("Details are in Brain › Agent Security › Security findings."))
        XCTAssertTrue(try Self.source("Kannu/managers/AgentStatus/SecurityFindingGuide.swift")
            .contains("turn blocking off in Brain › Agent Security › Agent policy."))
    }
}
