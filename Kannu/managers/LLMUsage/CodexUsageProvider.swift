import Foundation

struct CodexUsageProvider: UsageProvider {
    let id: ProviderID = .codex
    /// `$CODEX_HOME` or `~/.codex`; rollouts are read from its `sessions` and `archived_sessions`.
    let codexHome: URL
    let quotaClient: CodexQuotaClient

    init(codexHome: URL = CodexRolloutFiles.codexHome(), quotaClient: CodexQuotaClient = CodexQuotaClient()) {
        self.codexHome = codexHome
        self.quotaClient = quotaClient
    }

    func fetchSnapshot(now: Date, interactive: Bool) async throws -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        snapshot.lastUpdated = now

        let listing = CodexRolloutFiles.listing(codexHome: codexHome)
        if listing.hasLogs {
            // Same rule as the Claude provider, from the same constant: skip files too old to
            // contribute, but decide `logsUnavailable` from the unfiltered listing, compressed
            // rollouts included.
            snapshot = JSONLUsageParser.aggregate(
                records: CodexRolloutFiles.recentRecords(in: listing, now: now),
                now: now
            )
        } else {
            snapshot.logsUnavailable = true
        }
        // Tokens only, as for Claude. The pricing table has one input rate and no cached-input
        // rate, and most of a Codex request's input is cached, so an estimate would bill that
        // cached bulk at the full rate; on a ChatGPT plan no dollars are billed per token at all.
        snapshot.billedCostOnly = true

        let quota = await quotaClient.fetchLimits(interactive: interactive)
        snapshot.sessionLimit = quota.session
        snapshot.weekLimit = quota.week
        snapshot.quotaError = quota.errorMessage
        snapshot.quotaAction = quota.action
        snapshot.accountTier = quota.accountTier
        snapshot.isAuthFailure = quota.isAuthFailure

        if snapshot.logsUnavailable && !quota.hasLimits && quota.action == nil {
            throw UsageError.notConfigured("Sign in to Codex locally (~/.codex/auth.json) to show quota.")
        }

        return snapshot
    }
}
