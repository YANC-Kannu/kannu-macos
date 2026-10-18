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

/// The rate limits a Codex rollout records on every `token_count` event (`TokenCountEvent.rate_limits`,
/// a snake_case `RateLimitSnapshot` in `codex-rs/protocol/src/protocol.rs`; before `resets_at`
/// existed, `RateLimitWindow` had `resets_in_seconds`, as at `rust-v0.46.0`). Fixture-only: Codex is
/// not installed on the development Mac.
final class CodexRolloutRateLimitsTests: XCTestCase {
    private static func snapshot(id: String? = "codex", primary: String?, secondary: String?, plan: String? = "plus") -> String {
        let idJSON = id.map { "\"\($0)\"" } ?? "null"
        let planJSON = plan.map { "\"\($0)\"" } ?? "null"
        return #"{"limit_id":\#(idJSON),"limit_name":null,"primary":\#(primary ?? "null"),"secondary":\#(secondary ?? "null"),"credits":null,"individual_limit":null,"spend_control_reached":null,"plan_type":\#(planJSON),"rate_limit_reached_type":null}"#
    }

    private static func window(_ percent: Double, minutes: Int, resetsAt: Int) -> String {
        #"{"used_percent":\#(percent),"window_minutes":\#(minutes),"resets_at":\#(resetsAt)}"#
    }

    private static func tokenCount(at timestamp: String, rateLimits: String, info: String = "null") -> String {
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":\#(info),"rate_limits":\#(rateLimits)}}"#
    }

    private static let info = #"{"total_token_usage":{"input_tokens":12000,"cached_input_tokens":8000,"cache_write_input_tokens":0,"output_tokens":600,"reasoning_output_tokens":256,"total_tokens":12600},"last_token_usage":{"input_tokens":12000,"cached_input_tokens":8000,"cache_write_input_tokens":0,"output_tokens":600,"reasoning_output_tokens":256,"total_tokens":12600},"model_context_window":272000}"#
    private static let turnContext = #"{"timestamp":"2026-10-17T09:15:02.456Z","type":"turn_context","payload":{"turn_id":"turn-1","cwd":"/Users/dev/project","model":"gpt-5.3-codex"}}"#
    private static let message = #"{"timestamp":"2026-10-17T09:15:03.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"mentions token_count and rate_limits in passing"}]}}"#

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CodexRolloutRateLimitsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - One rollout

    func testTheLatestTokenCountWins() throws {
        let content = [
            Self.turnContext,
            Self.tokenCount(at: "2026-10-17T09:15:05.000Z", rateLimits: Self.snapshot(
                primary: Self.window(10.0, minutes: 300, resetsAt: 1_792_231_200), secondary: Self.window(2.0, minutes: 10080, resetsAt: 1_792_749_600)), info: Self.info),
            Self.message,
            Self.tokenCount(at: "2026-10-17T09:20:00.000Z", rateLimits: Self.snapshot(
                primary: Self.window(12.5, minutes: 300, resetsAt: 1_792_231_200), secondary: Self.window(3.5, minutes: 10080, resetsAt: 1_792_749_600)), info: Self.info),
            Self.message,
        ].joined(separator: "\n")
        XCTAssertEqual(CodexRolloutRateLimits.latest(in: content), CodexLimits(
            session: .init(usedPercent: 12.5, windowMinutes: 300, resetsAt: Date(timeIntervalSince1970: 1_792_231_200.0)),
            week: .init(usedPercent: 3.5, windowMinutes: 10080, resetsAt: Date(timeIntervalSince1970: 1_792_749_600.0)),
            extras: [],
            planType: "Plus",
            observedAt: try XCTUnwrap(ClaudeUsageLine.parseDate("2026-10-17T09:20:00.000Z"))),
                       "the figures carry the time Codex recorded them, not the time they were read")
    }

    func testAnEventBeforeTheFirstResponseStillCarriesTheLimits() {
        let content = Self.tokenCount(at: "2026-10-17T09:15:05.000Z", rateLimits: Self.snapshot(
            primary: Self.window(30.0, minutes: 300, resetsAt: 1_792_231_200), secondary: nil))
        XCTAssertEqual(CodexRolloutRateLimits.latest(in: content)?.session?.usedPercent, 30.0)
    }

    func testAnOlderRolloutsResetsInSecondsCountFromTheEventTime() throws {
        let old = #"{"primary":{"used_percent":44.0,"window_minutes":300,"resets_in_seconds":3600},"secondary":null}"#
        let content = Self.tokenCount(at: "2026-10-17T09:15:05.000Z", rateLimits: old, info: Self.info)
        let limits = try XCTUnwrap(CodexRolloutRateLimits.latest(in: content))
        let eventTime = try XCTUnwrap(ClaudeUsageLine.parseDate("2026-10-17T09:15:05.000Z"))
        XCTAssertEqual(limits.session?.resetsAt, eventTime.addingTimeInterval(3600.0))
        XCTAssertNil(limits.planType)
    }

