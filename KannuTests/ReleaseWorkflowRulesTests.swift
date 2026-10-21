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

/// A beta never reaches every user. The release workflow runs on every `v*` tag, and its last step
/// commits the appcast to `main`, which every installed Kannu reads: before pre-release tags were
/// handled, `v1.4.0-beta.1` would have been offered to everyone by Sparkle and published as the
/// Latest release. A tag with a hyphen is a pre-release now; these pins keep it one. The workflow
/// is YAML that only runs on a tag, so its text is read.
final class ReleaseWorkflowRulesTests: XCTestCase {
    private static let workflowPath = ".github/workflows/release.yml"

    func testAPreReleaseTagNeverReachesTheAppcast() throws {
        XCTAssertEqual(Self.problems(in: try Self.read(Self.workflowPath)), [])
    }

    func testTheScannerCatchesTheOldWorkflow() throws {
        let workflow = try Self.read(Self.workflowPath)
        let unguarded = workflow.replacingOccurrences(of: "        if: env.RELEASE_PRERELEASE != 'true'\n", with: "")
        XCTAssertEqual(Self.problems(in: unguarded), [
            "Export Sparkle Update Assets runs for a pre-release",
            "Upload Sparkle Artifact runs for a pre-release",
            "Update appcast on main runs for a pre-release",
        ])
        let unflagged = workflow
            .replacingOccurrences(of: "          prerelease: ${{ env.RELEASE_PRERELEASE == 'true' }}\n", with: "")
            .replacingOccurrences(of: "if [[ \"${VERSION}\" == *-* ]]; then", with: "if false; then")
        XCTAssertEqual(Self.problems(in: unflagged), [
            "a tag with a hyphen is not marked a pre-release",
            "the GitHub release is not published as a pre-release",
        ])
    }

    // MARK: - Rules

    static func problems(in workflow: String) -> [String] {
        var problems: [String] = []
        if !workflow.contains("if [[ \"${VERSION}\" == *-* ]]; then\n            echo \"RELEASE_PRERELEASE=true\" >> \"$GITHUB_ENV\"") {
            problems.append("a tag with a hyphen is not marked a pre-release")
        }
        for step in ["Export Sparkle Update Assets", "Upload Sparkle Artifact", "Update appcast on main"] {
            guard let range = workflow.range(of: "- name: \(step)\n") else {
                problems.append("\(step) is gone")
                continue
            }
            let next = workflow[range.upperBound...].prefix(80)
            if !next.hasPrefix("        if: env.RELEASE_PRERELEASE != 'true'\n") {
                problems.append("\(step) runs for a pre-release")
            }
        }
        let publish = workflow.range(of: "- name: Publish GitHub Release").map { String(workflow[$0.upperBound...].prefix(700)) } ?? ""
        if !publish.contains("prerelease: ${{ env.RELEASE_PRERELEASE == 'true' }}")
            || !publish.contains("make_latest: ${{ env.RELEASE_PRERELEASE == 'true' && 'false' || 'true' }}") {
            problems.append("the GitHub release is not published as a pre-release")
        }
        return problems
    }

    private static func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
