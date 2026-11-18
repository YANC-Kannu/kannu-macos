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

/// The sideways agent pill (David, 2026-11-18): on a notched MacBook the light sits beside the housing
/// with the agent's app icon opposite, it shows only on a state switch, and while it shows it takes the
/// closed notch from music and a running timer, which then return with no light in their centre. Since
/// 2026-11-18 it is the only light on a notched MacBook: the 1.x band below the notch and the Classic
/// three-dot style are gone (David: "we dont want the old legacy path, actually remove it", "no need
/// clasic"). Displays without a notch keep their centred light. The closed notch is one
/// if/else-if chain in a SwiftUI view with no unit surface, so these rules read the source, each
/// checked against a planted offender.
final class ClosedAgentPillRulesTests: XCTestCase {
    private static let contentViewPath = "Kannu/ContentView.swift"
    private static let activityPath = "Kannu/components/AgentStatus/AgentTrafficLightLiveActivity.swift"
    private static let lockPillPath = "Kannu/components/LockScreen/LockScreenLiveActivityOverlay.swift"
    private static let lockManagerPath = "Kannu/managers/LockScreenLiveActivityWindowManager.swift"
    private static let constantsPath = "Kannu/models/Constants.swift"

    // MARK: - Priority, no stacking

    func testTheSidewaysPillComesBeforeMusicAndTheTimer() throws {
        XCTAssertEqual(Self.priorityProblems(in: try Self.read(Self.contentViewPath)), [])
    }

    func testAChainWithMusicFirstIsCaught() {
        let planted = """
                      } else if canShowMusicDuringExpansion && musicPairingEligible {
                          MusicLiveActivity(secondary: musicSecondary)
                      } else if isPhysicalNotchScreen && !isCurrentScreenExpansionVisible && vm.notchState == .closed && showAgentTrafficLight {
                          sidewaysAgentPill()
                      } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .timer) && timerOwnsClosedNotch {
                          TimerLiveActivity(
            """
        XCTAssertEqual(Self.priorityProblems(in: planted), [
            "the sideways pill is not drawn ahead of the music pill",
            "the sideways pill's branch is not held to the reveal window",
            "the sideways pill ignores the fullscreen hide (!vm.hideOnClosed)",
        ])
    }

    func testMusicAndTheTimerCarryNoLightSideways() throws {
        XCTAssertEqual(Self.stackingProblems(in: try Self.read(Self.contentViewPath)), [])
    }

    func testTheStackedLightIsCaught() {
        let planted = """
            private var showAgentTrafficLight: Bool {
                if isClosedMusicPairingEligible || timerOwnsClosedNotch { return true }
                return agentLightDeadline != nil || isHovering
            }
                .overlay {
                    if showAgentTrafficLight {
                        AgentTrafficLightIndicator()
                    }
                }
                          TimerLiveActivity(
                              showsAgentLight: showAgentTrafficLight
            """
        XCTAssertEqual(Self.stackingProblems(in: planted), [
            "music or a timer still holds the light lit in sideways mode",
            "the music pill draws the light in its centre in sideways mode",
            "the timer draws the light in its centre in sideways mode",
        ])
    }

    // MARK: - No band, one light

    /// The band below a physical notch and the Classic style are gone, with their settings: nothing in the
    /// app names them, and the centred light stays for displays without a notch and the Dynamic Island.
    func testNoBandAndOneLight() throws {
        let sources = try Self.appSources()
        XCTAssertGreaterThan(sources.count, 100, "the scan read too few files")
        for (path, text) in sources {
            for gone in ["AgentPillLayout", "AgentTrafficLightStyle", "physicalNotchAgentTrafficLight",
                         "shouldExpandPhysicalNotchForAgent", "usesSidewaysAgentPill",
                         "bandBody", "TimerAgentLight"] where Self.usesWord(gone, in: Self.code(text)) {
                XCTFail("\(path) still uses \(gone)")
            }
        }

        let content = try Self.read(Self.contentViewPath)
        let activity = try Self.read(Self.activityPath)
        XCTAssertTrue(activity.contains("var sideways = false"), "the centred light must stay the activity's default")
        let centred = try XCTUnwrap(ClosedNotchTimerRulesTests.body(after: "private var centredBody: some View", in: activity))
        XCTAssertTrue(centred.contains("SecurityAlertPill("), "the shield-and-title pill stays with the centred light")
        XCTAssertTrue(centred.contains(".frame(width: contentWidth, height: notchContentHeight)"))
        XCTAssertTrue(content.contains("sideways: isPhysicalNotchScreen"),
                      "sideways must apply on a notched MacBook only: notchless and island displays keep their light")

        let dots = try XCTUnwrap(ClosedNotchTimerRulesTests.body(after: "struct AgentTrafficLightDots: View", in: activity))
        XCTAssertTrue(dots.contains("if let litColor {\n            dot(litColor)\n        }"), "the light draws more than the lit dot")
    }

