import Foundation
import os

struct CursorQuotaClient {
    private static let log = os.Logger(subsystem: "com.kannu.app", category: "CursorQuota")
    let session: URLSession
    init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    /// `interactive` is true only for a refresh the user asked for (see `CursorTokenStore`). The
    /// background poll calls this directly, so it opens its own single-read scope; inside the
    /// provider's refresh that scope is reused.
    func fetchLimits(interactive: Bool = false) async -> QuotaFetchResult {
        await CursorTokenStore.withSingleRead(interactive: interactive) { await limits() }
    }

    private func limits() async -> QuotaFetchResult {
        guard CursorTokenStore.accessToken() != nil else {
            // Without this a cursor-agent user whose only sign-in is the keychain item had no way
            // to approve the read: nothing else asks for an interactive Cursor refresh.
            if CursorTokenStore.keychainNeedsApproval() {
                Self.log.notice("cursor-access-token keychain item needs approval; not prompting outside a user-initiated refresh")
                return QuotaFetchResult(
                    errorMessage: String(localized: "Cursor keeps its sign-in in the keychain. Allow access to show usage limits."),
                    action: .grantCursorKeychainAccess
                )
            }
            Self.log.notice("no Cursor access token in Keychain or state.vscdb")
            return QuotaFetchResult(errorMessage: "Cursor not signed in")
        }

        var result = QuotaFetchResult()

        let summary = await fetchUsageSummary()
        if let summary {
            summary.cycle.apply(to: &result)
            result.onDemandSpendUSD = summary.onDemandSpendUSD
            result.accountTier = summary.accountTier
        }

        if result.week == nil, let connect = await fetchConnectLimits(membershipType: summary?.membershipType) {
            connect.apply(to: &result)
        }

        if result.week == nil && result.onDemandSpendUSD == nil {
            result.errorMessage = "Cursor quota unavailable"
        }

        return result
    }

    private struct UsageSummaryData: Equatable {
        var cycle: CycleLimits
        var onDemandSpendUSD: Double?
        var accountTier: String?
        /// Raw, for the single-pool check; `accountTier` is the display form.
        var membershipType: String?
    }

    /// The billing-cycle bars `CursorPlanUsage` decided on, as usage limits. Both pools reset at
    /// the cycle's end.
    private struct CycleLimits: Equatable {
        var main: CursorPlanUsage.Bar?
        var extras: [CursorPlanUsage.Bar] = []
        var resetsAt: Date?

        init(_ usage: CursorPlanUsage?, resetsAt: Date?) {
            main = usage?.mainBar
            extras = usage?.extraBars ?? []
            self.resetsAt = resetsAt
        }

        var hasMainBar: Bool { main != nil }

        func apply(to result: inout QuotaFetchResult) {
            guard let main else { return }
            result.week = UsageLimit(used: main.percent, limit: 100, resetsAt: resetsAt)
            result.weekKey = main.key
            result.weekLabel = main.label
            result.extraLimits = extras.map {
                NamedLimit(key: $0.key, limit: UsageLimit(used: $0.percent, limit: 100, resetsAt: resetsAt), label: $0.label)
            }
        }
    }

    private func fetchConnectLimits(membershipType: String?) async -> CycleLimits? {
        do {
            let (data, http) = try await CursorAPIHelpers.connectRequest(
                path: "/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
                session: session
            )
            guard (200..<300).contains(http.statusCode) else {
                Self.log.error("GetCurrentPeriodUsage HTTP \(http.statusCode)")
                return nil
            }
            guard let root = CursorAPIHelpers.parseJSONObject(data) else {
                Self.log.error("GetCurrentPeriodUsage invalid JSON (\(data.count) bytes)")
                return nil
            }
            guard let planUsage = root["planUsage"] as? [String: Any],
                  let usage = CursorPlanUsage.parse(planUsage, membershipType: membershipType) else {
                Self.log.error("GetCurrentPeriodUsage missing usable planUsage")
                return nil
            }
            return CycleLimits(usage, resetsAt: CursorAPIHelpers.parseTimestamp(root["billingCycleEnd"]))
        } catch {
            Self.log.error("GetCurrentPeriodUsage failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchUsageSummary() async -> UsageSummaryData? {
        guard let url = URL(string: "https://cursor.com/api/usage-summary") else { return nil }
        do {
            let (data, http) = try await CursorAPIHelpers.restRequest(url: url, session: session)
            guard (200..<300).contains(http.statusCode) else {
                Self.log.error("usage-summary HTTP \(http.statusCode)")
                return nil
            }
            guard let root = CursorAPIHelpers.parseJSONObject(data) else {
                Self.log.error("usage-summary invalid JSON")
                return nil
            }

            let individual = root["individualUsage"] as? [String: Any]
            let onDemandSpendUSD = CursorAPIHelpers.centsToUSD(
                (individual?["onDemand"] as? [String: Any])?["used"]
            )
            let cycle = CycleLimits(
                CursorPlanUsage.fromUsageSummary(root),
                resetsAt: CursorAPIHelpers.parseTimestamp(root["billingCycleEnd"])
            )

            guard cycle.hasMainBar || onDemandSpendUSD != nil else {
                Self.log.error("usage-summary missing usable quota fields")
                return nil
            }

            let membershipType = root["membershipType"] as? String
            let tier = membershipType ?? (root["subscriptionStatus"] as? String)
            return UsageSummaryData(cycle: cycle, onDemandSpendUSD: onDemandSpendUSD, accountTier: tier?.capitalized,
                                    membershipType: membershipType)
        } catch {
            Self.log.error("usage-summary failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
