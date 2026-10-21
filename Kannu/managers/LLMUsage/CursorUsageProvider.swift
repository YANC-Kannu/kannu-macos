import Foundation

struct CursorUsageProvider: UsageProvider {
    let id: ProviderID = .cursor
    let session: URLSession
    let quotaClient: CursorQuotaClient
    let eventsClient: CursorUsageEventsClient

    init(
        session: URLSession = URLSession(configuration: .ephemeral),
        quotaClient: CursorQuotaClient? = nil,
        eventsClient: CursorUsageEventsClient? = nil
    ) {
        self.session = session
        self.quotaClient = quotaClient ?? CursorQuotaClient(session: session)
        self.eventsClient = eventsClient ?? CursorUsageEventsClient(session: session)
    }

    func fetchSnapshot(now: Date, interactive: Bool) async throws -> UsageSnapshot {
        let quota = await quotaClient.fetchLimits()

        if var eventsSnapshot = await eventsClient.fetchSnapshot(now: now) {
            eventsSnapshot.sessionLimit = eventsSnapshot.sessionLimit ?? quota.session
            eventsSnapshot.weekLimit = eventsSnapshot.weekLimit ?? quota.week
            eventsSnapshot.weekLimitLabel = quota.weekLabel
            eventsSnapshot.weekLimitKey = quota.weekKey
            eventsSnapshot.extraLimits = quota.extraLimits
            eventsSnapshot.onDemandSpendUSD = quota.onDemandSpendUSD
            eventsSnapshot.quotaError = quota.errorMessage
            eventsSnapshot.accountTier = quota.accountTier
            return eventsSnapshot
        }

        if quota.hasLimits || quota.onDemandSpendUSD != nil {
            var snapshot = UsageSnapshot()
            snapshot.sessionLimit = quota.session
            snapshot.weekLimit = quota.week
            snapshot.weekLimitLabel = quota.weekLabel
            snapshot.weekLimitKey = quota.weekKey
            snapshot.extraLimits = quota.extraLimits
            snapshot.onDemandSpendUSD = quota.onDemandSpendUSD
            snapshot.quotaError = quota.errorMessage
            snapshot.accountTier = quota.accountTier
            snapshot.logsUnavailable = true
            snapshot.lastUpdated = now
            return snapshot
        }

        throw UsageError.notConfigured(quota.errorMessage ?? "Cursor not signed in")
    }
}
