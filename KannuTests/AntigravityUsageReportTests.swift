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

//
//  AntigravityUsageReportTests.swift
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

import Security
import XCTest

/// `agy -p "/usage" --output-format json` has no documented field names, so these fixtures are
/// plausible shapes, not captured output. They pin what the tolerant reader accepts and what it
/// refuses; none of it has been checked against a real `agy` (Antigravity is not installed here).
final class AntigravityUsageReportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_300_000)

    private func parse(_ json: String) -> [AntigravityQuotaPool] {
        AntigravityUsageReport.parse(Data(json.utf8), now: now)
    }

    private func iso(_ text: String) -> Date? { ISO8601DateFormatter().date(from: text) }

    // MARK: - The invocation, as data (REGRESSIONS entry 8)

    func testTheInvocationIsPinned() {
        XCTAssertEqual(AntigravityUsageCommand.arguments, ["-p", "/usage", "--output-format", "json"])
        XCTAssertNil(AntigravityUsageCommand.environment, "Kannu's environment, nothing added")
        XCTAssertGreaterThan(AntigravityUsageCommand.timeout, 0)
        XCTAssertLessThanOrEqual(AntigravityUsageCommand.timeout, 30, "headless agy has no timeout of its own")
        XCTAssertGreaterThanOrEqual(AntigravityUsageCommand.failureBackoff, 600)
        XCTAssertEqual(AntigravityUsageCommand.teamID, "EQHXZ8M8AV")
        let requirement = AntigravityUsageCommand.codeRequirement
        XCTAssertTrue(requirement.hasPrefix("anchor apple generic"))
        XCTAssertTrue(requirement.contains("field.1.2.840.113635.100.6.2.6"), "Developer ID intermediate")
        XCTAssertTrue(requirement.contains("field.1.2.840.113635.100.6.1.13"), "Developer ID Application leaf")
        XCTAssertTrue(requirement.hasSuffix("certificate leaf[subject.OU] = \"EQHXZ8M8AV\""))
        let home = URL(fileURLWithPath: "/Users/u")
        let candidates = AntigravityUsageCommand.candidates(home: home).map(\.path)
        XCTAssertEqual(candidates, ["/Users/u/.local/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy"])
        XCTAssertFalse(candidates.contains { $0.contains("/.gemini") }, "nothing is run from Antigravity's own data folder")
    }

    // MARK: - Shapes it accepts

    func testSnakeCasePoolsWithNamedWindows() throws {
        let pools = parse(#"""
        {"pools": [
          {"display_name": "Gemini Pro", "five_hour": {"used_percentage": 42.5, "resets_at": "2026-10-18T15:00:00Z"},
           "weekly": {"used_percentage": 10, "resets_at": "2026-10-21T00:00:00Z"}},
          {"display_name": "Gemini Flash", "five_hour": {"used_percentage": 3}}
        ]}
        """#)
        XCTAssertEqual(pools.count, 2)
        XCTAssertEqual(pools[0], AntigravityQuotaPool(name: "Gemini Pro",
                                                      fiveHour: .init(usedPercent: 42.5, resetsAt: iso("2026-10-18T15:00:00Z")),
                                                      weekly: .init(usedPercent: 10.0, resetsAt: iso("2026-10-21T00:00:00Z"))))
        XCTAssertEqual(pools[1].name, "Gemini Flash")
        XCTAssertEqual(pools[1].fiveHour?.usedPercent, 3.0)
        XCTAssertNil(pools[1].weekly)
    }

    func testCamelCaseWindowListsInsideTheHeadlessEnvelope() throws {
        // The headless JSON envelope (antigravity.google/docs/cli/headless) with the answer as JSON text
        // in `response`, beside its token `usage`, which is not a quota.
        let inner = #"{"quota":{"pools":[{"displayName":"Claude","windows":[{"window":"5h","remainingFraction":0.75,"resetTime":1792310000},{"window":"weekly","remainingFraction":0.9,"resetTime":1792900000000}]}]}}"#
        let envelope: [String: Any] = ["conversation_id": "", "status": "SUCCESS", "response": inner, "duration_seconds": 0.4,
                                       "usage": ["input_tokens": 0, "output_tokens": 0, "total_tokens": 0]]
        let pools = AntigravityUsageReport.parse(try JSONSerialization.data(withJSONObject: envelope), now: now)
        XCTAssertEqual(pools.count, 1)
        let pool = try XCTUnwrap(pools.first)
        XCTAssertEqual(pool.name, "Claude")
        XCTAssertEqual(try XCTUnwrap(pool.fiveHour?.usedPercent), 25.0, accuracy: 0.0001)
        XCTAssertEqual(pool.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_792_310_000), "epoch seconds")
        XCTAssertEqual(try XCTUnwrap(pool.weekly?.usedPercent), 10.0, accuracy: 0.0001)
        XCTAssertEqual(pool.weekly?.resetsAt, Date(timeIntervalSince1970: 1_792_900_000), "epoch milliseconds")
    }

    func testKeyedPoolsDurationsCountsAndRelativeResets() throws {
        let pools = parse(#"""
        {"structured_output": {"pools": {
          "gemini-pro": {"limits": [{"duration_seconds": 18000, "used": 30, "limit": 120, "resets_in_seconds": 600},
                                    {"duration_seconds": 604800, "remaining": 900, "limit": 1000}]},
          "gemini-flash": {"rate_limits": {"seven_day": {"remaining_percent": "80%", "reset_at": "2026-10-20T08:00:00.250Z"}}}
        }}}
        """#)
        XCTAssertEqual(pools.map(\.name), ["gemini-flash", "gemini-pro"], "keyed pools take their key as the name, in key order")
        let flash = pools[0], pro = pools[1]
        XCTAssertNil(flash.fiveHour)
        XCTAssertEqual(flash.weekly?.usedPercent, 20.0)
        XCTAssertNotNil(flash.weekly?.resetsAt, "fractional seconds")
        XCTAssertEqual(try XCTUnwrap(pro.fiveHour?.usedPercent), 25.0, accuracy: 0.0001)
        XCTAssertEqual(pro.fiveHour?.resetsAt, now.addingTimeInterval(600))
        XCTAssertEqual(try XCTUnwrap(pro.weekly?.usedPercent), 10.0, accuracy: 0.0001)
        XCTAssertNil(pro.weekly?.resetsAt)
    }

    func testASinglePoolAtTheTopLevel() {
        let pools = parse(#"{"fiveHour": {"usedPercent": 101}, "weekly": {"usedFraction": 0.5}, "plan": "Pro"}"#)
        XCTAssertEqual(pools, [AntigravityQuotaPool(name: nil, fiveHour: .init(usedPercent: 100.0, resetsAt: nil),
                                                    weekly: .init(usedPercent: 50.0, resetsAt: nil))],
                       "over 100 is clamped; no name field, no key: unnamed")
    }

    // MARK: - What it refuses

    func testNothingUsableGivesNoPools() throws {
        let refused = [
            "", "not json", "[]", "42", #""text""#,
            // A failed headless run.
            #"{"status": "ERROR", "error": "not signed in", "pools": [{"name": "x", "five_hour": {"used_percentage": 1}}]}"#,
            // Only token accounting.
            #"{"status": "SUCCESS", "response": "Model quotas\tGemini Pro\t42%", "usage": {"input_tokens": 0, "total_tokens": 0}}"#,
            // Windows Kannu does not map: a daily cap, an unnamed per-model fraction.
            #"{"pools": [{"name": "Pro", "daily": {"used_percentage": 50}}]}"#,
            #"{"models": [{"model": "gemini-3.1-pro", "quotaInfo": {"remainingFraction": 0.4, "resetTime": "2026-10-18T15:00:00Z"}}]}"#,
            // Values that are not numbers, or fractions out of range.
            #"{"pools": [{"name": "Pro", "five_hour": {"used_percentage": true}, "weekly": {"remaining_fraction": 4}}]}"#,
            #"{"pools": [{"name": "Pro", "five_hour": {"used_percentage": "lots"}}]}"#,
        ]
        for text in refused {
            XCTAssertEqual(parse(text), [], text)
        }
    }

    func testTheReaderIsBounded() throws {
        let many = (0..<40).map { #"{"name": "p\#($0)", "weekly": {"used_percentage": 1}}"# }.joined(separator: ",")
        XCTAssertEqual(parse(#"{"pools": [\#(many)]}"#).count, AntigravityUsageReport.maxPools)
        var deep = #"{"weekly": {"used_percentage": 5}}"#
        for _ in 0..<20 { deep = #"{"a": \#(deep)}"# }
        XCTAssertEqual(parse(deep), [], "nothing is looked for past the depth cap")
        let long = String(repeating: "N", count: 200)
        XCTAssertEqual(parse(#"{"pools": [{"name": "\#(long)", "weekly": {"used_percentage": 5}}]}"#).first?.name?.count, 48)
        XCTAssertNil(parse(#"{"pools": [{"name": "a\u0007b", "weekly": {"used_percentage": 5}}]}"#).first?.name,
                     "a control character is not a label")
        XCTAssertEqual(AntigravityUsageReport.parse(Data(count: AntigravityUsageCommand.stdoutCap + 1), now: now), [])
    }

    func testWindowNames() {
        for name in ["five_hour", "fiveHour", "5h", "5-hour", "5 hours", "session"] {
            XCTAssertEqual(AntigravityUsageReport.windowKind(named: name), .fiveHour, name)
        }
        for name in ["weekly", "week", "seven_day", "7d", "7 days", "168h"] {
            XCTAssertEqual(AntigravityUsageReport.windowKind(named: name), .weekly, name)
        }
        for name in ["daily", "15h", "monthly", "usage", ""] {
            XCTAssertNil(AntigravityUsageReport.windowKind(named: name), name)
        }
    }

    // MARK: - The card's slots

    func testOnePoolFillsTheTwoBarsWithNoLabel() {
        let pool = AntigravityQuotaPool(name: "Gemini Pro", fiveHour: .init(usedPercent: 40.0, resetsAt: nil),
                                        weekly: .init(usedPercent: 10.0, resetsAt: nil))
        let limits = AntigravityQuotaLimits(pools: [pool])
        XCTAssertEqual(limits.session, pool.fiveHour)
        XCTAssertEqual(limits.week, pool.weekly)
        XCTAssertNil(limits.label, "one pool is every model")
        XCTAssertTrue(limits.extras.isEmpty)
        XCTAssertTrue(AntigravityQuotaLimits(pools: []).isEmpty)
    }

    func testEveryOtherPoolBecomesLabelledExtras() {
        let weeklyOnly = AntigravityQuotaPool(name: "Images", fiveHour: nil, weekly: .init(usedPercent: 70.0, resetsAt: nil))
        let pro = AntigravityQuotaPool(name: "Gemini Pro", fiveHour: .init(usedPercent: 40.0, resetsAt: nil),
                                       weekly: .init(usedPercent: 10.0, resetsAt: nil))
        let unnamed = AntigravityQuotaPool(name: nil, fiveHour: .init(usedPercent: 5.0, resetsAt: nil),
                                           weekly: .init(usedPercent: 1.0, resetsAt: nil))
        let limits = AntigravityQuotaLimits(pools: [weeklyOnly, pro, unnamed])
        XCTAssertEqual(limits.session?.usedPercent, 40.0, "the first pool with a 5-hour window is the primary")
        XCTAssertEqual(limits.week?.usedPercent, 10.0)
        XCTAssertEqual(limits.label, "Gemini Pro")
        XCTAssertEqual(limits.extras.map(\.label), ["Images", "Pool 3", "Pool 3"])
        XCTAssertEqual(limits.extras.map(\.isSessionWindow), [false, true, false])
        XCTAssertEqual(limits.extras.map(\.window.usedPercent), [70.0, 5.0, 1.0])
        XCTAssertEqual(Set(limits.extras.map(\.key)).count, 3, "one key per bar")
        XCTAssertTrue(limits.extras.allSatisfy { $0.key.hasPrefix("antigravity_") })
        // Weekly windows alone still fill the weekly bar.
        let onlyWeekly = AntigravityQuotaLimits(pools: [weeklyOnly])
        XCTAssertNil(onlyWeekly.session)
        XCTAssertEqual(onlyWeekly.week?.usedPercent, 70.0)
    }

    // MARK: - The gates around the run

    func testTheProviderTakesTheNetworkFloor() {
        // `AntigravityUsageProvider.isLocalFileProvider` is `!reachesNetwork`. As a local-file
        // provider it would ask Google's backend on every 30-second tick and every tab open.
        XCTAssertTrue(AntigravityUsageCommand.reachesNetwork)
    }

    /// The same calls `AntigravityQuotaReader.isSignedByGoogle` makes, with the same flags.
    private func meetsTheRequirement(_ path: String) throws -> Bool {
        var requirement: SecRequirement?
        let created = SecRequirementCreateWithString(AntigravityUsageCommand.codeRequirement as CFString, [], &requirement)
        XCTAssertEqual(created, errSecSuccess, "a requirement that does not compile means agy is never run")
        let compiled = try XCTUnwrap(requirement)
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        return SecStaticCodeCheckValidity(code, flags, compiled) == errSecSuccess
    }

    func testTheCodeRequirementCompilesAndRefusesWhatGoogleDidNotSign() throws {
        XCTAssertFalse(try meetsTheRequirement("/bin/ls"), "signed by Apple, not with a Developer ID")
        XCTAssertFalse(try meetsTheRequirement("/usr/bin/python3"))
    }

    func testTheCodeRequirementAcceptsAGoogleSignedBinary() throws {
        // Google Chrome carries the same team's Developer ID, so it stands in for `agy`, which is not
        // installed here. Skipped on a Mac without Chrome.
        let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: chrome), "Google Chrome is not installed")
        XCTAssertTrue(try meetsTheRequirement(chrome))
    }

    // MARK: - What is checked again, and when

    private func facts(changed: Int64) -> AntigravityFileFacts {
        AntigravityFileFacts(device: 1, inode: 2, size: 3, modifiedNanoseconds: 4, changedNanoseconds: changed)
    }

    func testAVerdictPassOrFailIsKeptUntilTheFileChanges() {
        var verdicts = AntigravitySignatureVerdicts()
        XCTAssertNil(verdicts.verdict(path: "/a/agy", facts: facts(changed: 5)), "never checked")
        verdicts.record(false, path: "/a/agy", facts: facts(changed: 5))
        XCTAssertEqual(verdicts.verdict(path: "/a/agy", facts: facts(changed: 5)), false, "a fail is not hashed again")
        XCTAssertNil(verdicts.verdict(path: "/a/agy", facts: facts(changed: 6)), "a new ctime is checked again")
        XCTAssertNil(verdicts.verdict(path: "/b/agy", facts: facts(changed: 5)), "kept per path")
        verdicts.record(true, path: "/a/agy", facts: facts(changed: 6))
        XCTAssertEqual(verdicts.verdict(path: "/a/agy", facts: facts(changed: 6)), true)
        XCTAssertNil(verdicts.verdict(path: "/a/agy", facts: facts(changed: 5)), "the old facts are gone")
    }

    func testTheVerdictTableIsBounded() {
        var verdicts = AntigravitySignatureVerdicts()
        for index in 0..<AntigravitySignatureVerdicts.capacity {
            verdicts.record(true, path: "/v\(index)/agy", facts: facts(changed: 1))
        }
        XCTAssertEqual(verdicts.verdict(path: "/v0/agy", facts: facts(changed: 1)), true)
        verdicts.record(true, path: "/new/agy", facts: facts(changed: 1))
        XCTAssertNil(verdicts.verdict(path: "/v0/agy", facts: facts(changed: 1)), "started over")
        XCTAssertEqual(verdicts.verdict(path: "/new/agy", facts: facts(changed: 1)), true)
    }

    func testARewriteInPlaceWithItsTimeRestoredStillChangesTheFacts() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kannu-agy-facts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("agy")
        try Data("signed by google".utf8).write(to: file)
        let before = try XCTUnwrap(AntigravityFileFacts.of(path: file.path))
        var info = stat()
        XCTAssertEqual(stat(file.path, &info), 0)

        // Same size, same inode (no O_TRUNC, no rename), and the modification time put back.
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data("signed by nobody".utf8))
        try handle.close()
        var times = [info.st_atimespec, info.st_mtimespec]
        XCTAssertEqual(utimensat(AT_FDCWD, file.path, &times, 0), 0)

        let after = try XCTUnwrap(AntigravityFileFacts.of(path: file.path))
        XCTAssertEqual(after.inode, before.inode)
        XCTAssertEqual(after.size, before.size)
        XCTAssertEqual(after.modifiedNanoseconds, before.modifiedNanoseconds)
        XCTAssertNotEqual(after, before, "the ctime moved")
        XCTAssertNil(AntigravityFileFacts.of(path: folder.path), "a folder is not a binary")
        XCTAssertNil(AntigravityFileFacts.of(path: folder.appendingPathComponent("missing").path))
    }

    // MARK: - The last quota, after a run that gave none

    func testTheLastQuotaIsKeptForTheManagersBoundAndExpiredWindowsGo() throws {
        let soon = now.addingTimeInterval(120.0)
        let later = now.addingTimeInterval(86_400.0)
        let pro = AntigravityQuotaPool(name: "Gemini Pro", fiveHour: .init(usedPercent: 40.0, resetsAt: soon),
                                       weekly: .init(usedPercent: 10.0, resetsAt: later))
        let flash = AntigravityQuotaPool(name: "Flash", fiveHour: .init(usedPercent: 5.0, resetsAt: soon), weekly: nil)
        let reading = AntigravityQuotaReading(pools: [pro, flash], readAt: now)
        XCTAssertEqual(AntigravityQuotaReading.keptFor, 540.0, "3 x LLMUsageManager's 180 s floor")

        XCTAssertEqual(reading.kept(at: now.addingTimeInterval(60.0)), reading, "nothing has reset yet")
        let afterReset = try XCTUnwrap(reading.kept(at: now.addingTimeInterval(180.0)))
        XCTAssertEqual(afterReset.readAt, now, "kept bars carry the time agy said them")
        XCTAssertEqual(afterReset.pools.count, 1, "a pool with no window left goes")
        XCTAssertNil(afterReset.pools.first?.fiveHour, "a window past its reset no longer holds")
        XCTAssertEqual(afterReset.pools.first?.weekly?.usedPercent, 10.0)

        XCTAssertNil(reading.kept(at: now.addingTimeInterval(540.0)), "not past the manager's own bound")
        XCTAssertNil(reading.kept(at: now.addingTimeInterval(-1.0)), "the clock moved back")
        let allReset = AntigravityQuotaReading(pools: [flash], readAt: now)
        XCTAssertNil(allReset.kept(at: now.addingTimeInterval(180.0)), "nothing left to show")
        let noReset = AntigravityQuotaReading(
            pools: [AntigravityQuotaPool(name: nil, fiveHour: .init(usedPercent: 1.0, resetsAt: nil), weekly: nil)], readAt: now)
        XCTAssertEqual(noReset.kept(at: now.addingTimeInterval(539.0)), noReset, "no reset time: kept for the bound")
    }
}
