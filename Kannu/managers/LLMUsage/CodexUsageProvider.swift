import Foundation

struct CodexUsageProvider: UsageProvider {
    let id: ProviderID = .codex
    /// `$CODEX_HOME` or `~/.codex`; rollouts are read from its `sessions` and `archived_sessions`.
    let codexHome: URL
    let quotaClient: CodexQuotaClient
    /// A reference shared by every copy of this provider, so what was read survives between refreshes.
    private let usageCache = JSONLUsageCache(label: "codex", format: .codex)

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
            // rollouts included. The cache reads each rollout with the stateful Codex reader and
            // keeps that reader's state between refreshes, so only appended lines are read.
            snapshot = await JSONLUsageParser.aggregate(
                files: UsageWindows.recentlyModified(listing.plain, now: now),
                now: now,
                cache: usageCache
            )
        } else {
            snapshot.logsUnavailable = true
        }
        // Tokens only, as for Claude. The pricing table has one input rate and no cached-input
        // rate, and most of a Codex request's input is cached, so an estimate would bill that
        // cached bulk at the full rate; on a ChatGPT plan no dollars are billed per token at all.
        snapshot.billedCostOnly = true

        let quota = await quotaClient.fetchLimits(interactive: interactive, foreground: true, listing: listing)
        snapshot.sessionLimit = quota.session
        snapshot.weekLimit = quota.week
        snapshot.extraLimits = quota.extraLimits
        snapshot.quotaObservedAt = quota.observedAt
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
