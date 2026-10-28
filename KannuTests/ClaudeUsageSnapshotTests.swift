import XCTest

final class ClaudeUsageSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    private func makeJSON(
        tsMs: Int64,
        fiveHourPct: Double? = nil,
        fiveHourResetsAt: Double? = nil,
        sevenDayPct: Double? = nil,
        sevenDayResetsAt: Double? = nil
    ) -> [String: Any] {
        var json: [String: Any] = ["ts": NSNumber(value: tsMs)]
        if let fiveHourPct { json["five_hour_pct"] = NSNumber(value: fiveHourPct) }
        if let fiveHourResetsAt { json["five_hour_resets_at"] = NSNumber(value: fiveHourResetsAt) }
        if let sevenDayPct { json["seven_day_pct"] = NSNumber(value: sevenDayPct) }
        if let sevenDayResetsAt { json["seven_day_resets_at"] = NSNumber(value: sevenDayResetsAt) }
        return json
    }

    private func makeWindowJSON(tsMs: Int64, _ windows: [[String: Any]]) -> [String: Any] {
        ["ts": NSNumber(value: tsMs), "windows": windows]
    }

    private func makeSnapshot(
        fiveHour: (pct: Double, resetsAt: Date?)? = nil,
        sevenDay: (pct: Double, resetsAt: Date?)? = nil,
        extra: [ClaudeUsageSnapshot.Window] = [],
        observedAt: Date
    ) -> ClaudeUsageSnapshot {
        var windows: [ClaudeUsageSnapshot.Window] = []
        if let fiveHour {
            windows.append(.init(key: ClaudeUsageSnapshot.fiveHourKey,
                                 percent: fiveHour.pct, resetsAt: fiveHour.resetsAt))
        }
        if let sevenDay {
            windows.append(.init(key: ClaudeUsageSnapshot.sevenDayKey,
                                 percent: sevenDay.pct, resetsAt: sevenDay.resetsAt))
        }
        return ClaudeUsageSnapshot(windows: windows + extra, observedAt: observedAt)
    }

    // MARK: - Legacy flat shape

    func testParsesAllFields() {
        let snapshot = ClaudeUsageSnapshot.parse(json: makeJSON(
            tsMs: 1_788_000_000_000,
            fiveHourPct: 41.5, fiveHourResetsAt: 1_788_010_000,
            sevenDayPct: 72.3, sevenDayResetsAt: 1_788_345_600
        ))
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.fiveHourPercent, 41.5)
        XCTAssertEqual(snapshot?.sevenDayPercent, 72.3)
        XCTAssertEqual(snapshot?.fiveHourResetsAt, Date(timeIntervalSince1970: 1_788_010_000))
        XCTAssertEqual(snapshot?.observedAt, Date(timeIntervalSince1970: 1_788_000_000))
    }

    func testParsesPartialWindows() {
        let snapshot = ClaudeUsageSnapshot.parse(json: makeJSON(tsMs: 1_788_000_000_000, sevenDayPct: 50))
        XCTAssertNotNil(snapshot)
        XCTAssertNil(snapshot?.fiveHourPercent)
        XCTAssertEqual(snapshot?.sevenDayPercent, 50)
    }

    func testRejectsEmptyOrMissingTs() {
        XCTAssertNil(ClaudeUsageSnapshot.parse(json: makeJSON(tsMs: 1_788_000_000_000)))
        XCTAssertNil(ClaudeUsageSnapshot.parse(json: ["five_hour_pct": NSNumber(value: 10)]))
        XCTAssertNil(ClaudeUsageSnapshot.parse(json: [:]))
    }

    // MARK: - Open-ended window list

    func testParsesWindowListIncludingUnknownKeys() {
        let snapshot = ClaudeUsageSnapshot.parse(json: makeWindowJSON(tsMs: 1_788_000_000_000, [
            ["key": "five_hour", "pct": NSNumber(value: 17.5), "resets_at": NSNumber(value: 1_788_010_000)],
            ["key": "seven_day", "pct": NSNumber(value: 63.25)],
            ["key": "seven_day_opus", "pct": NSNumber(value: 88)]
        ]))
        XCTAssertEqual(snapshot?.windows.count, 3)
        XCTAssertEqual(snapshot?.fiveHourPercent, 17.5)
        // An unrecognised window must survive parsing — the display decides what to do with it.
        XCTAssertEqual(snapshot?.window("seven_day_opus")?.percent, 88)
        XCTAssertNil(snapshot?.window("seven_day_opus")?.resetsAt)
    }

    func testWindowListSkipsMalformedEntriesAndKeepsOrder() {
        let snapshot = ClaudeUsageSnapshot.parse(json: makeWindowJSON(tsMs: 1_788_000_000_000, [
            ["key": "seven_day_cowork", "pct": NSNumber(value: 12)],
            ["key": "", "pct": NSNumber(value: 5)],
            ["pct": NSNumber(value: 9)],
            ["key": "seven_day_sonnet"],
            ["key": "seven_day_opus", "pct": NSNumber(value: 30)]
        ]))
        XCTAssertEqual(snapshot?.windows.map(\.key), ["seven_day_cowork", "seven_day_opus"])
    }

    func testWindowListShapeWinsOverLegacyFields() {
        var json = makeWindowJSON(tsMs: 1_788_000_000_000, [
            ["key": "five_hour", "pct": NSNumber(value: 20)]
        ])
        json["five_hour_pct"] = NSNumber(value: 99)
        XCTAssertEqual(ClaudeUsageSnapshot.parse(json: json)?.fiveHourPercent, 20)
    }

    func testDisplayOrderPutsKnownWindowsFirst() {
        let snapshot = ClaudeUsageSnapshot(windows: [
            .init(key: "seven_day_opus", percent: 88, resetsAt: nil),
            .init(key: "seven_day", percent: 63, resetsAt: nil),
            .init(key: "seven_day_sonnet", percent: 10, resetsAt: nil),
            .init(key: "five_hour", percent: 17, resetsAt: nil)
        ], observedAt: now)
        XCTAssertEqual(snapshot.displayWindows(now: now).map(\.key),
                       ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"])
    }

    // MARK: - Per-model windows

    func testModelScopedWindowKeepsItsServerLabel() {
        // Per-model weekly windows are named by the server, not by a key we could recognise.
        let snapshot = ClaudeUsageSnapshot.parse(json: makeWindowJSON(tsMs: 1_788_000_000_000, [
            ["key": "five_hour", "pct": NSNumber(value: 9)],
            ["key": "seven_day", "pct": NSNumber(value: 63)],
            ["key": "model_scoped:Fable", "label": "Fable", "pct": NSNumber(value: 89),
             "resets_at": NSNumber(value: 1_788_359_400)]
        ]))
        let fable = snapshot?.window("model_scoped:Fable")
        XCTAssertEqual(fable?.percent, 89)
        XCTAssertEqual(fable?.label, "Fable")
        XCTAssertEqual(fable?.resetsAt, Date(timeIntervalSince1970: 1_788_359_400))
        // It sorts after the two universal windows, never before them.
        XCTAssertEqual(snapshot?.displayWindows(now: now).map(\.key),
                       ["five_hour", "seven_day", "model_scoped:Fable"])
    }

    func testLabelIsNilWhenAbsentOrEmpty() {
        let snapshot = ClaudeUsageSnapshot.parse(json: makeWindowJSON(tsMs: 1_788_000_000_000, [
            ["key": "five_hour", "pct": NSNumber(value: 9)],
            ["key": "model_scoped:Blank", "label": "", "pct": NSNumber(value: 12)]
        ]))
        XCTAssertNil(snapshot?.window("five_hour")?.label)
        XCTAssertNil(snapshot?.window("model_scoped:Blank")?.label)
    }

    func testExpiredModelScopedWindowIsHidden() {
        let snapshot = ClaudeUsageSnapshot(windows: [
            .init(key: "five_hour", percent: 9, resetsAt: now.addingTimeInterval(600)),
            .init(key: "model_scoped:Fable", percent: 89,
                  resetsAt: now.addingTimeInterval(-1), label: "Fable")
        ], observedAt: now)
        XCTAssertEqual(snapshot.displayWindows(now: now).map(\.key), ["five_hour"])
        XCTAssertFalse(snapshot.isEmpty(now: now))
    }

    // MARK: - Staleness

    func testFreshnessBoundary() {
        let fresh = makeSnapshot(fiveHour: (10, nil), observedAt: now.addingTimeInterval(-599))
        XCTAssertEqual(fresh.freshness(now: now), .fresh)
        let aged = makeSnapshot(fiveHour: (10, nil), observedAt: now.addingTimeInterval(-601))
        XCTAssertEqual(aged.freshness(now: now), .aged)
    }

    func testExpiredWindowHidden() {
        // 5h reset already passed: its percentage is stale fiction, must not show.
        let snapshot = makeSnapshot(
            fiveHour: (88, now.addingTimeInterval(-60)),
            sevenDay: (40, now.addingTimeInterval(86_400)),
            observedAt: now.addingTimeInterval(-3600))
        XCTAssertNil(snapshot.fiveHourDisplayPercent(now: now))
        XCTAssertEqual(snapshot.sevenDayDisplayPercent(now: now), 40)
        XCTAssertFalse(snapshot.isEmpty(now: now))
    }

    func testExpiredExtraWindowHidden() {
        let snapshot = ClaudeUsageSnapshot(windows: [
            .init(key: "seven_day_opus", percent: 88, resetsAt: now.addingTimeInterval(-1))
        ], observedAt: now)
        XCTAssertTrue(snapshot.displayWindows(now: now).isEmpty)
        XCTAssertTrue(snapshot.isEmpty(now: now))
    }

    func testAllWindowsExpiredIsEmpty() {
        let snapshot = makeSnapshot(
            fiveHour: (88, now.addingTimeInterval(-60)),
            sevenDay: (40, now.addingTimeInterval(-30)),
            observedAt: now.addingTimeInterval(-7200))
        XCTAssertTrue(snapshot.isEmpty(now: now))
    }

    func testWindowWithoutResetStaysVisible() {
        // Visible without a reset — but only for as long as the window it was read in can last.
        // A null reset used to keep the value on the card forever.
        let snapshot = ClaudeUsageSnapshot.parse(json: makeWindowJSON(tsMs: 1_788_000_000_000, [
            ["key": "five_hour", "pct": NSNumber(value: 25)],
            ["key": "seven_day", "pct": NSNumber(value: 40)]
        ]))
        XCTAssertEqual(snapshot?.fiveHourDisplayPercent(now: now), 25)
        XCTAssertEqual(snapshot?.fiveHourDisplayPercent(now: now.addingTimeInterval(5 * 3600 - 1)), 25)
        XCTAssertNil(snapshot?.fiveHourDisplayPercent(now: now.addingTimeInterval(5 * 3600)))
        XCTAssertEqual(snapshot?.sevenDayDisplayPercent(now: now.addingTimeInterval(7 * 86_400 - 1)), 40)
        XCTAssertNil(snapshot?.sevenDayDisplayPercent(now: now.addingTimeInterval(7 * 86_400)))
        // A reported reset is the bound by itself.
        let reported = ClaudeUsageSnapshot.parse(json: makeWindowJSON(tsMs: 1_788_000_000_000, [
            ["key": "five_hour", "pct": NSNumber(value: 25), "resets_at": NSNumber(value: 1_788_000_600)]
        ]))
        XCTAssertNil(reported?.window("five_hour")?.notAfter)
    }

    // MARK: - Refresh cadence

    func testFirstReadHappensEvenWhenIdle() {
        // Opening the usage card cold must show something, so the very first read is unconditional.
        XCTAssertTrue(ClaudeUsageSnapshot.shouldRefresh(
            now: now, lastRead: nil, state: .inactive, hasSnapshot: false))
    }

    func testRetriesWhileNothingHasBeenParsedYetButNotOnEveryRescan() {
        // A read that found no usable file leaves no snapshot; keep trying rather than latching
        // off — once a minute, not at every rescan: with nothing to show, the monitor re-parsed
        // ~/.claude.json and the desktop history on the main actor several times a second.
        XCTAssertFalse(ClaudeUsageSnapshot.shouldRefresh(
            now: now, lastRead: now.addingTimeInterval(-1), state: .inactive, hasSnapshot: false))
        XCTAssertFalse(ClaudeUsageSnapshot.shouldRefresh(
            now: now, lastRead: now.addingTimeInterval(-59), state: .executing, hasSnapshot: false))
        XCTAssertTrue(ClaudeUsageSnapshot.shouldRefresh(
            now: now, lastRead: now.addingTimeInterval(-60), state: .inactive, hasSnapshot: false))
    }

    func testDoesNotRefreshWhileNoAgentIsOnScreen() {
        XCTAssertFalse(ClaudeUsageSnapshot.shouldRefresh(
            now: now, lastRead: now.addingTimeInterval(-86_400), state: .inactive, hasSnapshot: true))
    }

    func testRefreshIntervalBoundaryWhileActive() {
        for state in [AgentTrafficLightState.executing, .thinking, .awaitingInput, .stopped] {
            XCTAssertFalse(ClaudeUsageSnapshot.shouldRefresh(
                now: now, lastRead: now.addingTimeInterval(-599), state: state, hasSnapshot: true),
                "\(state) should not re-read before the interval elapses")
            XCTAssertTrue(ClaudeUsageSnapshot.shouldRefresh(
                now: now, lastRead: now.addingTimeInterval(-600), state: state, hasSnapshot: true),
                "\(state) should re-read once the interval elapses")
        }
    }

    // MARK: - Merging sources

    private func window(_ key: String, pct: Double, resetsIn seconds: TimeInterval?, label: String? = nil,
                        severity: String? = nil) -> ClaudeUsageSnapshot.Window {
        .init(key: key, percent: pct, resetsAt: seconds.map { now.addingTimeInterval($0) },
              label: label, severity: severity)
    }

    func testMergeFillsLapsedKeyFromLowerSourceAndKeepsHigherLiveSiblings() {
        let higher = ClaudeUsageSnapshot(windows: [
            window("five_hour", pct: 61, resetsIn: -60),
            window("model_scoped:Fable", pct: 95, resetsIn: 3_600, label: "Fable", severity: "critical")
        ], observedAt: now.addingTimeInterval(-100))
        let lower = ClaudeUsageSnapshot(windows: [
            window("five_hour", pct: 25, resetsIn: 600)
        ], observedAt: now.addingTimeInterval(-50))

        let merged = ClaudeUsageSnapshot.merged([higher, lower], now: now)
        XCTAssertEqual(merged?.windows.map(\.key), ["model_scoped:Fable", "five_hour"])
        XCTAssertEqual(merged?.window("five_hour")?.percent, 25, "the lapsed higher copy must yield to the live lower one")
        XCTAssertEqual(merged?.window("five_hour")?.resetsAt, now.addingTimeInterval(600))
        XCTAssertEqual(merged?.window("model_scoped:Fable")?.severity, "critical")
    }

    func testMergeUsesLowerSourceWhenHigherIsEntirelyLapsed() {
        let higher = ClaudeUsageSnapshot(windows: [
            window("five_hour", pct: 61, resetsIn: -60),
            window("seven_day", pct: 80, resetsIn: -30)
        ], observedAt: now)
        let lower = ClaudeUsageSnapshot(windows: [
            window("five_hour", pct: 25, resetsIn: 600),
            window("seven_day", pct: 13, resetsIn: 6_000)
        ], observedAt: now.addingTimeInterval(-10))

        let merged = ClaudeUsageSnapshot.merged([higher, lower], now: now)
        XCTAssertEqual(merged?.fiveHourPercent, 25)
        XCTAssertEqual(merged?.sevenDayPercent, 13)
    }

    func testMergePrefersHigherSourceForAKeyLiveInBoth() {
        let higher = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 40, resetsIn: 300)], observedAt: now)
        let lower = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 45, resetsIn: 900)], observedAt: now)

        let merged = ClaudeUsageSnapshot.merged([higher, lower], now: now)
        XCTAssertEqual(merged?.windows.count, 1)
        XCTAssertEqual(merged?.fiveHourPercent, 40)
        XCTAssertEqual(merged?.fiveHourResetsAt, now.addingTimeInterval(300))
    }

    func testMergePrefersTheFresherSourceForAKeyLiveInBoth() {
        // The bug this pins: a weekly window fetched days ago is "live" until its reset, and
        // source rank let it beat the desktop app's sample from half an hour ago (20 % vs 31 %).
        let staleCache = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 20, resetsIn: 86_400)],
                                             observedAt: now.addingTimeInterval(-6 * 86_400))
        let freshDesktop = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 31, resetsIn: nil)],
                                               observedAt: now.addingTimeInterval(-1_800))
        let merged = ClaudeUsageSnapshot.merged([staleCache, freshDesktop], now: now)
        XCTAssertEqual(merged?.sevenDayPercent, 31)
        XCTAssertNil(merged?.sevenDayResetsAt, "the winning window is taken whole; no reset is borrowed from the loser")
        XCTAssertEqual(merged?.observedAt, now.addingTimeInterval(-1_800))
    }

    func testMergeBorrowsAnExactResetForAnInferredOne() {
        // Desktop history derives its reset from the last rollover it sampled, so it lands after
        // the server's. Taken by freshness it replaced the API's reset on every read, and the
        // usage-alert push key (the reset) fired the same window twice. The fresher percent still
        // wins; the exact reset rides along.
        let exact = now.addingTimeInterval(3 * 86_400)
        let cache = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 90, resetsIn: 3 * 86_400)],
                                        observedAt: now.addingTimeInterval(-1_200))
        let desktop = ClaudeUsageSnapshot(
            windows: [.init(key: "seven_day", percent: 96, resetsAt: exact.addingTimeInterval(1_800), resetIsInferred: true)],
            observedAt: now.addingTimeInterval(-300))
        let merged = ClaudeUsageSnapshot.merged([cache, desktop], now: now)
        XCTAssertEqual(merged?.sevenDayPercent, 96)
        XCTAssertEqual(merged?.sevenDayResetsAt, exact)
        XCTAssertEqual(merged?.window("seven_day")?.resetIsInferred, false)
        XCTAssertEqual(merged?.observedAt, now.addingTimeInterval(-300))
    }

    func testMergeKeepsAnInferredResetWhenNoSourceHasAnExactOne() {
        let inferred = now.addingTimeInterval(3 * 86_400)
        let cache = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 90, resetsIn: nil)],
                                        observedAt: now.addingTimeInterval(-1_200))
        let desktop = ClaudeUsageSnapshot(
            windows: [.init(key: "seven_day", percent: 96, resetsAt: inferred, resetIsInferred: true)],
            observedAt: now.addingTimeInterval(-300))
        let merged = ClaudeUsageSnapshot.merged([cache, desktop], now: now)
        XCTAssertEqual(merged?.sevenDayResetsAt, inferred)
        XCTAssertEqual(merged?.window("seven_day")?.resetIsInferred, true)
        // And an exact reset is never replaced by an inferred one, even when the inferred window wins.
        XCTAssertEqual(ClaudeUsageSnapshot.merged([desktop, cache], now: now)?.sevenDayResetsAt, inferred)
    }

    func testMergeRankOnlyBreaksTiesInFreshness() {
        let higher = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 40, resetsIn: 300)], observedAt: now.addingTimeInterval(-10))
        let lower = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 45, resetsIn: 900)], observedAt: now.addingTimeInterval(-10))
        XCTAssertEqual(ClaudeUsageSnapshot.merged([higher, lower], now: now)?.fiveHourPercent, 40)
        XCTAssertEqual(ClaudeUsageSnapshot.merged([lower, higher], now: now)?.fiveHourPercent, 45)
    }

    func testMergeALapsedFresherWindowStillLosesToALiveOlderOne() {
        let olderLive = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 40, resetsIn: 300)], observedAt: now.addingTimeInterval(-3_000))
        let fresherLapsed = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 90, resetsIn: -1)], observedAt: now)
        XCTAssertEqual(ClaudeUsageSnapshot.merged([fresherLapsed, olderLive], now: now)?.fiveHourPercent, 40)
    }

    func testMergeIsNilWhenNothingIsLiveAnywhere() {
        let lapsed = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 61, resetsIn: -1)], observedAt: now)
        XCTAssertNil(ClaudeUsageSnapshot.merged([nil, lapsed, nil], now: now))
        XCTAssertNil(ClaudeUsageSnapshot.merged([], now: now))
    }

    func testMergeOfIdenticalInputsIsEqual() {
        let a = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 40, resetsIn: 300)], observedAt: now)
        let b = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 10, resetsIn: 3_000)], observedAt: now.addingTimeInterval(-5))
        XCTAssertEqual(ClaudeUsageSnapshot.merged([a, b], now: now), ClaudeUsageSnapshot.merged([a, b], now: now))
    }

    func testMergeNilResetFillsOnlyAMissingKey() {
        let nilReset = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 100, resetsIn: nil)], observedAt: now)

        let liveHigher = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 40, resetsIn: 300)], observedAt: now)
        XCTAssertEqual(ClaudeUsageSnapshot.merged([liveHigher, nilReset], now: now)?.fiveHourPercent, 40)

        let lapsedHigher = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 40, resetsIn: -300)], observedAt: now)
        XCTAssertEqual(ClaudeUsageSnapshot.merged([lapsedHigher, nilReset], now: now)?.fiveHourPercent, 100)
    }

    func testMergeObservedAtIsNewestContributingSource() {
        let older = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 40, resetsIn: 300)], observedAt: now.addingTimeInterval(-500))
        let newerLapsed = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 80, resetsIn: -1)], observedAt: now)
        XCTAssertEqual(ClaudeUsageSnapshot.merged([older, newerLapsed], now: now)?.observedAt, now.addingTimeInterval(-500),
                       "a source that contributed nothing must not advertise freshness")

        let newerLive = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 80, resetsIn: 100)], observedAt: now)
        XCTAssertEqual(ClaudeUsageSnapshot.merged([older, newerLive], now: now)?.observedAt, now)
    }

    func testMergeKeepsEachWindowsOwnObservationTime() {
        // A weekly percent from a desktop sample days old must not borrow the age of a five-hour
        // value read a minute ago: the card shows each reading's age, the forecast uses it.
        let fresh = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 40, resetsIn: 300)],
                                        observedAt: now.addingTimeInterval(-60))
        let old = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 31, resetsIn: 86_400)],
                                      observedAt: now.addingTimeInterval(-3 * 86_400))
        let merged = ClaudeUsageSnapshot.merged([fresh, old], now: now)
        XCTAssertEqual(merged?.window("five_hour")?.observedAt, now.addingTimeInterval(-60))
        XCTAssertEqual(merged?.window("seven_day")?.observedAt, now.addingTimeInterval(-3 * 86_400))
        XCTAssertEqual(merged?.observedAt, now.addingTimeInterval(-60))
    }

    // MARK: - Automatic fetch

    /// CodeRabbit on #96: after "Sign in in Terminal" to the card's organization, nothing recorded
    /// the new one — the recorded organization wins over `~/.claude.json`, and the automatic refresh
    /// stood down while the hint said "another organization". It may run once the file names a
    /// different organization than the recorded one.
    func testAnotherOrganizationHoldsTheAutoFetchUntilClaudeCodeMoves() {
        let settled = now.addingTimeInterval(-3_600)
        func allows(_ recorded: String?, _ inConfig: String?, profileAt: Date?) -> Bool {
            ClaudeUsageSnapshot.otherOrganizationAllowsAutoFetch(recorded: recorded, inConfigNow: inConfig,
                                                                 profileFetchedAt: profileAt, recordedAt: settled)
        }
        XCTAssertFalse(allows("team", "team", profileAt: now),
                       "still on the recorded organization: nothing to fetch for the card")
        XCTAssertTrue(allows("team", "max", profileAt: now),
                      "a profile fetched since Kannu settled it names another: one paced fetch records where it went")
        XCTAssertFalse(allows("team", nil, profileAt: now))
        XCTAssertFalse(allows(nil, "max", profileAt: now), "nothing recorded is not 'another organization'")
    }

    /// 2026-10-28: a desktop-hosted session fetched its Max profile at 11:50:47 IST and kept
    /// writing that copy back, while Claude Code stayed on Team. Counting the file's organization
    /// alone ran `/usage` on nearly every visit of the Usage tab.
    func testAnOldProfileWrittenBackIsNotAMove() {
        let profile = Date(timeIntervalSince1970: 1_793_168_447.270)       // 2026-10-28 06:20:47Z
        let runBefore = profile.addingTimeInterval(-90)                      // the 11:49 IST run
        let runAfter = profile.addingTimeInterval(21)                        // the 11:51 IST run
        XCTAssertTrue(ClaudeUsageSnapshot.otherOrganizationAllowsAutoFetch(
            recorded: "team", inConfigNow: "max", profileFetchedAt: profile, recordedAt: runBefore),
                      "fetched after the last settled run: once")
        XCTAssertFalse(ClaudeUsageSnapshot.otherOrganizationAllowsAutoFetch(
            recorded: "team", inConfigNow: "max", profileFetchedAt: profile, recordedAt: runAfter),
                       "then never again for the same copy")
        XCTAssertFalse(ClaudeUsageSnapshot.otherOrganizationAllowsAutoFetch(
            recorded: "team", inConfigNow: "max", profileFetchedAt: nil, recordedAt: runAfter))
        XCTAssertTrue(ClaudeUsageSnapshot.otherOrganizationAllowsAutoFetch(
            recorded: "team", inConfigNow: "max", profileFetchedAt: profile, recordedAt: nil),
                      "never settled by this rule (an upgrade): one fetch settles it")
    }

    func testAutoFetchRunsWhenTheCacheIsOldOrMissing() {
        XCTAssertTrue(ClaudeUsageSnapshot.shouldAutoFetch(now: now, cacheObservedAt: nil, lastFetch: nil))
        XCTAssertTrue(ClaudeUsageSnapshot.shouldAutoFetch(
            now: now, cacheObservedAt: now.addingTimeInterval(-900), lastFetch: nil))
        XCTAssertFalse(ClaudeUsageSnapshot.shouldAutoFetch(
            now: now, cacheObservedAt: now.addingTimeInterval(-899), lastFetch: nil))
    }

    func testAutoFetchWaitsAfterAnyFetch() {
        // A run that left the cache as it was (no sign-in) must not repeat every poll tick.
        XCTAssertFalse(ClaudeUsageSnapshot.shouldAutoFetch(
            now: now, cacheObservedAt: nil, lastFetch: now.addingTimeInterval(-899)))
        XCTAssertTrue(ClaudeUsageSnapshot.shouldAutoFetch(
            now: now, cacheObservedAt: nil, lastFetch: now.addingTimeInterval(-900)))
    }

    // MARK: - One organization per card

    func testClaudeCodeOnAnotherOrganizationIsLeftOutWhole() {
        let statusline = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 5, resetsIn: 300)], observedAt: now)
        let cache = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 0, resetsIn: 3_000)], observedAt: now)
        let desktop = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 43, resetsIn: nil)],
                                          observedAt: now.addingTimeInterval(-3_000))
        let split = ClaudeUsageSnapshot.cardSources(statusline: statusline, cache: cache, desktop: desktop,
                                                    desktopOrganization: "max", claudeCodeOrganization: "team",
                                                    now: now)
        XCTAssertTrue(split.claudeCodeOnAnotherOrganization)
        XCTAssertFalse(split.showsClaudeCodeOrganization)
        XCTAssertEqual(split.sources.compactMap { $0 }, [desktop])
        // A fresher Team reading must not displace the Max one: that was the measured card.
        XCTAssertEqual(ClaudeUsageSnapshot.merged(split.sources, now: now)?.sevenDayPercent, 43)
    }

    func testOneOrganizationOrAnUnknownOneMergesAsBefore() {
        let cache = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 0, resetsIn: 3_000)], observedAt: now)
        let desktop = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 43, resetsIn: nil)], observedAt: now)
        for (desktopOrg, codeOrg) in [("max", "max"), (nil, "team"), ("max", nil)] as [(String?, String?)] {
            let card = ClaudeUsageSnapshot.cardSources(statusline: nil, cache: cache, desktop: desktop,
                                                       desktopOrganization: desktopOrg, claudeCodeOrganization: codeOrg,
                                                       now: now)
            XCTAssertFalse(card.claudeCodeOnAnotherOrganization)
            XCTAssertEqual(card.sources, [nil, cache, desktop])
        }
    }

    func testAnUnrecordedClaudeCodeOrganizationKeepsItsSourcesOff() {
        // Before Kannu's own fetch has recorded Claude Code's organization, the file it would come
        // from flips: trusting it put Team's zeros on the Max card for a first look.
        let cache = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 0, resetsIn: 3_000)], observedAt: now)
        let desktop = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 43, resetsIn: nil)],
                                          observedAt: now.addingTimeInterval(-3_000))
        let card = ClaudeUsageSnapshot.cardSources(statusline: nil, cache: cache, desktop: desktop,
                                                   desktopOrganization: "max", claudeCodeOrganization: "max",
                                                   claudeCodeOrganizationRecorded: false, now: now)
        XCTAssertEqual(card.sources.compactMap { $0 }, [desktop])
        XCTAssertTrue(card.claudeCodeOrganizationUnverified)
        XCTAssertFalse(card.claudeCodeOnAnotherOrganization, "unknown is not 'another': no line about it")
        // No desktop history: Claude Code's organization is the only one, recorded or not.
        let alone = ClaudeUsageSnapshot.cardSources(statusline: nil, cache: cache, desktop: nil,
                                                    desktopOrganization: nil, claudeCodeOrganization: nil,
                                                    claudeCodeOrganizationRecorded: false, now: now)
        XCTAssertEqual(alone.sources, [nil, cache, nil])
        XCTAssertFalse(alone.claudeCodeOrganizationUnverified)
    }

    func testAnUnverifiedOrganizationFetchesAtOnceOncePerLaunch() {
        // A fresh cache would normally wait 15 minutes; an unverified organization cannot.
        XCTAssertTrue(ClaudeUsageSnapshot.shouldAutoFetch(now: now, cacheObservedAt: now, lastFetch: nil,
                                                          organizationUnverified: true))
        // Once a fetch ran this launch, the normal cadence applies, so a failing one never loops.
        XCTAssertFalse(ClaudeUsageSnapshot.shouldAutoFetch(now: now, cacheObservedAt: now,
                                                           lastFetch: now.addingTimeInterval(-60),
                                                           organizationUnverified: true))
        XCTAssertFalse(ClaudeUsageSnapshot.shouldAutoFetch(now: now, cacheObservedAt: now, lastFetch: nil))
    }

    func testHintNamesTheOtherOrganizationFirst() {
        // Even with hooks off and a live cache: the cache is someone else's limits.
        let live = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 40, resetsIn: 300)], observedAt: now)
        XCTAssertEqual(ClaudeUsageSnapshot.hint(hooksInstalled: false, statusline: live, cache: live,
                                                claudeCodeOnAnotherOrganization: true, now: now), .otherOrganization)
    }

    func testADesktopWindowBorrowsTheExactResetForTheSameOrganization() {
        // The desktop's 5-hour value is fresher but has no reset; taken whole, it removed the
        // countdown and flipped the usage-alert key between the exact reset and none.
        let cache = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 40, resetsIn: 3_000)],
                                        observedAt: now.addingTimeInterval(-600))
        let desktop = ClaudeUsageSnapshot(windows: [
            .init(key: "five_hour", percent: 45, resetsAt: nil, resetIsInferred: true,
                  notAfter: now.addingTimeInterval(4 * 3600))
        ], observedAt: now)
        let merged = ClaudeUsageSnapshot.merged([nil, cache, desktop], now: now)
        XCTAssertEqual(merged?.fiveHourPercent, 45)
        XCTAssertEqual(merged?.fiveHourResetsAt, now.addingTimeInterval(3_000))
    }

    func testNotAfterHidesAWindowAtRenderTime() {
        let snapshot = ClaudeUsageSnapshot(windows: [
            .init(key: "five_hour", percent: 45, resetsAt: nil, notAfter: now.addingTimeInterval(60))
        ], observedAt: now)
        XCTAssertEqual(snapshot.fiveHourDisplayPercent(now: now), 45)
        XCTAssertNil(snapshot.fiveHourDisplayPercent(now: now.addingTimeInterval(60)))
    }

    // MARK: - Stale label

    func testTheStaleLabelWaitsLongerThanTheAutomaticFetch() {
        // Bars the automatic refresh keeps current must never dim between its runs.
        XCTAssertGreaterThan(ClaudeUsageSnapshot.staleLabelInterval, ClaudeUsageSnapshot.autoFetchInterval)
        XCTAssertNil(ClaudeUsageSnapshot.staleLabel(observedAt: now.addingTimeInterval(-1_800), now: now))
        XCTAssertNil(ClaudeUsageSnapshot.staleLabel(observedAt: nil, now: now))
        XCTAssertEqual(ClaudeUsageSnapshot.staleLabel(observedAt: now.addingTimeInterval(-1_860), now: now), "updated 31m ago")
        XCTAssertEqual(ClaudeUsageSnapshot.staleLabel(observedAt: now.addingTimeInterval(-3 * 3600), now: now), "updated 3h ago")
        XCTAssertEqual(ClaudeUsageSnapshot.staleLabel(observedAt: now.addingTimeInterval(-3 * 86_400), now: now), "updated 3d ago")
    }

    // MARK: - Sign-in hint

    func testHintIsNeverShownWithoutClaudeHooks() {
        XCTAssertNil(ClaudeUsageSnapshot.hint(hooksInstalled: false, statusline: nil, cache: nil, now: now))
    }

    func testHintIsSilentWhileTheStatuslineIsLive() {
        let live = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 40, resetsIn: 300)], observedAt: now)
        XCTAssertNil(ClaudeUsageSnapshot.hint(hooksInstalled: true, statusline: live, cache: nil, now: now))
    }

    func testHintIsSilentWhileTheCacheIsLive() {
        let lapsed = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 40, resetsIn: -300)], observedAt: now)
        let live = ClaudeUsageSnapshot(windows: [window("seven_day", pct: 10, resetsIn: 3_000)], observedAt: now)
        XCTAssertNil(ClaudeUsageSnapshot.hint(hooksInstalled: true, statusline: lapsed, cache: live, now: now))
    }

    func testHintAsksForSignInWhenNoServerBackedSourceIsLive() {
        let lapsed = ClaudeUsageSnapshot(windows: [window("five_hour", pct: 40, resetsIn: -300)], observedAt: now)
        XCTAssertEqual(ClaudeUsageSnapshot.hint(hooksInstalled: true, statusline: nil, cache: lapsed, now: now), .signInNeeded)
        XCTAssertEqual(ClaudeUsageSnapshot.hint(hooksInstalled: true, statusline: nil, cache: nil, now: now), .signInNeeded)
    }

    // MARK: - Statusline fast path

    func testStatuslineWriteIsReadWithinAMinute() {
        let written = now.addingTimeInterval(-5)
        XCTAssertTrue(ClaudeUsageSnapshot.shouldReadStatusline(now: now, modifiedAt: written, lastSeenModifiedAt: nil, lastRead: nil))
        XCTAssertTrue(ClaudeUsageSnapshot.shouldReadStatusline(now: now, modifiedAt: written,
                                                               lastSeenModifiedAt: now.addingTimeInterval(-300),
                                                               lastRead: now.addingTimeInterval(-61)))
    }

    func testUnchangedStatuslineIsNotReRead() {
        let written = now.addingTimeInterval(-300)
        XCTAssertFalse(ClaudeUsageSnapshot.shouldReadStatusline(now: now, modifiedAt: written, lastSeenModifiedAt: written,
                                                                lastRead: now.addingTimeInterval(-3600)))
        XCTAssertFalse(ClaudeUsageSnapshot.shouldReadStatusline(now: now, modifiedAt: nil, lastSeenModifiedAt: nil, lastRead: nil),
                       "no file, nothing to read")
    }

    func testStatuslineReadsAreThrottled() {
        XCTAssertFalse(ClaudeUsageSnapshot.shouldReadStatusline(now: now, modifiedAt: now,
                                                                lastSeenModifiedAt: now.addingTimeInterval(-30),
                                                                lastRead: now.addingTimeInterval(-30)),
                       "a busy session rewrites the file on every API call; once a minute is enough")
    }
}

