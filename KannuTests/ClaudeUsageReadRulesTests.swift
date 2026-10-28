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

/// REGRESSIONS entry 11 for the Claude usage readers: `~/.claude.json` (85 KB, rewritten whole by
/// every Claude Code process) and Claude Desktop's history are read on a worker, never on the main
/// actor. With nothing to show, the monitor re-parsed both on the main actor at every rescan —
/// several times a second under a busy agent (2026-10-28). The monitor is not in the logic target,
/// so its wiring is read from source (the `TrafficLightGateRulesTests` idiom); the reads themselves
/// are `ClaudeUsageSources.read`, which `ClaudeUsageOrganizationTests` runs against real files.
final class ClaudeUsageReadRulesTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func source(_ path: String) throws -> String {
        let text = try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
        // Comments may name the readers; only code counts.
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private static func body(of function: String, in text: String) throws -> String {
        let start = try XCTUnwrap(text.range(of: function), "\(function) not found")
        let open = try XCTUnwrap(text.range(of: "{", range: start.upperBound..<text.endIndex))
        var depth = 0
        var index = open.lowerBound
        repeat {
            if text[index] == "{" { depth += 1 } else if text[index] == "}" { depth -= 1 }
            index = text.index(after: index)
        } while index < text.endIndex && depth > 0
        return String(text[start.lowerBound..<index])
    }

    private static let monitorPath = "Kannu/managers/AgentStatus/CursorAgentStatusMonitor.swift"

    /// The blocking readers, by name. The monitor calls none of them: it calls
    /// `ClaudeUsageSources.read`, on its worker queue, which calls these.
    private static let fileReaders = [
        "ClaudeCachedUsage.read(", "ClaudeCachedUsage.load(",
        "ClaudeDesktopUsageHistory.read(", "ClaudeDesktopUsageHistory.load(",
        "ClaudeUsageSnapshot.load(", "Data(contentsOf:"
    ]

    func testTheMonitorReadsNoUsageFileItself() throws {
        let monitor = try Self.source(Self.monitorPath)
        for reader in Self.fileReaders where reader != "Data(contentsOf:" {
            XCTAssertFalse(monitor.contains(reader), "the monitor calls \(reader) — on the main actor")
        }
        XCTAssertEqual(monitor.components(separatedBy: "ClaudeUsageSources.read(").count - 1, 1,
                       "one call site for the usage read, and it is the worker's")
    }

    func testTheUsageReadRunsOnTheWorkerAndAppliesOnMain() throws {
        let monitor = try Self.source(Self.monitorPath)
        XCTAssertTrue(monitor.contains("static let claudeUsageReadQueue = DispatchQueue(label:"),
                      "the usage reads need their own serial queue: in order, and never the main one")
        let reader = try Self.body(of: "private func readClaudeUsageSources(", in: monitor)
        let worker = try XCTUnwrap(reader.range(of: "Self.claudeUsageReadQueue.async"), "the read must be dispatched")
        let read = try XCTUnwrap(reader.range(of: "ClaudeUsageSources.read("), "the worker must do the read")
        let hop = try XCTUnwrap(reader.range(of: "DispatchQueue.main.async"), "the result must come back to main")
        XCTAssertLessThan(worker.lowerBound, read.lowerBound, "read inside the worker block")
        XCTAssertLessThan(read.lowerBound, hop.lowerBound, "read before the hop back, never after it")
        XCTAssertTrue(reader[hop.upperBound...].contains("self.apply("), "applied on the main actor")
    }

    func testTheRescanAndTheReloadOnlyDecide() throws {
        let monitor = try Self.source(Self.monitorPath)
        for function in ["private func refreshClaudeUsage(", "private func reloadClaudeUsageNow("] {
            let body = try Self.body(of: function, in: monitor)
            XCTAssertTrue(body.contains("readClaudeUsageSources("), "\(function) must hand the read to the worker")
            for reader in Self.fileReaders + ["ClaudeUsageSources.read("] {
                XCTAssertFalse(body.contains(reader), "\(function) reads with \(reader) on the main actor")
            }
        }
        // A read in flight is not started again by every rescan.
        let refresh = try Self.body(of: "private func refreshClaudeUsage(", in: monitor)
        XCTAssertTrue(refresh.contains("claudeUsageReadsInFlight == 0"))
    }

    func testTheCardReadsTheMonitorNotTheFiles() throws {
        let provider = try Self.source("Kannu/managers/LLMUsage/ClaudeUsageProvider.swift")
        let apply = try Self.body(of: "private func applyRateLimitWindows(", in: provider)
        for reader in Self.fileReaders + ["ClaudeUsageSources.read("] {
            XCTAssertFalse(apply.contains(reader), "the main-actor mapping reads with \(reader)")
        }
    }
}
