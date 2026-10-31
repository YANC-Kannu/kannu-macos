//
//  SettingsAnimationRulesTests.swift
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

/// Closing Brain only orders its window out: its SwiftUI stays alive, and an animation in it goes on
/// ticking at the display's rate with nothing on screen. So a repeating animation under Settings
/// must end by itself (docs/REGRESSIONS.md, entry 23). What actually stops one can't be run in this
/// logic-only target, so the rule is pinned in the source, as the other rules tests do.
final class SettingsAnimationRulesTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func settingsSources() throws -> [String: String] {
        let directory = repoRoot.appendingPathComponent("Kannu/components/Settings")
        var sources: [String: String] = [:]
        let files = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        for case let file as URL in files where file.pathExtension == "swift" {
            sources[file.lastPathComponent] = try String(contentsOf: file, encoding: .utf8)
        }
        return sources
    }

    /// Lines that start an animation with no end. Comments may name it; code may not.
    private static func offenders(in source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { line in
            let code = line.components(separatedBy: "//")[0]
            return code.range(of: #"\.repeatForever\s*\("#, options: .regularExpression) != nil
        }
    }

    func testNothingUnderSettingsRepeatsForever() throws {
        let sources = try Self.settingsSources()
        XCTAssertFalse(sources.isEmpty, "the scan read nothing: the path moved")
        for (name, source) in sources {
            XCTAssertEqual(Self.offenders(in: source), [], "\(name) animates forever behind a closed Brain")
        }
    }

    func testTheHighlightPulseIsBounded() throws {
        let view = try XCTUnwrap(Self.settingsSources()["SettingsView.swift"])
        XCTAssertTrue(view.contains(".repeatCount(3, autoreverses: true)"))
    }

    /// Guards the detector, not the tree: a pattern that matched nothing would pass forever.
    func testTheScannerCatchesEveryShapeOfOffender() {
        let planted = """
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true }
        .animation(active ? .easeInOut.repeatForever() : .default, value: pulse)
        let pulse = Animation.easeIn.repeatForever (autoreverses: true)
        // A comment may name .repeatForever(autoreverses: true).
        .animation(.easeInOut.repeatCount(3), value: pulse)
        """
        XCTAssertEqual(Self.offenders(in: planted).count, 3)
    }
}
