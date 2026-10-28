import XCTest

final class ClaudeCachedUsageTests: XCTestCase {
    private let fetchedAtMs = 1_788_000_000_000.0

    private func config(
        limits: [[String: Any]] = [],
        fixed: [String: Any] = [:],
        accountUuid: String? = "acct-1",
        oauthUuid: String? = "acct-1"
    ) -> [String: Any] {
        var utilization: [String: Any] = fixed
        utilization["limits"] = limits
        var cache: [String: Any] = [
            "fetchedAtMs": NSNumber(value: fetchedAtMs),
            "utilization": utilization
        ]
        if let accountUuid { cache["accountUuid"] = accountUuid }
        var json: [String: Any] = ["cachedUsageUtilization": cache]
        if let oauthUuid { json["oauthAccount"] = ["accountUuid": oauthUuid] }
        return json
    }

    private func window(_ pct: Double, resets: String?) -> [String: Any] {
        var d: [String: Any] = ["utilization": NSNumber(value: pct)]
        if let resets { d["resets_at"] = resets }
        return d
    }

    private func scoped(_ name: String, _ pct: Double, kind: String = "weekly_scoped",
                        severity: String = "normal",
                        resets: String? = "2026-07-17T22:59:59.679456+00:00") -> [String: Any] {
        var d: [String: Any] = ["kind": kind, "group": "weekly", "percent": NSNumber(value: pct),
                                "severity": severity,
                                "scope": ["model": ["display_name": name]]]
        if let resets { d["resets_at"] = resets }
        return d
    }

    private func fixedLimit(_ kind: String, _ pct: Double, severity: String) -> [String: Any] {
        ["kind": kind, "group": kind, "percent": NSNumber(value: pct), "severity": severity,
         "scope": NSNull()]
    }

    func testPerModelSeverityIsCarried() {
        let snapshot = ClaudeCachedUsage.parse(json: config(limits: [scoped("Fable", 93, severity: "critical")]))
        XCTAssertEqual(snapshot?.window("model_scoped:Fable")?.severity, "critical")
    }

    func testFixedWindowBorrowsSeverityFromLimitsArray() {
        // The fixed five_hour object has no severity; the parallel limits[] session entry does.
        let snapshot = ClaudeCachedUsage.parse(json: config(
            limits: [fixedLimit("session", 9, severity: "warning")],
            fixed: ["five_hour": window(9, resets: "2026-08-30T18:00:00+00:00")]))
        XCTAssertEqual(snapshot?.window("five_hour")?.severity, "warning")
    }

    // MARK: - Per-model windows

    func testFableWeeklyIsItsOwnWindowWithItsOwnDenominator() {
        let snapshot = ClaudeCachedUsage.parse(json: config(
            limits: [scoped("Fable", 68)],
            fixed: ["seven_day": window(41, resets: "2026-09-02T12:09:00+00:00")]
        ))
        let fable = snapshot?.window("model_scoped:Fable")
        XCTAssertEqual(fable?.percent, 68)
        XCTAssertEqual(fable?.label, "Fable")
        // Explicitly not derived from the all-models weekly figure.
        XCTAssertEqual(snapshot?.window("seven_day")?.percent, 41)
        XCTAssertNotEqual(fable?.percent, snapshot?.window("seven_day")?.percent)
    }

    func testMicrosecondPrecisionResetParses() {
        // The timestamps carry microseconds; ISO8601DateFormatter resolves to milliseconds, which is
        // far finer than a countdown needs. Assert to the millisecond rather than demanding equality.
        let snapshot = ClaudeCachedUsage.parse(json: config(limits: [scoped("Fable", 68)]))
        let resets = snapshot?.window("model_scoped:Fable")?.resetsAt
        XCTAssertNotNil(resets)
        XCTAssertEqual(resets?.timeIntervalSince1970 ?? 0, 1_784_329_199.679456, accuracy: 0.001)
    }

    func testResetWithoutFractionalSecondsParses() {
        let snapshot = ClaudeCachedUsage.parse(json: config(
            limits: [scoped("Fable", 68, resets: "2026-09-02T12:09:00+00:00")]))
        XCTAssertEqual(snapshot?.window("model_scoped:Fable")?.resetsAt,
                       Date(timeIntervalSince1970: 1_788_350_940))
    }

    func testUnparseableResetYieldsNilRatherThanAWrongDate() {
        let snapshot = ClaudeCachedUsage.parse(json: config(
            limits: [scoped("Fable", 68, resets: "not-a-date")]))
        XCTAssertEqual(snapshot?.window("model_scoped:Fable")?.percent, 68)
        XCTAssertNil(snapshot?.window("model_scoped:Fable")?.resetsAt)
    }

