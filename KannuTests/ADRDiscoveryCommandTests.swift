//
//  ADRDiscoveryCommandTests.swift
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

/// The `adr-discovery` invocation as data — the REGRESSIONS entry 8 discipline. Every flag
/// here was checked against upstream's `cli.py` at `ADRUpstream.commit`.
final class ADRDiscoveryCommandTests: XCTestCase {
    private let out = URL(fileURLWithPath: "/Users/dev/.kannu/adr/discovery", isDirectory: true)

    func testArgumentsWriteAJSONSnapshotIntoTheWatchedFolder() {
        let args = ADRDiscoveryCommand.arguments(outputDirectory: out, policyFile: nil)
        XCTAssertEqual(args, ["--json", "--output-dir", "/Users/dev/.kannu/adr/discovery"])
        XCTAssertTrue(ADRDiscoveryCommand.isValidScan(arguments: args))
    }

    func testPolicyIsAppendedOnlyWhenConfigured() {
        let policy = URL(fileURLWithPath: "/Users/dev/policy.json")
        let args = ADRDiscoveryCommand.arguments(outputDirectory: out, policyFile: policy)
        XCTAssertEqual(args.suffix(2), ["--policy", "/Users/dev/policy.json"])
        XCTAssertTrue(ADRDiscoveryCommand.isValidScan(arguments: args))
    }

    func testForbiddenFlagsAreRejected() {
        // --dry-run writes nothing; --root scans a fixture tree; --diff/--explain change the output;
        // --resolve makes DNS lookups; --archive-skills writes a zip of every skill.
        for flag in ["--dry-run", "--root", "--diff", "--explain", "--resolve", "--archive-skills"] {
            XCTAssertFalse(ADRDiscoveryCommand.isValidScan(arguments: ["--json", "--output-dir", out.path, flag]), flag)
        }
        XCTAssertFalse(ADRDiscoveryCommand.isValidScan(arguments: ["--output-dir", out.path]), "no --json, no machine-readable file")
        XCTAssertFalse(ADRDiscoveryCommand.isValidScan(arguments: ["--json", "--output-dir"]), "dangling --output-dir")
    }

    func testExitCodesMatchUpstream() {
        XCTAssertTrue(ADRDiscoveryCommand.producedSnapshot(exitStatus: 0))
        XCTAssertTrue(ADRDiscoveryCommand.producedSnapshot(exitStatus: 2), "partial coverage still wrote a snapshot")
        XCTAssertFalse(ADRDiscoveryCommand.producedSnapshot(exitStatus: 1))
        XCTAssertFalse(ADRDiscoveryCommand.producedSnapshot(exitStatus: -1))
    }

    func testTimeoutIsBoundedButGenerous() {
        // A real scan here took 17 s; a hung one must not pin a worker forever.
        XCTAssertGreaterThanOrEqual(ADRDiscoveryCommand.timeout, 60)
        XCTAssertLessThanOrEqual(ADRDiscoveryCommand.timeout, 600)
    }

