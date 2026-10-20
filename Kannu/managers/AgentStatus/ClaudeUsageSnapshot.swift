import Foundation

/// Server-reported Claude subscription usage for one or more rate-limit windows.
///
/// Claude Code parses `anthropic-ratelimit-unified-*` response headers into per-window state and
/// hands the result to the configured statusLine command as `rate_limits`, keyed by window name
/// (`used_percentage` 0-100, `resets_at` unix epoch seconds). The window set is open-ended —
/// `five_hour` and `seven_day` are universal, and a plan may additionally report per-model or
/// per-surface weekly windows such as `seven_day_opus` — so windows are carried as a list rather
/// than as fixed fields. The Kannu statusline hook writes them to
/// `~/.kannu/agent-status/claude-usage.json`; this type parses that file and owns the staleness
/// rules for display.
///
/// The values are snapshots, not live queries: they update only while a Claude session is making
/// API calls. Display must therefore degrade by age rather than pretend liveness.
struct ClaudeUsageSnapshot: Equatable {
    /// One rate-limit window as the server reported it.
    struct Window: Equatable {
        /// The server's window name, e.g. `five_hour`, `seven_day`, `seven_day_opus`.
        let key: String
        /// Percentage of the window consumed, 0-100.
        let percent: Double
        /// When the window rolls over. Absent from sources that do not report it.
        let resetsAt: Date?
        /// The server's own name for this window, when it supplied one. Per-model weekly windows
        /// arrive labelled (e.g. "Fable") rather than under a key Kannu could name itself; the
        /// universal windows leave this nil because their names belong to us.
        var label: String? = nil
        /// The server's own severity for this window ("normal"/"warning"/"critical"), when it
        /// reports one. Today only the cached-usage source carries it; the statusline hook (v4+)
        /// forwards it whenever a bucket supplies one. Drives the bar accent.
        var severity: String? = nil
        /// True when `resetsAt` was derived rather than reported — the desktop history records no
        /// reset and infers one from the last rollover it saw. `merged` never lets such a reset
        /// displace an exact one for the same key, whatever their ages.
        var resetIsInferred: Bool = false
        /// When this window's value was read, where it differs from the snapshot's: `merged`
        /// takes each key from a different source, and a weekly percent from days ago must not
        /// borrow the age of a five-hour value from a minute ago. Nil means `observedAt`.
        var observedAt: Date? = nil
        /// The latest moment this value can still describe a running window, for a source that
        /// knows no reset — the desktop history. Past it the value is from an earlier window for
        /// certain, and `displayWindows` drops it, at render time as well as at the next read.
        var notAfter: Date? = nil
    }

    let windows: [Window]
    /// When the values were observed (the file's `ts`, milliseconds).
    let observedAt: Date
    /// The organization the numbers belong to, when the source says. One person can belong to
    /// several (a Max plan and a Team plan), each with its own limits and its own weekly reset.
    var organizationUUID: String? = nil

    static let fiveHourKey = "five_hour"
    static let sevenDayKey = "seven_day"

    /// Age under which `freshness` reports `.fresh`. The card's own "updated …" label waits for
    /// `staleLabelInterval`, which outlasts the automatic fetch.
    static let freshInterval: TimeInterval = 600

    /// How often the usage sources are re-read while an agent is on screen.
    ///
    /// Each updates on its own slow cadence — the statusline hook only when a session makes an
    /// API call, Claude Code's cache only on a usage fetch, the desktop history only while its
    /// menu-bar panel is in use — so reading faster than this re-parses identical bytes. The
    /// monitor's rescan runs every second, which is why the gate exists.
    static let refreshInterval: TimeInterval = 600

    /// Whether the caller should re-read its usage sources now.
    ///
    /// One read happens with no agent running, so the usage card is populated when opened cold;
    /// after that, refreshing is tied to an agent being on screen, because nothing else can move
    /// the numbers. `.stopped` still counts as on screen: the read just after a run ends is the
    /// one that matters most.
    static func shouldRefresh(
        now: Date,
        lastRead: Date?,
        state: AgentTrafficLightState,
        hasSnapshot: Bool
    ) -> Bool {
        guard let lastRead, hasSnapshot else { return true }
        guard state != .inactive else { return false }
        return now.timeIntervalSince(lastRead) >= refreshInterval
    }