    func testNonScopedKindsAreIgnored() {
        // The plain "weekly" entry duplicates seven_day; only weekly_scoped entries are per-model.
        let snapshot = ClaudeCachedUsage.parse(json: config(
            limits: [scoped("Fable", 41, kind: "weekly"), scoped("Fable", 68)]))
        XCTAssertEqual(snapshot?.windows.filter { $0.key.hasPrefix("model_scoped:") }.count, 1)
        XCTAssertEqual(snapshot?.window("model_scoped:Fable")?.percent, 68)
    }

    func testEntryWithoutAModelNameIsIgnored() {
        var noModel = scoped("Fable", 68)
        noModel["scope"] = ["model": ["display_name": ""]]
        XCTAssertNil(ClaudeCachedUsage.parse(json: config(limits: [noModel])))
    }

    func testEveryScopedModelIsCarried() {
        let snapshot = ClaudeCachedUsage.parse(json: config(
            limits: [scoped("Fable", 68), scoped("Haiku", 12)]))
        XCTAssertEqual(snapshot?.windows.map(\.key).filter { $0.hasPrefix("model_scoped:") },
                       ["model_scoped:Fable", "model_scoped:Haiku"])
    }

    // MARK: - Fixed windows

    func testFixedWindowsUseUtilizationNotUsedPercentage() {
        let snapshot = ClaudeCachedUsage.parse(json: config(fixed: [
            "five_hour": window(32, resets: "2026-08-30T18:27:00+00:00"),
            "seven_day": ["used_percentage": NSNumber(value: 99)]   // wrong field: must be ignored
        ]))
        XCTAssertEqual(snapshot?.fiveHourPercent, 32)
        XCTAssertNil(snapshot?.sevenDayPercent)
    }

    func testObservedAtComesFromFetchedAt() {
        let snapshot = ClaudeCachedUsage.parse(json: config(limits: [scoped("Fable", 68)]))
        XCTAssertEqual(snapshot?.observedAt, Date(timeIntervalSince1970: fetchedAtMs / 1000))
    }

    // MARK: - Rejection

    func testCacheForAnotherAccountIsRejected() {
        XCTAssertNil(ClaudeCachedUsage.parse(json: config(
            limits: [scoped("Fable", 68)], accountUuid: "acct-1", oauthUuid: "acct-2")))
    }

    func testMissingKeyOrEmptyPayloadReturnsNil() {
        XCTAssertNil(ClaudeCachedUsage.parse(json: [:]))
        XCTAssertNil(ClaudeCachedUsage.parse(json: ["cachedUsageUtilization": [:]]))
        XCTAssertNil(ClaudeCachedUsage.parse(json: config()))
        XCTAssertNil(ClaudeCachedUsage.load(from: URL(fileURLWithPath: "/nonexistent/.claude.json")))
    }

    func testZeroFetchedAtIsRejected() {
        var json = config(limits: [scoped("Fable", 68)])
        var cache = json["cachedUsageUtilization"] as! [String: Any]
        cache["fetchedAtMs"] = NSNumber(value: 0)
        json["cachedUsageUtilization"] = cache
        XCTAssertNil(ClaudeCachedUsage.parse(json: json))
    }

    // MARK: - Account context for the desktop history

    func testAccountContextCarriesOrganizationAndALapsedWeeklyReset() {
        // The cache's percentages lapsed weeks ago; its weekly reset still fixes the anchor.
        var json = config(fixed: ["seven_day": window(20, resets: "2026-09-09T00:00:00.230141+00:00")])
        json["oauthAccount"] = ["accountUuid": "acct-1", "organizationUuid": "org-1"]
        let context = ClaudeCachedUsage.accountContext(json: json)
        XCTAssertEqual(context.organizationUUID, "org-1")
        XCTAssertEqual(context.weeklyResetAnchor?.timeIntervalSince1970 ?? 0,
                       ISO8601DateFormatter().date(from: "2026-09-09T00:00:00Z")!.timeIntervalSince1970 + 0.230141,
                       accuracy: 0.001)
    }

    func testAnotherAccountsCacheSetsNoAnchor() {
        var json = config(fixed: ["seven_day": window(20, resets: "2026-09-09T00:00:00+00:00")],
                          accountUuid: "acct-1", oauthUuid: "acct-2")
        json["oauthAccount"] = ["accountUuid": "acct-2", "organizationUuid": "org-2"]
        let context = ClaudeCachedUsage.accountContext(json: json)
        XCTAssertNil(context.weeklyResetAnchor)
        XCTAssertEqual(context.organizationUUID, "org-2")
    }

    func testNoAccountNoContext() {
        XCTAssertEqual(ClaudeCachedUsage.accountContext(json: [:]), .init())
    }

    func testTheOrganizationRecordedAtFetchBeatsTheFlippingConfig() {
        XCTAssertEqual(ClaudeCachedUsage.claudeCodeOrganization(recordedAtFetch: "team", inConfigNow: "max"), "team")
        XCTAssertEqual(ClaudeCachedUsage.claudeCodeOrganization(recordedAtFetch: nil, inConfigNow: "max"), "max")
        XCTAssertNil(ClaudeCachedUsage.claudeCodeOrganization(recordedAtFetch: nil, inConfigNow: nil))
    }

