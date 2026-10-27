import XCTest

final class ClaudeDesktopUsageHistoryTests: XCTestCase {
    private func sample(t: Double, _ usage: [String: Double]) -> [String: Any] {
        ["t": NSNumber(value: t), "org": "org-uuid",
         "u": usage.mapValues { NSNumber(value: $0) }]
    }

    /// A minute after the fixture samples below, so their windows are still current.
    private let justAfter = Date(timeIntervalSince1970: 1_788_027_991.573 + 60)

    func testUsesNewestSampleRegardlessOfPosition() {
        let snapshot = ClaudeDesktopUsageHistory.parse(json: ["version": 2, "samples": [
            sample(t: 1_788_027_991_573, ["fh": 38, "sd": 61]),
            sample(t: 1_788_000_000_000, ["fh": 4, "sd": 12])
        ]], now: justAfter)
        XCTAssertEqual(snapshot?.fiveHourPercent, 38)
        XCTAssertEqual(snapshot?.sevenDayPercent, 61)
        XCTAssertEqual(snapshot?.observedAt, Date(timeIntervalSince1970: 1_788_027_991.573))
    }

    func testMapsShortCodesToWindowKeysInDisplayOrder() {
        let snapshot = ClaudeDesktopUsageHistory.parse(json: ["samples": [
            sample(t: 1_788_027_991_573, ["sn": 10, "sd": 61, "so": 88, "fh": 38])
        ]], now: justAfter)
        XCTAssertEqual(snapshot?.windows.map(\.key),
                       ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"])
    }

    func testExtraUsageCreditsAreNotAWindow() {
        // `xu` tracks extra-usage spend, not a rate limit; rendering it as a gauge would be a lie.
        let snapshot = ClaudeDesktopUsageHistory.parse(json: ["samples": [
            sample(t: 1_788_027_991_573, ["fh": 38, "xu": 5])
        ]], now: justAfter)
        XCTAssertEqual(snapshot?.windows.map(\.key), ["five_hour"])
    }

    // MARK: - What a sample can still vouch for

    /// Fixed clock so the age rules are deterministic: 2026-08-30 08:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_788_076_800)

    private func series(_ points: [(mins: Double, fh: Double?, sd: Double?)], org: String? = nil) -> [String: Any] {
        let base = 1_788_076_800_000.0
        return ["samples": points.map { p -> [String: Any] in
            var u: [String: Double] = [:]
            if let fh = p.fh { u["fh"] = fh }
            if let sd = p.sd { u["sd"] = sd }
            var entry: [String: Any] = ["t": NSNumber(value: base + p.mins * 60_000),
                                        "u": u.mapValues { NSNumber(value: $0) }]
            if let org { entry["org"] = org }
            return entry
        }]
    }

    func testFiveHourHasNoCountdown() {
        // The 5-hour window starts with the first message after the last one ended, so a rollover
        // in the samples says nothing about when the running window ends. Showing a countdown
        // derived from it was a guess presented as a fact.
        let snapshot = ClaudeDesktopUsageHistory.parse(json: series([
            (-120, 30, 50), (-90, 40, 51), (-60, 7, 51), (-30, 9, 52)
        ]), now: now)
        XCTAssertEqual(snapshot?.window("five_hour")?.percent, 9)
        XCTAssertNil(snapshot?.window("five_hour")?.resetsAt)
        // Marked inferred so `merged` lends it the server's exact reset when there is one.
        XCTAssertEqual(snapshot?.window("five_hour")?.resetIsInferred, true)
        XCTAssertEqual(snapshot?.window("five_hour")?.notAfter, now.addingTimeInterval(-30 * 60 + 5 * 3600))
    }

    func testFiveHourSampleOlderThanTheWindowIsDropped() {
        // A 10-hour-old "0 %" used to render as a live reading. Older than the window itself, the
        // sample cannot say anything about the window running now.
        let stale = ClaudeDesktopUsageHistory.parse(json: series([(-301.0, 0.0, 50.0)]), now: now)
        XCTAssertNil(stale?.window("five_hour"))
        XCTAssertEqual(stale?.window("seven_day")?.percent, 50)
        let recent = ClaudeDesktopUsageHistory.parse(json: series([(-299.0, 0.0, 50.0)]), now: now)
        XCTAssertEqual(recent?.window("five_hour")?.percent, 0)
    }

    func testADerivedResetIsMarkedInferred() throws {
        // Because it is derived, `ClaudeUsageSnapshot.merged` lets an exact reset from another
        // source replace it. sd drops 50 -> 2 (a rollover); fh never carries a reset.
        let snapshot = try XCTUnwrap(ClaudeDesktopUsageHistory.parse(json: series([
            (-120, 30, 50), (-60, 7, 2), (-30, 9, 4)
        ]), now: now))
        XCTAssertEqual(snapshot.window("seven_day")?.resetIsInferred, true)
        XCTAssertNotNil(snapshot.window("seven_day")?.resetsAt)
        XCTAssertNil(snapshot.window("five_hour")?.resetsAt)
    }

    func testWeeklyResetIsSevenDaysAfterTheRollover() {
        let snapshot = ClaudeDesktopUsageHistory.parse(json: series([
            (-120, 10, 82), (-90, 12, 0), (-30, 14, 3)
        ]), now: now)
        XCTAssertEqual(snapshot?.window("seven_day")?.resetsAt,
                       now.addingTimeInterval(-90 * 60 + 7 * 24 * 3600))
    }

    func testSmallDecayIsNotTreatedAsARollover() {
        // A point or two shed between samples is not a reset, so the earlier real rollover must
        // remain the anchor.
        let snapshot = ClaudeDesktopUsageHistory.parse(json: series([
            (-120, 1, 40), (-90, 1, 6), (-60, 1, 17), (-30, 1, 14)
        ]), now: now)
        XCTAssertEqual(snapshot?.window("seven_day")?.resetsAt,
                       now.addingTimeInterval(-90 * 60 + 7 * 24 * 3600))
    }

    func testAnyDecreaseLandingOnZeroIsARollover() {
        // 4 -> 0 is a two-point drop but unmistakably a reset.
        let snapshot = ClaudeDesktopUsageHistory.parse(json: series([
            (-120, 1, 30), (-90, 1, 4), (-45, 1, 0), (-30, 1, 2)
        ]), now: now)
        XCTAssertEqual(snapshot?.window("seven_day")?.resetsAt,
                       now.addingTimeInterval(-45 * 60 + 7 * 24 * 3600))
    }

    func testAWeeklyWindowWhoseResetPassedIsDropped() {
        // The rollover was eight days ago, so the week it began ended yesterday: the sample's
        // percentage belongs to a window that no longer exists. It used to lose only its
        // countdown and keep showing the number as if it were current.
        let snapshot = ClaudeDesktopUsageHistory.parse(json: series([
            (-8.0 * 24 * 60 - 30, 1.0, 40.0), (-8.0 * 24 * 60, 1.0, 3.0)
        ]), now: now)
        XCTAssertNil(snapshot?.window("seven_day"))
    }

    func testARolloverFoundAfterALongGapGivesNoCountdown() {
        // Measured: 72 % on Oct 11, then 0 % on Oct 14 — the rollover was somewhere in three
        // days. A countdown from the far end ran up to that whole gap late, so there is none; the
        // latest possible reset still bounds how long the value is shown.
        let snapshot = ClaudeDesktopUsageHistory.parse(json: series([
            (-3.0 * 24 * 60, 1.0, 72.0), (-10.0, 1.0, 0.0)
        ]), now: now)
        XCTAssertNil(snapshot?.window("seven_day")?.resetsAt)
        XCTAssertEqual(snapshot?.window("seven_day")?.notAfter, now.addingTimeInterval(-10 * 60 + 7 * 24 * 3600))
    }

    func testARolloverAnchorsLaterWeeksToo() {
        // CodeRabbit on #96: the rollover was ten days ago, and the next reset (three days ago)
        // went unseen because usage climbed past the last value before it. The sample is in the
        // week that ends in four days, not in one that ended three days ago.
        let snapshot = ClaudeDesktopUsageHistory.parse(json: series([
            (-10.0 * 24 * 60 - 30, 1.0, 80.0), (-10.0 * 24 * 60, 1.0, 2.0), (-60.0, 1.0, 60.0)
        ]), now: now)
        XCTAssertEqual(snapshot?.window("seven_day")?.percent, 60)
        XCTAssertEqual(snapshot?.window("seven_day")?.resetsAt, now.addingTimeInterval(-10 * 86_400 + 14 * 86_400))
    }

    func testADesktopValueExpiresBetweenReads() throws {
        // Read four hours after the sample, the 5-hour value is still possible; an hour and a
        // minute later it is not, even with no new read in between.
        let snapshot = try XCTUnwrap(ClaudeDesktopUsageHistory.parse(json: series([(-240.0, 30.0, 50.0)]), now: now))
        XCTAssertEqual(snapshot.fiveHourDisplayPercent(now: now), 30)
        XCTAssertNil(snapshot.fiveHourDisplayPercent(now: now.addingTimeInterval(61 * 60)))
        XCTAssertEqual(snapshot.sevenDayDisplayPercent(now: now.addingTimeInterval(61 * 60)), 50)
    }

    func testNoRolloverMeansNoResetButStillReportsPercentages() {
        let snapshot = ClaudeDesktopUsageHistory.parse(json: series([
            (-120, 10, 50), (-60, 20, 51), (-30, 38, 52)
        ]), now: now)
        XCTAssertNil(snapshot?.window("five_hour")?.resetsAt)
        XCTAssertEqual(snapshot?.window("five_hour")?.percent, 38)
        XCTAssertEqual(snapshot?.window("seven_day")?.percent, 52)
        XCTAssertNil(snapshot?.window("seven_day")?.resetsAt)
    }

    func testNoRolloverAndAWeekOldSampleIsDropped() {
        let snapshot = ClaudeDesktopUsageHistory.parse(json: series([(-7.0 * 24 * 60 - 1, nil, 52.0)]), now: now)
        XCTAssertNil(snapshot)
    }

    // MARK: - The weekly anchor

    private func utc(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    func testWeeklyResetFollowsTheAnchorHoweverOld() throws {
        // Real data, one organization (a Max plan): Claude Code's cache last fetched on Sep 2 with
        // the weekly reset at Wed Sep 9 00:00Z, so the desktop sample of Oct 17 23:45Z projects to
        // the week ending Wed Oct 21 00:00Z. The rollover-gap guess put that reset 18.6 hours late.
        let sample: [String: Any] = ["samples": [[
            "t": NSNumber(value: utc("2026-10-17T23:45:29Z").timeIntervalSince1970 * 1000),
            "org": "org-uuid", "u": ["fh": NSNumber(value: 0), "sd": NSNumber(value: 43)]
        ]]]
        let account = ClaudeCachedUsage.AccountContext(organizationUUID: "org-uuid",
                                                       weeklyResetAnchor: utc("2026-09-09T00:00:00Z"))
        let snapshot = try XCTUnwrap(ClaudeDesktopUsageHistory.parse(
            json: sample, now: utc("2026-10-18T00:13:00Z"), account: account))
        XCTAssertEqual(snapshot.window("seven_day")?.resetsAt, utc("2026-10-21T00:00:00Z"))
        XCTAssertEqual(snapshot.window("seven_day")?.percent, 43)
        XCTAssertEqual(snapshot.window("seven_day")?.resetIsInferred, true)
    }

    func testAnchoredWeekThatEndedSinceTheSampleIsDropped() {
        let sample: [String: Any] = ["samples": [[
            "t": NSNumber(value: utc("2026-10-13T20:00:00Z").timeIntervalSince1970 * 1000),
            "u": ["sd": NSNumber(value: 72)]
        ]]]
        let account = ClaudeCachedUsage.AccountContext(weeklyResetAnchor: utc("2026-09-09T00:00:00Z"))
        XCTAssertNil(ClaudeDesktopUsageHistory.parse(json: sample, now: utc("2026-10-14T01:00:00Z"),
                                                     account: account))
    }

    func testWeeklyResetStepsBothWaysAndIsStrictlyAfter() {
        let anchor = utc("2026-09-09T00:00:00Z")
        XCTAssertEqual(ClaudeDesktopUsageHistory.weeklyReset(after: utc("2026-10-17T23:45:00Z"), anchor: anchor),
                       utc("2026-10-21T00:00:00Z"))
        // An anchor still ahead (a live cache) steps backwards to the week the sample is in.
        XCTAssertEqual(ClaudeDesktopUsageHistory.weeklyReset(after: utc("2026-08-31T10:00:00Z"), anchor: anchor),
                       utc("2026-09-02T00:00:00Z"))
        // On the boundary itself the next week's reset is the one ahead.
        XCTAssertEqual(ClaudeDesktopUsageHistory.weeklyReset(after: utc("2026-10-14T00:00:00Z"), anchor: anchor),
                       utc("2026-10-21T00:00:00Z"))
    }

    // MARK: - One organization

    private func orgSample(_ minutes: Double, _ org: String, fh: Double) -> [String: Any] {
        ["t": NSNumber(value: 1_788_076_800_000 + minutes * 60_000), "org": org,
         "u": ["fh": NSNumber(value: fh)]]
    }

    func testTheDesktopsCurrentOrganizationIsTheOneRead() {
        // The card follows the organization the desktop app is on now — its newest sample's —
        // whatever Claude Code is signed in to. Older samples of another organization are other
        // limits entirely.
        let json: [String: Any] = ["samples": [
            orgSample(-60, "team", fh: 40),
            orgSample(-10, "max", fh: 95)
        ]]
        XCTAssertEqual(ClaudeDesktopUsageHistory.parse(json: json, now: now)?.fiveHourPercent, 95)
        XCTAssertEqual(ClaudeDesktopUsageHistory.parse(
            json: json, now: now, account: .init(organizationUUID: "team"))?.fiveHourPercent, 95)
        XCTAssertEqual(ClaudeDesktopUsageHistory.parse(json: json, now: now)?.organizationUUID, "max")
        XCTAssertEqual(ClaudeDesktopUsageHistory.organization(json: json), "max")
    }

    func testTheOrganizationIsKnownEvenWhenNoWindowIsCurrent() throws {
        // A day-old 5-hour sample shows nothing, but the card still follows this organization.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plan-usage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let json: [String: Any] = ["samples": [orgSample(-24 * 60, "max", fh: 40)]]
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let read = ClaudeDesktopUsageHistory.read(from: url, now: now)
        XCTAssertNil(read.snapshot)
        XCTAssertEqual(read.organizationUUID, "max")
    }

    func testAnotherOrganizationsWeeklyResetIsNotApplied() throws {
        // Measured 2026-10-18: one person, a Max plan resetting Wednesday 00:00Z and a Team plan
        // resetting Monday 05:00Z. Claude Code on Team must not date the Max week.
        let sample: [String: Any] = ["samples": [[
            "t": NSNumber(value: utc("2026-10-17T23:45:29Z").timeIntervalSince1970 * 1000),
            "org": "max", "u": ["sd": NSNumber(value: 43)]
        ]]]
        let teamAnchor = ClaudeCachedUsage.AccountContext(organizationUUID: "team",
                                                          weeklyResetAnchor: utc("2026-10-20T05:00:00Z"))
        let snapshot = try XCTUnwrap(ClaudeDesktopUsageHistory.parse(
            json: sample, now: utc("2026-10-18T00:13:00Z"), account: teamAnchor))
        XCTAssertNil(snapshot.window("seven_day")?.resetsAt, "no rollover seen, and the anchor is Team's")
        XCTAssertEqual(snapshot.window("seven_day")?.percent, 43)
    }

    func testRejectsUnusableInput() {
        XCTAssertNil(ClaudeDesktopUsageHistory.parse(json: [:]))
        XCTAssertNil(ClaudeDesktopUsageHistory.parse(json: ["samples": []]))
        XCTAssertNil(ClaudeDesktopUsageHistory.parse(json: ["samples": "not-a-list"]))
        // A sample carrying only unmapped codes yields nothing to show.
        XCTAssertNil(ClaudeDesktopUsageHistory.parse(json: ["samples": [
            sample(t: 1_788_027_991_573, ["xu": 5])
        ]]))
        // Missing or zero timestamps cannot be aged, so they are not usable.
        XCTAssertNil(ClaudeDesktopUsageHistory.parse(json: ["samples": [
            ["u": ["fh": NSNumber(value: 38)]]
        ]]))
    }

    func testMissingFileReturnsNil() {
        XCTAssertNil(ClaudeDesktopUsageHistory.load(
            from: URL(fileURLWithPath: "/nonexistent/plan-usage-history.json")))
    }
}
