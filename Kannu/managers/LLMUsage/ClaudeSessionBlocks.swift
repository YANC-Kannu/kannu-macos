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

/// Claude's current 5-hour block from local transcript records: the tokens spent in it and when it
/// resets — a local, auth-free glance value.
///
/// When Claude has reported the 5-hour window's reset (the card's limit bar carries it), the block is
/// the plan's own: `[reset − 5 h, reset)`. Otherwise it is reconstructed the way community tooling
/// (ccusage) does: anchored at the first request after the previous block ended, floored to the hour,
/// exactly five hours long. That is an approximation: one server sample put the window's start at
/// ten past the hour, so `isApproximate` says which one the card is showing.
///
/// Honest boundary: the plan's budget (the denominator) and Anthropic's model/cache-weighted
/// `utilization` exist only server-side, so this can never be a percentage — local token sums
/// are known to diverge from the server's accounting. It is a fuel gauge without a tank size.
///
/// Foundation-only on purpose: compiled into the logic test target.
enum ClaudeSessionBlocks {
    struct CurrentBlock: Equatable {
        let startedAt: Date
        let resetsAt: Date
        let totalTokens: Int
        /// Tokens per minute over the block so far; 0 while the block is under a minute old.
        let burnRatePerMinute: Double
        /// True for the hour-floored reconstruction; false when the block is the plan's own window.
        var isApproximate: Bool = true
    }

    static let blockLength: TimeInterval = 5 * 3600

    /// `records` are (timestamp, tokens) pairs in ANY order; only the block containing `now`
    /// is returned. With a plausible `fiveHourResetsAt` (after `now`, at most five hours and
    /// `UsageWindows.resetSlack` away) that is the plan's window, returned even with no local record
    /// in it: Claude says a window is running, and requests from other devices count against it too.
    /// Without one it is the reconstruction, nil when the latest activity predates it.
    static func currentBlock(records: [(timestamp: Date, tokens: Int)], now: Date,
                             fiveHourResetsAt: Date? = nil) -> CurrentBlock? {
        if let reset = fiveHourResetsAt, reset > now,
           reset <= now.addingTimeInterval(blockLength + UsageWindows.resetSlack) {
            let start = reset.addingTimeInterval(-blockLength)
            let tokens = records.reduce(0) { sum, record in
                record.timestamp >= start && record.timestamp <= now ? sum + record.tokens : sum
            }
            return CurrentBlock(startedAt: start, resetsAt: reset, totalTokens: tokens,
                                burnRatePerMinute: burnRate(tokens: tokens, since: start, now: now),
                                isApproximate: false)
        }
        let sorted = records.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return nil }

        var blockStart: Date?
        var blockTokens = 0
        var lastRecordAt: Date?

        for record in sorted where record.timestamp <= now {
            if let start = blockStart, record.timestamp < start.addingTimeInterval(blockLength) {
                blockTokens += record.tokens
            } else {
                blockStart = floorToHour(record.timestamp)
                blockTokens = record.tokens
            }
            lastRecordAt = record.timestamp
        }

        guard let start = blockStart, lastRecordAt != nil else { return nil }
        let resetsAt = start.addingTimeInterval(blockLength)
        guard now < resetsAt else { return nil } // latest block already expired — idle

        return CurrentBlock(
            startedAt: start,
            resetsAt: resetsAt,
            totalTokens: blockTokens,
            burnRatePerMinute: burnRate(tokens: blockTokens, since: start, now: now)
        )
    }

    private static func burnRate(tokens: Int, since start: Date, now: Date) -> Double {
        let elapsedMinutes = now.timeIntervalSince(start) / 60
        return elapsedMinutes >= 1 ? Double(tokens) / elapsedMinutes : 0
    }

    static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }
}
