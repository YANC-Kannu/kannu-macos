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

/// Whose limits the Claude card shows, and for how long (REGRESSIONS entry 8, 2026-10-29
/// addendum). On 2026-10-28 Claude Code (the CLI Kannu runs `/usage` with) moved to a Team
/// organization while Claude Desktop stayed on Max. Kannu knew Max's weekly reset only while
/// Claude Code was on Max, so the Desktop's 100 % sample from before Max's reset (05:30 IST)
/// stayed on the card until 23:01 IST, on a reset guessed from a rollover seen a week earlier; then
/// the card showed nothing, under a line calling the token totals Claude Desktop's readings.
final class ClaudeUsageOrganizationTests: XCTestCase {
    private typealias Resets = ClaudeCachedUsage.OrganizationResets

    private func utc(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private func run(started: String, seconds: TimeInterval = 6, organization: String?, profileAt: String?,
                     cacheAt: String?, weekly: String?, fiveHour: String? = nil) -> ClaudeCachedUsage.RunRead {
        var context = ClaudeCachedUsage.AccountContext()
        context.organizationUUID = organization
        context.profileFetchedAt = profileAt.map(utc)
        context.cacheFetchedAt = cacheAt.map(utc)
        context.weeklyResetAnchor = weekly.map(utc)
        context.fiveHourReset = fiveHour.map(utc)
        let start = utc(started)
        return ClaudeCachedUsage.RunRead(context: context, started: start, readAt: start.addingTimeInterval(seconds))
    }

    /// Claude Desktop's real samples around the week in question (one organization, Max).
    private var desktopHistory: [String: Any] {
        let samples: [(String, Double, Double)] = [
            ("2026-10-20T19:44:33Z", 0, 100), ("2026-10-21T17:31:34Z", 100, 14),
            ("2026-10-22T03:07:23Z", 49, 33), ("2026-10-26T06:35:47Z", 0, 98),
            ("2026-10-27T22:26:36Z", 0, 100)
        ]
        return ["version": 2, "samples": samples.map { t, fh, sd -> [String: Any] in
            ["t": NSNumber(value: utc(t).timeIntervalSince1970 * 1000), "org": "max",
             "u": ["fh": NSNumber(value: fh), "sd": NSNumber(value: sd)]]
        }]
    }

    // MARK: - The measured sequence

    func testMaxsWeekEndsAtItsOwnResetAfterClaudeCodeMovesToTeam() throws {
        // Oct 27: Claude Code on Max; Kannu's run fetches with a Max profile and Max's reset.
        let oct27 = ClaudeCachedUsage.attributeRun(
            run(started: "2026-10-27T10:00:00Z", organization: "max", profileAt: "2026-10-27T10:00:02Z",
                cacheAt: "2026-10-27T10:00:04Z", weekly: "2026-10-28T00:00:00Z", fiveHour: "2026-10-27T13:00:00Z"),
            lastKnown: "max", resets: [:])
        XCTAssertEqual(oct27.organization, "max")
        XCTAssertEqual(oct27.evidence, .profile)
        var resets: [String: Resets] = [:]
        resets["max"] = try XCTUnwrap(oct27.resets)
        XCTAssertEqual(resets["max"]?.weekly, utc("2026-10-28T00:00:00Z"))

        // Oct 28, 11:49 IST: the run fetches with a Team profile; Team's week ends Tuesday 05:00Z.
        let move = ClaudeCachedUsage.attributeRun(
            run(started: "2026-10-28T06:19:11Z", organization: "team", profileAt: "2026-10-28T06:19:14Z",
                cacheAt: "2026-10-28T06:19:15Z", weekly: "2026-11-03T05:00:00Z"),
            lastKnown: "max", resets: resets)
        XCTAssertEqual(move.organization, "team")
        resets["team"] = try XCTUnwrap(move.resets)
        XCTAssertEqual(resets["max"]?.weekly, utc("2026-10-28T00:00:00Z"), "Max's reset outlives the move")

        // 11:50:47 IST a desktop-hosted session writes its Max profile back; the 11:51 run sees it,
        // fetched outside the run, while the cache it wrote is Team's by its own week.
        let next = ClaudeCachedUsage.attributeRun(
            run(started: "2026-10-28T06:21:03Z", organization: "max", profileAt: "2026-10-28T06:20:47Z",
                cacheAt: "2026-10-28T06:21:06Z", weekly: "2026-11-03T05:00:00Z"),
            lastKnown: "team", resets: resets)
        XCTAssertEqual(next.organization, "team")
        XCTAssertEqual(next.evidence, .weeklyReset)

        // Desktop is on Max, its newest sample (03:56 IST) at 100 % from before Max's reset.
        func desktop(at now: String) -> ClaudeUsageSnapshot? {
            ClaudeDesktopUsageHistory.parse(json: desktopHistory, now: utc(now), resets: resets,
                                            claudeCodeOrganization: "team")
        }
        let before = try XCTUnwrap(desktop(at: "2026-10-27T23:30:00Z"))   // 05:00 IST
        XCTAssertEqual(before.sevenDayPercent, 100)
        XCTAssertEqual(before.sevenDayResetsAt, utc("2026-10-28T00:00:00Z"))
        XCTAssertNil(desktop(at: "2026-10-28T00:00:00Z")?.sevenDayDisplayPercent(now: utc("2026-10-28T00:00:00Z")),
                     "gone at 05:30 IST, Max's reset")
        XCTAssertNil(desktop(at: "2026-10-28T06:19:17Z"), "and nothing at all by the 11:49 run")
        XCTAssertNil(desktop(at: "2026-10-28T17:00:00Z"))

        // What Kannu did before: Max's reset forgotten, a rollover seen on Oct 21 projected — the
        // bar ran on to 23:01 IST. That guess is the last resort now, never the first.
        let guessed = ClaudeDesktopUsageHistory.parse(json: desktopHistory, now: utc("2026-10-28T06:19:17Z"),
                                                      resets: ["team": try XCTUnwrap(resets["team"])],
                                                      claudeCodeOrganization: "team")
        XCTAssertEqual(guessed?.sevenDayPercent, 100)
        XCTAssertEqual(guessed?.window("seven_day")?.notAfter, utc("2026-10-28T17:31:34Z"))

        // The card at 12:00 IST: Desktop has nothing live, so it shows Claude Code's (Team) bars.
        let now = utc("2026-10-28T06:30:00Z")
        let cache = ClaudeUsageSnapshot(windows: [
            .init(key: "seven_day", percent: 0, resetsAt: utc("2026-11-03T05:00:00Z")),
            .init(key: "five_hour", percent: 0, resetsAt: nil, notAfter: utc("2026-10-28T11:19:15Z"))
        ], observedAt: utc("2026-10-28T06:19:15Z"))
        let owner = ClaudeCachedUsage.cacheOwner(weeklyReset: utc("2026-11-03T05:00:00Z"), claudeCode: "team",
                                                 resets: resets)
        XCTAssertEqual(owner, .claudeCode)
        let card = ClaudeUsageSnapshot.cardSources(statusline: nil, cache: cache, desktop: desktop(at: "2026-10-28T06:30:00Z"),
                                                   desktopOrganization: "max", claudeCodeOrganization: "team",
                                                   cacheOwner: owner, now: now)
        XCTAssertTrue(card.showsClaudeCodeOrganization)
        XCTAssertEqual(ClaudeUsageSnapshot.merged(card.sources, now: now)?.sevenDayPercent, 0)
        XCTAssertEqual(ClaudeUsageSnapshot.hint(hooksInstalled: true, statusline: nil, cache: cache,
                                                claudeCodeOnAnotherOrganization: card.claudeCodeOnAnotherOrganization,
                                                showsClaudeCodeOrganization: card.showsClaudeCodeOrganization, now: now),
                       .otherOrganizationWithoutDesktopReading)
    }

    // MARK: - Whose usage a run fetched

    func testTheProfileCountsOnlyWhenFetchedInsideTheRun() {
        func organization(profileAt: String) -> String? {
            ClaudeCachedUsage.attributeRun(
                run(started: "2026-10-28T08:29:18Z", seconds: 5, organization: "max", profileAt: profileAt,
                    cacheAt: nil, weekly: nil),
                lastKnown: "team", resets: [:]).organization
        }
        XCTAssertEqual(organization(profileAt: "2026-10-28T08:29:20Z"), "max", "inside: Claude Code's own fetch")
        XCTAssertEqual(organization(profileAt: "2026-10-28T08:29:17Z"), "max", "within the slack before the start")
        XCTAssertEqual(organization(profileAt: "2026-10-28T08:29:24Z"), "max", "within the slack after the read")
        XCTAssertEqual(organization(profileAt: "2026-10-28T08:29:15Z"), "team", "before the run: the last known stands")
        XCTAssertEqual(organization(profileAt: "2026-10-28T08:29:26Z"), "team", "after the read: another process's")
        XCTAssertEqual(organization(profileAt: "2026-10-28T06:20:47Z"), "team", "hours old: a copy written back")
    }

    func testAContradictedProfileWithNoMatchingWeekYieldsToTheLastKnownOrganization() {
        // Team's week was never remembered, and the cache contradicts Max's. A desktop-hosted write
        // named Max inside the run, and Team's reset must not be kept as Max's.
        let resets = ["max": Resets(weekly: utc("2026-10-28T00:00:00Z"), reportedAt: utc("2026-10-27T10:00:04Z"))]
        func attribution(lastKnown: String?) -> ClaudeCachedUsage.RunAttribution {
            ClaudeCachedUsage.attributeRun(
                run(started: "2026-10-28T08:29:18Z", organization: "max", profileAt: "2026-10-28T08:29:19Z",
                    cacheAt: "2026-10-28T08:29:20Z", weekly: "2026-11-03T05:00:00Z"),
                lastKnown: lastKnown, resets: resets)
        }
        XCTAssertEqual(attribution(lastKnown: "team").organization, "team")
        XCTAssertEqual(attribution(lastKnown: "team").evidence, .lastKnown)
        XCTAssertEqual(attribution(lastKnown: "team").resets?.weekly, utc("2026-11-03T05:00:00Z"))
        // Max again: its week moved, and the run learns the new one rather than leaving it unknown.
        XCTAssertEqual(attribution(lastKnown: "max").organization, "max")
        XCTAssertEqual(attribution(lastKnown: "max").resets?.weekly, utc("2026-11-03T05:00:00Z"))
        XCTAssertEqual(attribution(lastKnown: nil).organization, "max", "the profile is all there is")
    }

    func testAProfileTheCachesOwnWeekContradictsYieldsToTheWeek() {
        // The profile landed inside the run but Max's own anchor says the cache is not Max's,
        // and Team's says it is Team's: the profile was another process's.
        let resets = ["max": Resets(weekly: utc("2026-10-28T00:00:00Z"), reportedAt: utc("2026-10-27T10:00:04Z")),
                      "team": Resets(weekly: utc("2026-11-03T05:00:00Z"), reportedAt: utc("2026-10-28T06:19:15Z"))]
        let attribution = ClaudeCachedUsage.attributeRun(
            run(started: "2026-10-28T08:29:18Z", organization: "max", profileAt: "2026-10-28T08:29:19Z",
                cacheAt: "2026-10-28T08:29:20Z", weekly: "2026-11-10T05:00:00Z"),
            lastKnown: "team", resets: resets)
        XCTAssertEqual(attribution.organization, "team")
        XCTAssertEqual(attribution.evidence, .weeklyReset)
        XCTAssertEqual(attribution.resets?.weekly, utc("2026-11-10T05:00:00Z"))
        // A new organization, never remembered: the profile is all there is, and its week is learned.
        let new = ClaudeCachedUsage.attributeRun(
            run(started: "2026-10-28T08:29:18Z", organization: "pro", profileAt: "2026-10-28T08:29:19Z",
                cacheAt: "2026-10-28T08:29:20Z", weekly: "2026-11-01T12:00:00Z"),
            lastKnown: "team", resets: resets)
        XCTAssertEqual(new.organization, "pro")
        XCTAssertEqual(new.resets?.weekly, utc("2026-11-01T12:00:00Z"))
    }

    func testAContradictedLastKnownOrganizationWithNoOtherInTheFileIsNeitherKeptNorTaught() {
        let resets = ["team": Resets(weekly: utc("2026-11-03T05:00:00Z"), reportedAt: utc("2026-10-28T06:19:15Z")),
                      "max": Resets(weekly: utc("2026-10-28T00:00:00Z"), reportedAt: utc("2026-10-27T10:00:04Z"))]
        func attribution(fileNames organization: String?) -> ClaudeCachedUsage.RunAttribution {
            ClaudeCachedUsage.attributeRun(
                run(started: "2026-10-28T08:29:18Z", organization: organization, profileAt: "2026-10-28T06:20:47Z",
                    cacheAt: "2026-10-28T08:29:20Z", weekly: "2026-11-05T12:00:00Z"),
                lastKnown: "team", resets: resets)
        }
        for named in [nil, "team", "max"] {
            let result = attribution(fileNames: named)
            XCTAssertNil(result.organization, "the cache is not Team's, and nothing says whose it is (\(named ?? "nil"))")
            XCTAssertNil(result.resets, "so nothing is remembered under anyone")
            XCTAssertEqual(result.evidence, .contradicted)
        }
    }

    /// Measured 2026-11-16: Claude Code had moved from Team to Max, and every one of Kannu's runs
    /// since ended "contradicted". Max's week was never remembered, the profile in the file was a day
    /// old, so the run learned nothing — and the next run the same. Its fresh cache went on no card.
    func testAContradictedLastKnownOrganizationYieldsToTheFilesOtherOrganization() {
        let resets = ["team": Resets(weekly: utc("2026-11-03T05:00:00Z"), reportedAt: utc("2026-10-28T06:19:15Z"))]
        let attribution = ClaudeCachedUsage.attributeRun(
            run(started: "2026-10-28T08:29:18Z", organization: "max", profileAt: "2026-10-28T06:20:47Z",
                cacheAt: "2026-10-28T08:29:20Z", weekly: "2026-11-04T00:00:00Z"),
            lastKnown: "team", resets: resets)
        XCTAssertEqual(attribution.organization, "max", "the cache is not Team's, and the file names Max")
        XCTAssertEqual(attribution.evidence, .movedOrganization)
        XCTAssertEqual(attribution.resets?.weekly, utc("2026-11-04T00:00:00Z"), "and Max's week is learned")
        // A cache the run did not write proves nothing: the last known one stands, as before.
        let unwritten = ClaudeCachedUsage.attributeRun(
            run(started: "2026-10-28T08:29:18Z", organization: "max", profileAt: "2026-10-28T06:20:47Z",
                cacheAt: "2026-10-28T06:19:15Z", weekly: "2026-11-04T00:00:00Z"),
            lastKnown: "team", resets: resets)
        XCTAssertEqual(unwritten.organization, "team")
        XCTAssertEqual(unwritten.evidence, .lastKnown)
    }

    /// The 2026-11-16 report from the two sources' own shapes: the weekly limit reset early, Claude
    /// Code's cache had the fresh week, and the card still showed Claude Desktop's sample from before
    /// the reset. Made-up organizations, times and percentages throughout.
    func testAnEarlyResetReachesTheCardOnceTheRunLearnsClaudeCodesOrganization() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let statusline = directory.appendingPathComponent("claude-usage.json")
        let config = directory.appendingPathComponent(".claude.json")
        let desktop = directory.appendingPathComponent("plan-usage-history.json")
        let max = "org-acme-max", team = "org-acme-team"
        func ms(_ text: String) -> NSNumber { NSNumber(value: utc(text).timeIntervalSince1970 * 1000) }
        // Claude Desktop is on Max; its newest sample is from before the early reset.
        try write(["version": 2, "samples": [
            ["t": ms("2026-11-12T09:00:00Z"), "org": team, "u": ["fh": NSNumber(value: 0), "sd": NSNumber(value: 41)]],
            ["t": ms("2026-11-15T20:00:00Z"), "org": max, "u": ["fh": NSNumber(value: 50), "sd": NSNumber(value: 88)]],
            ["t": ms("2026-11-16T03:00:00Z"), "org": max, "u": ["fh": NSNumber(value: 30), "sd": NSNumber(value: 72)]]
        ]], to: desktop)
        // Kannu's run at 07:00 wrote Claude Code's cache: Max's fresh week, on Max's Wednesday anchor.
        try write(["oauthAccount": ["accountUuid": "acct-acme", "organizationUuid": max,
                                    "organizationType": "claude_max",
                                    "profileFetchedAt": ms("2026-11-14T20:00:00Z")],
                   "cachedUsageUtilization": [
                       "accountUuid": "acct-acme",
                       "fetchedAtMs": ms("2026-11-16T07:00:04Z"),
                       "utilization": [
                           "five_hour": ["utilization": NSNumber(value: 40), "resets_at": "2026-11-16T11:00:00.000000+00:00"],
                           "seven_day": ["utilization": NSNumber(value: 6), "resets_at": "2026-11-18T00:00:00.000000+00:00"]
                       ]
                   ]], to: config)
        // Kannu last recorded Claude Code on Team, whose week ends Tuesday 05:00Z.
        var resets = [team: Resets(weekly: utc("2026-11-10T05:00:00Z"), reportedAt: utc("2026-11-09T12:00:00Z"))]
        let now = utc("2026-11-16T07:05:00Z")
        func card(recorded: String) throws -> ClaudeUsageSnapshot? {
            let full = try XCTUnwrap(ClaudeUsageSources.read(ClaudeUsageSources.Request(
                statuslineURL: statusline, configURL: config, desktopURL: desktop, now: now,
                recordedOrganization: recorded, resets: resets)).full)
            let sources = ClaudeUsageSnapshot.cardSources(
                statusline: nil, cache: full.config.snapshot, desktop: full.desktop,
                desktopOrganization: full.desktopOrganization, claudeCodeOrganization: full.claudeCodeOrganization,
                cacheOwner: full.cacheOwner, now: now)
            return ClaudeUsageSnapshot.merged(sources.sources, now: now)
        }

        // Before the run is attributed: the cache contradicts Team's week, so it goes on no card.
        XCTAssertEqual(try card(recorded: team)?.sevenDayPercent, 72, "the stale sample is all the card has")

        // The run: the file's profile is two days old, the cache Max's.
        let context = ClaudeCachedUsage.read(from: config).context
        XCTAssertEqual(context.organizationUUID, max)
        let attribution = ClaudeCachedUsage.attributeRun(
            ClaudeCachedUsage.RunRead(context: context, started: utc("2026-11-16T06:59:58Z"),
                                      readAt: utc("2026-11-16T07:00:06Z")),
            lastKnown: team, resets: resets)
        XCTAssertEqual(attribution.organization, max)
        XCTAssertEqual(attribution.evidence, .movedOrganization)
        resets[max] = try XCTUnwrap(attribution.resets)

        // After it: one organization, and the newest reading of each window wins.
        let after = try XCTUnwrap(try card(recorded: max))
        XCTAssertEqual(after.sevenDayPercent, 6)
        XCTAssertEqual(after.sevenDayResetsAt, utc("2026-11-18T00:00:00Z"))
        XCTAssertEqual(after.fiveHourPercent, 40)
        XCTAssertEqual(after.window("seven_day")?.observedAt, utc("2026-11-16T07:00:04Z"))
    }

