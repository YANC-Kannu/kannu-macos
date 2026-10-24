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

import XCTest

/// `codex app-server` over stdio. Every fixture follows the shapes in the docs
/// (https://learn.chatgpt.com/docs/app-server.md, "Initialization" and "6) Rate limits (ChatGPT)")
/// and in `codex-rs/app-server-protocol` (`v1.rs` `InitializeParams`/`InitializeResponse`,
/// `v2/account.rs` `GetAccountRateLimitsResponse`/`RateLimitSnapshot`/`RateLimitWindow`, and
/// `account_processor.rs` for the error texts). Codex is not installed on
/// the development Mac, so these fixtures are the only check of the protocol.
final class CodexAppServerProtocolTests: XCTestCase {
    // MARK: - Fixtures

    private static let initializeAnswer = #"{"id":1,"result":{"userAgent":"kannu/2.0 (Mac OS 15.6.0; arm64) unknown (kannu; 2.0)","codexHome":"/Users/dev/.codex","platformFamily":"unix","platformOs":"macos"}}"#

    private static func snapshot(id: String = "codex", name: String? = nil, primary: String?, secondary: String?,
                                 plan: String? = "plus") -> String {
        let nameJSON = name.map { "\"\($0)\"" } ?? "null"
        let planJSON = plan.map { "\"\($0)\"" } ?? "null"
        return #"{"limitId":"\#(id)","limitName":\#(nameJSON),"normalModelSlug":null,"primary":\#(primary ?? "null"),"secondary":\#(secondary ?? "null"),"credits":{"hasCredits":false,"unlimited":false,"balance":null},"individualLimit":null,"spendControlReached":null,"planType":\#(planJSON),"rateLimitReachedType":null}"#
    }

    private static let fiveHour = #"{"usedPercent":25,"windowDurationMins":300,"resetsAt":1792231200}"#
    private static let weekly = #"{"usedPercent":40,"windowDurationMins":10080,"resetsAt":1792749600}"#

    private static func rateLimitsAnswer(main: String, byID: [String: String]? = nil) -> String {
        let map = byID.map { entries in
            "{" + entries.keys.sorted().map { "\"\($0)\":\(entries[$0]!)" }.joined(separator: ",") + "}"
        } ?? "null"
        return #"{"id":2,"result":{"ordinaryUsageAllowed":null,"rateLimits":\#(main),"rateLimitsByLimitId":\#(map),"rateLimitResetCredits":null,"accountId":null,"rateLimitUpsell":null}}"#
    }

    private static func error(id: Int, code: Int, message: String) -> String {
        #"{"id":\#(id),"error":{"code":\#(code),"message":"\#(message)"}}"#
    }

    private static func stdout(_ lines: String...) -> Data {
        Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static func lines(of data: Data) throws -> [[String: Any]] {
        try data.split(separator: 0x0A).map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        }
    }

    // MARK: - Requests