    func testTheContextCarriesTheProfileTimeAndTheCachesOwnTimes() {
        // Read together, from one read: which fetch `oauthAccount` is from, and the cache's own
        // timestamp and resets — what a run is judged by.
        var json = config(fixed: [
            "five_hour": window(10, resets: "2026-10-28T09:00:00+00:00"),
            "seven_day": window(0, resets: "2026-11-03T05:00:00+00:00")
        ])
        json["oauthAccount"] = ["accountUuid": "acct-1", "organizationUuid": "org-1",
                                "profileFetchedAt": NSNumber(value: 1_793_168_447_270.0)]
        let context = ClaudeCachedUsage.accountContext(json: json)
        XCTAssertEqual(context.profileFetchedAt, Date(timeIntervalSince1970: 1_793_168_447.270))
        XCTAssertEqual(context.cacheFetchedAt, Date(timeIntervalSince1970: fetchedAtMs / 1000))
        XCTAssertEqual(context.fiveHourReset, ISO8601DateFormatter().date(from: "2026-10-28T09:00:00Z"))
        XCTAssertEqual(context.weeklyResetAnchor, ISO8601DateFormatter().date(from: "2026-11-03T05:00:00Z"))
        // Another login's cache says nothing about this account's.
        var other = json
        other["oauthAccount"] = ["accountUuid": "acct-2", "organizationUuid": "org-1"]
        let otherContext = ClaudeCachedUsage.accountContext(json: other)
        XCTAssertNil(otherContext.cacheFetchedAt)
        XCTAssertNil(otherContext.fiveHourReset)
    }

    // MARK: - A window with no reset expires

    func testANullResetExpiresAfterItsWindowsLength() throws {
        // Measured 2026-10-28: `five_hour` cached at 0 % with `resets_at: null` — it stayed on the
        // card forever. Now five hours from the fetch, a week for the weekly windows.
        let fetched = Date(timeIntervalSince1970: fetchedAtMs / 1000)
        var nullReset = window(0, resets: nil)
        nullReset["resets_at"] = NSNull()
        let snapshot = try XCTUnwrap(ClaudeCachedUsage.parse(json: config(
            limits: [scoped("Fable", 12, resets: nil)],
            fixed: ["five_hour": nullReset, "seven_day": window(3, resets: nil),
                    "seven_day_opus": window(9, resets: "2026-11-03T05:00:00+00:00")])))
        XCTAssertEqual(snapshot.window("five_hour")?.notAfter, fetched.addingTimeInterval(5 * 3600))
        XCTAssertEqual(snapshot.window("seven_day")?.notAfter, fetched.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(snapshot.window("model_scoped:Fable")?.notAfter, fetched.addingTimeInterval(7 * 86_400))
        XCTAssertNil(snapshot.window("seven_day_opus")?.notAfter, "a reported reset needs no other bound")
        XCTAssertEqual(snapshot.fiveHourDisplayPercent(now: fetched.addingTimeInterval(5 * 3600 - 1)), 0)
        XCTAssertNil(snapshot.fiveHourDisplayPercent(now: fetched.addingTimeInterval(5 * 3600)))
    }

    // MARK: - A read caught mid-write

    func testAHalfWrittenFileIsUnreadableNotEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claude-json-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(".claude.json")
        try Data(#"{"cachedUsageUtilization": {"fetchedAtMs": 17"#.utf8).write(to: url)
        XCTAssertTrue(ClaudeCachedUsage.read(from: url).unreadable, "the caller keeps what it read last")
        XCTAssertFalse(ClaudeCachedUsage.read(from: directory.appendingPathComponent("missing.json")).unreadable,
                       "a missing file is nothing to keep")
        try JSONSerialization.data(withJSONObject: config(limits: [scoped("Fable", 68)])).write(to: url)
        let read = ClaudeCachedUsage.read(from: url)
        XCTAssertFalse(read.unreadable)
        XCTAssertEqual(read.snapshot?.window("model_scoped:Fable")?.percent, 68)
    }

    func testThePlanTypeIsCarriedAndNamed() {
        var json = config(fixed: [:])
        json["oauthAccount"] = ["accountUuid": "acct-1", "organizationUuid": "org-1", "organizationType": "claude_team"]
        XCTAssertEqual(ClaudeCachedUsage.accountContext(json: json).organizationType, "claude_team")
        XCTAssertEqual(ClaudeCachedUsage.planName(organizationType: "claude_max"), "Max")
        XCTAssertEqual(ClaudeCachedUsage.planName(organizationType: "claude_team"), "Team")
        XCTAssertNil(ClaudeCachedUsage.planName(organizationType: "something_new"))
        XCTAssertNil(ClaudeCachedUsage.planName(organizationType: nil))
    }
}