    func testOnlyACacheTheRunWroteIsRemembered() {
        // Claude Code's write throttle can leave the stamp where it was: that cache is older than
        // the run, and its resets prove nothing about the run's organization.
        let attribution = ClaudeCachedUsage.attributeRun(
            run(started: "2026-10-28T08:29:18Z", organization: "team", profileAt: "2026-10-28T08:29:19Z",
                cacheAt: "2026-10-28T06:19:15Z", weekly: "2026-11-03T05:00:00Z"),
            lastKnown: "team", resets: [:])
        XCTAssertEqual(attribution.organization, "team")
        XCTAssertNil(attribution.resets)
        let bootstrap = ClaudeCachedUsage.attributeRun(
            run(started: "2026-10-28T08:29:18Z", organization: "max", profileAt: "2026-10-28T06:20:47Z",
                cacheAt: "2026-10-28T08:29:20Z", weekly: "2026-11-03T05:00:00Z"),
            lastKnown: "team", resets: [:])
        XCTAssertEqual(bootstrap.organization, "team", "nothing remembered yet: the last known stands")
        XCTAssertEqual(bootstrap.evidence, .lastKnown)
        XCTAssertEqual(bootstrap.resets?.weekly, utc("2026-11-03T05:00:00Z"), "and learns its week")
        // A cache that reports no weekly reset keeps the week already known.
        let known = ["team": Resets(weekly: utc("2026-11-03T05:00:00Z"), reportedAt: utc("2026-10-28T06:19:15Z"))]
        let noWeek = ClaudeCachedUsage.attributeRun(
            run(started: "2026-10-28T08:29:18Z", organization: "team", profileAt: "2026-10-28T08:29:19Z",
                cacheAt: "2026-10-28T08:29:20Z", weekly: nil, fiveHour: "2026-10-28T13:00:00Z"),
            lastKnown: "team", resets: known)
        XCTAssertEqual(noWeek.resets?.weekly, utc("2026-11-03T05:00:00Z"))
        XCTAssertEqual(noWeek.resets?.fiveHour, utc("2026-10-28T13:00:00Z"))
    }