    /// The statusline file is rewritten on every API call a Claude session makes, so between the
    /// full reads above it is re-read alone — at most once a minute, and only when it changed. That
    /// is what lets the usage forecast see the pace instead of one reading every ten minutes.
    static let statuslineReadInterval: TimeInterval = 60

    static func shouldReadStatusline(now: Date, modifiedAt: Date?, lastSeenModifiedAt: Date?, lastRead: Date?) -> Bool {
        guard let modifiedAt, modifiedAt != lastSeenModifiedAt else { return false }
        guard let lastRead else { return true }
        return now.timeIntervalSince(lastRead) >= statuslineReadInterval
    }

    /// How old Claude Code's cached usage may get, while the Usage tab is on screen, before Kannu
    /// runs `/usage` for it — and how long it then waits before trying again. Nothing else
    /// refreshes that cache for someone who uses Claude only in the desktop app.
    static let autoFetchInterval: TimeInterval = 900

    /// `organizationUnverified` (see `cardSources`) asks for the first fetch of a launch at once,
    /// whatever the cache's age: until it runs, Claude Code's numbers cannot go on the card.
    static func shouldAutoFetch(now: Date, cacheObservedAt: Date?, lastFetch: Date?,
                                organizationUnverified: Bool = false) -> Bool {
        if organizationUnverified, lastFetch == nil { return true }
        if let lastFetch, now.timeIntervalSince(lastFetch) < autoFetchInterval { return false }
        guard let cacheObservedAt else { return true }
        return now.timeIntervalSince(cacheObservedAt) >= autoFetchInterval
    }

    /// How old a reading may be before the card says so and dims it. Longer than the automatic
    /// fetch interval, so bars the automatic refresh keeps current never dim between its runs.
    static let staleLabelInterval: TimeInterval = 1800

