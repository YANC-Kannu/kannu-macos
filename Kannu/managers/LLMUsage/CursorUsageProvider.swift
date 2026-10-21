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
        // One token read for the whole refresh, shared by the quota, events and legacy requests.
        try await CursorTokenStore.withSingleRead(interactive: interactive) {
            try await snapshot(now: now, interactive: interactive)
        }
    }

    private func snapshot(now: Date, interactive: Bool) async throws -> UsageSnapshot {
        let quota = await quotaClient.fetchLimits(interactive: interactive)

        if var eventsSnapshot = await eventsClient.fetchSnapshot(now: now) {
            eventsSnapshot.sessionLimit = eventsSnapshot.sessionLimit ?? quota.session
            eventsSnapshot.weekLimit = eventsSnapshot.weekLimit ?? quota.week
            eventsSnapshot.weekLimitLabel = quota.weekLabel
            eventsSnapshot.weekLimitKey = quota.weekKey
            eventsSnapshot.extraLimits = quota.extraLimits
            eventsSnapshot.onDemandSpendUSD = quota.onDemandSpendUSD
            eventsSnapshot.quotaError = quota.errorMessage
            eventsSnapshot.quotaAction = quota.action
            eventsSnapshot.accountTier = quota.accountTier
            return eventsSnapshot
        }

        // A fix-it button keeps the card, as Codex's does: throwing here would hide the only way
        // to approve the keychain read.
        if quota.hasLimits || quota.onDemandSpendUSD != nil || quota.action != nil {
            var snapshot = UsageSnapshot()
            snapshot.sessionLimit = quota.session
            snapshot.weekLimit = quota.week
            snapshot.weekLimitLabel = quota.weekLabel
            snapshot.weekLimitKey = quota.weekKey
            snapshot.extraLimits = quota.extraLimits
            snapshot.onDemandSpendUSD = quota.onDemandSpendUSD
            snapshot.quotaError = quota.errorMessage
            snapshot.quotaAction = quota.action
            snapshot.accountTier = quota.accountTier
            snapshot.logsUnavailable = true
            snapshot.lastUpdated = now
            return snapshot
        }

        throw UsageError.notConfigured(quota.errorMessage ?? "Cursor not signed in")
    }
}
