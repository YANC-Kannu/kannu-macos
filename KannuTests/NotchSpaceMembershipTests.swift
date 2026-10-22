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

/// The notch window joins Kannu's own top-level CGSSpace on every hide option. Until 2026-10-22 only
/// "Never hide" did; everyone else was on `.canJoinAllSpaces` alone, and a window on the managed
/// spaces rides the Space-switch slide, so the notch visibly detached from the hardware notch and
/// re-attached on the next space. Fullscreen hiding is `KannuViewModel.hideOnClosed`, in the views,
/// and never depended on the membership, so the gate bought nothing. `AppDelegate` is AppKit with no
/// unit surface, so the invariant is read from the source (the `NotchInteractionTests` idiom).
final class NotchSpaceMembershipTests: XCTestCase {

    func testEveryNotchWindowJoinsTheNotchSpace() throws {
        let lines = try Self.codeLines("Kannu/KannuApp.swift")
        let insert = "NotchSpaceManager.shared.notchSpace.windows.insert(window)"
        let at = try XCTUnwrap(lines.firstIndex(of: insert), "createKannuWindow no longer inserts the window into the notch space")
        let previous = try XCTUnwrap(lines[..<at].last { !$0.isEmpty })
        XCTAssertFalse(previous.hasPrefix("if ") || previous.hasPrefix("guard ") || previous.hasPrefix("} else"),
                       "the insert is gated again (\(previous)); the hide option must not decide space membership")
    }

    func testTheSpaceSyncIsNotGatedOnTheHideOption() throws {
        let code = try Self.codeLines("Kannu/KannuApp.swift").joined(separator: "\n")
        let sync = try XCTUnwrap(Self.body(ofFunction: "syncNotchSpaceMembership", in: code),
                                 "syncNotchSpaceMembership went away; the stranded-notch repair relies on it")
        XCTAssertFalse(sync.contains("hideNotchOption"), "the sync empties the space for the hide options again")
        XCTAssertTrue(sync.contains("Set(windows.values)") && sync.contains("[window]"),
                      "the sync no longer rebuilds the set from the live windows")
    }

    func testTeardownStillLeavesTheSpace() throws {
        let code = try Self.codeLines("Kannu/KannuApp.swift").joined(separator: "\n")
        XCTAssertEqual(code.components(separatedBy: "notchSpace.windows.remove(window)").count - 1, 2,
                       "a window that joins the space on every option must leave it on every teardown path")
    }

    func testTheWindowKeepsItsManagedSpaceFallback() throws {
        let window = try Self.codeLines("Kannu/components/Notch/KannuWindow.swift").joined(separator: "\n")
        for behaviour in [".fullScreenAuxiliary,", ".canJoinAllSpaces,", ".stationary,", ".ignoresCycle,"] {
            XCTAssertTrue(window.contains(behaviour), "\(behaviour) left the notch window's collectionBehavior")
        }
    }

    // MARK: - Helpers

    private static func codeLines(_ path: String) throws -> [String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        return source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") }
    }

    /// The text of a function body, from its declaration to the next `func ` at file scope. Crude on
    /// purpose: enough to scope a pin to one function without parsing Swift.
    private static func body(ofFunction name: String, in text: String) -> String? {
        guard let start = text.range(of: "func \(name)(") else { return nil }
        let rest = text[start.upperBound...]
        let end = ["\nfunc ", "\nprivate func ", "\n@MainActor\nfunc ", "\n@MainActor\nprivate func "]
            .compactMap { rest.range(of: $0)?.lowerBound }
            .min() ?? rest.endIndex
        return String(rest[..<end])
    }
}
