import Foundation

struct JSONLUsageParser {
    /// Reads `files` through `cache` (only what was appended since the last refresh, on the cache's
    /// own utility queue) and folds the records that count into the card's totals, over the rolling
    /// windows: the provider reports no plan resets here.
    static func aggregate(files: [URL], now: Date, cache: JSONLUsageCache) async -> UsageSnapshot {
        snapshot(counting: await cache.records(files: files, now: now), now: now)
    }

    /// `records` arrive already decided by `JSONLUsageCache`: inside the rolling week, one per dedup
    /// key, in listing then line order — the checks this function used to make inline while it read
    /// every file whole.
    ///
    /// The week, and the per-model breakdown with it, is the plan's own when `weeklyResetsAt` is known
    /// (`UsageWindows.weekWindow`), and the 5-hour block likewise with `fiveHourResetsAt`
    /// (`ClaudeSessionBlocks.currentBlock`). "Today" is the calendar day and "session" the last five
    /// hours, as before.
    static func snapshot(counting records: [UsageRecord], now: Date,
                         weeklyResetsAt: Date? = nil, fiveHourResetsAt: Date? = nil) -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        var perModel: [String: UsageTotals] = [:]
        var blockRecords: [(timestamp: Date, tokens: Int)] = []
        let cal = Calendar.current
        let sessionStart = now.addingTimeInterval(-UsageWindows.session)
        let week = UsageWindows.weekWindow(now: now, weeklyResetsAt: weeklyResetsAt)
        snapshot.weekFollowsPlan = week.followsPlan

        for rec in records {
            // The one prompt rate a pricing table has is applied to everything the model read, as
            // before the split. Cost is shown only for providers that bill per token.
            let cost = ModelPricing.cost(model: rec.model, inputTokens: rec.promptTokens, outputTokens: rec.outputTokens)
            func add(_ t: inout UsageTotals) {
                t.addTokens(of: rec)
                if let cost { t.costUSD += cost } else { t.hasUnpricedModel = true }
            }
            if rec.timestamp >= week.start {
                add(&snapshot.week)
                var mt = perModel[rec.model] ?? UsageTotals()
                add(&mt)
                perModel[rec.model] = mt
            }
            if cal.isDate(rec.timestamp, inSameDayAs: now) { add(&snapshot.today) }
            if rec.timestamp >= sessionStart { add(&snapshot.session) }
            blockRecords.append((rec.timestamp, rec.headlineTokens))
        }
        snapshot.models = perModel
            .map { ModelUsage(model: $0.key, totals: $0.value) }
            .sorted { $0.totals.costUSD > $1.totals.costUSD }
        snapshot.localSessionBlock = ClaudeSessionBlocks.currentBlock(records: blockRecords, now: now,
                                                                      fiveHourResetsAt: fiveHourResetsAt)
        snapshot.lastUpdated = now
        return snapshot
    }

    /// The token half of `snapshot(counting:…)` copied onto a snapshot that already carries the
    /// plan's limits, with the windows anchored on the resets those limits report: the same ones the
    /// card's bars count down to.
    static func addTotals(counting records: [UsageRecord], to snapshot: inout UsageSnapshot, now: Date) {
        let totals = self.snapshot(counting: records, now: now,
                                   weeklyResetsAt: snapshot.weekLimit?.resetsAt,
                                   fiveHourResetsAt: snapshot.sessionLimit?.resetsAt)
        snapshot.session = totals.session
        snapshot.today = totals.today
        snapshot.week = totals.week
        snapshot.weekFollowsPlan = totals.weekFollowsPlan
        snapshot.models = totals.models
        snapshot.localSessionBlock = totals.localSessionBlock
    }
}
