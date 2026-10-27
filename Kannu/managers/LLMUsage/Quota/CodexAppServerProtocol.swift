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

/// Codex's rate limits in Kannu's terms, from a source that never touches Codex's sign-in: the
/// answer to `codex app-server`'s `account/rateLimits/read`, or the `rate_limits` a rollout's
/// `token_count` event carries. Both are one `RateLimitSnapshot` per metered bucket, camelCase on
/// the app-server wire (`codex-rs/app-server-protocol/src/protocol/v2/account.rs`) and snake_case
/// in a rollout (`codex-rs/protocol/src/protocol.rs`).
///
/// Foundation-only, so the KannuTests target compiles it; `CodexQuotaClient` turns it into the
/// card's `UsageLimit`s.
struct CodexLimits: Equatable {
    struct Window: Equatable {
        /// 0–100, as Codex reports it.
        var usedPercent: Double
        var windowMinutes: Int?
        var resetsAt: Date?
    }

    /// A window of a bucket other than the account's main one, such as a per-model limit.
    struct Extra: Equatable {
        /// `<limitId>.primary` or `<limitId>.secondary`: the same on every read, so the forecast's
        /// samples for one window line up.
        var key: String
        var label: String
        var window: Window
    }

    /// One `RateLimitSnapshot`, as read off the wire or a rollout line.
    struct Bucket: Equatable {
        var limitID: String?
        var limitName: String?
        var primary: Window?
        var secondary: Window?
        /// The wire value (`plus`, `pro`, `prolite`, …), not a display name.
        var planType: String?
        /// When a rollout recorded it (the `token_count` line's `timestamp`); nil for the
        /// app-server, whose answer is as new as the read.
        var observedAt: Date? = nil

        var hasWindow: Bool { primary != nil || secondary != nil }
    }

    enum KeyStyle {
        /// `usedPercent`, `windowDurationMins`, `resetsAt`, `limitId`, `planType`.
        case appServer
        /// `used_percent`, `window_minutes`, `resets_at` (or, before `resets_at` existed,
        /// `resets_in_seconds`), `limit_id`, `plan_type`.
        case rollout
    }

    /// The account's main bucket: what `account/rateLimits/read` returns as `rateLimits`, and the
    /// id the server files an id-less snapshot under.
    static let mainLimitID = "codex"

    /// The main bucket's short window (five hours on the plans seen so far).
    var session: Window?
    /// The main bucket's long window (weekly).
    var week: Window?
    var extras: [Extra] = []
    /// Display name of the ChatGPT plan ("Plus"), nil when unknown.
    var planType: String?
    /// When the main bucket's figures were recorded: a rollout's are as old as the last Codex
    /// request on this Mac. nil means now (the app-server's live answer).
    var observedAt: Date? = nil

    var hasLimits: Bool { session != nil || week != nil || !extras.isEmpty }

    /// The same limits without the windows whose reset has passed: their percentage describes a
    /// window that is over.
    func live(at now: Date) -> CodexLimits {
        func isLive(_ window: Window) -> Bool { window.resetsAt.map { $0 > now } ?? true }
        var copy = self
        copy.session = session.flatMap { isLive($0) ? $0 : nil }
        copy.week = week.flatMap { isLive($0) ? $0 : nil }
        copy.extras = extras.filter { isLive($0.window) }
        return copy
    }

    // MARK: Reading a snapshot

    static func bucket(_ value: Any?, style: KeyStyle, observedAt: Date? = nil) -> Bucket? {
        guard let object = value as? [String: Any] else { return nil }
        let isWire = style == .appServer
        return Bucket(limitID: nonEmpty(object[isWire ? "limitId" : "limit_id"]),
                      limitName: nonEmpty(object[isWire ? "limitName" : "limit_name"]),
                      primary: window(object["primary"], style: style, observedAt: observedAt),
                      secondary: window(object["secondary"], style: style, observedAt: observedAt),
                      planType: nonEmpty(object[isWire ? "planType" : "plan_type"]),
                      observedAt: observedAt)
    }

    /// nil for JSON null or a window without a usable percentage. The app-server sends
    /// `usedPercent` as an integer and a rollout as a float; both read as a number.
    static func window(_ value: Any?, style: KeyStyle, observedAt: Date?) -> Window? {
        guard let object = value as? [String: Any] else { return nil }
        let isWire = style == .appServer
        guard let used = (object[isWire ? "usedPercent" : "used_percent"] as? NSNumber)?.doubleValue,
              used.isFinite else { return nil }
        let minutes = (object[isWire ? "windowDurationMins" : "window_minutes"] as? NSNumber)?.intValue
        var resetsAt = (object[isWire ? "resetsAt" : "resets_at"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue) }
        if resetsAt == nil, !isWire, let observedAt,
           let seconds = (object["resets_in_seconds"] as? NSNumber)?.doubleValue {
            resetsAt = observedAt.addingTimeInterval(seconds)
        }
        return Window(usedPercent: used, windowMinutes: minutes, resetsAt: resetsAt)
    }

    // MARK: Mapping to Kannu's slots

