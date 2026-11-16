//
//  SettingsSidebarOrderTests.swift
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

/// Brain's sidebar shows one of two lists (David: "product pages plus Settings. Clicking Settings
/// swaps the sidebar to the settings list with a Back row"). The product list ends at Settings and
/// About, and the tab's group says which list it is on.
///
/// Search jumps to the first match in `availableTabs`' order, so that list follows the sidebar's. The
/// view is not in the logic target, so this reads the source.
final class SettingsSidebarOrderTests: XCTestCase {
    private static let path = "Kannu/components/Settings/SettingsView.swift"

    private static let product = ["agentStatus", "agentSecurity", "llmUsage", "tasks", "timer", "notes", "clipboard"]
    private static let settings = ["general", "appearance", "liveActivities", "lockScreen", "media", "devices", "hudAndOSD",
                                   "battery", "stats", "shelf", "downloads", "screenAssistant", "shortcuts", "extensions"]

    private static func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The text between `start` and the first `end` after it.
    private static func slice(_ source: String, from start: String, to end: String) throws -> String {
        let open = try XCTUnwrap(source.range(of: start), "\(start) not found")
        let close = try XCTUnwrap(source.range(of: end, range: open.upperBound..<source.endIndex), "\(end) not found")
        return String(source[open.upperBound..<close.lowerBound])
    }

    func testTheGroupsAreProductSettingsInfo() throws {
        let groups = try Self.slice(try Self.source(), from: "enum SettingsTabGroup", to: "var title")
        let cases = groups.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("case ") }
            .map { String($0.dropFirst(5)) }
        XCTAssertEqual(cases, ["product", "settings", "info"])
    }

    func testOnlyTheSettingsRowHasAName() throws {
        let source = try Self.source()
        XCTAssertTrue(source.contains(#"case .settings:         return String(localized: "Settings")"#))
        XCTAssertTrue(source.contains("case .product, .info:   return nil"), "a list with a header would need one on screen")
    }

    /// Search jumps to the first match in `availableTabs`, so it lists the tabs in sidebar order.
    func testSearchFollowsTheSidebarOrder() throws {
        XCTAssertEqual(try Self.ordered(try Self.source()), Self.product + Self.settings + ["about"])
    }

    private static func ordered(_ source: String) throws -> [String] {
        try slice(source, from: "let ordered: [SettingsTab] = [", to: "]").split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix(".") }
            .map { String($0.dropFirst().prefix { $0.isLetter || $0.isNumber }) }
    }

    /// `var group`'s tabs by the group they return. A case may run over several lines.
    private static func tabsByGroup(in body: String) throws -> [String: [String]] {
        let entry = try NSRegularExpression(pattern: #"case ([^:]+):\s*return \.(\w+)"#)
        let name = try NSRegularExpression(pattern: #"\.(\w+)"#)
        var out: [String: [String]] = [:]
        for match in entry.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let list = Range(match.range(at: 1), in: body), let group = Range(match.range(at: 2), in: body) else { continue }
            let text = String(body[list])
            let tabs = name.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { found in
                Range(found.range(at: 1), in: text).map { String(text[$0]) }
            }
            out[String(body[group]), default: []] += tabs
        }
        return out
    }

    func testEachTabIsInItsList() throws {
        let source = try Self.source()
        let body = try Self.slice(source, from: "var group: SettingsTabGroup {", to: "var isBeta")
        XCTAssertFalse(body.contains("default:"), "a default would let a new tab land on a list unread")
        let groups = try Self.tabsByGroup(in: body)
        XCTAssertEqual(groups["product"], Self.product)
        XCTAssertEqual(try XCTUnwrap(groups["settings"]).sorted(), Self.settings.sorted())
        XCTAssertEqual(groups["info"], ["about"])

        let every = groups.values.flatMap { $0 }
        XCTAssertEqual(every.count, 22, "a tab on two lists, or on none")
        XCTAssertEqual(Set(every), Set(try Self.ordered(source)), "every tab on a list is in the order, and the reverse")

        XCTAssertEqual(try Self.tabsByGroup(in: "case .a, .b,\n     .c:\n    return .one\ncase .d: return .two\n"),
                       ["one": ["a", "b", "c"], "two": ["d"]], "the parser must follow a case over several lines")
    }
}
