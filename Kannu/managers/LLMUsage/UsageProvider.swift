import Foundation
import Defaults

enum ProviderID: String, CaseIterable, Identifiable {
    case claude, codex, cursor, antigravity
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .antigravity: return "Antigravity"
        }
    }
    var enabledKey: Defaults.Key<Bool> {
        switch self {
        case .claude: return .enableClaudeProvider
        case .codex: return .enableCodexProvider
        case .cursor: return .enableCursorProvider
        case .antigravity: return .enableAntigravityProvider
        }
    }
}

struct UsageTotals: Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var costUSD: Double = 0
    var hasUnpricedModel: Bool = false
    var totalTokens: Int { inputTokens + outputTokens }
}

struct ModelUsage: Equatable, Identifiable {
    let model: String
    let totals: UsageTotals
    var id: String { model }
}

struct UsageLimit: Equatable {
    let used: Double
    let limit: Double
    var resetsAt: Date? = nil
    /// Server-reported severity ("normal"/"warning"/"critical") when available; drives the accent.
    var severity: String? = nil
    /// When the value was read, when the source says. A Claude window can come from a desktop
    /// sample days old; the card shows that age rather than passing the number off as current.
    var observedAt: Date? = nil
    /// The latest moment the value can still describe a running window, when it has no reset
    /// (`ClaudeUsageSnapshot.Window.notAfter`); the card drops it then, as it does at a reset.
    var notAfter: Date? = nil
    var fraction: Double { limit > 0 ? min(used / limit, 1) : 0 }
}

/// A user-fixable reason a quota fetch failed, surfaced as a button in the usage card.
enum QuotaAction: Equatable {
    case grantClaudeKeychainAccess
    /// Codex's sign-in lives in the "Codex Auth" keychain item (no auth.json) and macOS wants the
    /// user to approve Kannu reading it.
    case grantCodexKeychainAccess
    /// cursor-agent's "cursor-access-token" keychain item is the only Cursor sign-in found (no
    /// state.vscdb token) and macOS wants the user to approve Kannu reading it.
    case grantCursorKeychainAccess

    /// The one provider whose refresh may prompt when the user taps the button. Every other
    /// provider in that refresh stays silent, so approving Codex never raises Cursor's dialog.
    var provider: ProviderID {
        switch self {
        case .grantClaudeKeychainAccess: return .claude
        case .grantCodexKeychainAccess: return .codex
        case .grantCursorKeychainAccess: return .cursor
        }
    }

    var buttonTitle: String {
        switch self {
        // Says what approving buys, not what it costs. Plan tier already shows without it;
        // the keychain read is only needed for live 5h/7d limits.
        case .grantClaudeKeychainAccess, .grantCodexKeychainAccess, .grantCursorKeychainAccess:
            return "Show usage limits…"
        }
    }
}

/// A rate-limit window with no dedicated field on `UsageSnapshot` — a per-model or per-surface
/// weekly cap that only some plans report. Keyed by the provider's own window name so the view can
/// label it without the model having to know every name up front.
struct NamedLimit: Equatable {
    let key: String
    let limit: UsageLimit
    /// The provider's own name for this window, preferred over anything derived from the key.
    var label: String? = nil
    /// A 5-hour window (Antigravity reports one per model pool), shown with the 5-hour bar instead
    /// of under Weekly.
    var isSessionWindow: Bool = false
}

extension NamedLimit {
    /// Severity rides on the inner limit, so views read it uniformly across session/week/extra.
    var severity: String? { limit.severity }
}

