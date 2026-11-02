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

/// Codex rollouts through `JSONLUsageCache(format: .codex)`: read once, then only what was appended,
/// with `CodexUsageLine`'s state carried between refreshes. The oracle is `CodexUsageLine.records(in:)`
/// over the whole file — the one-shot read the cache must agree with however the file was split
/// across refreshes — followed by the cache's own week guard and cross-file dedup.
final class JSONLUsageCacheCodexTests: XCTestCase {
    /// 2026-10-17T12:00:00Z, a few hours after every fixture event.
    private let now = Date(timeIntervalSince1970: 1_792_238_400)
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kannu-codex-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixtures (the shapes Codex writes; see CodexUsageLineTests)

    private static let meta = #"{"timestamp":"2026-10-17T09:15:02.101Z","type":"session_meta","payload":{"id":"0199f2a4-6c1e-7d30-9a51-3f0e1c2b4d5e","timestamp":"2026-10-17T09:15:02.100Z","cwd":"/Users/dev/project","source":"cli"}}"#

    private static func forkMeta(at timestamp: String) -> String {
        #"{"timestamp":"\#(timestamp)","type":"session_meta","payload":{"id":"0199f2a4-child","timestamp":"\#(timestamp)","forked_from_id":"0199f2a4-6c1e-7d30-9a51-3f0e1c2b4d5e","source":"cli"}}"#
    }

    private static func turn(_ model: String, at timestamp: String) -> String {
        #"{"timestamp":"\#(timestamp)","type":"turn_context","payload":{"turn_id":"t","model":"\#(model)"}}"#
    }

    private static func usage(_ input: Int, _ output: Int) -> String {
        #"{"input_tokens":\#(input),"cached_input_tokens":0,"output_tokens":\#(output),"reasoning_output_tokens":0,"total_tokens":\#(input + output)}"#
    }

