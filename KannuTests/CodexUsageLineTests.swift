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

/// Codex rollout usage. Every fixture line follows the shapes upstream Codex writes, from
/// `codex-rs/protocol/src/protocol.rs` (`TokenUsage`, `TokenUsageInfo`, `TokenCountEvent`,
/// `RateLimitSnapshot`, `TurnContextItem`) and the rollout envelope (`timestamp`, `type`, `payload`;
/// timestamps with three fractional digits and a `Z`). Codex is not installed on the development
/// machine, so these fixtures are the only check of the format.
final class CodexUsageLineTests: XCTestCase {
    // MARK: - Fixtures

    private static let sessionMeta = #"{"timestamp":"2026-10-17T09:15:02.101Z","type":"session_meta","payload":{"id":"0199f2a4-6c1e-7d30-9a51-3f0e1c2b4d5e","timestamp":"2026-10-17T09:15:02.100Z","cwd":"/Users/dev/project","originator":"codex_cli_rs","cli_version":"0.150.0","source":"cli","model_provider":"openai"}}"#

    private static let rateLimits = #"{"limit_id":"codex","limit_name":null,"primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1792231200},"secondary":{"used_percent":3.5,"window_minutes":10080,"resets_at":1792749600},"credits":null,"individual_limit":null,"spend_control_reached":null,"plan_type":"plus","rate_limit_reached_type":null}"#

    private static func turnContext(_ model: String, at timestamp: String = "2026-10-17T09:15:02.456Z") -> String {
        #"{"timestamp":"\#(timestamp)","type":"turn_context","payload":{"turn_id":"turn-1","cwd":"/Users/dev/project","approval_policy":"on-request","sandbox_policy":{"type":"workspace-write","network_access":false},"model":"\#(model)","effort":"medium","summary":"auto"}}"#
    }

    /// One `TokenUsage`. `input_tokens` includes the cached and cache-write parts and
    /// `output_tokens` the reasoning part, so `total_tokens` is input plus output, as Codex computes
    /// it. Codex always writes `cache_write_input_tokens` (`#[serde(default)]`, never skipped).
    private static func usage(input: Int, cached: Int, output: Int, reasoning: Int, cacheWrite: Int = 0) -> String {
        #"{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"cache_write_input_tokens":\#(cacheWrite),"output_tokens":\#(output),"reasoning_output_tokens":\#(reasoning),"total_tokens":\#(input + output)}"#
    }

