import Foundation

struct JSONLUsageParser {
    static func parseLine(_ line: String) -> UsageRecord? {
        ClaudeUsageLine.parse(Data(line.utf8))
    }

    /// Claude transcripts: every line stands alone. Read one file at a time.
    static func aggregate(files: [URL], now: Date) -> UsageSnapshot {
        aggregate(records: files.lazy.flatMap { file -> [UsageRecord] in
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { return [] }
            return content.split(separator: "\n").compactMap { parseLine(String($0)) }
        }, now: now)
    }

    /// Totals for already-parsed requests, in file order. Codex rollouts arrive this way from
    /// `CodexRolloutFiles.recentRecords`, because a rollout is stateful: a usage event's model comes
    /// from an earlier line, and its count from comparing with the event before it.
    static func aggregate<Records: Sequence>(records: Records, now: Date) -> UsageSnapshot
    where Records.Element == UsageRecord {
        var snapshot = UsageSnapshot()
        var perModel: [String: UsageTotals] = [:]
        var seen = Set<String>()
        var blockRecords: [(timestamp: Date, tokens: Int)] = []
        let cal = Calendar.current
        let sessionStart = now.addingTimeInterval(-UsageWindows.session)
        let weekStart = now.addingTimeInterval(-UsageWindows.week)

        for rec in records {
            // Window guard *before* the dedup claim. The other order let a record outside the
            // week claim its key and then be dropped, so a later duplicate of the same request
            // inside the week was skipped as already-seen and never counted — an undercount, not
            // a double count. Transcripts really do carry the same request twice: a resumed or
            // forked history repeats earlier records verbatim.
            guard rec.timestamp >= weekStart else { continue }
            if let key = rec.dedupKey {
                if seen.contains(key) { continue }
                seen.insert(key)
            }
            let cost = ModelPricing.cost(model: rec.model, inputTokens: rec.inputTokens, outputTokens: rec.outputTokens)
            func add(_ t: inout UsageTotals) {
                t.inputTokens += rec.inputTokens
                t.outputTokens += rec.outputTokens
                if let cost { t.costUSD += cost } else { t.hasUnpricedModel = true }
            }
            add(&snapshot.week)
            if cal.isDate(rec.timestamp, inSameDayAs: now) { add(&snapshot.today) }
            if rec.timestamp >= sessionStart { add(&snapshot.session) }
            var mt = perModel[rec.model] ?? UsageTotals()
            add(&mt)
            perModel[rec.model] = mt
            blockRecords.append((rec.timestamp, rec.inputTokens + rec.outputTokens))
        }
        snapshot.models = perModel
            .map { ModelUsage(model: $0.key, totals: $0.value) }
            .sorted { $0.totals.costUSD > $1.totals.costUSD }
        snapshot.localSessionBlock = ClaudeSessionBlocks.currentBlock(records: blockRecords, now: now)
        snapshot.lastUpdated = now
        return snapshot
    }
}