    func testRequestsAreTheThreeDocumentedMessagesInOrder() throws {
        let data = CodexAppServerProtocol.requests(clientVersion: "2.0")
        XCTAssertEqual(data.last, 0x0A, "every message ends its line")
        let messages = try Self.lines(of: data)
        // No `account/read`: the plan is in the snapshot, and that answer carries the email address.
        XCTAssertEqual(messages.map { $0["method"] as? String },
                       ["initialize", "initialized", "account/rateLimits/read"])
        XCTAssertEqual(messages.map { ($0["id"] as? NSNumber)?.intValue }, [1, nil, 2])
        // `initialized` is a notification and carries no params, as upstream serializes it;
        // `account/rateLimits/read`'s are optional.
        XCTAssertNil(messages[1]["params"])
        XCTAssertNil(messages[2]["params"])
        XCTAssertTrue(messages.allSatisfy { $0["jsonrpc"] == nil }, "the app-server wire omits the jsonrpc member")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(#"\/"#), "method names are written unescaped")
    }

    func testInitializeIdentifiesKannuAndOptsIntoNothingExperimental() throws {
        let initialize = try XCTUnwrap(Self.lines(of: CodexAppServerProtocol.requests(clientVersion: "2.0.1")).first)
        let params = try XCTUnwrap(initialize["params"] as? [String: Any])
        let clientInfo = try XCTUnwrap(params["clientInfo"] as? [String: Any])
        XCTAssertEqual(clientInfo["name"] as? String, "kannu")
        XCTAssertEqual(clientInfo["title"] as? String, "Kannu")
        XCTAssertEqual(clientInfo["version"] as? String, "2.0.1")
        XCTAssertNil(params["capabilities"], "no experimentalApi, no attestation, nothing opted into")
    }

    // MARK: - Waiting

    func testIsCompleteWaitsForTheRateLimitsRead() {
        XCTAssertFalse(CodexAppServerProtocol.isComplete(Data()))
        XCTAssertFalse(CodexAppServerProtocol.isComplete(Self.stdout(Self.initializeAnswer)))
        XCTAssertTrue(CodexAppServerProtocol.isComplete(
            Self.stdout(Self.initializeAnswer, Self.rateLimitsAnswer(main: Self.snapshot(primary: Self.fiveHour, secondary: nil)))))
        // A refusal is an answer too.
        XCTAssertTrue(CodexAppServerProtocol.isComplete(
            Self.stdout(Self.initializeAnswer, Self.error(id: 2, code: -32603, message: "failed to fetch codex rate limits: boom"))))
    }

    func testIsCompleteStopsAtARefusedInitialize() {
        XCTAssertTrue(CodexAppServerProtocol.isComplete(Self.stdout(Self.error(id: 1, code: -32600, message: "Already initialized"))))
        XCTAssertEqual(CodexAppServerProtocol.decode(Self.stdout(Self.error(id: 1, code: -32600, message: "Already initialized"))),
                       .failed("initialize refused (-32600)"))
    }

    func testAPartialLineIsNotAnAnswer() {
        let answer = Self.rateLimitsAnswer(main: Self.snapshot(primary: Self.fiveHour, secondary: nil))
        let cut = Data((Self.initializeAnswer + "\n" + answer.prefix(60)).utf8)
        XCTAssertFalse(CodexAppServerProtocol.isComplete(cut))
        XCTAssertEqual(CodexAppServerProtocol.decode(cut), .failed("no answer to account/rateLimits/read"))
    }

    // MARK: - Decoding

    func testASingleBucketMapsPrimaryToSessionAndSecondaryToWeek() {
        let outcome = CodexAppServerProtocol.decode(Self.stdout(
            Self.initializeAnswer,
            Self.rateLimitsAnswer(main: Self.snapshot(primary: Self.fiveHour, secondary: Self.weekly),
                                  byID: ["codex": Self.snapshot(primary: Self.fiveHour, secondary: Self.weekly)])))
        XCTAssertEqual(outcome, .limits(CodexLimits(
            session: .init(usedPercent: 25.0, windowMinutes: 300, resetsAt: Date(timeIntervalSince1970: 1_792_231_200.0)),
            week: .init(usedPercent: 40.0, windowMinutes: 10080, resetsAt: Date(timeIntervalSince1970: 1_792_749_600.0)),
            extras: [],
            planType: "Plus",
            observedAt: nil)), "a live answer has no observation time of its own")
    }

    func testEveryOtherBucketBecomesLabelledExtras() {
        // The docs' multi-bucket example, with a weekly window added to the second bucket.
        let main = Self.snapshot(primary: #"{"usedPercent":25,"windowDurationMins":15,"resetsAt":1730947200}"#, secondary: nil, plan: nil)
        let other = Self.snapshot(id: "codex_other", name: "codex_other",
                                  primary: #"{"usedPercent":42,"windowDurationMins":60,"resetsAt":1730950800}"#,
                                  secondary: #"{"usedPercent":7,"windowDurationMins":10080,"resetsAt":1731000000}"#, plan: nil)
        let unnamed = Self.snapshot(id: "gpt_spark", primary: Self.fiveHour, secondary: nil, plan: nil)
        let outcome = CodexAppServerProtocol.decode(Self.stdout(
            Self.initializeAnswer,
            Self.rateLimitsAnswer(main: main, byID: ["codex": main, "codex_other": other, "gpt_spark": unnamed])))
        guard case .limits(let limits) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(limits.session?.usedPercent, 25.0)
        XCTAssertNil(limits.week)
        XCTAssertEqual(limits.extras.map(\.key), ["codex_other.primary", "codex_other.secondary", "gpt_spark.primary"])
        XCTAssertEqual(limits.extras.map(\.label), ["codex_other · 1h", "codex_other · 7d", "gpt spark · 5h"])
        XCTAssertEqual(limits.extras.map(\.window.usedPercent), [42.0, 7.0, 25.0])
        XCTAssertNil(limits.planType, "no plan in any snapshot")
    }

    func testMissingWindowsAreNotLimits() {
        let none = CodexAppServerProtocol.decode(Self.stdout(
            Self.initializeAnswer, Self.rateLimitsAnswer(main: Self.snapshot(primary: nil, secondary: nil))))
        XCTAssertEqual(none, .failed("account/rateLimits/read had no windows"))

        let weekOnly = CodexAppServerProtocol.decode(Self.stdout(
            Self.initializeAnswer, Self.rateLimitsAnswer(main: Self.snapshot(primary: nil, secondary: Self.weekly))))
        guard case .limits(let limits) = weekOnly else { return XCTFail("\(weekOnly)") }
        XCTAssertNil(limits.session)
        XCTAssertEqual(limits.week?.usedPercent, 40.0)
    }

    func testASingleLongWindowIsTheWeekNotTheSession() {
        let outcome = CodexAppServerProtocol.decode(Self.stdout(
            Self.initializeAnswer, Self.rateLimitsAnswer(main: Self.snapshot(primary: Self.weekly, secondary: nil))))
        guard case .limits(let limits) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertNil(limits.session, "a 7-day window is not shown as the 5-hour one")
        XCTAssertEqual(limits.week?.windowMinutes, 10080)
    }

    func testTheAuthenticationRefusalsMeanNotSignedIn() {
        for message in ["codex account authentication required to read rate limits",
                        "chatgpt authentication required to read rate limits"] {
            XCTAssertEqual(CodexAppServerProtocol.decode(Self.stdout(
                Self.initializeAnswer, Self.error(id: 2, code: -32600, message: message))), .notSignedIn, message)
        }
    }

    func testOtherRefusalsFailWithoutTheServersWords() {
        let outcome = CodexAppServerProtocol.decode(Self.stdout(
            Self.initializeAnswer,
            Self.error(id: 2, code: -32603, message: "failed to fetch codex rate limits: 401 for user@example.com")))
        XCTAssertEqual(outcome, .failed("account/rateLimits/read refused (-32603)"))
        // A server too old for the method.
        XCTAssertEqual(CodexAppServerProtocol.decode(Self.stdout(
            Self.initializeAnswer, Self.error(id: 2, code: -32601, message: "unknown method"))),
                       .failed("account/rateLimits/read refused (-32601)"))
        // "Not initialized" is the same code as the sign-in refusal, and is not one.
        XCTAssertEqual(CodexAppServerProtocol.decode(Self.stdout(
            Self.initializeAnswer, Self.error(id: 2, code: -32600, message: "Not initialized"))),
                       .failed("account/rateLimits/read refused (-32600)"))
    }

    func testNotificationsServerRequestsAndGarbageAreSkipped() {
        let outcome = CodexAppServerProtocol.decode(Self.stdout(
            "not json at all",
            #"{"method":"mcpServer/startupStatus/updated","params":{"threadId":null,"name":"docs","status":"ready","error":null,"failureReason":null}}"#,
            Self.initializeAnswer,
            #"{"method":"account/rateLimits/updated","params":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":99,"windowDurationMins":300,"resetsAt":1792231200}}}}"#,
            #"{"id":2,"method":"item/tool/requestUserInput","params":{}}"#,
            "[1,2,3]",
            Self.rateLimitsAnswer(main: Self.snapshot(primary: Self.fiveHour, secondary: Self.weekly))))
        guard case .limits(let limits) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(limits.session?.usedPercent, 25.0, "the notification and the server request with id 2 are not the answer")
    }

    func testNoAnswerFails() {
        XCTAssertEqual(CodexAppServerProtocol.decode(Data()), .failed("no answer to account/rateLimits/read"))
        XCTAssertEqual(CodexAppServerProtocol.decode(Self.stdout(Self.initializeAnswer)), .failed("no answer to account/rateLimits/read"))
    }

    func testThePlanIsTheSnapshots() {
        let main = Self.snapshot(primary: Self.fiveHour, secondary: Self.weekly, plan: "prolite")
        let outcome = CodexAppServerProtocol.decode(Self.stdout(Self.initializeAnswer, Self.rateLimitsAnswer(main: main)))
        guard case .limits(let limits) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(limits.planType, "Pro Lite")

        // A main snapshot without one takes the plan another bucket reports.
        let planless = Self.snapshot(primary: Self.fiveHour, secondary: nil, plan: nil)
        let other = Self.snapshot(id: "codex_other", primary: Self.fiveHour, secondary: nil, plan: "pro")
        let fromOther = CodexAppServerProtocol.decode(Self.stdout(
            Self.initializeAnswer, Self.rateLimitsAnswer(main: planless, byID: ["codex": planless, "codex_other": other])))
        guard case .limits(let otherLimits) = fromOther else { return XCTFail("\(fromOther)") }
        XCTAssertEqual(otherLimits.planType, "Pro")
    }

    func testPlanLabels() {
        XCTAssertEqual(CodexLimits.planLabel("plus"), "Plus")
        XCTAssertEqual(CodexLimits.planLabel("pro"), "Pro")
        XCTAssertEqual(CodexLimits.planLabel("promax"), "Pro Max")
        XCTAssertEqual(CodexLimits.planLabel("edu_plus"), "Edu Plus")
        XCTAssertNil(CodexLimits.planLabel("unknown"))
        XCTAssertNil(CodexLimits.planLabel(""))
        XCTAssertNil(CodexLimits.planLabel(nil))
    }

    func testWindowLabels() {
        XCTAssertEqual(CodexLimits.label("Spark", minutes: 300), "Spark · 5h")
        XCTAssertEqual(CodexLimits.label("Spark", minutes: 10080), "Spark · 7d")
        XCTAssertEqual(CodexLimits.label("Spark", minutes: 15), "Spark · 15m")
        XCTAssertEqual(CodexLimits.label("Spark", minutes: nil), "Spark")
    }

    func testLiveDropsWindowsPastTheirReset() {
        let now = Date(timeIntervalSince1970: 1_792_500_000.0)
        let limits = CodexLimits(
            session: .init(usedPercent: 80.0, windowMinutes: 300, resetsAt: Date(timeIntervalSince1970: 1_792_231_200.0)),
            week: .init(usedPercent: 40.0, windowMinutes: 10080, resetsAt: Date(timeIntervalSince1970: 1_792_749_600.0)),
            extras: [.init(key: "x.primary", label: "x", window: .init(usedPercent: 1.0, windowMinutes: nil, resetsAt: nil))],
            planType: "Plus")
        let live = limits.live(at: now)
        XCTAssertNil(live.session, "reset before now")
        XCTAssertEqual(live.week, limits.week)
        XCTAssertEqual(live.extras, limits.extras, "no reset time: kept")
        XCTAssertFalse(CodexLimits(session: limits.session).live(at: now).hasLimits, "nothing left once its only window reset")
    }

    // MARK: - Fallback order

    func testForegroundAsksTheAppServerThenTheRolloutThenWhamUsage() {
        XCTAssertEqual(CodexQuotaRoute.order(foreground: true), [.appServer, .rollout, .whamUsage])
    }

    func testTheBackgroundPollNeverStartsTheAppServer() {
        XCTAssertEqual(CodexQuotaRoute.order(foreground: false), [.rollout, .whamUsage])
    }

    func testTheFirstRouteThatAnswersWinsAndLaterOnesAreNotTried() async {
        var tried: [CodexQuotaRoute] = []
        let answer = await CodexQuotaRoute.firstAnswer(from: CodexQuotaRoute.order(foreground: true)) { route -> String? in
            tried.append(route)
            return route == .rollout ? "from the rollout" : nil
        }
        XCTAssertEqual(tried, [.appServer, .rollout])
        XCTAssertEqual(answer?.route, .rollout)
        XCTAssertEqual(answer?.answer, "from the rollout")
    }

    // MARK: - Each route's verdict

    private static let now = Date(timeIntervalSince1970: 1_792_500_000.0)
    private static let pastReset = Date(timeIntervalSince1970: 1_792_231_200.0)
    private static let futureReset = Date(timeIntervalSince1970: 1_792_749_600.0)

    func testTheAppServersNotSignedInIsFinalAndNeverFallsThrough() {
        // A `next` here would hand the refresh to wham/usage, which reads Codex's token.
        XCTAssertEqual(CodexQuotaRoute.step(.notSignedIn, now: Self.now), .notSignedIn)
    }

    func testAFailedAppServerFallsThrough() {
        XCTAssertEqual(CodexQuotaRoute.step(.failed("no answer to account/rateLimits/read"), now: Self.now), .next)
    }

    func testAnAppServerAnswerIsShownWithoutItsResetWindows() {
        let limits = CodexLimits(session: .init(usedPercent: 90.0, windowMinutes: 300, resetsAt: Self.pastReset),
                                 week: .init(usedPercent: 40.0, windowMinutes: 10080, resetsAt: Self.futureReset))
        XCTAssertEqual(CodexQuotaRoute.step(.limits(limits), now: Self.now),
                       .answer(CodexLimits(week: limits.week)))
    }

    func testAnAppServerAnswerWhoseWindowsAllResetFallsThrough() {
        let limits = CodexLimits(session: .init(usedPercent: 90.0, windowMinutes: 300, resetsAt: Self.pastReset),
                                 extras: [.init(key: "codex_other.primary", label: "codex_other · 5h",
                                                window: .init(usedPercent: 5.0, windowMinutes: 300, resetsAt: Self.pastReset))])
        XCTAssertEqual(CodexQuotaRoute.step(.limits(limits), now: Self.now), .next)
    }

    func testARolloutAnswersOnlyWithALiveMainWindow() {
        let extra = CodexLimits.Extra(key: "codex_other.primary", label: "codex_other · 5h",
                                      window: .init(usedPercent: 60.0, windowMinutes: 300, resetsAt: Self.futureReset))
        let observed = Date(timeIntervalSince1970: 1_792_499_000.0)
        XCTAssertEqual(CodexQuotaRoute.step(rollout: nil, now: Self.now), .next)
        XCTAssertEqual(CodexQuotaRoute.step(rollout: CodexLimits(extras: [extra]), now: Self.now), .next,
                       "another bucket alone would hide the 5-hour and weekly gauges")
        XCTAssertEqual(CodexQuotaRoute.step(rollout: CodexLimits(session: .init(usedPercent: 90.0, windowMinutes: 300, resetsAt: Self.pastReset),
                                                                 extras: [extra]), now: Self.now), .next,
                       "the main window has reset: only the extras are left")
        let live = CodexLimits(week: .init(usedPercent: 40.0, windowMinutes: 10080, resetsAt: Self.futureReset),
                               extras: [extra], observedAt: observed)
        XCTAssertEqual(CodexQuotaRoute.step(rollout: live, now: Self.now), .answer(live), "its observation time is kept")
    }

    func testNoAnswerFromAnyRouteIsNil() async {
        var tried: [CodexQuotaRoute] = []
        let answer = await CodexQuotaRoute.firstAnswer(from: CodexQuotaRoute.order(foreground: false)) { route -> String? in
            tried.append(route)
            return nil
        }
        XCTAssertEqual(tried, [.rollout, .whamUsage])
        XCTAssertNil(answer)
    }
}
