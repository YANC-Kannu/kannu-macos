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

import Foundation

/// Token usage read from one Codex rollout file, line by line in file order.
///
/// Codex does not write Claude's `message.usage` shape. It records usage as an `event_msg` line whose
/// payload is a `token_count` event (`TokenCountEvent` in `codex-rs/protocol/src/protocol.rs`):
///
///     {"timestamp":"…","type":"event_msg","payload":{"type":"token_count",
///      "info":{"total_token_usage":{…},"last_token_usage":{…},"model_context_window":…},
///      "rate_limits":{…}}}
///
/// `info` is null until the first response of a session completes. `total_token_usage` is the
/// session's running total and `last_token_usage` is the latest response alone, so a request is
/// counted from `last_token_usage`; summing the totals would count every earlier request again on
/// each event. Codex also re-emits a `token_count` whose `info` has not changed, so an event whose
/// running total did not move is the same request again and is skipped. When `last_token_usage` is
/// missing, the request is the difference between this total and the previous one. ccusage applies
/// the same two rules.
///
/// The event carries no model. It comes from the latest `turn_context` line before it, whose payload
/// has a `model` field.
///
/// `input_tokens` already includes `cached_input_tokens` (and any `cache_write_input_tokens`), and
/// `output_tokens` already includes `reasoning_output_tokens`, so neither is added a second time.
///
/// A forked session or a spawned subagent starts its rollout with its parent's history, `token_count`
/// events included, re-stamped with the moment of the fork. Counting them would add the parent's
/// usage again for every fork. The file's first line, `session_meta`, says whether it is one
/// (`forked_from_id`, `parent_thread_id`, or `source.subagent.thread_spawn.parent_thread_id`); if
/// so, the usage events written in one burst right after it are the replayed history. They move the
/// running total and count nothing. ccusage's Codex adapter (`replay.rs`) found such bursts span
/// 10–40 ms, with 5.8–15.3 s before the child's own first request, and uses the same 1 s pause; this
/// reader also anchors the burst at `session_meta`, so a history with a single usage event is caught
/// too.
struct CodexUsageLine {
    /// One `TokenUsage` object.
    struct Tokens: Equatable {
        var input = 0
        var cachedInput = 0
        var output = 0
        var reasoningOutput = 0
        var total = 0

        init(input: Int = 0, cachedInput: Int = 0, output: Int = 0, reasoningOutput: Int = 0, total: Int = 0) {
            self.input = input
            self.cachedInput = cachedInput
            self.output = output
            self.reasoningOutput = reasoningOutput
            self.total = total
        }

        /// nil when `value` is not a JSON object, so a missing usage object stays distinct from a
        /// zero one.
        init?(_ value: Any?) {
            guard let object = value as? [String: Any] else { return nil }
            func count(_ key: String) -> Int { max(0, (object[key] as? NSNumber)?.intValue ?? 0) }
            self.init(input: count("input_tokens"), cachedInput: count("cached_input_tokens"),
                      output: count("output_tokens"), reasoningOutput: count("reasoning_output_tokens"),
                      total: count("total_tokens"))
        }

        /// What was added since `previous`, clamped at zero for a total that went backwards.
        func since(_ previous: Tokens?) -> Tokens {
            guard let previous else { return self }
            return Tokens(input: max(0, input - previous.input),
                          cachedInput: max(0, cachedInput - previous.cachedInput),
                          output: max(0, output - previous.output),
                          reasoningOutput: max(0, reasoningOutput - previous.reasoningOutput),
                          total: max(0, total - previous.total))
        }
    }

    /// The model of the latest `turn_context` read so far.
    private(set) var model: String?
    private var previousTotal: Tokens?
    private var replay = Replay.undecided

    /// Longest gap between two replayed usage events (and between `session_meta` and the first).
    static let replayBurstPause: TimeInterval = 1

