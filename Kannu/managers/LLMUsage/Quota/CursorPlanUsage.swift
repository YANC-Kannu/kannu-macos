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

/// Cursor's included usage for the current billing cycle, as plain percentages.
///
/// Cursor splits included usage into two pools — Auto (`autoPercentUsed`) and API
/// (`apiPercentUsed`, named third-party models) — next to the blended `totalPercentUsed`. The blend
/// can sit at 45 % while the API pool is at 97 %, so the split wins whenever Cursor reports it and
/// the total is only the fallback — except on a single-pool plan, where the blend is the real cap.
/// Field names come from third-party reports (ClaudeBar issue 303 for `usage-summary`'s
/// `individualUsage.plan`, paseo PR 3717 for `GetCurrentPeriodUsage`'s `planUsage` and the
/// single-pool plan names); no live response was read to write this.
///
/// Foundation-only on purpose, so the test target can compile it without the networking client.
struct CursorPlanUsage: Equatable {
    /// The main billing-cycle bar: the Auto pool when the split is reported, else the blended total.
    let cyclePercent: Double
    /// True when `cyclePercent` is the Auto pool rather than the blended total.
    let cycleIsAuto: Bool
    /// The API pool, when reported.
    let apiPercent: Double?

    /// One bar on the Cursor card, as plain values. `key` is also the alert and forecast reading
    /// key, so the Auto pool and the blended total never share a forecast series.
    struct Bar: Equatable {
        let key: String
        /// Nil keeps the card's default label.
        let label: String?
        let percent: Double
    }

    /// The reading key of the blended total, the key every earlier build used for Cursor's cycle.
    static let totalKey = "week"
    static let autoKey = "auto"
    static let apiKey = "api"

    /// The main billing-cycle bar: "Auto" when it is the Auto pool, unlabelled when it is the blend.
    var mainBar: Bar {
        cycleIsAuto
            ? Bar(key: Self.autoKey, label: String(localized: "Auto"), percent: cyclePercent)
            : Bar(key: Self.totalKey, label: nil, percent: cyclePercent)
    }

    /// The bars after the main one: the API pool, when reported.
    var extraBars: [Bar] {
        apiPercent.map { [Bar(key: Self.apiKey, label: String(localized: "API"), percent: $0)] } ?? []
    }

    /// Plans with one included pool, after paseo PR 3717 (`SINGLE_POOL_PLAN_NAMES`). Paseo matches
    /// `GetPlanInfo`'s `planName`; Kannu has only `usage-summary`'s `membershipType`, and whether it
    /// spells these plans the same way is unverified.
    static let singlePoolPlans: Set<String> = ["start", "express"]

    static func isSinglePoolPlan(_ membershipType: String?) -> Bool {
        guard let name = membershipType?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return singlePoolPlans.contains(name)
    }

    /// Reads one plan-usage object (`individualUsage.plan`, `individualUsage.overall`,
    /// `teamUsage.pooled` or `planUsage`). Nil when it carries no usable main figure — an
    /// enterprise `overall` whose `limit` is null, for one. On a single-pool plan the blended total
    /// is the bar even when the split is sent, and no API bar is shown.
    static func parse(_ planUsage: [String: Any], membershipType: String? = nil) -> CursorPlanUsage? {
        if isSinglePoolPlan(membershipType), let total = totalPercent(from: planUsage) {
            return CursorPlanUsage(cyclePercent: total, cycleIsAuto: false, apiPercent: nil)
        }
        let auto = percent(planUsage["autoPercentUsed"])
        let api = percent(planUsage["apiPercentUsed"])
        guard let cycle = auto ?? totalPercent(from: planUsage) else { return nil }
        return CursorPlanUsage(cyclePercent: cycle, cycleIsAuto: auto != nil, apiPercent: api)
    }

    /// Reads a `usage-summary` response: the individual plan first, then `overall`, then the team
    /// pool. Enterprise accounts send no `plan` and a null `overall.limit`; that reads as nil here
    /// rather than as a bogus percentage, and on-demand spend is shown on its own.
    static func fromUsageSummary(_ root: [String: Any]) -> CursorPlanUsage? {
        let membershipType = root["membershipType"] as? String
        let individual = root["individualUsage"] as? [String: Any]
        if let plan = individual?["plan"] as? [String: Any], let usage = parse(plan, membershipType: membershipType) {
            return usage
        }
        if let overall = individual?["overall"] as? [String: Any],
           let usage = parse(overall, membershipType: membershipType) {
            return usage
        }
        if let pooled = (root["teamUsage"] as? [String: Any])?["pooled"] as? [String: Any] {
            return parse(pooled, membershipType: membershipType)
        }
        return nil
    }

    /// The blended percent: `totalPercentUsed`, else derived from the spend and limit fields.
    static func totalPercent(from planUsage: [String: Any]) -> Double? {
        if let percent = percent(planUsage["totalPercentUsed"]) {
            return percent
        }
        if let limit = number(planUsage["limit"]), limit > 0 {
            let included = number(planUsage["includedSpend"])
                ?? number(planUsage["totalSpend"])
                ?? number(planUsage["used"])
            if let included {
                return min((included / limit) * 100, 100)
            }
            if let remaining = number(planUsage["remaining"]) {
                return min(((limit - remaining) / limit) * 100, 100)
            }
        }
        return nil
    }

    private static func percent(_ value: Any?) -> Double? {
        guard let percent = number(value), percent.isFinite else { return nil }
        return percent
    }

    /// Accepts numbers or numeric strings, mirroring `CursorAPIHelpers.parseDouble` without
    /// depending on it. A JSON `null` (`NSNull`) and a boolean are not numbers.
    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.doubleValue
        case let string as String:
            return Double(string.trimmingCharacters(in: .whitespaces))
        default:
            return nil
        }
    }
}