    private static func tokenCount(at timestamp: String, total: String?, last: String?) -> String {
        var info: [String] = []
        if let total { info.append(#""total_token_usage":\#(total)"#) }
        if let last { info.append(#""last_token_usage":\#(last)"#) }
        info.append(#""model_context_window":272000"#)
        return #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{\#(info.joined(separator: ","))},"rate_limits":\#(rateLimits)}}"#
    }

    /// What Codex writes before the session's first response completes.
    private static func tokenCountWithoutInfo(at timestamp: String) -> String {
        #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":\#(rateLimits)}}"#
    }

    private static let first = usage(input: 12000, cached: 8000, output: 600, reasoning: 256)
    private static let secondTotal = usage(input: 25000, cached: 19000, output: 1000, reasoning: 300)
    private static let secondLast = usage(input: 13000, cached: 11000, output: 400, reasoning: 44)

    private static func file(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }

    // MARK: - token_count

    func testEachRequestCountsItsLastTokenUsageNotTheRunningTotal() throws {
        let records = CodexUsageLine.records(in: Self.file([
            Self.sessionMeta,
            Self.turnContext("gpt-5.1-codex"),
            Self.tokenCountWithoutInfo(at: "2026-10-17T09:15:03.000Z"),
            Self.tokenCount(at: "2026-10-17T09:15:09.789Z", total: Self.first, last: Self.first),
            Self.tokenCount(at: "2026-10-17T09:16:30.012Z", total: Self.secondTotal, last: Self.secondLast),
        ]))
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.promptTokens), [12000, 13000])
        XCTAssertEqual(records.map(\.outputTokens), [600, 400])
        XCTAssertEqual(records.map(\.promptTokens).reduce(0, +), 25000, "the requests add up to the final running total")
        XCTAssertEqual(records.map(\.model), ["gpt-5.1-codex", "gpt-5.1-codex"])
        let expected = try XCTUnwrap(ClaudeUsageLine.parseDate("2026-10-17T09:15:09.789Z"))
        XCTAssertEqual(records[0].timestamp, expected)
    }

    func testCachedAndReasoningTokensAreNotAddedASecondTime() throws {
        let record = try XCTUnwrap(CodexUsageLine.records(in: Self.file([
            Self.turnContext("gpt-5.1-codex"),
            Self.tokenCount(at: "2026-10-17T09:15:09.789Z", total: Self.first, last: Self.first),
        ])).first)
        XCTAssertEqual(record.promptTokens, 12000, "cached_input_tokens is part of input_tokens")
        XCTAssertEqual(record.outputTokens, 600, "reasoning_output_tokens is part of output_tokens")
    }

    func testCacheWriteTokensArePartOfInputAndNotAddedAgain() throws {
        // Upstream-shaped (ccusage pins the same request): 935040 input of which 875306 cached
        // reads and 57610 cache writes; total_tokens is input plus output.
        let request = Self.usage(input: 935040, cached: 875306, output: 11150, reasoning: 1141, cacheWrite: 57610)
        let record = try XCTUnwrap(CodexUsageLine.records(in: Self.file([
            Self.turnContext("gpt-5.6-terra"),
            Self.tokenCount(at: "2026-10-17T09:15:09.789Z", total: request, last: request),
        ])).first)
        XCTAssertEqual(record.promptTokens, 935040)
        XCTAssertEqual(record.outputTokens, 11150)
    }

    /// The card's split: the cached part of `input_tokens` is a cache read and stays out of the
    /// headline, the cache-write part is new input, the rest uncached.
    func testTheCachedInputIsACacheReadAndTheHeadlineLeavesItOut() throws {
        let request = Self.usage(input: 935040, cached: 875306, output: 11150, reasoning: 1141, cacheWrite: 57610)
        let record = try XCTUnwrap(CodexUsageLine.records(in: Self.file([
            Self.turnContext("gpt-5.6-terra"),
            Self.tokenCount(at: "2026-10-17T09:15:09.789Z", total: request, last: request),
        ])).first)
        XCTAssertEqual(record.cacheReadTokens, 875306)
        XCTAssertEqual(record.cacheWriteTokens, 57610)
        XCTAssertEqual(record.uncachedInputTokens, 935040 - 875306 - 57610)
        XCTAssertEqual(record.headlineTokens, 935040 - 875306 + 11150)

        // Parts that claim more than the whole are clamped, never negative.
        let odd = Self.usage(input: 100, cached: 90, output: 5, reasoning: 0, cacheWrite: 50)
        let clamped = try XCTUnwrap(CodexUsageLine.records(in: Self.file([
            Self.tokenCount(at: "2026-10-17T09:15:09.789Z", total: odd, last: odd),
        ])).first)
        XCTAssertEqual([clamped.uncachedInputTokens, clamped.cacheWriteTokens, clamped.cacheReadTokens], [0, 10, 90])
        XCTAssertEqual(clamped.promptTokens, 100)
    }

    func testInfoNullIsNoRequestAndLeavesTheCountIntact() {
        var reader = CodexUsageLine()
        XCTAssertNil(reader.consume(Self.tokenCountWithoutInfo(at: "2026-10-17T09:15:03.000Z")))
        XCTAssertNotNil(reader.consume(Self.tokenCount(at: "2026-10-17T09:15:09.789Z", total: Self.first, last: Self.first)))
        // A rate-limit update between requests also arrives with info null.
        XCTAssertNil(reader.consume(Self.tokenCountWithoutInfo(at: "2026-10-17T09:15:20.000Z")))
        let next = reader.consume(Self.tokenCount(at: "2026-10-17T09:16:30.012Z", total: Self.secondTotal, last: Self.secondLast))
        XCTAssertEqual(next?.promptTokens, 13000)
    }

    func testARepeatedEventWithAnUnchangedTotalIsTheSameRequest() {
        let records = CodexUsageLine.records(in: Self.file([
            Self.turnContext("gpt-5.1-codex"),
            Self.tokenCount(at: "2026-10-17T09:15:09.789Z", total: Self.first, last: Self.first),
            Self.tokenCount(at: "2026-10-17T09:15:09.902Z", total: Self.first, last: Self.first),
        ]))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.promptTokens, 12000)
    }

    func testWithoutLastTokenUsageTheRequestIsWhatTheTotalGrewBy() {
        let records = CodexUsageLine.records(in: Self.file([
            Self.turnContext("gpt-5.1-codex"),
            Self.tokenCount(at: "2026-10-17T09:15:09.789Z", total: Self.first, last: nil),
            Self.tokenCount(at: "2026-10-17T09:16:30.012Z", total: Self.secondTotal, last: nil),
        ]))
        XCTAssertEqual(records.map(\.promptTokens), [12000, 13000])
        XCTAssertEqual(records.map(\.outputTokens), [600, 400])
    }

    func testTheModelIsTheLatestTurnContextBeforeTheEvent() {
        let records = CodexUsageLine.records(in: Self.file([
            Self.tokenCount(at: "2026-10-17T09:15:01.000Z",
                            total: Self.usage(input: 10, cached: 0, output: 5, reasoning: 0),
                            last: Self.usage(input: 10, cached: 0, output: 5, reasoning: 0)),
            Self.turnContext("gpt-5.1-codex"),
            Self.tokenCount(at: "2026-10-17T09:15:09.789Z",
                            total: Self.usage(input: 12010, cached: 8000, output: 605, reasoning: 256),
                            last: Self.first),
            Self.turnContext("gpt-5.1-codex-mini", at: "2026-10-17T09:16:00.000Z"),
            Self.turnContext("  ", at: "2026-10-17T09:16:00.500Z"),
            Self.tokenCount(at: "2026-10-17T09:16:30.012Z",
                            total: Self.usage(input: 25010, cached: 19000, output: 1005, reasoning: 300),
                            last: Self.secondLast),
        ]))
        XCTAssertEqual(records.map(\.model), ["unknown", "gpt-5.1-codex", "gpt-5.1-codex-mini"],
                       "no turn_context yet reads as unknown; a blank model does not replace the last one")
    }

    func testGarbageAndOtherLinesAreIgnoredWithoutLosingTheFile() {
        let valid = Self.tokenCount(at: "2026-10-17T09:15:09.789Z", total: Self.first, last: Self.first)
        let records = CodexUsageLine.records(in: Self.file([
            "",
            "not json at all",
            "{",
            String(valid.dropLast(40)),
            "[1,2,3]",
            #"{"timestamp":"2026-10-17T09:15:04.000Z","type":"event_msg","payload":"token_count"}"#,
            #"{"timestamp":"2026-10-17T09:15:05.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"the token_count event follows each turn_context"}]}}"#,
            #"{"timestamp":"2026-10-17T09:15:06.000Z","type":"event_msg","payload":{"type":"agent_message","message":"token_count"}}"#,
            Self.tokenCount(at: "not a date", total: Self.usage(input: 1, cached: 0, output: 1, reasoning: 0),
                            last: Self.usage(input: 1, cached: 0, output: 1, reasoning: 0)),
            Self.tokenCount(at: "2026-10-17T09:15:07.000Z", total: nil,
                            last: Self.usage(input: 0, cached: 0, output: 0, reasoning: 0)),
            Self.turnContext("gpt-5.1-codex"),
            Self.tokenCount(at: "2026-10-17T09:15:09.789Z",
                            total: Self.usage(input: 12001, cached: 8000, output: 601, reasoning: 256),
                            last: Self.first),
        ]))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.promptTokens, 12000)
        XCTAssertEqual(records.first?.model, "gpt-5.1-codex")
        XCTAssertTrue(CodexUsageLine.records(in: "").isEmpty)
    }

    func testAVerbatimCopyOfARolloutSharesItsKeysAndDistinctRequestsDoNot() {
        let content = Self.file([
            Self.turnContext("gpt-5.1-codex"),
            Self.tokenCount(at: "2026-10-17T09:15:09.789Z", total: Self.first, last: Self.first),
            Self.tokenCount(at: "2026-10-17T09:16:30.012Z", total: Self.secondTotal, last: Self.secondLast),
        ])
        let active = CodexUsageLine.records(in: content).map(\.dedupKey)
        let archived = CodexUsageLine.records(in: content).map(\.dedupKey)
        XCTAssertEqual(active, archived, "a copy in archived_sessions must count once")
        XCTAssertEqual(Set(active.compactMap { $0 }).count, 2)
    }

    func testTheClaudeReaderIsNotUsedForCodexLines() {
        // A Codex token_count line has no `message.usage` and no top-level `usage`, so routing Codex
        // through the Claude reader silently counted nothing. Pin that it still matches nothing, so
        // the two readers cannot both count one line.
        let line = Self.tokenCount(at: "2026-10-17T09:15:09.789Z", total: Self.first, last: Self.first)
        XCTAssertNil(ClaudeUsageLine.parse(Data(line.utf8)))
    }

    // MARK: - Forks and subagents

    /// The first line of a forked or subagent rollout (upstream `SessionMeta`). `parent` is the raw
    /// JSON member naming the parent, if any; `source` is the `SessionSource` value.
    private static func childMeta(at timestamp: Any, parent: String?, source: String = #""cli""#,
                                  id: String = "0199f2c1-0000-7000-8000-00000000c41d") -> String {
        let stamp = timestamp is String ? #""\#(timestamp)""# : "\(timestamp)"
        let parentMember = parent.map { $0 + "," } ?? ""
        return #"{"timestamp":\#(stamp),"type":"session_meta","payload":{"id":"\#(id)",\#(parentMember)"timestamp":"2026-10-17T10:00:00.118Z","cwd":"/Users/dev/project","originator":"codex_cli_rs","cli_version":"0.150.0","source":\#(source),"model_provider":"openai"}}"#
    }

    private static let forkedFrom = #""forked_from_id":"0199f2a4-6c1e-7d30-9a51-3f0e1c2b4d5e""#

    private static let threadSpawnSource = #"{"subagent":{"thread_spawn":{"parent_thread_id":"0199f2a4-6c1e-7d30-9a51-3f0e1c2b4d5e","depth":1,"agent_path":null,"agent_nickname":"Scout","agent_role":"explorer"}}}"#

    func testASubagentDoesNotCountTheParentHistoryItReplays() {
        // A thread_spawn subagent: its rollout opens with the parent's history, re-stamped to the
        // spawn instant, then its own requests with a running total of its own.
        let ownFirst = Self.usage(input: 3000, cached: 1000, output: 200, reasoning: 50)
        let records = CodexUsageLine.records(in: Self.file([
            Self.childMeta(at: "2026-10-17T10:00:00.120Z", parent: nil, source: Self.threadSpawnSource),
            // The parent's own session_meta, replayed: it must not reopen the decision.
            Self.sessionMeta.replacingOccurrences(of: "2026-10-17T09:15:02.101Z", with: "2026-10-17T10:00:00.121Z"),
            Self.turnContext("gpt-5.1-codex", at: "2026-10-17T10:00:00.122Z"),
            Self.tokenCount(at: "2026-10-17T10:00:00.124Z", total: Self.first, last: Self.first),
            Self.tokenCount(at: "2026-10-17T10:00:00.131Z", total: Self.secondTotal, last: Self.secondLast),
            Self.turnContext("gpt-5.1-codex-mini", at: "2026-10-17T10:00:00.140Z"),
            Self.tokenCount(at: "2026-10-17T10:00:09.512Z", total: ownFirst, last: ownFirst),
            Self.tokenCount(at: "2026-10-17T10:00:21.004Z",
                            total: Self.usage(input: 4500, cached: 2000, output: 280, reasoning: 60),
                            last: Self.usage(input: 1500, cached: 1000, output: 80, reasoning: 10)),
        ]))
        XCTAssertEqual(records.map(\.promptTokens), [3000, 1500])
        XCTAssertEqual(records.map(\.outputTokens), [200, 80])
        XCTAssertEqual(records.map(\.model), ["gpt-5.1-codex-mini", "gpt-5.1-codex-mini"])
    }

    func testAForkWithASingleReplayedRequestCountsOnlyItsOwn() {
        // One replayed event at the fork instant, then the child's own request: one the burst
        // between two replayed events alone would miss. Anchoring at session_meta catches it.
        let records = CodexUsageLine.records(in: Self.file([
            Self.childMeta(at: "2026-10-17T10:00:00.120Z", parent: Self.forkedFrom),
            Self.turnContext("gpt-5.1-codex", at: "2026-10-17T10:00:00.120Z"),
            Self.tokenCount(at: "2026-10-17T10:00:00.120Z", total: Self.first, last: Self.first),
            Self.tokenCount(at: "2026-10-17T10:02:00.000Z", total: Self.secondTotal, last: Self.secondLast),
        ]))
        XCTAssertEqual(records.map(\.promptTokens), [13000],
                       "the child's request counts even though it equals the parent's next one")
    }

    func testAReplayedBurstAcrossASecondBoundaryIsStillOneBurst() {
        let records = CodexUsageLine.records(in: Self.file([
            Self.childMeta(at: "2026-10-17T10:00:00.985Z", parent: Self.forkedFrom),
            Self.tokenCount(at: "2026-10-17T10:00:00.986Z", total: Self.usage(input: 100, cached: 0, output: 10, reasoning: 0), last: nil),
            Self.tokenCount(at: "2026-10-17T10:00:00.999Z", total: Self.usage(input: 300, cached: 0, output: 30, reasoning: 0), last: nil),
            Self.tokenCount(at: "2026-10-17T10:00:01.000Z", total: Self.usage(input: 600, cached: 0, output: 60, reasoning: 0), last: nil),
            Self.tokenCount(at: "2026-10-17T10:00:01.009Z", total: Self.usage(input: 1000, cached: 0, output: 100, reasoning: 0), last: nil),
            Self.tokenCount(at: "2026-10-17T10:00:08.000Z", total: Self.usage(input: 1500, cached: 0, output: 150, reasoning: 0), last: nil),
        ]))
        XCTAssertEqual(records.map(\.promptTokens), [500], "the replayed totals still set the baseline")
        XCTAssertEqual(records.map(\.outputTokens), [50])
    }

    func testEveryLaterRequestOfAForkCountsAfterTheReplay() {
        let records = CodexUsageLine.records(in: Self.file([
            Self.childMeta(at: "2026-10-17T10:00:00.000Z", parent: Self.forkedFrom),
            Self.tokenCount(at: "2026-10-17T10:00:00.100Z", total: Self.first, last: Self.first),
            Self.tokenCount(at: "2026-10-17T10:00:00.200Z", total: Self.secondTotal, last: Self.secondLast),
            Self.tokenCount(at: "2026-10-17T10:00:30.000Z",
                            total: Self.usage(input: 25100, cached: 19000, output: 1010, reasoning: 300),
                            last: Self.usage(input: 100, cached: 0, output: 10, reasoning: 0)),
            // Quicker than a second after the previous request: the replay is over, so it counts.
            Self.tokenCount(at: "2026-10-17T10:00:30.400Z",
                            total: Self.usage(input: 25300, cached: 19000, output: 1030, reasoning: 300),
                            last: Self.usage(input: 200, cached: 0, output: 20, reasoning: 0)),
        ]))
        XCTAssertEqual(records.map(\.promptTokens), [100, 200])
    }

    func testOnlyAForkOrSubagentHasItsOpeningBurstSkipped() {
        let own = [
            Self.tokenCount(at: "2026-10-17T09:15:02.300Z", total: Self.first, last: Self.first),
            Self.tokenCount(at: "2026-10-17T09:15:02.800Z", total: Self.secondTotal, last: Self.secondLast),
        ]
        // A session of its own, however quickly its requests follow session_meta.
        XCTAssertEqual(CodexUsageLine.records(in: Self.file([Self.sessionMeta] + own)).map(\.promptTokens), [12000, 13000])
        // A session that names itself as its parent is its own too.
        let selfParent = Self.childMeta(at: "2026-10-17T09:15:02.101Z", parent: #""forked_from_id":"0199f2a4-self""#,
                                        id: "0199f2a4-self")
        XCTAssertEqual(CodexUsageLine.records(in: Self.file([selfParent] + own)).map(\.promptTokens), [12000, 13000])
        // An empty parent id is no parent.
        let blankParent = Self.childMeta(at: "2026-10-17T09:15:02.101Z", parent: #""forked_from_id":"""#)
        XCTAssertEqual(CodexUsageLine.records(in: Self.file([blankParent] + own)).map(\.promptTokens), [12000, 13000])
        // Usage before any session_meta: nothing says the file is a fork.
        XCTAssertEqual(CodexUsageLine.records(in: Self.file(own)).map(\.promptTokens), [12000, 13000])
    }

    func testAForkWhoseFirstRequestComesLaterReplayedNothing() {
        // A fork that copied no usage (a paginated history references its parent instead).
        let records = CodexUsageLine.records(in: Self.file([
            Self.childMeta(at: "2026-10-17T10:00:00.120Z", parent: #""parent_thread_id":"0199f2a4-6c1e-7d30-9a51-3f0e1c2b4d5e""#),
            Self.tokenCount(at: "2026-10-17T10:00:05.000Z", total: Self.first, last: Self.first),
        ]))
        XCTAssertEqual(records.map(\.promptTokens), [12000])
    }

    func testAnEpochSecondsSessionMetaTimestampAnchorsTheReplay() {
        // 1792231200 is 2026-10-17T10:00:00Z.
        let records = CodexUsageLine.records(in: Self.file([
            Self.childMeta(at: 1792231200, parent: Self.forkedFrom),
            Self.tokenCount(at: "2026-10-17T10:00:00.000Z", total: Self.first, last: Self.first),
            Self.tokenCount(at: "2026-10-17T10:04:00.000Z", total: Self.secondTotal, last: Self.secondLast),
        ]))
        XCTAssertEqual(records.map(\.promptTokens), [13000])
    }

    // MARK: - Rollout files

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("kannu-codex-rollouts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
    }

    private func write(_ relativePath: String, in home: URL, contents: String = "") throws {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    func testCodexHomeIsCodexHomeWhenSetAndDotCodexOtherwise() {
        let home = URL(fileURLWithPath: "/Users/dev", isDirectory: true)
        XCTAssertEqual(CodexRolloutFiles.codexHome(environment: ["CODEX_HOME": "/srv/codex"], home: home).path, "/srv/codex")
        XCTAssertEqual(CodexRolloutFiles.codexHome(environment: ["CODEX_HOME": "  /srv/codex\n"], home: home).path, "/srv/codex")
        XCTAssertEqual(CodexRolloutFiles.codexHome(environment: ["CODEX_HOME": "  "], home: home).path, "/Users/dev/.codex")
        XCTAssertEqual(CodexRolloutFiles.codexHome(environment: [:], home: home).path, "/Users/dev/.codex")
    }

    func testRolloutsAreFoundInSessionsAndArchivedSessionsUnderCodexHome() throws {
        let codexHome = tempRoot.appendingPathComponent("custom-codex-home", isDirectory: true)
        let content = Self.file([
            Self.turnContext("gpt-5.1-codex"),
            Self.tokenCount(at: "2026-10-17T09:15:09.789Z", total: Self.first, last: Self.first),
        ])
        try write("sessions/2026/10/17/rollout-2026-10-17T09-15-02-a.jsonl", in: codexHome, contents: content)
        try write("archived_sessions/rollout-2026-10-12T08-00-00-b.jsonl", in: codexHome, contents: content)
        try write("sessions/2026/10/01/rollout-2026-10-01T10-00-00-c.jsonl.zst", in: codexHome)
        try write("sessions/2026/10/17/notes.txt", in: codexHome)
        try write("history.jsonl", in: codexHome, contents: content)
        // A home that only exists through CODEX_HOME: the default ~/.codex must not be consulted.
        let resolved = CodexRolloutFiles.codexHome(environment: ["CODEX_HOME": codexHome.path],
                                                   home: tempRoot.appendingPathComponent("no-such-user"))
        let listing = CodexRolloutFiles.listing(codexHome: resolved)
        XCTAssertEqual(Set(listing.plain.map(\.lastPathComponent)),
                       ["rollout-2026-10-17T09-15-02-a.jsonl", "rollout-2026-10-12T08-00-00-b.jsonl"],
                       "history.jsonl at the home's top level is the prompt history, not a rollout")
        XCTAssertEqual(listing.compressedCount, 1)
        XCTAssertTrue(listing.hasLogs)
        for file in listing.plain {
            let records = CodexUsageLine.records(in: try String(contentsOf: file, encoding: .utf8))
            XCTAssertEqual(records.map(\.promptTokens), [12000])
        }
    }

    func testOnlyCompressedRolloutsStillMeanCodexHasLogs() throws {
        let codexHome = tempRoot.appendingPathComponent(".codex", isDirectory: true)
        try write("sessions/2026/09/01/rollout-2026-09-01T10-00-00-c.jsonl.zst", in: codexHome)
        let listing = CodexRolloutFiles.listing(codexHome: codexHome)
        XCTAssertTrue(listing.plain.isEmpty, "compressed rollouts are never opened")
        XCTAssertTrue(listing.hasLogs)
    }

    func testNoRolloutDirectoriesMeansNoLogs() throws {
        let codexHome = tempRoot.appendingPathComponent(".codex", isDirectory: true)
        try write("auth.json", in: codexHome, contents: "{}")
        XCTAssertEqual(CodexRolloutFiles.listing(codexHome: codexHome), CodexRolloutFiles.Listing())
        XCTAssertFalse(CodexRolloutFiles.listing(codexHome: tempRoot.appendingPathComponent("missing")).hasLogs)
    }

    func testEitherRolloutFolderTurnsTheProviderOnAtFirstLaunch() throws {
        let archivedOnly = tempRoot.appendingPathComponent("archived-only", isDirectory: true)
        try write("archived_sessions/rollout-2026-09-01T10-00-00-a.jsonl", in: archivedOnly)
        XCTAssertTrue(CodexRolloutFiles.hasRolloutDirectory(codexHome: archivedOnly))
        let sessionsOnly = tempRoot.appendingPathComponent("sessions-only", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsOnly.appendingPathComponent("sessions"),
                                                withIntermediateDirectories: true)
        XCTAssertTrue(CodexRolloutFiles.hasRolloutDirectory(codexHome: sessionsOnly))
        let neither = tempRoot.appendingPathComponent("neither", isDirectory: true)
        try write("auth.json", in: neither, contents: "{}")
        XCTAssertFalse(CodexRolloutFiles.hasRolloutDirectory(codexHome: neither))
    }

    /// What `CodexUsageProvider` counts, end to end on disk: discovery under CODEX_HOME, the recency
    /// filter, the cache's Codex format (the original bug read rollouts with the Claude reader and
    /// counted 0), the replay skip and the cross-file dedup.
    func testTheProvidersPathReadsEveryRecentRolloutWithTheCodexReader() throws {
        let codexHome = tempRoot.appendingPathComponent("codex-home", isDirectory: true)
        let rollout = Self.file([
            Self.sessionMeta,
            Self.turnContext("gpt-5.1-codex"),
            Self.tokenCount(at: "2026-10-17T09:15:09.789Z", total: Self.first, last: Self.first),
            Self.tokenCount(at: "2026-10-17T09:16:30.012Z", total: Self.secondTotal, last: Self.secondLast),
        ])
        try write("sessions/2026/10/17/rollout-2026-10-17T09-15-02-a.jsonl", in: codexHome, contents: rollout)
        try write("archived_sessions/rollout-2026-10-17T09-15-02-a.jsonl", in: codexHome, contents: rollout)
        try write("sessions/2026/10/17/rollout-2026-10-17T10-00-00-fork.jsonl", in: codexHome, contents: Self.file([
            Self.childMeta(at: "2026-10-17T10:00:00.120Z", parent: Self.forkedFrom),
            Self.tokenCount(at: "2026-10-17T10:00:00.124Z", total: Self.first, last: Self.first),
            Self.tokenCount(at: "2026-10-17T10:00:00.131Z", total: Self.secondTotal, last: Self.secondLast),
            Self.tokenCount(at: "2026-10-17T10:00:09.512Z",
                            total: Self.usage(input: 25700, cached: 19000, output: 1040, reasoning: 300),
                            last: Self.usage(input: 700, cached: 0, output: 40, reasoning: 0)),
        ]))
        // A Claude-shaped line in a rollout folder is not a Codex request.
        try write("sessions/2026/10/17/rollout-2026-10-17T11-00-00-claude.jsonl", in: codexHome,
                  contents: #"{"type":"assistant","timestamp":"2026-10-17T11:00:01.000Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":5}}}"# + "\n")
        try write("sessions/2026/10/01/rollout-2026-10-01T10-00-00-old.jsonl", in: codexHome, contents: rollout)
        // A fixed "now" a few hours after the fixtures, so the week guard never ages them out.
        let now = try XCTUnwrap(ClaudeUsageLine.parseDate("2026-10-17T12:00:00.000Z"))
        let old = codexHome.appendingPathComponent("sessions/2026/10/01/rollout-2026-10-01T10-00-00-old.jsonl")
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10 * 86400)], ofItemAtPath: old.path)

        let listing = CodexRolloutFiles.listing(codexHome: codexHome)
        XCTAssertEqual(listing.plain.count, 5)
        let recent = UsageWindows.recentlyModified(listing.plain, now: now)
        XCTAssertEqual(recent.count, 4, "the old file is skipped")
        let records = JSONLUsageCache(label: "codex", format: .codex).refresh(files: recent, now: now).records
        XCTAssertEqual(records.map(\.promptTokens).sorted(), [700, 12000, 13000],
                       "the rollout's two requests once (the archived copy shares its keys) and the fork's own request")
    }
}
