//
//  ClaudeTurnTokensTests.swift
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

/// A Claude request's tokens: read from the transcript bytes after the turn's start offset (and
/// every subagent transcript), counted once per message, never from history copied into the file.
final class ClaudeTurnTokensTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_789_000_000)
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kannu-turn-tokens-\(UUID().uuidString)/.claude/projects", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("p"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root.deletingLastPathComponent().deletingLastPathComponent()) }
    }

    // MARK: - Fixtures

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// One assistant record as Claude writes it (compact JSON, one line, newline-terminated).
    private func assistant(_ id: String, request: String = "req", at offset: TimeInterval = 5,
                           input: Int = 10, cacheWrite: Int = 0, cacheRead: Int = 1000, output: Int = 20,
                           stopReason: Any = "end_turn", extra: [String: Any] = [:]) -> Data {
        var object: [String: Any] = [
            "parentUuid": "x", "isSidechain": false, "requestId": "\(request)-\(id)", "type": "assistant",
            "timestamp": Self.iso.string(from: start.addingTimeInterval(offset)),
            "message": ["id": "msg_\(id)", "model": "claude-opus-5", "role": "assistant", "stop_reason": stopReason,
                        "usage": ["input_tokens": input, "cache_creation_input_tokens": cacheWrite,
                                  "cache_read_input_tokens": cacheRead, "output_tokens": output]] as [String: Any],
        ]
        object.merge(extra) { _, new in new }
        return try! JSONSerialization.data(withJSONObject: object) + Data([0x0A])
    }

    private func line(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object) + Data([0x0A])
    }

    private func accumulator(offset: Int64 = 0) -> ClaudeTranscriptTokenAccumulator {
        ClaudeTranscriptTokenAccumulator(startOffset: offset, windowStart: start.addingTimeInterval(-60))
    }

    // MARK: - Usage line

    /// Input, cache writes, cache reads and output are kept apart (they used to be one "input" that
    /// counted the re-read context), and the key is message plus request.
    func testTheLineSplitsInputCacheWritesCacheReadsAndOutput() throws {
        let record = try XCTUnwrap(ClaudeUsageLine.parse(assistant("a", input: 3, cacheWrite: 700, cacheRead: 5000,
                                                                   output: 40).dropLast()))
        XCTAssertEqual(record.uncachedInputTokens, 3)
        XCTAssertEqual(record.cacheWriteTokens, 700)
        XCTAssertEqual(record.cacheReadTokens, 5000)
        XCTAssertEqual(record.outputTokens, 40)
        XCTAssertEqual(record.promptTokens, 3 + 700 + 5000, "everything the model read")
        XCTAssertEqual(record.headlineTokens, 3 + 700 + 40, "the headline leaves the cache reads out")
        XCTAssertEqual(record.dedupKey, "msg_a-req-a")
        XCTAssertNil(ClaudeUsageLine.parse(assistant("z", input: 0, cacheRead: 0, output: 0)), "zero usage is no record")
        XCTAssertNotNil(ClaudeUsageLine.parse(assistant("r", input: 0, cacheRead: 9, output: 0)), "a cache read alone is usage")
    }

    /// `cache_creation` breaks the writes down by lifetime: it stands in for a missing flat count and is
    /// never added to one.
    func testTheCacheWriteBreakdownIsATotalNeverAnAddition() throws {
        func parse(_ usage: [String: Any]) throws -> UsageRecord {
            try XCTUnwrap(ClaudeUsageLine.parse(line([
                "type": "assistant", "timestamp": Self.iso.string(from: start), "requestId": "r",
                "message": ["id": "m", "model": "claude-opus-5", "usage": usage] as [String: Any],
            ]).dropLast()))
        }
        let both = try parse(["input_tokens": 1, "cache_creation_input_tokens": 300, "output_tokens": 2,
                              "cache_creation": ["ephemeral_5m_input_tokens": 100, "ephemeral_1h_input_tokens": 200]])
        XCTAssertEqual(both.cacheWriteTokens, 300)
        let breakdownOnly = try parse(["input_tokens": 1, "output_tokens": 2,
                                       "cache_creation": ["ephemeral_5m_input_tokens": 40, "ephemeral_1h_input_tokens": 60]])
        XCTAssertEqual(breakdownOnly.cacheWriteTokens, 100)
    }

    /// The headline of a window adds what each record adds to it, cache reads apart.
    func testTotalsKeepTheSplitAndTheHeadlineExcludesCacheReads() throws {
        var totals = UsageTotals()
        totals.addTokens(of: try XCTUnwrap(ClaudeUsageLine.parse(assistant("a", input: 3, cacheWrite: 70, cacheRead: 5000,
                                                                           output: 40).dropLast())))
        totals.addTokens(of: try XCTUnwrap(ClaudeUsageLine.parse(assistant("b", input: 2, cacheRead: 5100,
                                                                           output: 10).dropLast())))
        XCTAssertEqual(totals, UsageTotals(uncachedInputTokens: 5, cacheWriteTokens: 70, cacheReadTokens: 10_100,
                                           outputTokens: 50))
        XCTAssertEqual(totals.totalTokens, 125, "the 10,100 re-read tokens are not in the headline")
    }

    /// Two lines of one message: each count the larger, whichever line carries it.
    func testMergingKeepsTheFirstLinesPlaceAndTheLargestCounts() throws {
        let snapshot = try XCTUnwrap(ClaudeUsageLine.parse(assistant("a", at: 5, output: 3, stopReason: NSNull()).dropLast()))
        let final = try XCTUnwrap(ClaudeUsageLine.parse(assistant("a", at: 6, output: 500).dropLast()))
        let merged = snapshot.merging(final)
        XCTAssertEqual(merged.outputTokens, 500)
        XCTAssertEqual(merged.timestamp, snapshot.timestamp)
        XCTAssertEqual(final.merging(snapshot).outputTokens, 500, "order does not matter for the counts")
        XCTAssertEqual(final.merging(final), final)
    }

    func testTopLevelUsageFallbackStillParses() throws {
        // The reader's fallback: usage at the top level, the request named `request_id`, a timestamp
        // with no fraction. This is not the Codex format, which this reader never matches; Codex
        // rollouts are pinned by `CodexUsageLineTests`.
        let record = try XCTUnwrap(ClaudeUsageLine.parse(line([
            "timestamp": "2026-09-11T10:00:00Z", "model": "claude-haiku-4-5", "request_id": "r1",
            "usage": ["input_tokens": 7, "output_tokens": 2],
        ]).dropLast()))
        XCTAssertEqual(record.uncachedInputTokens, 7)
        XCTAssertEqual(record.model, "claude-haiku-4-5")
        XCTAssertEqual(record.dedupKey, "-r1")
    }

    // MARK: - Accumulator

    func testASplitMessageCountsOnce() {
        var acc = accumulator()
        acc.consume(assistant("a") + assistant("a") + assistant("b"))
        XCTAssertEqual(acc.newInput, 2 * 10)
        XCTAssertEqual(acc.cacheRead, 2 * 1000)
        XCTAssertEqual(acc.output, 40)
    }

    /// Claude Code 2.1.219–2.1.304 wrote a subagent message's first line mid-stream (`stop_reason`
    /// null, a few output tokens) and the real counts on a later line. The later line adds what it
    /// reports beyond the first, in this pass or a later one, and nothing when it reports less.
    func testAStreamingSnapshotFirstAddsTheLaterLinesOutput() {
        var acc = accumulator()
        acc.consume(assistant("a", output: 3, stopReason: NSNull()))
        XCTAssertEqual(acc.output, 3)
        acc.consume(assistant("a", cacheWrite: 50, output: 480))
        XCTAssertEqual(acc.output, 480)
        XCTAssertEqual(acc.newInput, 10 + 50, "the input counted once, the later cache write added")
        XCTAssertEqual(acc.cacheRead, 1000)
        acc.consume(assistant("a", output: 7, stopReason: NSNull()))
        XCTAssertEqual(acc.output, 480, "a smaller repeat takes nothing back and adds nothing")
        acc.consume(assistant("b", output: 20))
        XCTAssertEqual(acc.output, 500)
    }

    /// The context is the latest call's whole prompt, replaced call by call and never summed; a
    /// sidechain record (a subagent's call in the chat's own file) is not the chat's context.
    func testTheContextIsTheLatestCallsPromptNotASum() {
        var acc = accumulator()
        XCTAssertNil(acc.context)
        acc.consume(assistant("a", input: 5, cacheWrite: 1000, cacheRead: 400_000))
        XCTAssertEqual(acc.context, 401_005)
        acc.consume(assistant("b", input: 2, cacheWrite: 300, cacheRead: 401_000))
        XCTAssertEqual(acc.context, 401_302)
        acc.consume(assistant("s", input: 9, cacheRead: 30_000, extra: ["isSidechain": true]))
        XCTAssertEqual(acc.context, 401_302, "a sidechain's call")
        XCTAssertEqual(acc.cacheRead, 831_000, "its tokens still count")
    }

    func testAPartialLineWaitsForItsNewline() {
        let record = assistant("a")
        var acc = accumulator()
        acc.consume(record.prefix(30))
        XCTAssertEqual(acc.output, 0)
        acc.consume(record.dropFirst(30))
        XCTAssertEqual(acc.output, 20)
        XCTAssertEqual(acc.readOffset, Int64(record.count))
    }

    func testOnlyAssistantRecordsCount() {
        var acc = accumulator()
        // A user record quoting the marker (escaped inside its string), and one carrying usage.
        acc.consume(line(["type": "user", "message": ["content": #"he wrote "type":"assistant" and "usage":{}"#],
                          "timestamp": Self.iso.string(from: start)]))
        acc.consume(line(["type": "user", "timestamp": Self.iso.string(from: start.addingTimeInterval(1)),
                          "message": ["usage": ["input_tokens": 99, "output_tokens": 99]]]))
        acc.consume(line(["type": "system", "subtype": "api_error"]))
        XCTAssertEqual(acc.newInput, 0)
        XCTAssertNil(acc.context)
        acc.consume(assistant("a"))
        XCTAssertEqual(acc.output, 20)
    }

    func testHistoryCopiedIntoTheFileIsNotThisRequest() {
        var acc = accumulator()
        acc.consume(assistant("old", at: -3600) + assistant("slack", at: -30) + assistant("new", at: 10))
        XCTAssertEqual(acc.output, 40, "an hour old is a resumed chat's history; half a minute is clock slack")
    }

    func testAReplacedOrShrunkFileIsReadAgainFromTheStart() {
        var acc = accumulator(offset: 100)
        XCTAssertEqual(acc.step(size: 500, fileID: 1), .read(from: 100, count: 400))
        acc.consume(Data(repeating: 0x20, count: 400))
        XCTAssertEqual(acc.step(size: 500, fileID: 1), .upToDate)
        XCTAssertEqual(acc.step(size: 800, fileID: 2), .read(from: 0, count: 800), "a new inode")
        acc.consume(Data(repeating: 0x20, count: 800))
        XCTAssertEqual(acc.step(size: 300, fileID: 2), .read(from: 0, count: 300), "shrank below what was read")
        var late = accumulator(offset: 1000)
        XCTAssertEqual(late.step(size: 200, fileID: 9), .read(from: 0, count: 200), "an offset past the end is a replaced file")
    }

    func testReadsAreChunked() {
        var acc = accumulator()
        XCTAssertEqual(acc.step(size: 10 << 20, fileID: 1), .read(from: 0, count: 4 << 20))
    }

    func testAnOverlongLineIsSkippedToItsNewline() {
        var acc = accumulator()
        acc.consume(Data(repeating: 0x41, count: (8 << 20) + 1))
        acc.consume(Data(repeating: 0x41, count: 100) + Data([0x0A]))
        acc.consume(assistant("after"))
        XCTAssertEqual(acc.output, 20)
    }

    func testTheSeenKeysAreBounded() {
        var acc = accumulator()
        var data = Data()
        for index in 0...ClaudeTranscriptTokenAccumulator.seenLimit { data.append(assistant("m\(index)", output: 1)) }
        acc.consume(data)
        acc.consume(assistant("m0", output: 1))
        XCTAssertEqual(acc.output, ClaudeTranscriptTokenAccumulator.seenLimit + 2,
                       "the oldest key is forgotten: split records are adjacent, so this never matters in practice")
        acc.consume(assistant("m\(ClaudeTranscriptTokenAccumulator.seenLimit)", output: 1))
        XCTAssertEqual(acc.output, ClaudeTranscriptTokenAccumulator.seenLimit + 2, "a recent key is still known")
    }

    // MARK: - Requests

    func testRequestsAreForVisibleClaudeCardsWithAFollowableTurn() {
        let home = "/Users/u"
        func card(_ id: String, provider: String = "claude", visible: Bool = true, path: String? = "/Users/u/.claude/projects/p/c.jsonl",
                  offset: Int64? = 10) -> AgentSessionStatus {
            var session = AgentSessionStatus(id: "\(provider)-\(id)", provider: provider, conversationID: id, chatName: nil,
                                             projectName: nil, rawState: "executing", displayState: .executing, updatedAt: start,
                                             isVisible: visible, executionStartedAt: nil)
            session.turn = HookTurn(startedAt: start, toolCalls: 1, transcriptPath: path, transcriptOffset: offset)
            return session
        }
        var turnless = card("t")
        turnless.turn = nil
        let requests = ClaudeTurnTokenRequest.requests(from: [
            card("a"), card("a"), card("b", provider: "cursor"), card("c", visible: false), card("d", offset: nil),
            card("e", path: "/Users/u/Documents/x.jsonl"), card("f", path: "/Volumes/x/.claude/projects/p/c.jsonl"), turnless,
        ], home: home)
        XCTAssertEqual(requests.map(\.conversationID), ["a"])
        XCTAssertEqual(requests.first?.subagentDirectory, "/Users/u/.claude/projects/p/c/subagents")
        XCTAssertEqual(requests.first?.windowStart, start.addingTimeInterval(-60))
    }

    // MARK: - Reader

    private func write(_ relative: String, _ data: Data) throws -> String {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url.path
    }

    private func append(_ data: Data, to path: String) throws {
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    }

    func testTheMainTranscriptFromItsOffsetPlusEverySubagentLayout() throws {
        let before = assistant("before", at: 1)
        let main = try write("p/sess.jsonl", before + assistant("m1") + assistant("m2"))
        _ = try write("p/sess/subagents/agent-a1.jsonl", assistant("s1", output: 100))
        _ = try write("p/sess/subagents/workflows/wf_x/agent-a2.jsonl", assistant("s2", output: 1000))
        _ = try write("p/sess/subagents/notes.txt", Data("x".utf8))
        let reader = ClaudeTurnTokenReader(projectsRoot: root.path)
        let request = ClaudeTurnTokenRequest(conversationID: "sess", mainPath: main, startOffset: Int64(before.count),
                                             startedAt: start)
        let pass = reader.pass([request], now: start)
        XCTAssertFalse(pass.behind)
        XCTAssertEqual(pass.tokens["sess"]?.output, 20 + 20 + 100 + 1000, "the record before the offset is the last request's")
        XCTAssertEqual(pass.tokens["sess"]?.startOffset, Int64(before.count))
        try append(assistant("m3"), to: main)
        XCTAssertEqual(reader.pass([request], now: start).tokens["sess"]?.output, 1160, "an append is read next pass")
    }

    /// "83k in · 40k out · 458k context": the new input and output add up across the chat and its
    /// subagents; the context is the chat's own latest call, never a subagent's, even a later one.
    func testTheContextComesFromTheChatsLatestCallNeverASubagent() throws {
        let main = try write("p/ctx.jsonl", assistant("m1", input: 4, cacheWrite: 900, cacheRead: 400_000, output: 30)
                                            + assistant("m2", at: 8, input: 2, cacheWrite: 100, cacheRead: 401_000, output: 50))
        _ = try write("p/ctx/subagents/agent-a1.jsonl",
                      assistant("s1", at: 20, input: 7, cacheWrite: 5000, cacheRead: 90_000, output: 700))
        let request = ClaudeTurnTokenRequest(conversationID: "ctx", mainPath: main, startOffset: 0, startedAt: start)
        let reader = ClaudeTurnTokenReader(projectsRoot: root.path)
        let tokens = try XCTUnwrap(reader.pass([request], now: start).tokens["ctx"])
        XCTAssertEqual(tokens.context, 2 + 100 + 401_000, "the chat's latest call, not the later subagent's")
        XCTAssertEqual(tokens.newInput, 4 + 900 + 2 + 100 + 7 + 5000)
        XCTAssertEqual(tokens.cacheRead, 400_000 + 401_000 + 90_000)
        XCTAssertEqual(tokens.output, 780)
        try append(assistant("m3", at: 30, input: 1, cacheWrite: 0, cacheRead: 401_100, output: 5), to: main)
        XCTAssertEqual(reader.pass([request], now: start).tokens["ctx"]?.context, 401_101, "replaced, never added")

        let quiet = try write("p/quiet.jsonl", Data())
        _ = try write("p/quiet/subagents/agent-q.jsonl", assistant("q", cacheRead: 50_000))
        let noCall = ClaudeTurnTokenRequest(conversationID: "quiet", mainPath: quiet, startOffset: 0, startedAt: start)
        let subagentOnly = try XCTUnwrap(reader.pass([noCall], now: start).tokens["quiet"])
        XCTAssertNil(subagentOnly.context, "no call of the chat's own yet: no context rather than a subagent's")
    }

    func testAChatIsReportedOnlyOnceCaughtUp() throws {
        var data = Data()
        for index in 0..<20 { data.append(assistant("m\(index)", output: 1)) }
        let main = try write("p/big.jsonl", data)
        let reader = ClaudeTurnTokenReader(projectsRoot: root.path)
        reader.passBudget = data.count / 3
        let request = ClaudeTurnTokenRequest(conversationID: "big", mainPath: main, startOffset: 0, startedAt: start)
        var passes = 0
        var last = reader.pass([request], now: start)
        while last.behind && passes < 10 {
            XCTAssertNil(last.tokens["big"], "no climbing totals while catching up")
            passes += 1
            last = reader.pass([request], now: start)
        }
        XCTAssertGreaterThan(passes, 0)
        XCTAssertEqual(last.tokens["big"]?.output, 20)
    }

    func testSymlinksAndFilesOutsideTheProjectsFolderAreNeverRead() throws {
        let real = try write("p/real.jsonl", assistant("a"))
        let link = root.appendingPathComponent("p/link.jsonl").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("kannu-outside-\(UUID().uuidString).jsonl")
        try assistant("x").write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let outLink = root.appendingPathComponent("p/out.jsonl").path
        try FileManager.default.createSymbolicLink(atPath: outLink, withDestinationPath: outside.path)
        let reader = ClaudeTurnTokenReader(projectsRoot: root.path)
        for path in [link, outLink, outside.path] {
            let request = ClaudeTurnTokenRequest(conversationID: "c", mainPath: path, startOffset: 0, startedAt: start)
            XCTAssertNil(reader.pass([request], now: start).tokens["c"], path)
        }
        // A symlinked subagent file is not followed either.
        let main = try write("p/s2.jsonl", assistant("m"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("p/s2/subagents"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("p/s2/subagents/agent-l.jsonl").path,
                                                   withDestinationPath: outside.path)
        let request = ClaudeTurnTokenRequest(conversationID: "s2", mainPath: main, startOffset: 0, startedAt: start)
        XCTAssertEqual(reader.pass([request], now: start).tokens["s2"]?.output, 20)
    }

    func testTooManySubagentFilesHideTheTotalRatherThanUndercount() throws {
        let main = try write("p/fan.jsonl", assistant("m"))
        for index in 0...ClaudeTurnTokenReader.subagentFileLimit {
            _ = try write("p/fan/subagents/agent-\(index).jsonl", Data())
        }
        let request = ClaudeTurnTokenRequest(conversationID: "fan", mainPath: main, startOffset: 0, startedAt: start)
        XCTAssertNil(ClaudeTurnTokenReader(projectsRoot: root.path).pass([request], now: start).tokens["fan"])
    }

    func testSubagentFilesLastWrittenBeforeTheTurnAreNotRead() throws {
        let main = try write("p/e.jsonl", assistant("m"))
        let old = try write("p/e/subagents/agent-old.jsonl", assistant("o", output: 500))
        try FileManager.default.setAttributes([.modificationDate: start.addingTimeInterval(-3600)], ofItemAtPath: old)
        let request = ClaudeTurnTokenRequest(conversationID: "e", mainPath: main, startOffset: 0, startedAt: start)
        XCTAssertEqual(ClaudeTurnTokenReader(projectsRoot: root.path).pass([request], now: start).tokens["e"]?.output, 20,
                       "a subagent of an earlier request")
    }
}