    func testNullOrEmptyRateLimitsAreNoLimits() {
        XCTAssertNil(CodexRolloutRateLimits.latest(in: Self.tokenCount(at: "2026-10-17T09:15:05.000Z", rateLimits: "null", info: Self.info)))
        XCTAssertNil(CodexRolloutRateLimits.latest(in: Self.tokenCount(at: "2026-10-17T09:15:05.000Z",
                                                                       rateLimits: Self.snapshot(primary: nil, secondary: nil))))
        XCTAssertNil(CodexRolloutRateLimits.latest(in: [Self.turnContext, Self.message, "garbage"].joined(separator: "\n")))
    }

    func testAnEmptySnapshotDoesNotHideTheOneBeforeIt() {
        let content = [
            Self.tokenCount(at: "2026-10-17T09:15:05.000Z", rateLimits: Self.snapshot(
                primary: Self.window(20.0, minutes: 300, resetsAt: 1_792_231_200), secondary: nil)),
            Self.tokenCount(at: "2026-10-17T09:16:05.000Z", rateLimits: Self.snapshot(primary: nil, secondary: nil)),
        ].joined(separator: "\n")
        XCTAssertEqual(CodexRolloutRateLimits.latest(in: content)?.session?.usedPercent, 20.0)
    }

    func testOtherBucketsWrittenAfterTheMainOneAreExtras() {
        let content = [
            Self.tokenCount(at: "2026-10-17T09:15:05.000Z", rateLimits: Self.snapshot(
                id: nil, primary: Self.window(20.0, minutes: 300, resetsAt: 1_792_231_200), secondary: nil)),
            Self.tokenCount(at: "2026-10-17T09:16:05.000Z", rateLimits: Self.snapshot(
                id: "gpt_spark", primary: Self.window(60.0, minutes: 300, resetsAt: 1_792_231_200), secondary: nil, plan: nil)),
        ].joined(separator: "\n")
        let limits = CodexRolloutRateLimits.latest(in: content)
        XCTAssertEqual(limits?.session?.usedPercent, 20.0, "an id-less snapshot is the main bucket")
        XCTAssertEqual(limits?.extras.map(\.key), ["gpt_spark.primary"])
        XCTAssertEqual(limits?.extras.first?.label, "gpt spark · 5h")
        XCTAssertEqual(limits?.observedAt, ClaudeUsageLine.parseDate("2026-10-17T09:15:05.000Z"), "the main snapshot's time")
    }

    /// Upstream writes one bucket per `token_count`: the last a response's headers carried, and
    /// `codex` comes first. An account whose responses also carry another family writes only that.
    private static func otherBucketOnly(at timestamp: String, percent: Double) -> String {
        tokenCount(at: timestamp, rateLimits: snapshot(
            id: "codex_other", primary: window(percent, minutes: 300, resetsAt: 1_792_231_200), secondary: nil, plan: nil), info: info)
    }

    func testEventsCarryingOnlyAnotherBucketAreNoAnswer() {
        let content = [
            Self.otherBucketOnly(at: "2026-10-17T09:15:05.000Z", percent: 50.0),
            Self.message,
            Self.otherBucketOnly(at: "2026-10-17T09:20:00.000Z", percent: 55.0),
        ].joined(separator: "\n")
        XCTAssertNil(CodexRolloutRateLimits.latest(in: content), "extras alone would hide the 5-hour and weekly limits")
    }

    // MARK: - Files