    func testTheFirstRunEverTakesTheFile() {
        let attribution = ClaudeCachedUsage.attributeRun(
            run(started: "2026-10-28T08:29:18Z", organization: "max", profileAt: nil,
                cacheAt: "2026-10-28T08:29:20Z", weekly: "2026-10-28T00:00:00Z"),
            lastKnown: nil, resets: [:])
        XCTAssertEqual(attribution.organization, "max")
        XCTAssertEqual(attribution.evidence, .configOnly)
        let nothing = ClaudeCachedUsage.attributeRun(
            run(started: "2026-10-28T08:29:18Z", organization: nil, profileAt: nil, cacheAt: nil, weekly: nil),
            lastKnown: nil, resets: [:])
        XCTAssertNil(nothing.organization)
        XCTAssertEqual(nothing.evidence, .none)
    }

    // MARK: - Weekly anchors

    func testWeeklyAnchorsMatchWholeWeeksApartOnly() {
        let max = utc("2026-10-28T00:00:00Z")
        XCTAssertTrue(ClaudeCachedUsage.onSameWeeklyAnchor(utc("2026-09-09T00:00:00Z").addingTimeInterval(0.230141), max),
                      "the cache's microseconds")
        XCTAssertTrue(ClaudeCachedUsage.onSameWeeklyAnchor(utc("2026-11-25T00:05:00Z"), max))
        XCTAssertTrue(ClaudeCachedUsage.onSameWeeklyAnchor(utc("2026-10-20T23:55:00Z"), max))
        XCTAssertFalse(ClaudeCachedUsage.onSameWeeklyAnchor(utc("2026-11-03T05:00:00Z"), max), "Team's Tuesday 05:00Z")
        XCTAssertFalse(ClaudeCachedUsage.onSameWeeklyAnchor(utc("2026-10-28T01:00:00Z"), max))
        let both = ["max": Resets(weekly: max, reportedAt: max), "team": Resets(weekly: utc("2026-11-03T05:00:00Z"), reportedAt: max)]
        XCTAssertEqual(ClaudeCachedUsage.organization(onWeeklyAnchorOf: utc("2026-10-20T05:00:00Z"), in: both), "team")
        XCTAssertNil(ClaudeCachedUsage.organization(onWeeklyAnchorOf: utc("2026-10-20T06:00:00Z"), in: both))
        let twins = ["a": Resets(weekly: max, reportedAt: max), "b": Resets(weekly: max.addingTimeInterval(-604_800), reportedAt: max)]
        XCTAssertNil(ClaudeCachedUsage.organization(onWeeklyAnchorOf: max, in: twins), "two on one anchor: it cannot say")
    }

