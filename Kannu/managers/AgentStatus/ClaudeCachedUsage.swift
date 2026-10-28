import Foundation

/// Reads the usage payload Claude Code caches for itself in `~/.claude.json`.
///
/// After a successful `GET /api/oauth/usage` — which `/usage` triggers — Claude Code stores the
/// response under `cachedUsageUtilization`, and clears it on logout:
///
/// ```json
/// {"cachedUsageUtilization": {"fetchedAtMs": …, "accountUuid": "…", "utilization": {
///     "five_hour": {"utilization": 32, "resets_at": "…"},
///     "seven_day": {"utilization": 41, "resets_at": "…"},
///     "limits": [{"kind": "weekly_scoped", "percent": 68, "resets_at": "…",
///                 "scope": {"model": {"display_name": "Fable"}}}]}}}
/// ```
///
/// This is the only local source carrying **per-model weekly windows**. The statusline hook can
/// deliver them too, as `rate_limits.model_scoped`, but only while a session drives it; the desktop
/// app's history file drops them entirely. It also reports real reset timestamps, which the history
/// file forces Kannu to infer.
///
/// Reading it needs no credentials and makes no network call. Only the usage keys are touched.
enum ClaudeCachedUsage {
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    /// The fixed windows, in display order. `cinder_cove` is undocumented but present in the
    /// schema, so it is carried through generically rather than dropped.
    private static let fixedWindows = [
        "five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet",
        "seven_day_oauth_apps", "cinder_cove"
    ]

    /// The `limits[]` array names its windows by a different `kind` than the fixed-field keys.
    /// This maps a fixed key to its `limits[]` kind so a fixed bar can borrow that entry's severity.
    private static func limitsKind(forKey key: String) -> String {
        switch key {
        case "five_hour": return "session"
        case "seven_day": return "weekly_all"
        default: return key
        }
    }

    static func load(from url: URL = defaultURL) -> ClaudeUsageSnapshot? {
        read(from: url).snapshot
    }

    /// The organization Claude Code's own sign-in is on: what Kannu recorded straight after its
    /// last successful fetch, else what the file says now. The file alone flips — measured
    /// 2026-10-18, it read Max after a sign-in, Team after Claude Code's next `/usage`, and Max
    /// again once a desktop-hosted session had run.
    static func claudeCodeOrganization(recordedAtFetch: String?, inConfigNow: String?) -> String? {
        recordedAtFetch ?? inConfigNow
    }

    /// What one read of this file says about whose usage the cache holds. Ids, plan types and
    /// times only — never the account's name, email or any credential.
    ///
    /// The cache's own weekly reset stays useful long after its percentages have lapsed: each
    /// organization resets on its own fixed weekly anchor (measured 2026-10-18: a Max plan on
    /// Wednesday 00:00Z, a Team plan of the same person on Tuesday 05:00Z), so a reset weeks old
    /// still says which hour of which weekday that organization's week ends — and which
    /// organization a cache belongs to.
    struct AccountContext: Equatable {
        /// `oauthAccount.organizationUuid`. Every Claude Code process rewrites `oauthAccount` from
        /// its own copy, a desktop-hosted session's with the desktop's organization, so on its own
        /// this says nothing about the cache: `profileFetchedAt` says which fetch the copy is from.
        var organizationUUID: String?
        /// The cache's weekly (`seven_day`) reset, for this account's cache only.
        var weeklyResetAnchor: Date?
        /// `oauthAccount.organizationType` alongside the organization, e.g. "claude_max".
        var organizationType: String?
        /// `oauthAccount.profileFetchedAt`: when the profile the organization above came from was
        /// fetched.
        var profileFetchedAt: Date?
        /// `cachedUsageUtilization.fetchedAtMs`, for this account's cache only.
        var cacheFetchedAt: Date?
        /// The cache's five-hour reset; nil when no five-hour window was running.
        var fiveHourReset: Date?
    }

    /// One read of the file: the cache and the account context, taken together.
    struct ConfigRead: Equatable {
        var snapshot: ClaudeUsageSnapshot?
        var context = AccountContext()
        /// The file was there but would not parse — Claude Code rewrites it whole, so this is most
        /// often a read caught mid-write. The caller keeps what it read last instead of dropping
        /// the cache until its next read, ten minutes on.
        var unreadable = false
    }

