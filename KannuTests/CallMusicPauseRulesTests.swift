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

/// "Pause music during calls": the pauser is a subscription and one command, with no unit surface,
/// so its wiring is pinned by reading the source, each rule against a planted offender.
///
/// What David decided (2026-11-27): on by default, pause only. A call pauses the music once, as
/// it starts; nothing resumes it, and nothing toggles it.
final class CallMusicPauseRulesTests: XCTestCase {
    private static let pauserPath = "Kannu/managers/CallMusicPauser.swift"
    private static let policyPath = "Kannu/models/CallMusicPolicy.swift"
    private static let appPath = "Kannu/KannuApp.swift"

    private static func read(_ path: String) throws -> String {
        try ClosedCallPillRulesTests.read(path)
    }

    // MARK: - Only pause()

    func testThePauserSendsOnlyAnExplicitPause() throws {
        XCTAssertEqual(Self.commandProblems(in: try Self.read(Self.pauserPath)), [])
    }

    func testAToggleOrASecondPauseIsCaught() throws {
        let real = try Self.read(Self.pauserPath)
        XCTAssertEqual(Self.commandProblems(in: real.replacingOccurrences(of: "music.pause()", with: "music.togglePlay()")),
                       ["the pauser does not send music.pause()", "the pauser sends togglePlay"])
        XCTAssertEqual(Self.commandProblems(in: real.replacingOccurrences(of: "music.pause()", with: "music.playPause()")),
                       ["the pauser does not send music.pause()", "the pauser sends playPause"])
        XCTAssertEqual(Self.commandProblems(in: real.replacingOccurrences(of: "music.pause()", with: "music.pause()\n        music.pause()")),
                       ["the pauser sends more than one pause"])
    }

    func testAPauseOutsideThePolicysAnswerIsCaught() throws {
        let real = try Self.read(Self.pauserPath)
        XCTAssertEqual(Self.commandProblems(in: real.replacingOccurrences(of: "guard decision == .pause, let next else { return }",
                                                                          with: "guard let next else { return }")),
                       ["the pause is not behind the policy's .pause"])
    }

    // MARK: - The setting gate

    func testThePauserIsGatedOnBothSwitches() throws {
        XCTAssertEqual(Self.gateProblems(pauser: try Self.read(Self.pauserPath), policy: try Self.read(Self.policyPath)), [])
    }

    func testAMissingGateIsCaught() throws {
        let pauser = try Self.read(Self.pauserPath)
        let policy = try Self.read(Self.policyPath)
        XCTAssertEqual(Self.gateProblems(pauser: pauser.replacingOccurrences(of: "Defaults[.enableCallActivity] && Defaults[.pauseMusicDuringCalls]",
                                                                             with: "Defaults[.enableCallActivity]"), policy: policy),
                       ["the pauser does not read pauseMusicDuringCalls"])
        XCTAssertEqual(Self.gateProblems(pauser: pauser.replacingOccurrences(of: "isEnabled: Self.isEnabled", with: "isEnabled: true"), policy: policy),
                       ["the policy is not asked with the switches"])
        XCTAssertEqual(Self.gateProblems(pauser: pauser, policy: policy.replacingOccurrences(of: "guard isEnabled, isPlaying,", with: "guard isPlaying,")),
                       ["the policy does not check the switch"])
    }

    // MARK: - stop(), and its owner

    func testTheOwnerStartsAndStopsThePauser() throws {
        XCTAssertEqual(Self.lifecycleProblems(app: try Self.read(Self.appPath), pauser: try Self.read(Self.pauserPath)), [])
    }

    func testAPauserThatOutlivesItsSwitchIsCaught() throws {
        let app = try Self.read(Self.appPath)
        let pauser = try Self.read(Self.pauserPath)
        XCTAssertEqual(Self.lifecycleProblems(app: app.replacingOccurrences(of: "CallMusicPauser.shared.stop()", with: ""), pauser: pauser),
                       ["switching Calls off does not stop the pauser"])
        XCTAssertEqual(Self.lifecycleProblems(app: app, pauser: pauser.replacingOccurrences(of: "subscription?.cancel()", with: "")),
                       ["stop() does not cancel the subscription"])
        XCTAssertEqual(Self.lifecycleProblems(app: app, pauser: pauser.replacingOccurrences(of: "func stop()", with: "func halt()")),
                       ["the pauser has no stop()"])
        // The launch start taken out (the switches' sinks, inside continueLaunch() too, keep theirs).
        let early = app.replacingOccurrences(of: "CallActivityManager.shared.startMonitoring()\n            CallMusicPauser.shared.sync()",
                                             with: "CallActivityManager.shared.startMonitoring()")
        XCTAssertEqual(Self.lifecycleProblems(app: early, pauser: pauser), ["the pauser is not started beside the call monitor in continueLaunch()"])
        let ungated = app.replacingOccurrences(of: "Defaults.publisher(.pauseMusicDuringCalls, options: [])", with: "Defaults.publisher(.enableHaptics, options: [])")
        XCTAssertEqual(Self.lifecycleProblems(app: ungated, pauser: pauser), ["switching Pause music during calls does nothing"])
    }

