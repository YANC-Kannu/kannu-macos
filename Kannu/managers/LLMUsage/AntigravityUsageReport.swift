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

/// How Kannu asks the Antigravity CLI for its model quotas, held as data so tests pin it
/// (docs/REGRESSIONS.md entry 8: a usage spawn is verified, not reasoned about).
///
/// UNVERIFIED. Built from Antigravity's public docs and changelog only; it has never run against a
/// real `agy`. CLI v1.1.11 (2026-08-07) made print mode answer the read-only slash commands,
/// `/usage` and `/quota` among them, without an agent turn, without spending quota and without
/// leaving a conversation behind, and `--output-format json` gives them a structured payload. The
/// payload's field names are not documented anywhere public, so `AntigravityUsageReport` reads it
/// tolerantly. `/usage` reaches Google's backend, so the provider refreshes on the network floor
/// (`reachesNetwork`).
enum AntigravityUsageCommand {
    static let arguments = ["-p", "/usage", "--output-format", "json"]

    /// Headless runs have had no timeout of their own since CLI v1.2.6; this one is Kannu's.
    static let timeout: TimeInterval = 20

    static let stdoutCap = 512_000

    /// Kannu's environment, unchanged: no flag or variable goes in that a real fetch has not shown
    /// to work (entry 8).
    static let environment: [String: String]? = nil

    /// Google LLC's Apple Developer team. Seen on Antigravity.app 2.19.1 ("Developer ID Application:
    /// Google LLC (EQHXZ8M8AV)", CodexBar PR #4238, appcatalog.cloud) and on Google Chrome on the Mac
    /// this was written on. Nothing public says how the `agy` binary itself is signed: unverified,
    /// and a binary signed any other way is never run.
    static let teamID = "EQHXZ8M8AV"

    /// A Developer ID Application signature issued to that team.
    static var codeRequirement: String {
        "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// Where `agy` is looked for, in order. The official installer (antigravity.google/cli/install.sh)
    /// puts it in `~/.local/bin`; Homebrew's two prefixes cover a package or a hand-made link. No
    /// public source shows an `agy` inside Antigravity.app (the bundle's documented binary is its
    /// language server), so no bundle path is guessed.
    static func candidates(home: URL) -> [URL] {
        [home.appendingPathComponent(".local/bin/agy"),
         URL(fileURLWithPath: "/opt/homebrew/bin/agy"),
         URL(fileURLWithPath: "/usr/local/bin/agy")]
    }

    /// After a run that gave no quota (not signed in, an error, a payload Kannu cannot read),
    /// refreshes leave `agy` alone this long. Only the Usage tab's Refresh button lifts it
    /// (`AntigravityQuotaReader.clearBackoff`): the 30-second tick, opening the tab and every other
    /// caller of `refreshAll` wait it out.
    static let failureBackoff: TimeInterval = 15 * 60

    /// `/usage` asks Google's backend, so the provider is not a local-file one and takes
    /// `LLMUsageManager`'s network floor. Pinned by a test: as a local-file provider it would run
    /// `agy` on every 30-second tick and every time the Usage tab opens.
    static let reachesNetwork = true
}

/// What a file was when its signature was checked. The status-change time is in it because it is
/// the one the file's owner cannot set back: a binary rewritten in place to the same size, with its
/// modification time restored, still has a new ctime. The check of the facts and the exec that
/// follows are still two steps, so a swap between them is not caught (see `AntigravityQuotaReader`).
struct AntigravityFileFacts: Equatable {
    let device: Int64
    let inode: UInt64
    let size: Int64
    let modifiedNanoseconds: Int64
    let changedNanoseconds: Int64

    /// `stat` of the file at `path`, which the caller has already resolved: nil unless it is a
    /// regular file that can be read.
    static func of(path: String) -> AntigravityFileFacts? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        func nanoseconds(_ time: timespec) -> Int64 { Int64(time.tv_sec) * 1_000_000_000 + Int64(time.tv_nsec) }
        return AntigravityFileFacts(device: Int64(info.st_dev), inode: UInt64(info.st_ino), size: Int64(info.st_size),
                                    modifiedNanoseconds: nanoseconds(info.st_mtimespec),
                                    changedNanoseconds: nanoseconds(info.st_ctimespec))
    }
}

/// Signature verdicts, each kept while its file's facts are unchanged, so neither a pass nor a fail
/// hashes the binary again on every refresh. An `agy` signed some other way (a Homebrew build, one
/// built by hand) fails once, not every 3 minutes. A new file, such as `agy` updating itself, has new
/// facts and is checked again.
struct AntigravitySignatureVerdicts {
    /// Candidates resolve to at most a few paths. A symlink retargeted on every update could keep
    /// adding new ones, so the table starts over past this many.
    static let capacity = 8