    // MARK: - Whose usage the cache holds, between runs

    func testTheCachesOwnWeekNamesItsOwner() {
        let resets = ["max": Resets(weekly: utc("2026-10-28T00:00:00Z"), reportedAt: utc("2026-10-27T10:00:04Z")),
                      "team": Resets(weekly: utc("2026-11-03T05:00:00Z"), reportedAt: utc("2026-10-28T06:19:15Z"))]
        XCTAssertEqual(ClaudeCachedUsage.cacheOwner(weeklyReset: utc("2026-11-10T05:00:00Z"), claudeCode: "team", resets: resets),
                       .claudeCode)
        XCTAssertEqual(ClaudeCachedUsage.cacheOwner(weeklyReset: utc("2026-11-04T00:00:00Z"), claudeCode: "team", resets: resets),
                       .organization("max"), "a desktop-hosted session's /usage")
        XCTAssertEqual(ClaudeCachedUsage.cacheOwner(weeklyReset: utc("2026-11-05T12:00:00Z"), claudeCode: "team", resets: resets),
                       .unknown)
        XCTAssertEqual(ClaudeCachedUsage.cacheOwner(weeklyReset: utc("2026-11-05T12:00:00Z"), claudeCode: "pro", resets: resets),
                       .claudeCode, "nothing remembered for Claude Code's: nothing contradicts it")
        XCTAssertEqual(ClaudeCachedUsage.cacheOwner(weeklyReset: nil, claudeCode: "team", resets: resets), .claudeCode)
    }

