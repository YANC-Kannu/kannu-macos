//
//  ADRDocsTests.swift
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

/// `docs/ADR.md` is what a user reads before trusting Kannu with ADR; when the code's list of
/// watched files or the scan schedule changes, the document must change with it. Read from the
/// source tree, like `SettingsHighlightInventoryTests`.
final class ADRDocsTests: XCTestCase {
    private static let doc: String = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // KannuTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("docs/ADR.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    private func section(_ heading: String) throws -> String {
        let doc = Self.doc
        let start = try XCTUnwrap(doc.range(of: heading), "\(heading) is gone")
        let next = doc.range(of: "\n## ", range: start.upperBound..<doc.endIndex)?.lowerBound ?? doc.endIndex
        return String(doc[start.lowerBound..<next])
    }

    func testTheScanSectionNamesEveryWatchedSettingsFile() throws {
        let scans = try section("## 3. Let Kannu run it")
        for location in MCPServerWatch.globalLocations(home: "~") {
            let path = location.path
            let name = String(path.split(separator: "/").last ?? "")
            XCTAssertTrue(scans.contains(path) || scans.contains(name), "\(path) is watched but not documented")
        }
        XCTAssertFalse(scans.contains("/.mcp.json"), "a scan is triggered by the global files only")
        let flowed = scans.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        XCTAssertTrue(flowed.contains("once a minute"))
        XCTAssertTrue(flowed.contains("1, 2, 4, 8 and 16 hours"), "the retry after a failed scan")
        XCTAssertTrue(flowed.contains("24 hours"))
    }

    /// The install lines a user copies from the page are the ones Settings copies: the same
    /// pinned commit, so the two can never send people to different code.
    func testTheDocumentedInstallLinesAreThePinnedOnes() throws {
        let install = try section("## 1. Install ADR Discovery")
        XCTAssertTrue(install.contains(ADRUpstream.discoveryInstallCommand))
        XCTAssertTrue(install.contains(ADRUpstream.discoveryPipxCommand))
        let detection = try section("## 8. Session analysis with ADR Detection")
        XCTAssertTrue(detection.contains(ADRUpstream.detectionCloneCommand))
        XCTAssertTrue(detection.contains(ADRUpstream.detectionUpdateCommand))
        XCTAssertFalse(Self.doc.contains("github.com/uber/ADR#subdirectory"), "an unpinned install line is left somewhere")
        XCTAssertFalse(Self.doc.contains("cd ADR/Detection && uv sync"), "an unpinned clone line is left somewhere")
    }

    func testTheSensorIsDocumentedAsUnusedAndTheSectionsAreInOrder() throws {
        let sensor = try section("## 7. ADR Sensor")
        XCTAssertTrue(sensor.contains("Kannu does not use it"))
        XCTAssertTrue(sensor.contains("Copy install command"))
        XCTAssertTrue(sensor.contains("never installs anything"))
        let numbers = Self.doc.components(separatedBy: "\n## ").compactMap { Int($0.prefix(while: \.isNumber)) }
        XCTAssertEqual(numbers, numbers.sorted(), "the numbered sections run in order")
        XCTAssertEqual(numbers, Array(1...numbers.count))
    }

    func testTheFindingCardIsDocumented() throws {
        // Markdown wraps and emphasises; compare on the words.
        let card = try section("## What Kannu does with findings")
            .replacingOccurrences(of: "*", with: "")
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        for phrase in ["Reveal File in Finder", "Reveal Project Folder", "Open Chat", "Copy Details", "Acknowledge"] {
            XCTAssertTrue(card.contains(phrase), phrase)
        }
    }

    /// The hosts the hook can refuse a call on (`POLICY_DENY_EVENTS`) are what a user agrees to when
    /// turning blocking on, so the Settings row, its `Defaults` doc comment and section 9 must name
    /// every one of them (docs/REGRESSIONS.md entry 1, v46 addendum: the table grew and the row did not).
    func testEveryHostThatCanRefuseIsNamedWhereTheUserOptsIn() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        func read(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        // Wrapped prose and doc comments compared on the words.
        func words(_ text: String) -> String {
            text.replacingOccurrences(of: "///", with: " ").replacingOccurrences(of: "*", with: "")
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        }

        let script = try read("scripts/kannu-agent-status.sh")
        let start = try XCTUnwrap(script.range(of: "POLICY_DENY_EVENTS = {"), "the deny table is gone")
        let end = try XCTUnwrap(script.range(of: "\nPOLICY_", range: start.upperBound..<script.endIndex))
        let table = String(script[start.upperBound..<end.lowerBound])
        let keyPattern = try NSRegularExpression(pattern: "\"([a-z]+)\": \\{")
        let providers = keyPattern.matches(in: table, range: NSRange(table.startIndex..., in: table)).compactMap {
            Range($0.range(at: 1), in: table).map { String(table[$0]) }
        }
        XCTAssertEqual(Set(providers), ["claude", "cursor", "antigravity"], "a new host: name it below and in the row")
        let names = ["claude": "Claude Code", "cursor": "Cursor", "antigravity": "Antigravity"]

        let settings = try read("Kannu/components/Settings/AgentSecuritySettings.swift")
        let row = try XCTUnwrap(settings.components(separatedBy: "\n").first { $0.contains("SettingsRow(\"Block matching tool calls\"") })
        let constants = try read("Kannu/models/Constants.swift")
        let docEnd = try XCTUnwrap(constants.range(of: "static let enforceAgentPolicy"))
        let docStart = try XCTUnwrap(constants.range(of: "/// The agent policy", options: .backwards,
                                                     range: constants.startIndex..<docEnd.lowerBound))
        let comment = words(String(constants[docStart.lowerBound..<docEnd.lowerBound]))
        let heading = try XCTUnwrap(Self.doc.components(separatedBy: "\n").first { $0.hasPrefix("## 9. Agent policy") })
        for provider in providers {
            let name = try XCTUnwrap(names[provider], "no display name for \(provider)")
            XCTAssertTrue(row.contains(name), "the Block matching tool calls row does not name \(name)")
            XCTAssertTrue(comment.contains(name), "the enforceAgentPolicy doc comment does not name \(name)")
            XCTAssertTrue(heading.contains(name), "docs/ADR.md section 9 does not name \(name)")
        }
    }
}