    // MARK: - No resume, no play

    func testNothingResumesTheMusic() throws {
        XCTAssertEqual(Self.resumeProblems(in: [try Self.read(Self.pauserPath), try Self.read(Self.policyPath)]), [])
    }

    func testAResumeIsCaught() throws {
        let pauser = try Self.read(Self.pauserPath)
        let policy = try Self.read(Self.policyPath)
        let resumed = pauser.replacingOccurrences(of: "    private func handle(", with: """
                private func callEnded() {
                    MusicManager.shared.play()
                }

                private func handle(
            """)
        XCTAssertEqual(Self.resumeProblems(in: [resumed, policy]), ["a play() path"])
        XCTAssertEqual(Self.resumeProblems(in: [pauser, policy.replacingOccurrences(of: "case none", with: "case none\n        case resume")]),
                       ["a resume path"])
    }

    // MARK: - Rules

    /// The source with comments taken out, so a doc comment that names what is never done never counts.
    static func code(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            guard let comment = line.range(of: "//") else { return line }
            return String(line[..<comment.lowerBound])
        }.joined(separator: "\n")
    }

    static func commandProblems(in text: String) -> [String] {
        let code = code(text)
        var problems: [String] = []
        let pauses = code.components(separatedBy: "music.pause()").count - 1
        if pauses == 0 { problems.append("the pauser does not send music.pause()") }
        if pauses > 1 { problems.append("the pauser sends more than one pause") }
        for command in ["togglePlay", "playPause"] where code.contains(command) {
            problems.append("the pauser sends \(command)")
        }
        if pauses > 0, let gate = code.range(of: "guard decision == .pause"),
           let pause = code.range(of: "music.pause()"), gate.lowerBound < pause.lowerBound {
            // The pause follows the policy's answer.
        } else if pauses > 0 {
            problems.append("the pause is not behind the policy's .pause")
        }
        return problems
    }

    static func gateProblems(pauser: String, policy: String) -> [String] {
        let pauser = code(pauser)
        var problems: [String] = []
        let enabled = ClosedNotchTimerRulesTests.body(after: "static var isEnabled: Bool", in: pauser) ?? ""
        if !enabled.contains("Defaults[.pauseMusicDuringCalls]") { problems.append("the pauser does not read pauseMusicDuringCalls") }
        if !enabled.contains("Defaults[.enableCallActivity]") { problems.append("the pauser does not read enableCallActivity") }
        if !pauser.contains("isEnabled: Self.isEnabled") { problems.append("the policy is not asked with the switches") }
        if !code(policy).contains("guard isEnabled,") { problems.append("the policy does not check the switch") }
        return problems
    }

    static func lifecycleProblems(app: String, pauser: String) -> [String] {
        var problems: [String] = []
        let launch = ClosedNotchTimerRulesTests.body(after: "private func continueLaunch()", in: app) ?? ""
        if !launch.contains("CallActivityManager.shared.startMonitoring()\n            CallMusicPauser.shared.sync()") {
            problems.append("the pauser is not started beside the call monitor in continueLaunch()")
        }
        let calls = app.range(of: "Defaults.publisher(.enableCallActivity, options: [])").map { String(app[$0.upperBound...].prefix(600)) } ?? ""
        if !calls.contains("CallActivityManager.shared.stopMonitoring()\n                    CallMusicPauser.shared.stop()") {
            problems.append("switching Calls off does not stop the pauser")
        }
        let own = app.range(of: "Defaults.publisher(.pauseMusicDuringCalls, options: [])").map { String(app[$0.upperBound...].prefix(300)) } ?? ""
        if !own.contains("CallMusicPauser.shared.sync()") { problems.append("switching Pause music during calls does nothing") }

        if let stop = ClosedNotchTimerRulesTests.body(after: "func stop()", in: pauser) {
            if !stop.contains("subscription?.cancel()") { problems.append("stop() does not cancel the subscription") }
        } else {
            problems.append("the pauser has no stop()")
        }
        let sync = ClosedNotchTimerRulesTests.body(after: "func sync()", in: pauser) ?? ""
        if !sync.contains("stop()") { problems.append("sync() never stops the pauser") }
        return problems
    }

    static func resumeProblems(in texts: [String]) -> [String] {
        let code = texts.map(code).joined(separator: "\n")
        var problems: [String] = []
        if code.contains(".play()") { problems.append("a play() path") }
        if code.range(of: "resume", options: .caseInsensitive) != nil { problems.append("a resume path") }
        return problems
    }
}