    private var verdicts: [String: (facts: AntigravityFileFacts, trusted: Bool)] = [:]

    /// The kept verdict for this file, or nil when it has never been checked or has changed since.
    func verdict(path: String, facts: AntigravityFileFacts) -> Bool? {
        guard let entry = verdicts[path], entry.facts == facts else { return nil }
        return entry.trusted
    }

    mutating func record(_ trusted: Bool, path: String, facts: AntigravityFileFacts) {
        if verdicts[path] == nil, verdicts.count >= Self.capacity { verdicts.removeAll() }
        verdicts[path] = (facts, trusted)
    }
}

/// The quota pools `agy` reported, and when it reported them.
struct AntigravityQuotaReading: Equatable {
    var pools: [AntigravityQuotaPool]
    var readAt: Date

    /// How long a reading is still shown after runs that give nothing: a timeout, a network blip, a
    /// non-zero exit, or a run the failure backoff skipped. The same bound as
    /// `LLMUsageManager.maxPreservedResultAge` (3 × its 180 s floor). One bad run then does not
    /// blank the bars for the whole 15-minute backoff, and figures are not kept for long after a
    /// sign-out either.
    static let keptFor: TimeInterval = 540

    /// This reading as it still holds at `now`. nil once it is `keptFor` old, or when it was read
    /// after `now` (the clock moved back). A window whose reset has passed is dropped, because its
    /// figure no longer holds, and so is a pool left with no window. nil when no pool is left.
    func kept(at now: Date) -> AntigravityQuotaReading? {
        let age = now.timeIntervalSince(readAt)
        guard age >= 0, age < Self.keptFor else { return nil }
        let live: [AntigravityQuotaPool] = pools.compactMap { pool in
            var kept = pool
            if let reset = pool.fiveHour?.resetsAt, reset <= now { kept.fiveHour = nil }
            if let reset = pool.weekly?.resetsAt, reset <= now { kept.weekly = nil }
            return kept.fiveHour == nil && kept.weekly == nil ? nil : kept
        }
        return live.isEmpty ? nil : AntigravityQuotaReading(pools: live, readAt: readAt)
    }
}

/// One rate-limit window of a model pool, as a used percentage.
struct AntigravityQuotaWindow: Equatable {
    let usedPercent: Double
    let resetsAt: Date?
}

/// One model pool (a group of models sharing a quota) and its 5-hour and weekly windows.
struct AntigravityQuotaPool: Equatable {
    var name: String?
    var fiveHour: AntigravityQuotaWindow?
    var weekly: AntigravityQuotaWindow?
}

/// Reads what `agy -p "/usage" --output-format json` prints. The shape is undocumented, so this
/// accepts the plausible ones and ignores everything else: an object that carries a 5-hour or a
/// weekly window is a pool, wherever it sits (top level, a `pools`-like list or map, or the headless
/// envelope's `response` given as JSON text). A window is a used or remaining percentage, fraction
/// or count, with an optional reset. Other windows (daily caps) and the envelope's token `usage`
/// are not windows and are skipped. Untrusted input: bounded in depth, nodes and pools.
enum AntigravityUsageReport {
    enum WindowKind: Equatable { case fiveHour, weekly }

    static let maxPools = 12
    private static let maxDepth = 8
    private static let maxNodes = 4_000
    private static let maxNameLength = 48

    /// Headless statuses that mean no answer (antigravity.google/docs/cli/headless).
    private static let failedStatuses: Set<String> = ["ERROR", "CANCELED", "CANCELLED", "INTERRUPTED", "INVALID"]