    private enum Replay {
        /// Nothing decided yet: no `session_meta` and no usage event read.
        case undecided
        /// A fork or subagent whose replayed history has not ended; `last` is the time of
        /// `session_meta` or of the latest replayed usage event.
        case replaying(last: Date)
        /// Every usage event from here on is the file's own.
        case done
    }

    init() {}

    /// True until the first `session_meta` or usage event is read: only then can a `session_meta`
    /// line still decide whether the file replays a parent's history. Lets a byte-level reader
    /// skip parsing the copies a replayed history carries, as `consume(_:)` does.
    var isAwaitingSessionMeta: Bool {
        if case .undecided = replay { return true }
        return false
    }

    /// Every request in one rollout file's contents, read in one go. The Usage tab reads rollouts
    /// through `JSONLUsageCache(format: .codex)` instead, which keeps this reader's state between
    /// refreshes; this is the reference that cache is tested against.
    static func records(in content: String) -> [UsageRecord] {
        var reader = CodexUsageLine()
        var records: [UsageRecord] = []
        for line in content.split(separator: "\n") {
            if let record = reader.consume(line) { records.append(record) }
        }
        return records
    }

    /// Reads the next line of the file. Returns a record only for a `token_count` event that adds
    /// usage; a `turn_context` line updates the model and returns nil.
    mutating func consume<Line: StringProtocol>(_ line: Line) -> UsageRecord? {
        // Most rollout lines are conversation items, some of them large. Only these kinds can
        // matter, so skip JSON parsing for the rest. A line that mentions one of the words in its
        // text still goes through the type checks below. `session_meta` matters only until the
        // first one is read: a replayed history carries its parent's too.
        let mayBeMeta: Bool
        if case .undecided = replay { mayBeMeta = line.contains("session_meta") } else { mayBeMeta = false }
        guard mayBeMeta || line.contains("token_count") || line.contains("turn_context") else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return nil
        }
        return consume(object)
    }

    mutating func consume(_ object: [String: Any]) -> UsageRecord? {
        guard let payload = object["payload"] as? [String: Any] else { return nil }
        switch object["type"] as? String {
        case "session_meta":
            if case .undecided = replay {
                replay = Self.replayStart(payload, lineTimestamp: object["timestamp"]).map { .replaying(last: $0) } ?? .done
            }
            return nil
        case "turn_context":
            if let name = (payload["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                model = name
            }
            return nil
        case "event_msg":
            guard payload["type"] as? String == "token_count" else { return nil }
            return tokenCount(payload, timestamp: object["timestamp"] as? String)
        default:
            return nil
        }
    }

    private mutating func tokenCount(_ payload: [String: Any], timestamp: String?) -> UsageRecord? {
        // JSON null arrives as NSNull, which this cast rejects.
        guard let info = payload["info"] as? [String: Any] else { return nil }
        let total = Tokens(info["total_token_usage"])
        let last = Tokens(info["last_token_usage"])
        guard total != nil || last != nil else { return nil }
        if isReplayed(at: timestamp.flatMap { ClaudeUsageLine.parseDate($0) }) {
            // The parent's request, already counted from the parent's own rollout. It still sets
            // the baseline the child's first own event is measured against.
            if let total { previousTotal = total }
            return nil
        }
        let advanced = total == nil || total != previousTotal
        let usage = (advanced ? last : nil) ?? total?.since(previousTotal)
        if let total { previousTotal = total }
        guard let usage, usage.input + usage.output > 0,
              let timestamp, let date = ClaudeUsageLine.parseDate(timestamp) else { return nil }
        // The event carries no request id. Its own timestamp plus the running total stand in for
        // one, so a verbatim copy of the same rollout (one in `sessions`, one in
        // `archived_sessions`) counts once; two different requests would have to match to the
        // millisecond and in their running totals to collide.
        let key = "codex-\(timestamp)-\(total?.total ?? -1)-\(usage.input)-\(usage.output)"
        return UsageRecord(timestamp: date, model: model ?? "unknown",
                           inputTokens: usage.input, outputTokens: usage.output, dedupKey: key)
    }

    /// Whether the usage event at `date` belongs to a replayed parent history; ends the replay
    /// at the first event that does not.
    private mutating func isReplayed(at date: Date?) -> Bool {
        switch replay {
        case .undecided:
            // Usage before any `session_meta`: nothing says this file is a fork.
            replay = .done
            return false
        case .done:
            return false
        case .replaying(let last):
            guard let date, (0...Self.replayBurstPause).contains(date.timeIntervalSince(last)) else {
                replay = .done
                return false
            }
            replay = .replaying(last: date)
            return true
        }
    }

    /// The time a fork or subagent rollout's replayed history starts from, or nil for a session
    /// of its own. A session naming itself as its parent is its own.
    private static func replayStart(_ payload: [String: Any], lineTimestamp: Any?) -> Date? {
        let id = payload["id"] as? String
        func isParent(_ value: Any?) -> Bool {
            guard let parent = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !parent.isEmpty else { return false }
            return parent != id
        }
        let threadSpawn = ((payload["source"] as? [String: Any])?["subagent"] as? [String: Any])?["thread_spawn"]
        guard isParent(payload["forked_from_id"]) || isParent(payload["parent_thread_id"])
                || isParent((threadSpawn as? [String: Any])?["parent_thread_id"]) else { return nil }
        return date(lineTimestamp) ?? date(payload["timestamp"])
    }

    /// An RFC 3339 string, as Codex writes, or epoch seconds (milliseconds above 10^11).
    private static func date(_ value: Any?) -> Date? {
        if let string = value as? String { return ClaudeUsageLine.parseDate(string) }
        guard let number = value as? NSNumber else { return nil }
        let seconds = number.doubleValue > 1e11 ? number.doubleValue / 1000 : number.doubleValue
        return Date(timeIntervalSince1970: seconds)
    }
}

