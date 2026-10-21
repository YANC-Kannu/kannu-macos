import Foundation

/// Reads the usage history the Claude desktop app keeps for itself.
///
/// The app records rate-limit samples into
/// `~/Library/Application Support/Claude/plan-usage-history.json`, retaining roughly 30 days —
/// but only while its menu-bar panel has been opened within the last day, so gaps of days are
/// normal and the newest sample can be very old:
///
/// ```json
/// {"version": 2, "samples": [{"t": 1788027991573, "org": "…", "u": {"fh": 38, "sd": 61}}]}
/// ```
///
/// `u` is keyed by the app's short codes for each rate-limit window, and the values are the same
/// percentages the statusline hook receives. This is a fallback: it fills the gauges when no
/// statusline snapshot exists — a user who only ever runs Claude in the desktop app never triggers
/// the hook — while the hook stays primary because it reports reset times outright, where this file
/// records none (see `parse(json:now:account:)` for what a sample can still vouch for).
///
/// Nothing about this file is documented, so parsing is defensive throughout: any surprise yields
/// nil and the caller shows no usage, exactly as if the file were absent.
enum ClaudeDesktopUsageHistory {
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    }

    /// The app's short code for each rate-limit window. `xu` is deliberately absent: it tracks
    /// extra-usage credits, which is spend, not a rate-limit window, and must not become a gauge.
    static let windowKeysByCode: [String: String] = [
        "fh": "five_hour",
        "sd": "seven_day",
        "so": "seven_day_opus",
        "sn": "seven_day_sonnet",
        "cw": "seven_day_cowork",
        "oa": "seven_day_oauth_apps",
        "om": "seven_day_omelette",
        "op": "omelette_promotional"
    ]

    /// Display order for the windows above, so the gauges do not reshuffle between reads.
    private static let codeOrder = ["fh", "sd", "so", "sn", "cw", "oa", "om", "op"]

    private static let fiveHours: TimeInterval = 5 * 3600
    private static let week: TimeInterval = 7 * 24 * 3600

    static func load(from url: URL = defaultURL, now: Date = Date(),
                     account: ClaudeCachedUsage.AccountContext = .init()) -> ClaudeUsageSnapshot? {
        read(from: url, now: now, account: account).snapshot
    }

    /// The snapshot, and the organization the desktop app records usage for even when none of
    /// its windows is current any more — the card follows that organization either way.
    static func read(from url: URL = defaultURL, now: Date = Date(),
                     account: ClaudeCachedUsage.AccountContext = .init())
        -> (snapshot: ClaudeUsageSnapshot?, organizationUUID: String?) {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil) }
        return (parse(json: json, now: now, account: account), organization(json: json))
    }

    /// The organization of the newest sample that names one: the one the desktop app is on now.
    static func organization(json: [String: Any]) -> String? {
        guard let rawSamples = json["samples"] as? [[String: Any]] else { return nil }
        return rawSamples
            .compactMap { sample -> (tMs: Double, org: String)? in
                guard let tMs = (sample["t"] as? NSNumber)?.doubleValue,
                      let org = sample["org"] as? String, !org.isEmpty else { return nil }
                return (tMs, org)
            }
            .max { $0.tMs < $1.tMs }?.org
    }

    private struct Sample {
        let tMs: Double
        let org: String?
        let usage: [String: Any]
    }

    /// The newest sample of one organization, with only the windows it can still vouch for.
    ///
    /// The app samples only while its menu-bar panel has been opened in the last day, so a sample
    /// can be days old. A value older than its window is from an earlier window for certain and is
    /// dropped; a younger one may still be current, and goes on screen with its age (the card says
    /// "updated 3h ago") and a `notAfter` bound, so it also expires between reads. Every window
    /// here is marked `resetIsInferred` — this file reports no reset — so `merged` lends it the
    /// server's exact reset whenever Claude Code's cache has one for the same organization.
    ///
    /// - **5 hour**: the window starts with the first message after the last one ended, so its
    ///   reset cannot be recovered from samples. No countdown; `notAfter` is five hours after the
    ///   sample.
    /// - **Weekly**: the window resets on a fixed weekly anchor per organization, taken from Claude
    ///   Code's cached reset when Claude Code is on the same organization, however old
    ///   (`ClaudeCachedUsage.AccountContext`). The reset after the sample is exact; once it has
    ///   passed, the bar is dropped. Without an anchor, a rollover seen in the samples stands in,
    ///   projected the same way: a countdown only when it was caught within an hour, else just the
    ///   latest possible reset as `notAfter` — a rollover found after a gap of days could have
    ///   happened at any point in it, and a countdown measured from its far end ran up to that
    ///   whole gap late.
    /// - **Anything else**: kept for at most a week after the sample, with no countdown.
    static func parse(json: [String: Any], now: Date = Date(),
                      account: ClaudeCachedUsage.AccountContext = .init()) -> ClaudeUsageSnapshot? {
        guard let rawSamples = json["samples"] as? [[String: Any]] else { return nil }

        // Trust the timestamps rather than the append order.
        let all = rawSamples.compactMap { sample -> Sample? in
            guard let tMs = (sample["t"] as? NSNumber)?.doubleValue, tMs > 0,
                  let usage = sample["u"] as? [String: Any] else { return nil }
            let org = (sample["org"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return Sample(tMs: tMs, org: org, usage: usage)
        }.sorted { $0.tMs < $1.tMs }

        // One organization's usage only: the one the desktop app is on now, its newest sample's.
        // Samples from another organization (a second plan, or another account once signed in)
        // are other limits entirely.
        let organization = all.last(where: { $0.org != nil })?.org
        let samples = organization.map { id in all.filter { $0.org == id } } ?? all
        // Another organization's weekly reset says nothing about this one's.
        let anchor = account.organizationUUID == nil || organization == nil || account.organizationUUID == organization
            ? account.weeklyResetAnchor : nil

        guard let newest = samples.last else { return nil }
        let observedAt = Date(timeIntervalSince1970: newest.tMs / 1000)

        let windows = codeOrder.compactMap { code -> ClaudeUsageSnapshot.Window? in
            guard let key = windowKeysByCode[code],
                  let percent = (newest.usage[code] as? NSNumber)?.doubleValue else { return nil }
            var resetsAt: Date?
            var notAfter: Date
            if key == ClaudeUsageSnapshot.fiveHourKey {
                notAfter = observedAt.addingTimeInterval(fiveHours)
            } else if key.hasPrefix("seven_day") {
                notAfter = observedAt.addingTimeInterval(week)
                if let anchor {
                    resetsAt = weeklyReset(after: observedAt, anchor: anchor)
                } else if let rollover = lastRollover(for: code, in: samples) {
                    // A rollover is an anchor too: project it in whole weeks to the week the
                    // sample is in. A later reset can go unseen — usage climbing past the last
                    // value before it — and `rollover + 7 days` then lies in the past and hid a
                    // current bar. `seenAt` is the latest moment the rollover can have happened.
                    let latest = weeklyReset(after: observedAt, anchor: rollover.seenAt)
                    if rollover.seenAt.timeIntervalSince(rollover.notBefore) <= precisionGap {
                        resetsAt = latest
                    } else {
                        notAfter = min(notAfter, latest)
                    }
                }
            } else {
                notAfter = observedAt.addingTimeInterval(week)
            }
            if let resetsAt { notAfter = min(notAfter, resetsAt) }
            guard notAfter > now else { return nil }
            // Nothing here is reported by the server: `merged` lends the exact reset when it has one.
            return ClaudeUsageSnapshot.Window(key: key, percent: percent, resetsAt: resetsAt,
                                              resetIsInferred: true, notAfter: notAfter)
        }
        guard !windows.isEmpty else { return nil }

        return ClaudeUsageSnapshot(windows: windows, observedAt: observedAt, organizationUUID: organization)
    }

    /// A rollover found within this long of the sample before it is dated precisely enough for a
    /// countdown.
    private static let precisionGap: TimeInterval = 3600

    /// The first weekly reset strictly after `date`, stepping from `anchor` in whole weeks in
    /// either direction.
    static func weeklyReset(after date: Date, anchor: Date) -> Date {
        let weeks = (date.timeIntervalSince(anchor) / week).rounded(.down) + 1
        return anchor.addingTimeInterval(weeks * week)
    }

    /// When a window last rolled over, as seen in the samples — the stand-in for a weekly anchor
    /// when Claude Code is on another organization or has never cached one. `seenAt` is the first
    /// sample after the drop and `notBefore` the one before it: the rollover happened in between.
    ///
    /// A rollover is visible as a drop in utilization. Small decays are not rollovers, hence the
    /// threshold; a decrease landing on zero is one however small.
    private static func lastRollover(for code: String, in samples: [Sample]) -> (notBefore: Date, seenAt: Date)? {
        var rollover: (notBefore: Double, seenAt: Double)?
        var previous: (tMs: Double, value: Double)?
        for sample in samples {
            guard let value = (sample.usage[code] as? NSNumber)?.doubleValue else { continue }
            if let previous, value < previous.value, previous.value - value > 5 || value == 0 {
                rollover = (previous.tMs, sample.tMs)
            }
            previous = (sample.tMs, value)
        }
        return rollover.map { (Date(timeIntervalSince1970: $0.notBefore / 1000), Date(timeIntervalSince1970: $0.seenAt / 1000)) }
    }
}