    static func parse(_ data: Data, now: Date) -> [AntigravityQuotaPool] {
        guard !data.isEmpty, data.count <= AntigravityUsageCommand.stdoutCap,
              let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return [] }
        if let envelope = root as? [String: Any], let status = envelope["status"] as? String,
           failedStatuses.contains(status.uppercased()) {
            return []
        }
        var pools: [AntigravityQuotaPool] = []
        var nodes = 0
        collect(root, key: nil, depth: 0, into: &pools, nodes: &nodes, now: now)
        return pools
    }

    // MARK: - Walking the document

    private static func collect(_ value: Any, key: String?, depth: Int, into pools: inout [AntigravityQuotaPool],
                                nodes: inout Int, now: Date) {
        guard depth <= maxDepth, nodes < maxNodes, pools.count < maxPools else { return }
        nodes += 1
        switch value {
        case let text as String:
            // The headless envelope carries the answer in `response`, possibly as JSON text.
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard depth <= 2, trimmed.first == "{" || trimmed.first == "[",
                  let inner = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) else { return }
            collect(inner, key: key, depth: depth + 1, into: &pools, nodes: &nodes, now: now)
        case let list as [Any]:
            for item in list { collect(item, key: nil, depth: depth + 1, into: &pools, nodes: &nodes, now: now) }
        case let object as [String: Any]:
            if let pool = pool(from: object, key: key, now: now) {
                pools.append(pool)
                return
            }
            // JSONSerialization keeps no key order; sorted, the result is at least stable.
            for (childKey, child) in object.sorted(by: { $0.key < $1.key }) {
                collect(child, key: childKey, depth: depth + 1, into: &pools, nodes: &nodes, now: now)
            }
        default:
            return
        }
    }

    /// Keys whose value lists or maps a pool's windows.
    private static let windowListKeys = ["windows", "limits", "rate_limits", "rateLimits", "quota_windows", "quotaWindows"]
    /// Fields that name a window inside such a list.
    private static let windowNameKeys = ["window", "name", "kind", "type", "period", "duration", "id", "label",
                                         "window_name", "windowName"]
    private static let windowSecondsKeys = ["duration_seconds", "durationSeconds", "window_seconds", "windowSeconds",
                                            "period_seconds", "periodSeconds"]
    private static let poolNameKeys = ["display_name", "displayName", "name", "label", "pool", "pool_name", "poolName",
                                       "model_group", "modelGroup", "group", "model", "title", "id"]
    /// Container keys that never name a pool.
    private static let containerKeys: Set<String> = ["pools", "quota", "quotas", "usage", "data", "result", "results",
                                                     "response", "structured_output", "payload", "models", "groups"]

    private static func pool(from object: [String: Any], key: String?, now: Date) -> AntigravityQuotaPool? {
        var pool = AntigravityQuotaPool()
        func assign(_ kind: WindowKind?, _ window: AntigravityQuotaWindow?) {
            guard let kind, let window else { return }
            switch kind {
            case .fiveHour where pool.fiveHour == nil: pool.fiveHour = window
            case .weekly where pool.weekly == nil: pool.weekly = window
            default: break
            }
        }
        for (field, value) in object.sorted(by: { $0.key < $1.key }) {
            guard let windowObject = value as? [String: Any] else { continue }
            assign(windowKind(named: field), window(from: windowObject, now: now))
        }
        for listKey in windowListKeys {
            if let list = object[listKey] as? [Any] {
                for case let item as [String: Any] in list {
                    assign(windowKind(of: item), window(from: item, now: now))
                }
            } else if let map = object[listKey] as? [String: Any] {
                for (field, value) in map.sorted(by: { $0.key < $1.key }) {
                    guard let windowObject = value as? [String: Any] else { continue }
                    assign(windowKind(named: field) ?? windowKind(of: windowObject), window(from: windowObject, now: now))
                }
            }
        }
        guard pool.fiveHour != nil || pool.weekly != nil else { return nil }
        pool.name = poolNameKeys.lazy.compactMap { displayName(object[$0]) }.first
            ?? key.flatMap { containerKeys.contains($0) || windowKind(named: $0) != nil ? nil : displayName($0) }
        return pool
    }

    // MARK: - Windows

    static func windowKind(named raw: String) -> WindowKind? {
        let compact = String(raw.lowercased().filter { $0.isLetter || $0.isNumber })
        if compact.contains("fivehour") || compact.hasPrefix("5h") || compact.hasPrefix("session") { return .fiveHour }
        if compact.contains("week") || compact.contains("sevenday") || compact.hasPrefix("7d") || compact == "168h" {
            return .weekly
        }
        return nil
    }

    private static func windowKind(of object: [String: Any]) -> WindowKind? {
        for key in windowNameKeys {
            if let name = object[key] as? String, let kind = windowKind(named: name) { return kind }
        }
        for key in windowSecondsKeys {
            switch number(object[key]) {
            case 18_000: return .fiveHour
            case 604_800: return .weekly
            default: continue
            }
        }
        return nil
    }

    private static func window(from object: [String: Any], now: Date) -> AntigravityQuotaWindow? {
        guard let used = usedPercent(object), used.isFinite else { return nil }
        return AntigravityQuotaWindow(usedPercent: min(max(used, 0), 100), resetsAt: resetDate(object, now: now))
    }

    private static func usedPercent(_ object: [String: Any]) -> Double? {
        func first(_ keys: [String]) -> Double? { keys.lazy.compactMap { number(object[$0]) }.first }
        func fraction(_ value: Double?) -> Double? { value.flatMap { (0...1).contains($0) ? $0 : nil } }
        if let percent = first(["used_percentage", "used_percent", "usedPercent", "usedPercentage", "percent_used",
                                "percentUsed", "usage_percent", "usagePercent", "utilization"]) {
            return percent
        }
        if let used = fraction(first(["used_fraction", "usedFraction", "fraction_used", "fractionUsed"])) {
            return used * 100
        }
        if let remaining = fraction(first(["remaining_fraction", "remainingFraction", "fraction_remaining", "fractionRemaining"])) {
            return (1 - remaining) * 100
        }
        if let remaining = first(["remaining_percentage", "remaining_percent", "remainingPercent", "remainingPercentage",
                                  "percent_remaining", "percentRemaining"]) {
            return 100 - remaining
        }
        guard let limit = first(["limit", "total", "max", "allowance"]), limit > 0 else { return nil }
        if let used = first(["used", "consumed"]) { return used / limit * 100 }
        if let remaining = first(["remaining", "left"]) { return (1 - remaining / limit) * 100 }
        return nil
    }

    private static func resetDate(_ object: [String: Any], now: Date) -> Date? {
        for key in ["resets_at", "resetsAt", "reset_at", "resetAt", "reset_time", "resetTime", "next_reset", "nextReset",
                    "window_end", "windowEnd", "resets", "reset"] {
            if let date = date(object[key]) { return date }
        }
        for key in ["resets_in_seconds", "resetsInSeconds", "reset_in_seconds", "resetInSeconds",
                    "seconds_until_reset", "secondsUntilReset"] {
            if let seconds = number(object[key]), seconds >= 0, seconds <= 30 * 86_400 { return now.addingTimeInterval(seconds) }
        }
        return nil
    }

    // MARK: - Values

    /// A JSON number that is not a Bool, or a number written as text ("42", "42%").
    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let double = number.doubleValue
            return double.isFinite ? double : nil
        }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let digits = trimmed.hasSuffix("%") ? String(trimmed.dropLast()) : trimmed
            return Double(digits).flatMap { $0.isFinite ? $0 : nil }
        }
        return nil
    }

    /// ISO 8601 text (CLI v1.2.15: piped and JSON output stay in UTC), or epoch seconds or milliseconds.
    private static func date(_ value: Any?) -> Date? {
        if let text = value as? String {
            let plain = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = plain.date(from: text) ?? fractional.date(from: text) { return date }
        }
        guard let epoch = number(value) else { return nil }
        if epoch > 100_000_000_000 { return Date(timeIntervalSince1970: epoch / 1000) }
        if epoch > 1_000_000_000 { return Date(timeIntervalSince1970: epoch) }
        return nil
    }

    private static func displayName(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else { return nil }
        return String(text.prefix(maxNameLength))
    }
}