    // MARK: Each organization's resets

    /// Where one organization's windows reset, as Claude Code's cache reported them while it was
    /// on that organization. Kept per organization (`Defaults[.claudeOrganizationResets]`, by
    /// organization id) because each has its own. Remembering only the organization Claude Code
    /// was on at the moment lost Max's reset when Claude Code moved to Team on 2026-10-28, and
    /// Claude Desktop's Max week, at 100 %, then stayed on the card about 17 hours past its reset.
    struct OrganizationResets: Codable, Equatable {
        /// One weekly reset of this organization. Any one serves as the anchor: weeks step from it
        /// in either direction (`ClaudeDesktopUsageHistory.weeklyReset(after:anchor:)`).
        var weekly: Date?
        /// The five-hour window's reset, nil when no window was running.
        var fiveHour: Date?
        /// When the cache reported these (its `fetchedAtMs`).
        var reportedAt: Date
    }

    /// How far apart two resets may be and still lie on one weekly anchor. Anchors are on the
    /// hour and differ by hours between organizations; this absorbs the fractions of a second the
    /// cache reports, and cannot join two anchors.
    static let anchorTolerance: TimeInterval = 600
    private static let week: TimeInterval = 7 * 24 * 3600
    private static let fiveHours: TimeInterval = 5 * 3600

    /// Whether two weekly resets lie on the same weekly anchor: a whole number of weeks apart.
    static func onSameWeeklyAnchor(_ a: Date, _ b: Date) -> Bool {
        let offset = abs(a.timeIntervalSince(b).truncatingRemainder(dividingBy: week))
        return offset <= anchorTolerance || week - offset <= anchorTolerance
    }