struct UsageSnapshot: Equatable {
    var session: UsageTotals = .init()
    var today: UsageTotals = .init()
    var week: UsageTotals = .init()
    var sessionLimit: UsageLimit? = nil // 5h window quota
    var weekLimit: UsageLimit? = nil // 7d all-models window quota (Cursor: the billing cycle)
    /// The provider's own name for the `weekLimit` bar (Cursor's "Auto" pool); nil keeps the
    /// view's default.
    var weekLimitLabel: String? = nil
    /// The alert and forecast reading key of the `weekLimit` bar. Cursor's Auto pool reads as
    /// "auto", so its forecast never continues a series of blended totals.
    var weekLimitKey: String = "week"
    /// What `sessionLimit` and `weekLimit` measure when it is not every model: Antigravity's quota
    /// is per model pool, and these two are its first pool's. nil reads as all models.
    var limitsLabel: String? = nil
    /// Additional rate-limit windows beyond the 5h/7d pair, in the order the provider reported them.
    var extraLimits: [NamedLimit] = []
    /// When those limits were recorded, when that is earlier than `lastUpdated` (Codex's rollout).
    var quotaObservedAt: Date? = nil
    var onDemandSpendUSD: Double? = nil // billing-cycle on-demand spend from usage-summary
    var models: [ModelUsage] = []
    var lastUpdated: Date = .distantPast
    var quotaError: String? = nil
    /// Set when the quota failure has a one-tap fix the user can trigger.
    var quotaAction: QuotaAction? = nil
    /// Locally reconstructed current 5-hour block (Claude): tokens + reset time, shown when
    /// the server-side limit gauge is unavailable. Never a percentage — no local denominator.
    var localSessionBlock: ClaudeSessionBlocks.CurrentBlock? = nil
    var logsUnavailable: Bool = false
    /// Show only provider-billed spend; never display pricing-table estimates.
    var billedCostOnly: Bool = false
    /// Account plan/tier label (e.g. "Pro", "Max") shown next to the provider name.
    var accountTier: String? = nil
    /// Set when the quota failure is a definitive auth failure (not-signed-in, 401, 403,
    /// expired token) rather than a transient error (429, 500+).
    /// Used by `isFatallyUnconfigured` to drop the card from the Usage tab.
    var isAuthFailure: Bool = false
    /// Keeps this card's forecast series apart from another organization's under the same window
    /// keys (`ClaudeUsageSnapshot.readingScope`).
    var readingScope: String? = nil
    /// Further cards of this provider: Claude's second organization.
    var extraCards: [UsageSnapshot] = []
    /// Limits and nothing else: token totals, the status row and Refresh stay on the first card.
    var limitsOnly: Bool = false

    /// True when the provider has nothing useful to show AND the reason is a definitive
    /// auth failure (not signed-in / expired token / 401 / 403) — NOT a transient error
    /// like 429 or 500. Only those cases drop the card from the Usage tab.
    var isFatallyUnconfigured: Bool {
        // A card carrying a fix-it button or an explanatory quota message must stay visible:
        // hiding it strands the user with no path to recovery.
        if quotaAction != nil || quotaError != nil { return false }
        let hasNoRealUsage = logsUnavailable
            || (today.totalTokens == 0 && week.totalTokens == 0 && session.totalTokens == 0)
        let hasNoQuota = sessionLimit == nil && weekLimit == nil
        return hasNoRealUsage && hasNoQuota && isAuthFailure
    }

    /// Short account-status note (e.g. "Out of extra credits"). Distinct from `quotaError`:
    /// this is a fact about the account, not a failure to fetch anything.
    var accountNote: String? = nil
}

struct QuotaFetchResult: Equatable {
    var session: UsageLimit?
    var week: UsageLimit?
    /// Becomes `UsageSnapshot.weekLimitLabel`.
    var weekLabel: String? = nil
    /// Becomes `UsageSnapshot.weekLimitKey`.
    var weekKey: String = "week"
    /// Windows beyond the session/week pair, as `UsageSnapshot.extraLimits` takes them: Cursor's
    /// API pool, Codex's other limit families.
    var extraLimits: [NamedLimit] = []
    var onDemandSpendUSD: Double? = nil
    var accountTier: String? = nil
    var errorMessage: String?
    var action: QuotaAction? = nil
    /// True for definitive auth failures (not-signed-in, 401, 403, expired refresh token).
    /// False for transient errors (429, 500+, network hiccup) — those should NOT move the
    /// card from the Usage tab, since the provider IS configured.
    var isAuthFailure: Bool = false
    /// When the limits were recorded, if not at the read: Codex's rollout holds the figures of
    /// the last local request. nil means now.
    var observedAt: Date? = nil

    var hasLimits: Bool { session != nil || week != nil || !extraLimits.isEmpty }
}

enum UsageResult {
    case loading
    case success(UsageSnapshot)
    case failure(String)
}

protocol UsageProvider {
    var id: ProviderID { get }
    /// True for providers that read local files (near-instant, no network).
    /// These bypass the 60-second shared throttle and refresh on every panel open.
    var isLocalFileProvider: Bool { get }
    /// `interactive` is true only for a refresh the user explicitly asked for; providers may
    /// then take steps that can show a system dialog (e.g. a cross-app keychain read).
    func fetchSnapshot(now: Date, interactive: Bool) async throws -> UsageSnapshot
}

extension UsageProvider {
    var isLocalFileProvider: Bool { false }
    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        try await fetchSnapshot(now: now, interactive: false)
    }
}
