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

/// The Cursor billing-cycle bars. The split and period-usage fixtures follow third-party reports of
/// the response shapes (ClaudeBar issue 303 for `usage-summary`, paseo PR 3717 for
/// `GetCurrentPeriodUsage` and the single-pool plans); the enterprise fixtures are synthetic. No live
/// Cursor response was read, so these pin Kannu's reading of those shapes, not Cursor's API.
///
/// Not covered by any test: copying the bars into `UsageSnapshot` (`CursorUsageProvider`), the
/// background poll's pass-through (`UsageAlertManager`) and the card itself (`NotchLLMUsageView`,
/// "Billing cycle") — those files are not in the logic test target.
final class CursorPlanUsageTests: XCTestCase {
    private func object(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - usage-summary

    func testTheSplitMakesAutoTheCycleBarAndAPIAnExtra() throws {
        let root = try object(#"""
        {"billingCycleStart":"2026-10-01T00:00:00.000Z","billingCycleEnd":"2026-11-01T00:00:00.000Z",
         "membershipType":"pro_plus","limitType":"user",
         "individualUsage":{
           "plan":{"enabled":true,"used":1790,"limit":4000,"remaining":2210,
                   "breakdown":{"included":1790,"bonus":0,"total":1790},
                   "autoPercentUsed":39.9,"apiPercentUsed":97.2,"totalPercentUsed":44.7},
           "onDemand":{"enabled":false,"used":0,"limit":null,"remaining":null}}}
        """#)

        let usage = try XCTUnwrap(CursorPlanUsage.fromUsageSummary(root))

        XCTAssertEqual(usage.cyclePercent, 39.9, accuracy: 0.001)
        XCTAssertTrue(usage.cycleIsAuto)
        XCTAssertEqual(try XCTUnwrap(usage.apiPercent), 97.2, accuracy: 0.001,
                       "the blended 44.7 must not hide an API pool that is nearly spent")
    }

    func testWithoutTheSplitTheTotalIsTheCycleBar() throws {
        let root = try object(#"""
        {"individualUsage":{"plan":{"enabled":true,"used":1790,"limit":4000,"totalPercentUsed":44.7}}}
        """#)

        let usage = try XCTUnwrap(CursorPlanUsage.fromUsageSummary(root))

        XCTAssertEqual(usage.cyclePercent, 44.7, accuracy: 0.001)
        XCTAssertFalse(usage.cycleIsAuto)
        XCTAssertNil(usage.apiPercent)
    }

    func testWithoutAnyPercentTheTotalIsDerivedFromSpend() throws {
        let root = try object(#"""
        {"individualUsage":{"plan":{"enabled":true,"used":1200,"limit":2000,"remaining":800}}}
        """#)

        let usage = try XCTUnwrap(CursorPlanUsage.fromUsageSummary(root))

        XCTAssertEqual(usage.cyclePercent, 60.0, accuracy: 0.001)
        XCTAssertFalse(usage.cycleIsAuto)
    }

    func testAnAPIPercentAloneIsNotACycleBar() throws {
        let root = try object(#"""
        {"individualUsage":{"plan":{"enabled":true,"apiPercentUsed":12.5}}}
        """#)

        XCTAssertNil(CursorPlanUsage.fromUsageSummary(root))
    }

    /// Enterprise: no `plan` object, and `overall.limit` is null. Nothing usable — no percentage,
    /// no crash, and no zero bar pretending the cycle is untouched. Synthetic fixture: neither
    /// third-party source shows an enterprise response; the shape comes from the task description.
    func testAnEnterpriseSummaryWithANullLimitHasNoCycleBar() throws {
        let root = try object(#"""
        {"membershipType":"enterprise",
         "individualUsage":{
           "overall":{"enabled":true,"used":52340,"limit":null,"remaining":null},
           "onDemand":{"enabled":true,"used":52340,"limit":null,"remaining":null}},
         "teamUsage":{"pooled":{"enabled":true,"used":901234,"limit":null,"remaining":null}}}
        """#)

        XCTAssertNil(CursorPlanUsage.fromUsageSummary(root))
    }

    /// Synthetic fixture, as above.
    func testAnEnterpriseSummaryFallsBackToAUsableTeamPool() throws {
        let root = try object(#"""
        {"individualUsage":{"overall":{"enabled":true,"used":52340,"limit":null}},
         "teamUsage":{"pooled":{"enabled":true,"used":250000,"limit":1000000}}}
        """#)

        let usage = try XCTUnwrap(CursorPlanUsage.fromUsageSummary(root))

        XCTAssertEqual(usage.cyclePercent, 25.0, accuracy: 0.001)
        XCTAssertFalse(usage.cycleIsAuto)
    }

    func testAnEmptySummaryHasNoCycleBar() throws {
        XCTAssertNil(CursorPlanUsage.fromUsageSummary(try object("{}")))
    }

    // MARK: - GetCurrentPeriodUsage

    func testThePeriodUsageSplitIsReadFromPlanUsage() throws {
        let root = try object(#"""
        {"billingCycleStart":"1759276800000","billingCycleEnd":"1761955200000",
         "planUsage":{"totalSpend":1956,"includedSpend":1956,"remaining":2044,"limit":4000,
                      "autoPercentUsed":48.9,"apiPercentUsed":0.8,"totalPercentUsed":41.2}}
        """#)
        let planUsage = try XCTUnwrap(root["planUsage"] as? [String: Any])

        let usage = try XCTUnwrap(CursorPlanUsage.parse(planUsage))

        XCTAssertEqual(usage.cyclePercent, 48.9, accuracy: 0.001)
        XCTAssertTrue(usage.cycleIsAuto)
        XCTAssertEqual(try XCTUnwrap(usage.apiPercent), 0.8, accuracy: 0.001)
    }

    func testAPeriodUsageWithoutTheSplitDerivesTheTotalFromIncludedSpend() throws {
        let planUsage = try object(#"{"totalSpend":3000,"includedSpend":1000,"limit":4000}"#)

        let usage = try XCTUnwrap(CursorPlanUsage.parse(planUsage))

        XCTAssertEqual(usage.cyclePercent, 25.0, accuracy: 0.001, "includedSpend is preferred over totalSpend")
        XCTAssertNil(usage.apiPercent)
    }

    // MARK: - Single-pool plans

    /// paseo PR 3717 shows a Start plan that still sends the split: the blended total is the bar.
    func testASinglePoolPlanUsesTheTotalEvenWhenTheSplitIsSent() throws {
        let root = try object(#"""
        {"membershipType":"Start",
         "individualUsage":{"plan":{"enabled":true,"autoPercentUsed":12,"apiPercentUsed":3,"totalPercentUsed":18.4}}}
        """#)

        let usage = try XCTUnwrap(CursorPlanUsage.fromUsageSummary(root))

        XCTAssertEqual(usage.cyclePercent, 18.4, accuracy: 0.001)
        XCTAssertFalse(usage.cycleIsAuto)
        XCTAssertNil(usage.apiPercent, "one pool, so no API bar")
        XCTAssertTrue(CursorPlanUsage.isSinglePoolPlan(" express "))
        XCTAssertFalse(CursorPlanUsage.isSinglePoolPlan("pro_plus"))
        XCTAssertFalse(CursorPlanUsage.isSinglePoolPlan(nil))
    }

    func testASinglePoolPlanWithoutATotalStillReadsTheSplit() throws {
        let planUsage = try object(#"{"autoPercentUsed":12,"apiPercentUsed":3}"#)

        let usage = try XCTUnwrap(CursorPlanUsage.parse(planUsage, membershipType: "start"))

        XCTAssertEqual(usage.cyclePercent, 12.0, accuracy: 0.001)
        XCTAssertTrue(usage.cycleIsAuto)
    }

    // MARK: - Bars

    func testTheSplitBarsAreAutoThenAPIEachOnItsOwnKey() {
        let usage = CursorPlanUsage(cyclePercent: 39.9, cycleIsAuto: true, apiPercent: 97.2)

        XCTAssertEqual(usage.mainBar, .init(key: "auto", label: "Auto", percent: 39.9))
        XCTAssertEqual(usage.extraBars, [.init(key: "api", label: "API", percent: 97.2)])
    }

    /// The blended total keeps the "week" key, so its forecast series and push carry on as before,
    /// and the Auto pool never continues a series of blended readings.
    func testTheBlendedBarKeepsTheWeekKeyAndTheDefaultLabel() {
        let usage = CursorPlanUsage(cyclePercent: 44.7, cycleIsAuto: false, apiPercent: nil)

        XCTAssertEqual(usage.mainBar, .init(key: "week", label: nil, percent: 44.7))
        XCTAssertTrue(usage.extraBars.isEmpty)
        XCTAssertNotEqual(CursorPlanUsage.autoKey, CursorPlanUsage.totalKey)
    }

    // MARK: - Numbers

    func testNumericStringsCountAndBooleansAndNullsDoNot() throws {
        XCTAssertEqual(try XCTUnwrap(CursorPlanUsage.parse(try object(#"{"autoPercentUsed":"39.9"}"#))).cyclePercent,
                       39.9, accuracy: 0.001)
        XCTAssertNil(CursorPlanUsage.parse(try object(#"{"totalPercentUsed":true}"#)))
        XCTAssertNil(CursorPlanUsage.parse(try object(#"{"totalPercentUsed":null,"limit":null,"used":10}"#)))
    }
}