    /// The two stored choices are removed on launch, as the minimalistic UI's keys are.
    func testTheRemovedChoicesAreCleanedUp() throws {
        let constants = try Self.read(Self.constantsPath)
        let migrate = try XCTUnwrap(ClosedNotchTimerRulesTests.body(after: "static func migrateRemovedAgentLightChoices()", in: constants))
        XCTAssertTrue(migrate.contains(#"["agentTrafficLightStyle", "agentPillLayout"]"#))
        XCTAssertTrue(migrate.contains("UserDefaults.standard.removeObject(forKey: key)"))
        let app = try Self.read("Kannu/KannuApp.swift")
        XCTAssertTrue(app.contains("Defaults.Keys.migrateRemovedMinimalisticUI()\n        Defaults.Keys.migrateRemovedAgentLightChoices()"),
                      "the cleanup no longer runs beside the other removed-feature migrations")
    }

    // MARK: - The icon

    func testTheIconNeverMoves() throws {
        let activity = try Self.read(Self.activityPath)
        for type in ["struct AgentPillIcon", "struct AgentSidewaysPillRow", "struct AgentLockPillRow"] {
            let body = try XCTUnwrap(ClosedNotchTimerRulesTests.body(after: type, in: activity), "\(type) is gone")
            XCTAssertEqual(Self.motion(in: body), [], "\(type) animates; the icon must stay still (CHANGELOG 2026-08-19)")
        }
    }

    func testAPulsingIconIsCaught() {
        let planted = """
                AgentProviderIconView(source: source, size: size)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            """
        XCTAssertEqual(Self.motion(in: planted), ["scaleEffect", "repeatForever", ".animation("])
    }

    /// Every placement is drawn by the one view that observes the monitor (`ClosedNotchObservationTests`
    /// pins the count): the icon and the dots follow the same session, and the lock pill reads the mirror.
    func testOneObserverDrawsEveryPlacement() throws {
        let activity = try Self.read(Self.activityPath)
        let indicator = try XCTUnwrap(ClosedNotchTimerRulesTests.body(after: "struct AgentTrafficLightIndicator: View", in: activity))
        for placement in ["case let .beside(", "case let .lockPill(", "AgentSidewaysPillRow(", "AgentLockPillRow("] {
            XCTAssertTrue(indicator.contains(placement), "the indicator no longer draws \(placement)")
        }
        let lock = try Self.read(Self.lockPillPath)
        XCTAssertTrue(lock.contains("AgentTrafficLightIndicator(placement: .lockPill("))
        XCTAssertTrue(lock.contains("@ObservedObject private var agentLight = CursorAgentStatusMonitor.shared.projection"))
    }

    // MARK: - Reduce Motion

    func testReduceMotionFadesTheWings() throws {
        let content = try Self.read(Self.contentViewPath)
        let animation = try XCTUnwrap(ClosedNotchTimerRulesTests.body(after: "private var agentRevealAnimation: Animation?", in: content))
        XCTAssertTrue(animation.contains("isPhysicalNotchScreen && reduceMotion ? nil : vm.animation"),
                      "under Reduce Motion the notch must not slide its wings out")
        let transition = try XCTUnwrap(ClosedNotchTimerRulesTests.body(after: "private var agentLightTransition: AnyTransition", in: content))
        XCTAssertTrue(transition.contains("? .opacity"), "under Reduce Motion the wings fade")
        // Every reveal and collapse moves through it: the pulse, the attention flash and the expiry.
        let uses = content.components(separatedBy: "withAnimation(agentRevealAnimation)").count - 1
            + content.components(separatedBy: "withAnimation(self.agentRevealAnimation)").count - 1
        XCTAssertEqual(uses, 3)
        XCTAssertFalse(content.contains("withAnimation(vm.animation) {\n                agentLightDeadline"),
                       "a reveal still animates with vm.animation directly")
        let helper = try XCTUnwrap(ClosedNotchTimerRulesTests.body(after: "private func sidewaysAgentPill()", in: content))
        XCTAssertTrue(helper.contains(".transition(agentLightTransition)"))
    }

    func testNothingNewRepeats() throws {
        for path in [Self.activityPath, Self.lockPillPath, "Kannu/sizing/ClosedAgentPillLayout.swift"] {
            // Code only: the comments name what was removed.
            let text = try Self.read(path).components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            XCTAssertFalse(text.contains(".repeatForever"), "\(path) repeats forever (docs/REGRESSIONS.md entry 22)")
            XCTAssertFalse(text.contains("TimelineView"), "\(path) runs a clock")
        }
    }

    // MARK: - The lock-screen pill

    func testTheLockPillRevealsOnASwitchWhileLockedAndOnTheFlash() throws {
        let lock = try Self.read(Self.lockPillPath)
        let arm = try XCTUnwrap(ClosedNotchTimerRulesTests.body(after: "private func armAgentReveal()", in: lock))
        for clause in ["enableAgentStatusFeature", "LockScreenManager.shared.isLocked",
                       "notchRevealHoldSeconds"] {
            XCTAssertTrue(arm.contains(clause), "the lock pill's reveal lost \(clause)")
        }
        XCTAssertTrue(lock.contains(".onChange(of: agentLight.trafficLightState)"), "a switch no longer arms it")
        XCTAssertTrue(lock.contains("try? await Task.sleep"), "one sleep ends the reveal")

        let manager = try Self.read(Self.lockManagerPath)
        XCTAssertTrue(manager.contains("guard Defaults[.enableLockScreenLiveActivity] || forAttentionAlert else {"),
                      "the pill follows the lock-screen live activity setting, the attention flash aside")
        let flash = try XCTUnwrap(ClosedNotchTimerRulesTests.body(after: "func flashForAttentionAlert(duration: TimeInterval)", in: manager))
        XCTAssertTrue(flash.contains("overlayModel.showsAgentForAlert = true"),
                      "the attention flash no longer carries the dot and icon")
        let size = try XCTUnwrap(ClosedNotchTimerRulesTests.body(after: "private func windowSize(for notchSize: CGSize) -> CGSize", in: manager))
        XCTAssertTrue(size.contains("let totalWidth = notchSize.width + (indicatorWidth * 2) + (horizontalPadding * 2)"),
                      "the lock pill's window must keep its size: the reveal draws inside its wings (entry 17)")
    }

    // MARK: - Rules

    static func priorityProblems(in text: String) -> [String] {
        var problems: [String] = []
        let lines = text.components(separatedBy: "\n")
        let pill = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "sidewaysAgentPill()" }
        let music = lines.firstIndex { $0.contains("MusicLiveActivity(secondary: musicSecondary)") }
        let timer = lines.firstIndex { $0.contains("TimerLiveActivity(") }
        guard let pill else { return ["the sideways pill is not in the chain"] }
        if let music, music < pill { problems.append("the sideways pill is not drawn ahead of the music pill") }
        if let timer, timer < pill { problems.append("the sideways pill is not drawn ahead of the timer") }
        let condition = lines[..<pill].last { $0.contains("} else if ") } ?? ""
        if !condition.contains("isPhysicalNotchScreen") {
            problems.append("the sideways pill's branch is not sideways-only")
        }
        if !condition.contains("agentLightDeadline != nil") {
            problems.append("the sideways pill's branch is not held to the reveal window")
        }
        if !condition.contains("!vm.hideOnClosed") {
            problems.append("the sideways pill ignores the fullscreen hide (!vm.hideOnClosed)")
        }
        return problems
    }

    static func stackingProblems(in text: String) -> [String] {
        var problems: [String] = []
        let light = ClosedNotchTimerRulesTests.body(after: "private var showAgentTrafficLight: Bool", in: text) ?? ""
        if !light.contains("if isNonNotchScreen {\n            if isClosedMusicPairingEligible || timerOwnsClosedNotch { return true }") {
            problems.append("music or a timer still holds the light lit in sideways mode")
        }
        if !text.contains("if showAgentTrafficLight && isNonNotchScreen {\n                        AgentTrafficLightIndicator()") {
            problems.append("the music pill draws the light in its centre in sideways mode")
        }
        if !text.contains("showsAgentLight: showAgentTrafficLight && isNonNotchScreen") {
            problems.append("the timer draws the light in its centre in sideways mode")
        }
        return problems
    }

    /// Any motion applied in `text`.
    static func motion(in text: String) -> [String] {
        ["scaleEffect", "repeatForever", ".animation(", "withAnimation", "TimelineView", "symbolEffect", "phaseAnimator",
         "keyframeAnimator", "rotationEffect"].filter(text.contains)
    }

    /// Every Swift file under `Kannu/`, keyed by its repository path.
    private static func appSources() throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var result: [String: String] = [:]
        let files = FileManager.default.enumerator(at: root.appendingPathComponent("Kannu"), includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            result[String(url.path.dropFirst(root.path.count + 1))] = try String(contentsOf: url, encoding: .utf8)
        }
        return result
    }

    /// Whether `word` appears in `text` as a whole identifier: `AgentPillLayout` is not `ClosedAgentPillLayout`.
    static func usesWord(_ word: String, in text: String) -> Bool {
        text.range(of: "(?<![A-Za-z0-9_])" + NSRegularExpression.escapedPattern(for: word) + "(?![A-Za-z0-9_])",
                   options: .regularExpression) != nil
    }

    func testAWholeWordIsCaughtAndALongerNameIsNot() {
        XCTAssertTrue(Self.usesWord("AgentPillLayout", in: "@Default(.x) var y: AgentPillLayout"))
        XCTAssertTrue(Self.usesWord("AgentPillLayout", in: "Key<AgentPillLayout>(\"agentPillLayout\")"))
        XCTAssertFalse(Self.usesWord("AgentPillLayout", in: "ClosedAgentPillLayout(closedHeight: 32)"))
        XCTAssertFalse(Self.usesWord("AgentPillLayout", in: "AgentPillLayoutPreview()"))
    }

    /// Code only: comments may name what was removed.
    private static func code(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private static func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