    /// "updated 3h ago" for a reading older than `staleLabelInterval`, else nil.
    static func staleLabel(observedAt: Date?, now: Date) -> String? {
        guard let observedAt else { return nil }
        let seconds = now.timeIntervalSince(observedAt)
        guard seconds > staleLabelInterval else { return nil }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return String(localized: "updated \(minutes)m ago") }
        let hours = minutes / 60
        if hours < 48 { return String(localized: "updated \(hours)h ago") }
        return String(localized: "updated \(hours / 24)d ago")
    }

    enum Freshness: Equatable {
        case fresh
        /// Stale but still meaningful — show dimmed with relative age.
        case aged
    }

    func freshness(now: Date = Date()) -> Freshness {
        now.timeIntervalSince(observedAt) <= Self.freshInterval ? .fresh : .aged
    }

    /// Windows safe to put on screen, in display order: the 5-hour window, the all-models weekly
    /// window, then any additional windows in the order the source reported them.
    ///
    /// A window whose reset time has passed has certainly rolled over; its percentage is stale
    /// fiction and must not be shown.
    func displayWindows(now: Date = Date()) -> [Window] {
        let live = windows.filter { window in
            if let notAfter = window.notAfter, now >= notAfter { return false }
            guard let resetsAt = window.resetsAt else { return true }
            return now < resetsAt
        }
        func rank(_ key: String) -> Int {
            switch key {
            case Self.fiveHourKey: return 0
            case Self.sevenDayKey: return 1
            default: return 2
            }
        }
        // Comparing on the source index too keeps equal ranks in reported order.
        return live.enumerated()
            .sorted { (rank($0.element.key), $0.offset) < (rank($1.element.key), $1.offset) }
            .map(\.element)
    }

    func window(_ key: String) -> Window? {
        windows.first { $0.key == key }
    }

    var fiveHourPercent: Double? { window(Self.fiveHourKey)?.percent }
    var fiveHourResetsAt: Date? { window(Self.fiveHourKey)?.resetsAt }
    var sevenDayPercent: Double? { window(Self.sevenDayKey)?.percent }
    var sevenDayResetsAt: Date? { window(Self.sevenDayKey)?.resetsAt }

    func fiveHourDisplayPercent(now: Date = Date()) -> Double? {
        displayWindows(now: now).first { $0.key == Self.fiveHourKey }?.percent
    }

    func sevenDayDisplayPercent(now: Date = Date()) -> Double? {
        displayWindows(now: now).first { $0.key == Self.sevenDayKey }?.percent
    }

    /// True when nothing is left to show — no windows, or every one of them past its reset.
    func isEmpty(now: Date = Date()) -> Bool {
        displayWindows(now: now).isEmpty
    }

    /// Combines several sources one window key at a time: each key is taken from the source whose
    /// live copy (per `displayWindows`) was observed most recently; source order (statusline,
    /// cache, desktop history) only breaks ties. One lapsed window in a good source therefore
    /// neither hides that source's live siblings nor blocks a lesser source from covering the gap.
    ///
    /// Freshness, not rank, because "live" only means the reset has not passed: a weekly window
    /// fetched six days ago is still live for the rest of its week, and ranking by source let it
    /// beat the desktop app's sample from half an hour ago — the weekly bar sat at 20 % while the
    /// account was at 31 %. A percentage is a reading, and the newer reading is the truer one.
    ///
    /// A nil-reset window counts as live, as everywhere else. Lapsed copies are dropped, not
    /// carried. Severity is never borrowed across sources for one key: `accent(severity:fraction:)`
    /// gives it precedence, so a stale "normal" would suppress the red band on a fresher value.
    /// Output order follows the winning sources in rank order, then each source's own order, so
    /// the gauges do not reshuffle between reads. `observedAt` is the newest among the sources
    /// that contributed a window; each window also keeps its own source's time, so an old
    /// reading still shows its age next to a fresh one.
    ///
    /// One exception to "the winning window is taken whole": an *inferred* reset never beats an
    /// exact one. The desktop history derives its reset from the last rollover it happened to
    /// sample, so it lands minutes after the server's; taken by freshness it displaced the API's
    /// own reset on every read, the countdown moved, and the usage-alert push key — which is the
    /// reset — treated the same window as a new instance and pushed it twice. The fresher percent
    /// still wins; its reset is borrowed from the highest-ranked live source that has an exact one.
    ///
    /// Returns nil when nothing is live anywhere. Pure in its inputs, so repeated merges of
    /// unchanged files compare equal and do not republish.
    static func merged(_ sources: [ClaudeUsageSnapshot?], now: Date) -> ClaudeUsageSnapshot? {
        let present = sources.compactMap { $0 }
        var exactResets: [String: Date] = [:]
        for source in present {
            for window in source.displayWindows(now: now) where !window.resetIsInferred {
                if let reset = window.resetsAt, exactResets[window.key] == nil { exactResets[window.key] = reset }
            }
        }
        // Winner per key: newest observedAt, ties to the earlier (higher-ranked) source.
        var winnerIndex: [String: Int] = [:]
        for (index, source) in present.enumerated() {
            for window in source.displayWindows(now: now) {
                if let current = winnerIndex[window.key], present[current].observedAt >= source.observedAt {
                    continue
                }
                winnerIndex[window.key] = index
            }
        }
        var windows: [Window] = []
        var observedAt: Date?
        for (index, source) in present.enumerated() {
            for window in source.displayWindows(now: now) where winnerIndex[window.key] == index {
                var taken = window
                if taken.resetIsInferred, let exact = exactResets[taken.key] {
                    taken = Window(key: taken.key, percent: taken.percent, resetsAt: exact,
                                   label: taken.label, severity: taken.severity, resetIsInferred: false,
                                   notAfter: taken.notAfter)
                }
                taken.observedAt = window.observedAt ?? source.observedAt
                windows.append(taken)
                observedAt = max(observedAt ?? source.observedAt, source.observedAt)
            }
        }
        guard let observedAt, !windows.isEmpty else { return nil }
        return ClaudeUsageSnapshot(windows: windows, observedAt: observedAt)
    }

    /// Which sources one card may combine.
    ///
    /// The card follows the organization Claude Desktop records usage for — its history's newest
    /// sample — because that is what desktop-hosted agents spend (the user's call, 2026-10-18).
    /// Claude Code's own sources, its statusline and its cache, describe the organization its
    /// sign-in is bound to. When that is a different one they are left out whole, never merged
    /// per key, so a card never shows one organization's five-hour bar beside another's week.
    /// With no desktop history at all, Claude Code's organization is the only one there is.
    ///
    /// `claudeCodeOrganizationRecorded` is false until Kannu's own fetch has recorded which
    /// organization Claude Code's sign-in is on. Until then the organization is a guess — the file
    /// it comes from flips between them — so with desktop history to follow, Claude Code's
    /// sources stay off the card (`claudeCodeOrganizationUnverified`), and the automatic refresh
    /// fetches at once to find out (`shouldAutoFetch`). A first look at the card must not show one
    /// organization's numbers as another's.
    static func cardSources(
        statusline: ClaudeUsageSnapshot?,
        cache: ClaudeUsageSnapshot?,
        desktop: ClaudeUsageSnapshot?,
        desktopOrganization: String?,
        claudeCodeOrganization: String?,
        claudeCodeOrganizationRecorded: Bool = true
    ) -> (sources: [ClaudeUsageSnapshot?], claudeCodeOnAnotherOrganization: Bool, claudeCodeOrganizationUnverified: Bool) {
        guard let desktopOrganization else { return ([statusline, cache, desktop], false, false) }
        guard claudeCodeOrganizationRecorded else { return ([desktop], false, true) }
        guard let claudeCodeOrganization, desktopOrganization != claudeCodeOrganization else {
            return ([statusline, cache, desktop], false, false)
        }
        return ([desktop], true, false)
    }

    /// Why the card may be showing less than it should.
    enum Hint: Equatable {
        /// Claude hooks are installed, so Claude Code is in use, yet neither server-backed source
        /// (statusline file, Claude Code's usage cache) has a live window. Claude Code's usage
        /// fetch returns nothing when its sign-in lacks the `user:profile` scope, and the same
        /// gate leaves the statusline's `rate_limits` null. Refresh fixes both: it runs `/usage`
        /// and, when that finds no plan data, starts Claude Code's own claude.ai sign-in.
        /// Sessions inside the desktop app run on a host token without that scope, which is why
        /// those sessions alone never fill the cache.
        case signInNeeded
        /// Claude Code is signed in to a different organization than the one Claude Desktop
        /// records usage for, so its exact numbers belong to someone else's limits and the bars
        /// come from the desktop history alone. Signing Claude Code in to the same organization
        /// brings the exact numbers back.
        case otherOrganization
    }

    /// Desktop-only users (no Claude hooks) are never nagged: the desktop history is the source
    /// they were always meant to have.
    static func hint(
        hooksInstalled: Bool,
        statusline: ClaudeUsageSnapshot?,
        cache: ClaudeUsageSnapshot?,
        claudeCodeOnAnotherOrganization: Bool = false,
        now: Date
    ) -> Hint? {
        if claudeCodeOnAnotherOrganization { return .otherOrganization }
        guard hooksInstalled else { return nil }
        let serverBacked = [statusline, cache].compactMap { $0 }.contains { !$0.isEmpty(now: now) }
        return serverBacked ? nil : .signInNeeded
    }

    /// Parses both file shapes: the `windows` array written by the current hook, and the flat
    /// `five_hour_pct` / `seven_day_pct` form written by hooks predating open-ended windows.
    /// Older files stay readable so the gauges do not blank out between the app upgrading and
    /// the next statusline write.
    static func parse(json: [String: Any]) -> ClaudeUsageSnapshot? {
        guard let tsMs = (json["ts"] as? NSNumber)?.int64Value, tsMs > 0 else { return nil }

        let windows = parseWindowList(json["windows"]) ?? parseLegacyWindows(json)
        guard !windows.isEmpty else { return nil }

        return ClaudeUsageSnapshot(
            windows: windows,
            observedAt: Date(timeIntervalSince1970: TimeInterval(tsMs) / 1000)
        )
    }

    static func load(from url: URL) -> ClaudeUsageSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return parse(json: json)
    }

    private static func parseWindowList(_ value: Any?) -> [Window]? {
        guard let entries = value as? [[String: Any]] else { return nil }
        return entries.compactMap { entry in
            guard let key = entry["key"] as? String, !key.isEmpty,
                  let percent = (entry["pct"] as? NSNumber)?.doubleValue else { return nil }
            let label = (entry["label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let severity = (entry["severity"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return Window(key: key, percent: percent,
                          resetsAt: epochDate(entry["resets_at"]), label: label, severity: severity)
        }
    }

    private static func parseLegacyWindows(_ json: [String: Any]) -> [Window] {
        [(fiveHourKey, "five_hour_pct", "five_hour_resets_at"),
         (sevenDayKey, "seven_day_pct", "seven_day_resets_at")].compactMap { key, pctKey, resetKey in
            guard let percent = (json[pctKey] as? NSNumber)?.doubleValue else { return nil }
            return Window(key: key, percent: percent, resetsAt: epochDate(json[resetKey]))
        }
    }

    private static func epochDate(_ value: Any?) -> Date? {
        guard let epoch = (value as? NSNumber)?.doubleValue, epoch > 0 else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }
}