    /// The one remembered organization whose weekly anchor `reset` lies on. Nil when none does,
    /// and when several do: then the reset cannot say which.
    static func organization(onWeeklyAnchorOf reset: Date?, in resets: [String: OrganizationResets]) -> String? {
        guard let reset else { return nil }
        let matches = resets.compactMap { organization, saved in
            saved.weekly.map { onSameWeeklyAnchor(reset, $0) } == true ? organization : nil
        }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Whose usage the cache holds, for a read outside Kannu's own run: the organization whose
    /// weekly anchor its own weekly reset lies on, when exactly one remembered organization's
    /// does; else Claude Code's, unless the reset contradicts Claude Code's remembered anchor.
    /// A desktop-hosted session's `/usage` writes this cache too, with the desktop's numbers.
    static func cacheOwner(weeklyReset: Date?, claudeCode: String?,
                           resets: [String: OrganizationResets]) -> ClaudeUsageSnapshot.CacheOwner {
        if let matched = organization(onWeeklyAnchorOf: weeklyReset, in: resets) {
            return matched == claudeCode ? .claudeCode : .organization(matched)
        }
        if let claudeCode, let weeklyReset, let anchor = resets[claudeCode]?.weekly,
           !onSameWeeklyAnchor(weeklyReset, anchor) {
            return .unknown
        }
        return .claudeCode
    }

    // MARK: Kannu's own run

    /// One read of this file straight after one of Kannu's `/usage` runs: the cache's timestamp
    /// and resets and `oauthAccount`, from the same bytes, with the run's window.
    struct RunRead: Equatable {
        var context: AccountContext
        /// When the run started, and when this read was taken at its end.
        var started: Date
        var readAt: Date
    }

    /// Whose usage one run fetched, and what to remember for that organization.
    struct RunAttribution: Equatable {
        enum Evidence: String {
            /// `oauthAccount` was fetched during the run: Claude Code's own token said so.
            case profile
            /// The cache the run wrote resets on exactly one remembered organization's anchor.
            case weeklyReset
            /// Nothing new: the organization Kannu knew before the run.
            case lastKnown
            /// The cache the run wrote resets off the last known organization's anchor, and on no
            /// other remembered one: whose it is cannot be said.
            case contradicted
            /// Nothing was ever recorded: the file's organization is all there is (as before).
            case configOnly
            case none
        }
        /// Claude Code's organization after this run; nil leaves the recorded one as it is.
        var organization: String?
        /// The cache's resets, to remember under `organization` — only for a cache the run wrote.
        var resets: OrganizationResets? = nil
        var evidence: Evidence
    }

    /// Slack on both ends of a run's window: the stamps are another process's, rounded to the
    /// millisecond.
    static let runWindowSlack: TimeInterval = 2

    /// Decides whose usage a run fetched. `oauthAccount` counts only when its `profileFetchedAt`
    /// falls inside the run — a desktop-hosted session rewrites it at any time with the desktop's
    /// organization (measured 2026-10-28: it named Max, fetched 90 s after the run that recorded
    /// Team, while the cache stayed Team's). Otherwise the last known organization stands. Either
    /// way the cache the run wrote is checked against the remembered weekly anchors: its own week
    /// names its organization when exactly one anchor matches, and a profile whose own
    /// organization's anchor the cache contradicts, while another's matches, was another
    /// process's.
    static func attributeRun(_ run: RunRead, lastKnown: String?,
                             resets: [String: OrganizationResets]) -> RunAttribution {
        let window = run.started.addingTimeInterval(-runWindowSlack)...run.readAt.addingTimeInterval(runWindowSlack)
        let context = run.context
        let cacheInRun = context.cacheFetchedAt.map(window.contains) == true
        let matched = cacheInRun ? organization(onWeeklyAnchorOf: context.weeklyResetAnchor, in: resets) : nil
        let profiled = context.profileFetchedAt.map(window.contains) == true ? context.organizationUUID : nil
        func contradicts(_ organization: String) -> Bool {
            guard cacheInRun, let reset = context.weeklyResetAnchor,
                  let anchor = resets[organization]?.weekly else { return false }
            return !onSameWeeklyAnchor(reset, anchor)
        }

        var attribution = RunAttribution(organization: nil, resets: nil, evidence: .none)
        if let profiled {
            if let matched, matched != profiled, contradicts(profiled) {
                attribution = RunAttribution(organization: matched, evidence: .weeklyReset)
            } else {
                attribution = RunAttribution(organization: profiled, evidence: .profile)
            }
        } else if let matched {
            attribution = RunAttribution(organization: matched, evidence: .weeklyReset)
        } else if let lastKnown {
            attribution = contradicts(lastKnown)
                ? RunAttribution(organization: nil, evidence: .contradicted)
                : RunAttribution(organization: lastKnown, evidence: .lastKnown)
        } else if let inConfig = context.organizationUUID {
            attribution = RunAttribution(organization: inConfig, evidence: .configOnly)
        }
        if cacheInRun, let organization = attribution.organization, let fetchedAt = context.cacheFetchedAt {
            // A cache with no weekly reset keeps the anchor already known: any one week fixes it.
            attribution.resets = OrganizationResets(weekly: context.weeklyResetAnchor ?? resets[organization]?.weekly,
                                                    fiveHour: context.fiveHourReset, reportedAt: fetchedAt)
        }
        return attribution
    }

    /// The plan an organization type names, for the card's one line about organizations. Only
    /// the plan — never the organization's or the account's name.
    static func planName(organizationType: String?) -> String? {
        switch organizationType {
        case "claude_max": return "Max"
        case "claude_pro": return "Pro"
        case "claude_team": return "Team"
        case "claude_enterprise": return "Enterprise"
        default: return nil
        }
    }

    /// One read of `~/.claude.json` for both the cached usage and the account context — the file
    /// is large, and the usage cadence must not parse it twice. Blocking I/O: never on the main
    /// actor (REGRESSIONS entry 11).
    static func read(from url: URL = defaultURL) -> ConfigRead {
        guard let data = try? Data(contentsOf: url) else { return ConfigRead() }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ConfigRead(unreadable: true)
        }
        return ConfigRead(snapshot: parse(json: json), context: accountContext(json: json))
    }

