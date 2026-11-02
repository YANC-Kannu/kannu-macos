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

/// One request's tokens, split the way the providers report them.
///
/// The split matters because the parts differ by orders of magnitude. Every request of a long chat
/// reads its whole context back from the prompt cache, so cache reads were 97–98 % of every Claude
/// total measured on the development machine: a week of 2.26 B tokens was 54.9 M without them. Those
/// are the same tokens counted again on every request, so the headline (`headlineTokens`) leaves them
/// out and the card shows them apart.
struct UsageRecord: Equatable {
    let timestamp: Date
    let model: String
    /// Prompt tokens neither written to nor read from a cache.
    var uncachedInputTokens: Int
    /// Prompt tokens written to the prompt cache (Claude's `cache_creation_input_tokens`): new to the
    /// model, kept for the requests after this one.
    var cacheWriteTokens: Int
    /// Prompt tokens read back from the cache: context the model has already seen.
    var cacheReadTokens: Int
    var outputTokens: Int
    let dedupKey: String?

    init(timestamp: Date, model: String, uncachedInputTokens: Int, cacheWriteTokens: Int = 0,
         cacheReadTokens: Int = 0, outputTokens: Int, dedupKey: String?) {
        self.timestamp = timestamp
        self.model = model
        self.uncachedInputTokens = uncachedInputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheReadTokens = cacheReadTokens
        self.outputTokens = outputTokens
        self.dedupKey = dedupKey
    }

    /// Everything the model read for this request. What a single prompt rate is priced against.
    var promptTokens: Int { uncachedInputTokens + cacheWriteTokens + cacheReadTokens }

    /// New tokens in, plus the output: the count the card leads with. Cache reads are left out.
    var headlineTokens: Int { uncachedInputTokens + cacheWriteTokens + outputTokens }

    /// Two lines of one message (same `dedupKey`): this record's time, model and key, and each count
    /// the larger of the two. Claude Code 2.1.219–2.1.304 wrote a subagent message's first line
    /// mid-stream (`stop_reason` null, output 2–16) and its real counts on a later line, so keeping
    /// the first line lost 23 % of a week's output. Identical lines merge to themselves.
    func merging(_ other: UsageRecord) -> UsageRecord {
        var merged = self
        merged.uncachedInputTokens = max(uncachedInputTokens, other.uncachedInputTokens)
        merged.cacheWriteTokens = max(cacheWriteTokens, other.cacheWriteTokens)
        merged.cacheReadTokens = max(cacheReadTokens, other.cacheReadTokens)
        merged.outputTokens = max(outputTokens, other.outputTokens)
        return merged
    }
}

/// A window's token counts (today, the week, a model), split as `UsageRecord` is.
struct UsageTotals: Equatable {
    var uncachedInputTokens: Int = 0
    var cacheWriteTokens: Int = 0
    var cacheReadTokens: Int = 0
    var outputTokens: Int = 0
    var costUSD: Double = 0
    var hasUnpricedModel: Bool = false

    /// The headline: new input (uncached or written to the cache) plus output. Cache reads are shown
    /// on their own (`cacheReadTokens`), never in this sum.
    var totalTokens: Int { uncachedInputTokens + cacheWriteTokens + outputTokens }

    /// Adds `record`'s tokens; the cost is the caller's, which knows the prices.
    mutating func addTokens(of record: UsageRecord) {
        uncachedInputTokens += record.uncachedInputTokens
        cacheWriteTokens += record.cacheWriteTokens
        cacheReadTokens += record.cacheReadTokens
        outputTokens += record.outputTokens
    }
}

/// One Claude transcript line's token usage. (Codex rollouts use a different, stateful shape: see
/// `CodexUsageLine`. The top-level `usage`/`request_id` fallback below never matches one.) Input,
/// cache writes, cache reads and output are kept apart. Claude splits one assistant message across
/// several records with the same `dedupKey` (message id + request id); readers count the key once,
/// with `UsageRecord.merging`, because the records do not always repeat the same usage. Lifted out
/// of `JSONLUsageParser` so the logic test target (and the turn-token reader) can use it.
enum ClaudeUsageLine {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        if let d = iso.date(from: s) { return d }
        return isoPlain.date(from: s)
    }

    static func parse(_ data: Data) -> UsageRecord? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parse(obj)
    }

    static func parse(_ obj: [String: Any]) -> UsageRecord? {
        let message = obj["message"] as? [String: Any]
        let usage = (message?["usage"] as? [String: Any]) ?? (obj["usage"] as? [String: Any])
        guard let usage else { return nil }
        func count(_ value: Any?) -> Int { max(0, value as? Int ?? 0) }
        let input = count(usage["input_tokens"])
        // `cache_creation` breaks the same writes down by lifetime. It is the total when the flat key
        // is missing, and never added to it.
        let byLifetime = (usage["cache_creation"] as? [String: Any]).map {
            count($0["ephemeral_5m_input_tokens"]) + count($0["ephemeral_1h_input_tokens"])
        } ?? 0
        let cacheWrite = max(count(usage["cache_creation_input_tokens"]), byLifetime)
        let cacheRead = count(usage["cache_read_input_tokens"])
        let output = count(usage["output_tokens"])
        guard input + cacheWrite + cacheRead + output > 0 else { return nil }
        let model = (message?["model"] as? String) ?? (obj["model"] as? String) ?? "unknown"
        let tsString = (obj["timestamp"] as? String) ?? (message?["timestamp"] as? String) ?? ""
        guard let ts = parseDate(tsString) else { return nil }
        let messageId = message?["id"] as? String
        let requestId = (obj["requestId"] as? String) ?? (obj["request_id"] as? String)
        let dedupKey = (messageId != nil || requestId != nil) ? "\(messageId ?? "")-\(requestId ?? "")" : nil
        return UsageRecord(timestamp: ts, model: model, uncachedInputTokens: input, cacheWriteTokens: cacheWrite,
                           cacheReadTokens: cacheRead, outputTokens: output, dedupKey: dedupKey)
    }
}