    /// The main bucket's primary window is the session limit and its secondary the weekly one;
    /// every other bucket's windows become extras, ordered by bucket id. The plan is the
    /// snapshots' own `planType`, which upstream fills in on every snapshot from the usage
    /// payload (`backend-client/src/client.rs`), so no second request is needed for it.
    static func mapped(main: Bucket?, others: [Bucket]) -> CodexLimits {
        var limits = CodexLimits()
        limits.observedAt = main?.observedAt
        if let main {
            limits.session = main.primary
            limits.week = main.secondary
            // A plan with a single long window reports it as the primary one; it is not a
            // five-hour window, so it is not shown as one.
            if limits.week == nil, let only = limits.session, let minutes = only.windowMinutes, minutes > 24 * 60 {
                limits.week = only
                limits.session = nil
            }
        }
        let mainID = main?.limitID ?? mainLimitID
        let extraBuckets = others
            .filter { $0.limitID != nil && $0.limitID != mainID }
            .sorted { ($0.limitID ?? "") < ($1.limitID ?? "") }
        for bucket in extraBuckets {
            guard let id = bucket.limitID else { continue }
            let name = bucket.limitName ?? id.replacingOccurrences(of: "_", with: " ")
            for (slot, window) in [("primary", bucket.primary), ("secondary", bucket.secondary)] {
                guard let window else { continue }
                limits.extras.append(Extra(key: "\(id).\(slot)", label: label(name, minutes: window.windowMinutes),
                                           window: window))
            }
        }
        limits.planType = planLabel(main?.planType)
            ?? extraBuckets.lazy.compactMap { planLabel($0.planType) }.first
        return limits
    }

    /// "codex other · 7d": a bucket's name and its window length, since one bucket can have two.
    static func label(_ name: String, minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return name }
        let day = 24 * 60
        let span: String
        if minutes % day == 0 {
            span = String(localized: "\(minutes / day)d")
        } else if minutes % 60 == 0 {
            span = String(localized: "\(minutes / 60)h")
        } else {
            span = String(localized: "\(minutes)m")
        }
        return "\(name) · \(span)"
    }

    /// `PlanType`'s wire names (`codex-rs/protocol/src/account.rs`) as the card shows them.
    static func planLabel(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty, raw != "unknown" else { return nil }
        switch raw {
        case "prolite": return "Pro Lite"
        case "promax": return "Pro Max"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else { return nil }
        return string
    }
}

/// The conversation Kannu has with `codex app-server` over stdio: JSON-RPC 2.0 without the
/// `"jsonrpc"` member, one message per line (https://learn.chatgpt.com/docs/app-server.md,
/// "Protocol"). OpenAI calls the app-server experimental and unsupported for production use, so
/// every answer here is checked and anything unexpected falls back to the rollout.
///
/// All three messages are written at once, as the docs' own client does: the server reads its
/// stdin in order and finishes `initialize` before it dispatches the next request. Kannu never
/// opts into `experimentalApi`, never starts a thread or a turn, and asks for nothing but the
/// account's limits. Not `account/read` either: the plan is already in every rate-limit snapshot,
/// and `account/read` would also put the account's email address on Kannu's stdout.
///
/// Shapes checked against `codex-rs/app-server-protocol` (`InitializeParams` in `v1.rs`;
/// `GetAccountRateLimitsResponse`, `RateLimitSnapshot`, `RateLimitWindow` in `v2/account.rs`) and
/// the handler in `app-server/src/request_processors/account_processor.rs`. Codex is not installed
/// on the development Mac: none of this has been run against a real server.
enum CodexAppServerProtocol {
    static let initializeID = 1
    static let rateLimitsID = 2

    /// `clientInfo.name`. OpenAI's Compliance Logs identify an integration by it.
    static let clientName = "kannu"

    /// The JSON-RPC error code the server answers a request it refuses with, among them
    /// "codex account authentication required to read rate limits" and "chatgpt authentication
    /// required to read rate limits".
    static let invalidRequestCode = -32600

    /// `initialize`, the `initialized` notification, `account/rateLimits/read`. `initialized`
    /// carries no `params`, as upstream serializes it; `account/rateLimits/read`'s are optional.
    static func requests(clientVersion: String) -> Data {
        let messages: [[String: Any]] = [
            ["method": "initialize", "id": initializeID,
             "params": ["clientInfo": ["name": clientName, "title": "Kannu", "version": clientVersion]]],
            ["method": "initialized"],
            ["method": "account/rateLimits/read", "id": rateLimitsID],
        ]
        var data = Data()
        for message in messages {
            guard let line = try? JSONSerialization.data(withJSONObject: message,
                                                         options: [.sortedKeys, .withoutEscapingSlashes]) else { continue }
            data.append(line)
            data.append(0x0A)
        }
        return data
    }

    /// One JSON-RPC response: a `result` object or an `error`.
    struct Response {
        var result: [String: Any]?
        var errorCode: Int?
        var errorMessage: String?

        var isError: Bool { errorCode != nil }
    }