    private func write(_ content: String, to name: String, modified: Date) throws -> URL {
        let sessions = directory.appendingPathComponent("sessions/2026/10/17", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent(name)
        try content.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        return file
    }

    func testTheNewestRolloutWithLimitsIsRead() throws {
        let now = Date()
        _ = try write(Self.tokenCount(at: "2026-10-17T08:00:00.000Z", rateLimits: Self.snapshot(
            primary: Self.window(5.0, minutes: 300, resetsAt: 1_792_231_200), secondary: nil)),
                      to: "rollout-older.jsonl", modified: now.addingTimeInterval(-7200.0))
        _ = try write(Self.tokenCount(at: "2026-10-17T09:00:00.000Z", rateLimits: Self.snapshot(
            primary: Self.window(15.0, minutes: 300, resetsAt: 1_792_231_200), secondary: nil)),
                      to: "rollout-newer.jsonl", modified: now.addingTimeInterval(-3600.0))
        // The newest file of all is a session that has not made a request yet.
        _ = try write(Self.turnContext, to: "rollout-newest.jsonl", modified: now.addingTimeInterval(-60.0))

        let listing = CodexRolloutFiles.listing(codexHome: directory)
        XCTAssertEqual(CodexRolloutFiles.latestRateLimits(in: listing, now: now)?.session?.usedPercent, 15.0)
    }

    func testANewestRolloutWithOnlyAnotherBucketGivesWayToAnOlderMainOne() throws {
        let now = Date()
        _ = try write(Self.tokenCount(at: "2026-10-17T08:00:00.000Z", rateLimits: Self.snapshot(
            primary: Self.window(5.0, minutes: 300, resetsAt: 1_792_231_200), secondary: nil)),
                      to: "rollout-older.jsonl", modified: now.addingTimeInterval(-7200.0))
        _ = try write(Self.otherBucketOnly(at: "2026-10-17T09:00:00.000Z", percent: 70.0),
                      to: "rollout-newer.jsonl", modified: now.addingTimeInterval(-60.0))
        let limits = CodexRolloutFiles.latestRateLimits(in: CodexRolloutFiles.listing(codexHome: directory), now: now)
        XCTAssertEqual(limits?.session?.usedPercent, 5.0)
        XCTAssertEqual(limits?.observedAt, ClaudeUsageLine.parseDate("2026-10-17T08:00:00.000Z"))
    }

    func testOnlyAnotherBucketInEveryRolloutIsNoAnswer() throws {
        let now = Date()
        _ = try write(Self.otherBucketOnly(at: "2026-10-17T09:00:00.000Z", percent: 70.0),
                      to: "rollout-only-other.jsonl", modified: now.addingTimeInterval(-60.0))
        XCTAssertNil(CodexRolloutFiles.latestRateLimits(in: CodexRolloutFiles.listing(codexHome: directory), now: now))
    }

    func testRolloutsOutsideTheUsageWindowAreNotRead() throws {
        let now = Date()
        _ = try write(Self.tokenCount(at: "2026-09-01T08:00:00.000Z", rateLimits: Self.snapshot(
            primary: Self.window(5.0, minutes: 300, resetsAt: 1_792_231_200), secondary: nil)),
                      to: "rollout-old.jsonl", modified: now.addingTimeInterval(-30.0 * 24.0 * 3600.0))
        XCTAssertNil(CodexRolloutFiles.latestRateLimits(in: CodexRolloutFiles.listing(codexHome: directory), now: now))
    }

    func testATailWithoutTheMainSnapshotWidensToTheWholeFile() throws {
        let filler = String(repeating: Self.message + "\n", count: 40)
        let content = Self.tokenCount(at: "2026-10-17T09:00:00.000Z", rateLimits: Self.snapshot(
            primary: Self.window(33.0, minutes: 300, resetsAt: 1_792_231_200), secondary: nil)) + "\n" + filler
        let file = try write(content, to: "rollout-long.jsonl", modified: Date())
        XCTAssertGreaterThan(content.utf8.count, 2048)
        XCTAssertEqual(CodexRolloutFiles.rateLimits(inFile: file, tailBytes: 2048)?.session?.usedPercent, 33.0)
    }

    func testATailOfAnotherBucketsSnapshotsDoesNotWiden() throws {
        // The main snapshot is there, but only before the tail: on an account whose events carry
        // another bucket, reading every long file whole on every poll to find one is not worth it.
        let filler = String(repeating: Self.message + "\n", count: 40)
        let content = Self.tokenCount(at: "2026-10-17T09:00:00.000Z", rateLimits: Self.snapshot(
            primary: Self.window(33.0, minutes: 300, resetsAt: 1_792_231_200), secondary: nil)) + "\n" + filler
            + Self.otherBucketOnly(at: "2026-10-17T09:30:00.000Z", percent: 70.0) + "\n"
        let file = try write(content, to: "rollout-other-tail.jsonl", modified: Date())
        XCTAssertGreaterThan(content.utf8.count, 2048)
        XCTAssertNil(CodexRolloutFiles.rateLimits(inFile: file, tailBytes: 2048))
        XCTAssertEqual(CodexRolloutFiles.rateLimits(inFile: file, tailBytes: 1 << 20)?.session?.usedPercent, 33.0,
                       "read whole, the same file answers")
    }

    func testATailWithTheMainSnapshotIsEnough() throws {
        let filler = String(repeating: Self.message + "\n", count: 40)
        let content = filler + Self.tokenCount(at: "2026-10-17T09:00:00.000Z", rateLimits: Self.snapshot(
            primary: Self.window(44.0, minutes: 300, resetsAt: 1_792_231_200), secondary: nil)) + "\n"
        let file = try write(content, to: "rollout-tail.jsonl", modified: Date())
        XCTAssertEqual(CodexRolloutFiles.rateLimits(inFile: file, tailBytes: 2048)?.session?.usedPercent, 44.0)
    }
}