    /// `total` is the running total, `last` the latest request (nil leaves it out, so the reader
    /// takes the difference from the previous total).
    private static func count(at timestamp: String, total: (Int, Int), last: (Int, Int)?) -> String {
        var info = [#""total_token_usage":\#(usage(total.0, total.1))"#]
        if let last { info.append(#""last_token_usage":\#(usage(last.0, last.1))"#) }
        return #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{\#(info.joined(separator: ","))}}}"#
    }

    private static let chatter = #"{"timestamp":"2026-10-17T09:15:03.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"hello"}]}}"#

    /// A session with every rule the reader applies: the model from an earlier line, a re-emitted
    /// unchanged total, a total without `last_token_usage`, and a model change.
    private static let session: [String] = [
        meta,
        turn("gpt-5.1-codex", at: "2026-10-17T09:15:02.456Z"),
        chatter,
        count(at: "2026-10-17T09:15:09.789Z", total: (12000, 600), last: (12000, 600)),
        count(at: "2026-10-17T09:15:10.001Z", total: (12000, 600), last: (12000, 600)),
        chatter,
        count(at: "2026-10-17T09:16:30.012Z", total: (25000, 1000), last: nil),
        turn("gpt-5.1-codex-mini", at: "2026-10-17T09:20:00.000Z"),
        count(at: "2026-10-17T09:21:00.500Z", total: (25700, 1040), last: (700, 40)),
    ]

    private func file(_ name: String, _ lines: [String], terminated: Bool = true) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data((lines.joined(separator: "\n") + (terminated ? "\n" : "")).utf8).write(to: url)
        return url
    }

    private func append(_ url: URL, _ text: String) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private func describe(_ record: UsageRecord) -> String {
        "\(record.timestamp.timeIntervalSince1970)|\(record.model)|\(record.promptTokens)|\(record.outputTokens)|\(record.dedupKey ?? "-")"
    }

    private func oneShot(_ lines: [String]) -> [String] {
        CodexUsageLine.records(in: lines.joined(separator: "\n") + "\n").map(describe)
    }

    private func refresh(_ cache: JSONLUsageCache, _ files: [URL], at date: Date? = nil) -> [String] {
        cache.refresh(files: files, now: date ?? now).records.map(describe)
    }

    // MARK: - Incremental reads keep the reader's state

    func testEverySplitAcrossTwoRefreshesCountsWhatOneReadCounts() throws {
        let expected = oneShot(Self.session)
        XCTAssertEqual(expected.count, 3, "12000 + 13000 (difference of totals) + 700; the re-emit is skipped")
        for split in 0...Self.session.count {
            let url = try file("split-\(split).jsonl", Array(Self.session.prefix(split)))
            let cache = JSONLUsageCache(label: "test", format: .codex)
            _ = refresh(cache, [url])
            let rest = Self.session.dropFirst(split)
            if !rest.isEmpty { try append(url, rest.joined(separator: "\n") + "\n") }
            XCTAssertEqual(refresh(cache, [url]), expected, "split after line \(split)")
        }
    }

    func testOneRefreshPerAppendedLineCountsWhatOneReadCounts() throws {
        let url = try file("lines.jsonl", [])
        let cache = JSONLUsageCache(label: "test", format: .codex)
        for line in Self.session {
            try append(url, line + "\n")
            _ = refresh(cache, [url])
        }
        XCTAssertEqual(refresh(cache, [url]), oneShot(Self.session))
    }

    func testAnAppendedEventTakesTheModelReadInAnEarlierRefresh() throws {
        let url = try file("model.jsonl", [Self.meta, Self.turn("gpt-5.1-codex", at: "2026-10-17T09:15:02.456Z")])
        let cache = JSONLUsageCache(label: "test", format: .codex)
        XCTAssertEqual(refresh(cache, [url]), [])
        try append(url, Self.count(at: "2026-10-17T09:15:09.789Z", total: (12000, 600), last: (12000, 600)) + "\n")
        let records = cache.refresh(files: [url], now: now).records
        XCTAssertEqual(records.map(\.model), ["gpt-5.1-codex"])
    }

    func testAnUnchangedSecondRefreshReadsNothingAndCountsTheSame() throws {
        let url = try file("same.jsonl", Self.session)
        let cache = JSONLUsageCache(label: "test", format: .codex)
        let first = cache.refresh(files: [url], now: now)
        let second = cache.refresh(files: [url], now: now)
        XCTAssertEqual(second.stats.bytesRead, 0)
        XCTAssertEqual(second.records.map(describe), first.records.map(describe))
    }

    // MARK: - The unterminated last line

    func testAnUnfinishedLastEventCountsOnceAndIsNotCommittedTwice() throws {
        let head = Array(Self.session.prefix(4))   // ends with the first token_count
        let url = try file("tail.jsonl", head, terminated: false)
        let cache = JSONLUsageCache(label: "test", format: .codex)
        XCTAssertEqual(refresh(cache, [url]).count, 1, "a complete but unterminated event counts meanwhile")
        try append(url, "\n")
        XCTAssertEqual(refresh(cache, [url]), oneShot(head))
        // The re-emitted unchanged total must still be recognised: the tail read did not move the
        // kept reader's baseline, and the finished line set it exactly once.
        try append(url, Self.session[4] + "\n")
        XCTAssertEqual(refresh(cache, [url]), oneShot(Array(Self.session.prefix(5))))
    }

    func testAHalfWrittenLastLineIsReadOnceFinished() throws {
        let line = Self.count(at: "2026-10-17T09:15:09.789Z", total: (12000, 600), last: (12000, 600))
        let url = try file("half.jsonl", [Self.meta, Self.turn("gpt-5.1-codex", at: "2026-10-17T09:15:02.456Z")])
        try append(url, String(line.prefix(40)))
        let cache = JSONLUsageCache(label: "test", format: .codex)
        XCTAssertEqual(refresh(cache, [url]), [])
        try append(url, String(line.dropFirst(40)) + "\n")
        XCTAssertEqual(refresh(cache, [url]).count, 1)
    }

    // MARK: - Forks, old lines, replaced files

    func testAForkReplaySplitAcrossRefreshesStillCountsNothingOfTheParent() throws {
        let fork = [
            Self.forkMeta(at: "2026-10-17T10:00:00.120Z"),
            Self.count(at: "2026-10-17T10:00:00.124Z", total: (12000, 600), last: (12000, 600)),
            Self.count(at: "2026-10-17T10:00:00.131Z", total: (25000, 1000), last: (13000, 400)),
            Self.count(at: "2026-10-17T10:00:09.512Z", total: (25700, 1040), last: (700, 40)),
        ]
        XCTAssertEqual(oneShot(fork).count, 1, "only the child's own request")
        for split in 1..<fork.count {
            let url = try file("fork-\(split).jsonl", Array(fork.prefix(split)))
            let cache = JSONLUsageCache(label: "test", format: .codex)
            _ = refresh(cache, [url])
            try append(url, fork.dropFirst(split).joined(separator: "\n") + "\n")
            XCTAssertEqual(refresh(cache, [url]), oneShot(fork), "split after line \(split)")
        }
    }

    /// Lines older than the week count nothing themselves but still feed the reader: the model of a
    /// newer event, and the total its difference is taken from.
    func testLinesOlderThanTheWeekStillFeedTheReader() throws {
        let url = try file("old.jsonl", [
            Self.meta,
            Self.turn("gpt-5.1-codex", at: "2026-10-01T09:00:00.000Z"),
            Self.count(at: "2026-10-01T09:00:05.000Z", total: (12000, 600), last: (12000, 600)),
            Self.count(at: "2026-10-17T09:00:05.000Z", total: (25000, 1000), last: nil),
        ])
        let records = JSONLUsageCache(label: "test", format: .codex).refresh(files: [url], now: now).records
        XCTAssertEqual(records.map(\.promptTokens), [13000], "the old request is outside the week")
        XCTAssertEqual(records.map(\.model), ["gpt-5.1-codex"])
    }

    func testAReplacedRolloutStartsWithAFreshReader() throws {
        let url = try file("replaced.jsonl", Array(Self.session.prefix(4)))
        let cache = JSONLUsageCache(label: "test", format: .codex)
        XCTAssertEqual(refresh(cache, [url]).count, 1)
        try FileManager.default.removeItem(at: url)
        let lines = [Self.count(at: "2026-10-17T11:00:00.000Z", total: (500, 50), last: (500, 50))]
        _ = try file("replaced.jsonl", lines)
        let records = cache.refresh(files: [url], now: now).records
        XCTAssertEqual(records.map(\.model), ["unknown"], "no model carried over from the old file")
        XCTAssertEqual(records.map(describe), oneShot(lines))
    }

    // MARK: - Across files, and the formats stay apart

    func testAnArchivedCopyOfARolloutCountsOnce() throws {
        let active = try file("active.jsonl", Self.session)
        let archived = try file("archived.jsonl", Self.session)
        let records = refresh(JSONLUsageCache(label: "test", format: .codex), [active, archived])
        XCTAssertEqual(records, oneShot(Self.session))
    }

    func testEachFormatReadsOnlyItsOwnLines() throws {
        let claude = #"{"type":"assistant","timestamp":"2026-10-17T11:00:01.000Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":5}}}"#
        let url = try file("mixed.jsonl", Self.session + [claude])
        XCTAssertEqual(refresh(JSONLUsageCache(label: "test", format: .codex), [url]), oneShot(Self.session))
        let claudeOnly = JSONLUsageCache(label: "test").refresh(files: [url], now: now).records
        XCTAssertEqual(claudeOnly.map(\.model), ["claude-sonnet-4-5"], "the Claude format never reads a token_count")
    }

    func testOnlyLinesTheCodexReaderCanUseAreParsed() throws {
        let url = try file("parsed.jsonl", Self.session)
        let stats = JSONLUsageCache(label: "test", format: .codex).refresh(files: [url], now: now).stats
        XCTAssertEqual(stats.linesParsed, Self.session.count - 2, "the two chatter lines are never parsed")
    }

    /// A conversation line that only mentions the words (a user asking about `token_count`, a tool
    /// printing a rollout) carries them inside a string, escaped or bare, never as `"token_count"`.
    func testALineThatOnlyMentionsTheWordsIsNotParsed() throws {
        let mention = #"{"timestamp":"2026-10-17T09:15:03.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"why is token_count zero after turn_context? see {\"type\":\"token_count\"} and session_meta"}]}}"#
        let url = try file("mention.jsonl", Self.session + [mention])
        let result = JSONLUsageCache(label: "test", format: .codex).refresh(files: [url], now: now)
        XCTAssertEqual(result.stats.linesParsed, Self.session.count - 2)
        XCTAssertEqual(result.records.map(describe), oneShot(Self.session))
    }

    /// Records that have left the week are dropped from the file's entry, not just skipped when
    /// counted, so a rollout that stays listed for weeks does not keep every old request.
    func testRecordsThatLeaveTheWeekAreNotKept() throws {
        let url = try file("aging.jsonl", Self.session)
        let cache = JSONLUsageCache(label: "test", format: .codex)
        _ = cache.refresh(files: [url], now: now)
        XCTAssertEqual(cache.keptRecordCount(for: url), 3)
        let later = now.addingTimeInterval(UsageWindows.week + 3600)
        XCTAssertTrue(cache.refresh(files: [url], now: later).records.isEmpty)
        XCTAssertEqual(cache.keptRecordCount(for: url), 0)
        // The reader's state is kept: a request appended now is still measured against the old total.
        try append(url, Self.count(at: "2026-10-24T13:00:00.000Z", total: (26000, 1100), last: nil) + "\n")
        XCTAssertEqual(cache.refresh(files: [url], now: later).records.map(\.promptTokens), [300])
    }
}