    static func accountContext(json: [String: Any]) -> AccountContext {
        let account = json["oauthAccount"] as? [String: Any]
        var context = AccountContext()
        context.organizationUUID = (account?["organizationUuid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        context.organizationType = (account?["organizationType"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        context.profileFetchedAt = epochMillisecondsDate(account?["profileFetchedAt"])
        if let cache = json["cachedUsageUtilization"] as? [String: Any] {
            // Only this account's cache may say anything, as for the percentages.
            let cached = cache["accountUuid"] as? String
            let current = account?["accountUuid"] as? String
            if cached == nil || current == nil || cached == current {
                context.cacheFetchedAt = epochMillisecondsDate(cache["fetchedAtMs"])
                let utilization = cache["utilization"] as? [String: Any]
                context.weeklyResetAnchor = isoDate((utilization?["seven_day"] as? [String: Any])?["resets_at"])
                context.fiveHourReset = isoDate((utilization?["five_hour"] as? [String: Any])?["resets_at"])
            }
        }
        return context
    }

    /// The window a value with no reported reset can still describe, counted from when it was
    /// read: five hours for the five-hour window, a week for every weekly one. The cache leaves
    /// `resets_at` null for a window that is not running — measured 2026-10-28, `five_hour` was
    /// null at 0 % — and a null used to keep that 0 % on the card forever.
    static func expiryWithoutReset(key: String, observedAt: Date) -> Date {
        observedAt.addingTimeInterval(key == ClaudeUsageSnapshot.fiveHourKey ? fiveHours : week)
    }

    static func parse(json: [String: Any]) -> ClaudeUsageSnapshot? {
        guard let cache = json["cachedUsageUtilization"] as? [String: Any],
              let fetchedAtMs = (cache["fetchedAtMs"] as? NSNumber)?.doubleValue, fetchedAtMs > 0,
              let utilization = cache["utilization"] as? [String: Any] else { return nil }

        // Claude Code guards the cache by account; a mismatch means it belongs to a different login
        // and its numbers are not this user's.
        if let cached = cache["accountUuid"] as? String,
           let current = (json["oauthAccount"] as? [String: Any])?["accountUuid"] as? String,
           cached != current {
            return nil
        }

        // The fixed windows carry no severity of their own, but the parallel `limits[]` array
        // does — keyed by kind. Build that lookup once so the fixed bars can borrow it.
        let limitsArray = utilization["limits"] as? [[String: Any]] ?? []
        var severityByKind: [String: String] = [:]
        for entry in limitsArray {
            if let kind = entry["kind"] as? String,
               let severity = entry["severity"] as? String, !severity.isEmpty {
                severityByKind[kind] = severity
            }
        }

        var windows: [ClaudeUsageSnapshot.Window] = []
        let observedAt = Date(timeIntervalSince1970: fetchedAtMs / 1000)
        // A null reset expires like the desktop history's values do (`expiryWithoutReset`).
        func notAfter(_ key: String, _ resetsAt: Date?) -> Date? {
            resetsAt == nil ? expiryWithoutReset(key: key, observedAt: observedAt) : nil
        }

        for key in fixedWindows {
            guard let bucket = utilization[key] as? [String: Any],
                  let percent = (bucket["utilization"] as? NSNumber)?.doubleValue else { continue }
            let resetsAt = isoDate(bucket["resets_at"])
            windows.append(.init(key: key, percent: percent, resetsAt: resetsAt,
                                 severity: severityByKind[Self.limitsKind(forKey: key)],
                                 notAfter: notAfter(key, resetsAt)))
        }

        // Per-model weekly windows, selected the way Claude Code selects them for its own display.
        for entry in limitsArray {
            guard entry["kind"] as? String == "weekly_scoped",
                  let scope = entry["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let name = model["display_name"] as? String, !name.isEmpty,
                  let percent = (entry["percent"] as? NSNumber)?.doubleValue else { continue }
            let key = "model_scoped:\(name)"
            let resetsAt = isoDate(entry["resets_at"])
            windows.append(.init(key: key, percent: percent, resetsAt: resetsAt, label: name,
                                 severity: entry["severity"] as? String, notAfter: notAfter(key, resetsAt)))
        }

        guard !windows.isEmpty else { return nil }

        return ClaudeUsageSnapshot(
            windows: windows,
            observedAt: observedAt
            // No organization: the cache records the account, and `oauthAccount` is rewritten by
            // every Claude Code process (see `cacheOwner(weeklyReset:claudeCode:resets:)`).
        )
    }

    /// `fetchedAtMs` and `profileFetchedAt` are epoch milliseconds.
    private static func epochMillisecondsDate(_ value: Any?) -> Date? {
        guard let ms = (value as? NSNumber)?.doubleValue, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// The timestamps here are ISO 8601 strings carrying microseconds, unlike the epoch seconds the
    /// statusline hook reports. A value that will not parse yields nil rather than a wrong date.
    private static func isoDate(_ value: Any?) -> Date? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