    // MARK: - The card when the organizations differ

    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    private func snapshot(_ key: String, _ percent: Double, resetsIn seconds: TimeInterval?,
                          observedAgo: TimeInterval = 60) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(windows: [.init(key: key, percent: percent, resetsAt: seconds.map { now.addingTimeInterval($0) })],
                            observedAt: now.addingTimeInterval(-observedAgo))
    }

    /// David, 2026-10-30: "if a user has both show multiple ones". One card per organization with a
    /// live reading, Claude Desktop's first; never one organization's bar on another's card.
    func testEachOrganizationWithALiveReadingGetsACard() {
        let statusline = snapshot("five_hour", 12, resetsIn: 3_000)
        let cache = snapshot("seven_day", 30, resetsIn: 86_400)
        let lapsedCache = snapshot("seven_day", 30, resetsIn: -60)
        let desktopLive = snapshot("seven_day", 80, resetsIn: nil, observedAgo: 3_600)
        let desktopLapsed = snapshot("seven_day", 100, resetsIn: -60, observedAgo: 3_600)
        func card(_ desktop: ClaudeUsageSnapshot?, statusline: ClaudeUsageSnapshot? = nil,
                  cache: ClaudeUsageSnapshot?, owner: ClaudeUsageSnapshot.CacheOwner = .claudeCode)
            -> ClaudeUsageSnapshot.CardSources {
            ClaudeUsageSnapshot.cardSources(statusline: statusline, cache: cache, desktop: desktop,
                                            desktopOrganization: "max", claudeCodeOrganization: "team",
                                            cacheOwner: owner, now: now)
        }
        // Both live: two cards.
        let both = card(desktopLive, statusline: statusline, cache: cache)
        XCTAssertEqual(both.sources.compactMap { $0 }, [desktopLive])
        XCTAssertEqual(both.secondCardSources?.compactMap { $0 }, [statusline, cache], "Claude Code's own, never mixed")
        XCTAssertFalse(both.showsClaudeCodeOrganization)
        XCTAssertEqual(ClaudeUsageSnapshot.hint(hooksInstalled: true, statusline: statusline, cache: cache,
                                                claudeCodeOnAnotherOrganization: both.claudeCodeOnAnotherOrganization,
                                                showsClaudeCodeOrganization: both.showsClaudeCodeOrganization, now: now),
                       .otherOrganization, "the first card's chip names Claude Desktop's plan")
        // Only Claude Desktop live: its card alone.
        let desktopOnly = card(desktopLive, cache: lapsedCache)
        XCTAssertEqual(desktopOnly.sources.compactMap { $0 }, [desktopLive])
        XCTAssertNil(desktopOnly.secondCardSources, "an organization with no live reading gets no card")
        // Only Claude Code live: its card alone, first.
        for desktop in [desktopLapsed, nil] {
            let codes = card(desktop, statusline: statusline, cache: cache)
            XCTAssertTrue(codes.claudeCodeOnAnotherOrganization)
            XCTAssertTrue(codes.showsClaudeCodeOrganization)
            XCTAssertEqual(codes.sources.compactMap { $0 }, [statusline, cache], "Claude Code's own, never mixed")
            XCTAssertNil(codes.secondCardSources, "never the same bars on two cards")
        }
        // The cache whose own week is Max's is Desktop's organization's: exact numbers for its card,
        // and Claude Code's statusline alone is left for the second.
        let maxCache = card(desktopLapsed, statusline: statusline, cache: cache, owner: .organization("max"))
        XCTAssertEqual(maxCache.sources.compactMap { $0 }, [cache, desktopLapsed])
        XCTAssertFalse(maxCache.showsClaudeCodeOrganization)
        XCTAssertEqual(maxCache.secondCardSources?.compactMap { $0 }, [statusline])
        // An unknown cache goes nowhere.
        XCTAssertEqual(card(nil, statusline: statusline, cache: cache, owner: .unknown).sources.compactMap { $0 }, [statusline])
    }

    func testOneOrganizationOrAnUnverifiedOneHasOneCard() {
        let statusline = snapshot("five_hour", 12, resetsIn: 3_000)
        let cache = snapshot("seven_day", 30, resetsIn: 86_400)
        let desktop = snapshot("seven_day", 80, resetsIn: nil, observedAgo: 3_600)
        let same = ClaudeUsageSnapshot.cardSources(statusline: statusline, cache: cache, desktop: desktop,
                                                   desktopOrganization: "max", claudeCodeOrganization: "max", now: now)
        XCTAssertNil(same.secondCardSources)
        let unknown = ClaudeUsageSnapshot.cardSources(statusline: statusline, cache: cache, desktop: desktop,
                                                      desktopOrganization: "max", claudeCodeOrganization: nil, now: now)
        XCTAssertNil(unknown.secondCardSources)
        // Until Kannu's own fetch has recorded it, Claude Code's organization is a guess: its numbers
        // must not go on a card with a plan's name on it.
        let unverified = ClaudeUsageSnapshot.cardSources(statusline: statusline, cache: cache, desktop: desktop,
                                                         desktopOrganization: "max", claudeCodeOrganization: "team",
                                                         claudeCodeOrganizationRecorded: false, now: now)
        XCTAssertTrue(unverified.claudeCodeOrganizationUnverified)
        XCTAssertNil(unverified.secondCardSources)
    }

    func testNothingLiveOnEitherSideStillSaysWhoseItWouldBe() {
        let lapsed = snapshot("seven_day", 100, resetsIn: -60)
        let card = ClaudeUsageSnapshot.cardSources(statusline: nil, cache: lapsed, desktop: nil,
                                                   desktopOrganization: "max", claudeCodeOrganization: "team", now: now)
        XCTAssertTrue(card.showsClaudeCodeOrganization)
        XCTAssertNil(ClaudeUsageSnapshot.merged(card.sources, now: now), "no bar: the card must not claim readings")
        XCTAssertEqual(ClaudeUsageSnapshot.hint(hooksInstalled: true, statusline: nil, cache: lapsed,
                                                claudeCodeOnAnotherOrganization: true,
                                                showsClaudeCodeOrganization: true, now: now),
                       .otherOrganizationWithoutDesktopReading)
        XCTAssertEqual(ClaudeUsageSnapshot.hint(hooksInstalled: true, statusline: nil, cache: lapsed,
                                                claudeCodeOnAnotherOrganization: true, now: now),
                       .otherOrganization)
    }

    func testOneOrganizationKeepsAnotherOrganizationsCacheOff() {
        let statusline = snapshot("five_hour", 12, resetsIn: 3_000)
        let cache = snapshot("seven_day", 30, resetsIn: 86_400)
        let desktop = snapshot("seven_day", 80, resetsIn: nil, observedAgo: 3_600)
        let same = ClaudeUsageSnapshot.cardSources(statusline: statusline, cache: cache, desktop: desktop,
                                                   desktopOrganization: "max", claudeCodeOrganization: "max",
                                                   cacheOwner: .organization("team"), now: now)
        XCTAssertEqual(same.sources.compactMap { $0 }, [statusline, desktop])
        // Unverified, only a cache its own week ties to Desktop's organization may join.
        let unverified = ClaudeUsageSnapshot.cardSources(statusline: statusline, cache: cache, desktop: desktop,
                                                         desktopOrganization: "max", claudeCodeOrganization: "max",
                                                         claudeCodeOrganizationRecorded: false,
                                                         cacheOwner: .organization("max"), now: now)
        XCTAssertEqual(unverified.sources.compactMap { $0 }, [cache, desktop])
        XCTAssertTrue(unverified.claudeCodeOrganizationUnverified)
    }

    // MARK: - The off-main read

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claude-usage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ json: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: json).write(to: url)
    }

    func testOneReadLendsTheCachesWeekToTheDesktopOnlyForARecordedOrganization() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let statusline = directory.appendingPathComponent("claude-usage.json")
        let config = directory.appendingPathComponent(".claude.json")
        let desktop = directory.appendingPathComponent("plan-usage-history.json")
        try write(["ts": NSNumber(value: 1_793_000_000_000.0),
                   "windows": [["key": "five_hour", "pct": NSNumber(value: 7)]]], to: statusline)
        try write(["oauthAccount": ["accountUuid": "acct", "organizationUuid": "max",
                                    "profileFetchedAt": NSNumber(value: utc("2026-10-27T10:00:02Z").timeIntervalSince1970 * 1000)],
                   "cachedUsageUtilization": [
                       "accountUuid": "acct",
                       "fetchedAtMs": NSNumber(value: utc("2026-10-27T10:00:04Z").timeIntervalSince1970 * 1000),
                       "utilization": ["seven_day": ["utilization": NSNumber(value: 61),
                                                     "resets_at": "2026-10-28T00:00:00+00:00"]]
                   ]], to: config)
        try write(desktopHistory, to: desktop)
        func request(recorded: String?, statuslineOnly: Bool = false) -> ClaudeUsageSources.Request {
            ClaudeUsageSources.Request(statuslineURL: statusline, configURL: config, desktopURL: desktop,
                                       statuslineOnly: statuslineOnly, now: utc("2026-10-27T23:30:00Z"),
                                       recordedOrganization: recorded)
        }

        let quick = ClaudeUsageSources.read(request(recorded: "max", statuslineOnly: true))
        XCTAssertEqual(quick.statusline?.window("five_hour")?.percent, 7)
        XCTAssertNil(quick.full, "between full reads only the statusline file is read")

        let full = try XCTUnwrap(ClaudeUsageSources.read(request(recorded: "max")).full)
        XCTAssertEqual(full.config.snapshot?.sevenDayPercent, 61)
        XCTAssertEqual(full.cacheOwner, .claudeCode)
        XCTAssertEqual(full.desktopOrganization, "max")
        XCTAssertEqual(full.desktop?.sevenDayResetsAt, utc("2026-10-28T00:00:00Z"), "the cache's week, lent")

        let unrecorded = try XCTUnwrap(ClaudeUsageSources.read(request(recorded: nil)).full)
        XCTAssertEqual(unrecorded.claudeCodeOrganization, "max", "the file's, unverified")
        XCTAssertNil(unrecorded.desktop?.sevenDayResetsAt, "a guessed organization lends no week")
    }
}