    /// The responses in `stdout` so far, by request id. Notifications, server requests and
    /// anything that is not one JSON object on one line are skipped.
    static func responses(in stdout: Data) -> [Int: Response] {
        var responses: [Int: Response] = [:]
        for line in stdout.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["method"] == nil,
                  let id = (object["id"] as? NSNumber)?.intValue else { continue }
            if let error = object["error"] as? [String: Any] {
                responses[id] = Response(errorCode: (error["code"] as? NSNumber)?.intValue ?? 0,
                                         errorMessage: error["message"] as? String)
            } else if let result = object["result"] as? [String: Any] {
                responses[id] = Response(result: result)
            }
        }
        return responses
    }

    /// True once there is nothing more to wait for: the read has been answered, or `initialize`
    /// failed and every request after it will be refused.
    static func isComplete(_ stdout: Data) -> Bool {
        let replies = responses(in: stdout)
        if replies[initializeID]?.isError == true { return true }
        return replies[rateLimitsID] != nil
    }

    enum Outcome: Equatable {
        case limits(CodexLimits)
        /// The server says there is no ChatGPT sign-in to read limits with.
        case notSignedIn
        /// Anything else. The reason is Kannu's own words, safe to log; the server's text never is.
        case failed(String)
    }

    /// What the server's answers add up to.
    static func decode(_ stdout: Data) -> Outcome {
        let replies = responses(in: stdout)
        if let code = replies[initializeID]?.errorCode {
            return .failed("initialize refused (\(code))")
        }
        guard let reply = replies[rateLimitsID] else { return .failed("no answer to account/rateLimits/read") }
        if let code = reply.errorCode {
            if code == invalidRequestCode, reply.errorMessage?.contains("authentication required") == true {
                return .notSignedIn
            }
            return .failed("account/rateLimits/read refused (\(code))")
        }
        guard let result = reply.result else { return .failed("empty answer to account/rateLimits/read") }
        let main = CodexLimits.bucket(result["rateLimits"], style: .appServer)
        let byID = result["rateLimitsByLimitId"] as? [String: Any] ?? [:]
        let others = byID.compactMap { key, value -> CodexLimits.Bucket? in
            guard var bucket = CodexLimits.bucket(value, style: .appServer) else { return nil }
            if bucket.limitID == nil { bucket.limitID = key }
            return bucket
        }
        let limits = CodexLimits.mapped(main: main, others: others)
        return limits.hasLimits ? .limits(limits) : .failed("account/rateLimits/read had no windows")
    }
}

/// Where Codex's limits come from, in the order they are tried.
enum CodexQuotaRoute: String, Equatable {
    /// `codex app-server`'s `account/rateLimits/read`: live, and Codex handles its own sign-in.
    case appServer
    /// The latest `rate_limits` in the newest rollout: no process, no sign-in, as old as the last
    /// Codex request on this Mac.
    case rollout
    /// The undocumented `chatgpt.com/backend-api/wham/usage` with Codex's saved token. Kept only
    /// until the app-server route is verified on a real install; then it goes.
    case whamUsage

    /// A foreground refresh asks the app-server first. The background poll never spawns a
    /// process: it runs every five minutes while an agent works.
    static func order(foreground: Bool) -> [CodexQuotaRoute] {
        foreground ? [.appServer, .rollout, .whamUsage] : [.rollout, .whamUsage]
    }

    /// What the app-server's outcome means for the routes after it. Its "not signed in" is final:
    /// Codex read its own sign-in and found none, so neither a rollout written before a sign-out
    /// nor wham/usage's read of Codex's token may answer instead.
    static func step(_ outcome: CodexAppServerProtocol.Outcome, now: Date) -> CodexRouteStep {
        switch outcome {
        case .limits(let limits):
            let live = limits.live(at: now)
            return live.hasLimits ? .answer(live) : .next
        case .notSignedIn:
            return .notSignedIn
        case .failed:
            return .next
        }
    }

    /// What a rollout's limits mean for the routes after it. They answer only with a live window
    /// of the main bucket: upstream writes one bucket per `token_count` event, so a rollout whose
    /// newest events carry another bucket says nothing about the 5-hour and weekly limits, and
    /// showing its extras alone would hide those two gauges and silence their alerts.
    static func step(rollout limits: CodexLimits?, now: Date) -> CodexRouteStep {
        guard let live = limits?.live(at: now), live.session != nil || live.week != nil else { return .next }
        return .answer(live)
    }

    /// The first route in `routes` that answers, and its answer. Later routes are never tried.
    static func firstAnswer<Answer>(from routes: [CodexQuotaRoute],
                                    _ attempt: (CodexQuotaRoute) async -> Answer?) async -> (route: CodexQuotaRoute, answer: Answer)? {
        for route in routes {
            if let answer = await attempt(route) { return (route, answer) }
        }
        return nil
    }
}

/// One route's verdict, decided here so that the order's privacy rules are tested: a `next` from
/// the wrong place lets Kannu read Codex's token when it should not.
enum CodexRouteStep: Equatable {
    /// Show these limits, windows past their reset already dropped; later routes are not tried.
    case answer(CodexLimits)
    /// No ChatGPT sign-in: show that, and try nothing after it.
    case notSignedIn
    /// No usable answer: try the next route.
    case next
}