    /// The prompt is the whole spec the user's agent gets, so pin what it must carry: where to
    /// write, the default list, the forbidden lists (since upstream a3ab5f7 they flag MCP servers
    /// too, and a match is high), the check that keeps a bad file from failing every scan, and the
    /// rule against copying secrets out of MCP configs.
    func testThePolicyDraftingPromptStatesTheFormatAndItsLimits() {
        let prompt = ADRDiscoveryCommand.policyDraftingPrompt
        XCTAssertTrue(prompt.contains(ADRDiscoveryCommand.suggestedPolicyPath))
        XCTAssertTrue(prompt.contains(#"{"tenant_domains": ["#))
        XCTAssertTrue(prompt.contains("python3 -m json.tool"))
        XCTAssertTrue(prompt.contains("never tokens, headers or environment values"))
        XCTAssertFalse(prompt.contains("never flag an MCP server"), "forbidden_indicators do flag MCP servers now")
        for indicator in [#""forbidden_indicators""#, #"{"kind": "mcp_endpoint""#, #"{"kind": "package""#, #""asset_kind": "mcp_server""#] {
            XCTAssertTrue(prompt.contains(indicator), indicator)
        }
        XCTAssertTrue(prompt.contains("high-severity finding"))
        XCTAssertTrue(prompt.contains("Leave all four out unless I ask"), "the forbidden lists stay opt-in")
        XCTAssertTrue(prompt.contains("unknown kind or an extra field"), "a bad indicator fails every scan")
        // ADR's normalize_url drops user info, query and fragment before comparing, so copying them
        // from an MCP config only puts a URL's secrets in a second file.
        XCTAssertTrue(prompt.contains("never user info, a query string or a fragment"))
        XCTAssertTrue(prompt.contains("if the path itself carries a key, use a name indicator instead"))
        XCTAssertTrue(prompt.contains("Ask me"))
        // The suggested file is ADR's policy, never inside the snapshots folder Kannu watches.
        XCTAssertFalse(ADRDiscoveryCommand.suggestedPolicyPath.contains("/discovery/"))
    }

    // MARK: - The upstream pin

    /// Every install line Kannu hands out names one full commit: an unpinned `main` install is the
    /// supply-chain shape Kannu reports for MCP servers.
    func testInstallLinesArePinnedToOneFullCommit() {
        let commit = ADRUpstream.commit
        XCTAssertEqual(commit.count, 40)
        XCTAssertTrue(commit.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        XCTAssertEqual(ADRUpstream.discoveryInstallCommand,
                       #"uv tool install "adr-discovery @ git+https://github.com/uber/ADR@"# + commit + #"#subdirectory=Discovery""#)
        XCTAssertEqual(ADRUpstream.discoveryPipxCommand,
                       #"pipx install "git+https://github.com/uber/ADR@"# + commit + #"#subdirectory=Discovery""#)
        XCTAssertEqual(ADRUpstream.detectionCloneCommand,
                       "git clone https://github.com/uber/ADR && cd ADR && git checkout \(commit) && cd Detection && uv sync")
        XCTAssertEqual(ADRUpstream.detectionUpdateCommand, "git fetch && git checkout \(commit) && uv sync")
        for line in [ADRUpstream.discoveryInstallCommand, ADRUpstream.discoveryPipxCommand] {
            XCTAssertFalse(line.contains("ADR#"), "the revision goes before the fragment: \(line)")
        }
    }

    /// `before` and `after` are upstream's `adr_baseline.py` either side of 1c8ecd6, which added the
    /// `isinstance` check (twice); a checkout without it cannot parse Claude Code 2.1's list-shaped
    /// JSON.
    func testACheckoutWithoutTheClaudeCode21FixIsStale() {
        let before = """
                claude_result = json.loads(result.stdout)
                if claude_result.get('subtype') != 'success' or claude_result.get('is_error'):
            """
        let after = """
                claude_result = json.loads(result.stdout)
                if isinstance(claude_result, list):
                    claude_result = next((item for item in reversed(claude_result) if isinstance(item, dict) and item.get('type') == 'result'), claude_result[-1] if claude_result else {})
                if claude_result.get('subtype') != 'success' or claude_result.get('is_error'):
            """
        XCTAssertTrue(ADRUpstream.predatesClaudeCode21OutputFix(baselineSource: before))
        XCTAssertFalse(ADRUpstream.predatesClaudeCode21OutputFix(baselineSource: after))
    }

    /// A stale verdict hides "Analyze with ADR Detection", and its update line checks out the pin,
    /// so only the old code itself may trigger it: a later upstream rewrite that drops the
    /// `claude_result = json.loads(` line, or an empty file, is left for the run to judge, never
    /// sent back to the pin.
    func testACheckoutWithoutTheOldCodeIsNotStale() {
        let rewritten = """
                payload = _parse_claude_json(result.stdout)
                if payload.get('subtype') != 'success' or payload.get('is_error'):
            """
        XCTAssertFalse(ADRUpstream.predatesClaudeCode21OutputFix(baselineSource: rewritten))
        XCTAssertFalse(ADRUpstream.predatesClaudeCode21OutputFix(baselineSource: ""))
    }

    /// `ADRConnection` (not in this target) is what Settings' Copy buttons and the Detection
    /// checkout row read, so pin its source: the pinned constants, never an unpinned literal, and
    /// the stale-checkout check still called.
    func testSettingsCopiesThePinnedLinesAndChecksForAStaleCheckout() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let connection = try String(contentsOf: root.appendingPathComponent("Kannu/managers/AgentStatus/ADRConnection.swift"), encoding: .utf8)
        for use in [
            "return ADRUpstream.discoveryInstallCommand",
            "return ADRUpstream.discoveryPipxCommand",
            "static let detectionCloneCommand = ADRUpstream.detectionCloneCommand",
            "ADRUpstream.predatesClaudeCode21OutputFix(",
            "\\(ADRUpstream.detectionUpdateCommand)",
        ] {
            XCTAssertTrue(connection.contains(use), use)
        }
        // No app source may carry an unpinned install line of its own.
        let kannu = root.appendingPathComponent("Kannu")
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: kannu, includingPropertiesForKeys: nil))
        var scanned = 0
        for case let url as URL in walker where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            scanned += 1
            for unpinned in ["github.com/uber/ADR#subdirectory", "cd ADR/Detection && uv sync"] {
                XCTAssertFalse(source.contains(unpinned), "\(url.lastPathComponent) has \(unpinned)")
            }
        }
        XCTAssertGreaterThan(scanned, 100, "the walk found the app sources")
    }
}