/// Where Codex keeps its rollout files.
///
/// Codex's home is `$CODEX_HOME`, or `~/.codex` when that is unset. Rollouts live under its
/// `sessions/YYYY/MM/DD/` and, once archived, `archived_sessions/`. Codex compresses a rollout to
/// `.jsonl.zst` only after it has been idle for 7 days (`MIN_ROLLOUT_AGE` in
/// `codex-rs/rollout/src/compression.rs`), so a compressed file cannot hold a request inside the
/// widest window and is never opened. It still proves Codex has written logs, which is what
/// `logsUnavailable` asks.
enum CodexRolloutFiles {
    static let subdirectories = ["sessions", "archived_sessions"]

    struct Listing: Equatable {
        /// Plain `.jsonl` rollouts, the only ones read.
        var plain: [URL] = []
        /// `.jsonl.zst` rollouts, counted and never parsed.
        var compressedCount = 0
        var hasLogs: Bool { !plain.isEmpty || compressedCount > 0 }
    }

    /// Whether `codexHome` has either rollout folder: the first-launch check that turns the Codex
    /// provider on. A directory test, not a listing, because it runs synchronously at launch.
    static func hasRolloutDirectory(codexHome: URL, fileManager: FileManager = .default) -> Bool {
        subdirectories.contains { subdirectory in
            fileManager.fileExists(atPath: codexHome.appendingPathComponent(subdirectory, isDirectory: true).path)
        }
    }

    /// Mirrors Codex: a non-empty `CODEX_HOME` replaces the default outright.
    static func codexHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let value = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return home.appendingPathComponent(".codex", isDirectory: true)
    }

    static func listing(codexHome: URL, fileManager: FileManager = .default) -> Listing {
        var listing = Listing()
        for subdirectory in subdirectories {
            let directory = codexHome.appendingPathComponent(subdirectory, isDirectory: true)
            guard fileManager.fileExists(atPath: directory.path),
                  let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)
            else { continue }
            for case let file as URL in enumerator {
                let name = file.lastPathComponent
                if name.hasSuffix(".jsonl") {
                    listing.plain.append(file)
                } else if name.hasSuffix(".jsonl.zst") {
                    listing.compressedCount += 1
                }
            }
        }
        return listing
    }
}