/// The pools mapped onto the Usage card's slots: the first pool with a 5-hour window (else the first
/// with a weekly one) fills the 5-hour and weekly bars, and every other pool's windows are extra bars
/// labelled with its name. Kept free of the card's own types so the logic test target can reach it.
struct AntigravityQuotaLimits: Equatable {
    struct Extra: Equatable {
        let key: String
        let label: String
        /// A 5-hour window, shown with the 5-hour bars rather than the weekly ones.
        let isSessionWindow: Bool
        let window: AntigravityQuotaWindow
    }

    var session: AntigravityQuotaWindow?
    var week: AntigravityQuotaWindow?
    /// The primary pool's name, set only when there is more than one pool (one pool is all models).
    var label: String?
    var extras: [Extra] = []

    var isEmpty: Bool { session == nil && week == nil && extras.isEmpty }

    init(pools: [AntigravityQuotaPool]) {
        guard let primary = pools.firstIndex(where: { $0.fiveHour != nil })
                ?? pools.firstIndex(where: { $0.weekly != nil }) else { return }
        session = pools[primary].fiveHour
        week = pools[primary].weekly
        if pools.count > 1 { label = pools[primary].name }
        for (index, pool) in pools.enumerated() where index != primary {
            let name = pool.name ?? String(localized: "Pool \(index + 1)")
            let slug = String(name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
            let stem = "antigravity_\(index)_\(slug)"
            if let window = pool.fiveHour {
                extras.append(Extra(key: stem + "_five_hour", label: name, isSessionWindow: true, window: window))
            }
            if let window = pool.weekly {
                extras.append(Extra(key: stem + "_weekly", label: name, isSessionWindow: false, window: window))
            }
        }
    }
}
