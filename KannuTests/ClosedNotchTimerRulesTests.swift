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

/// A running timer keeps the closed notch. `ContentView`'s closed notch is one if/else-if chain in
/// which the first match wins, and the standalone agent light sat above the timer: with no music
/// playing, the light took the whole notch for 7 s after every agent change, while the pointer was
/// on it, and for as long as a high security finding waited — the timer was not drawn at all. Caps
/// Lock's indicator outranked it until released, and on a display without a notch the island hid
/// until hover with a timer running. The chain lives in a SwiftUI view with no unit surface, so it
/// is pinned by reading the source, with a planted copy of the old chain for each rule.
final class ClosedNotchTimerRulesTests: XCTestCase {
    private static let contentViewPath = "Kannu/ContentView.swift"
    private static let capsLockPath = "Kannu/managers/CapsLockManager.swift"
    private static let timerActivityPath = "Kannu/components/Timer/TimerLiveActivity.swift"

    func testTheClosedNotchGivesARunningTimerItsPlace() throws {
        XCTAssertEqual(Self.chainProblems(in: try Self.read(Self.contentViewPath)), [])
    }

    func testTheOldChainIsCaught() {
        let planted = """
            private var showAgentTrafficLight: Bool {
                if isClosedMusicPairingEligible { return true }
                return agentLightDeadline != nil || isHovering
            }
            private var shouldHideUntilHover: Bool {
                hideUntilHoverAppliesHere
                    && !showAgentTrafficLight
            }
                      } else if vm.notchState == .closed && capsLockManager.isCapsLockActive && Defaults[.enableCapsLockIndicator] && !vm.hideOnClosed && !lockScreenManager.isLocked {
                          InlineHUD(type: .constant(.capsLock))
                      } else if !isCurrentScreenExpansionVisible && vm.notchState == .closed && showAgentTrafficLight && !vm.hideOnClosed {
                          // No music playing: standalone traffic light.
                            AgentTrafficLightLiveActivity(
                                isHovering: isHovering
                            )
                      } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .timer) && vm.notchState == .closed && timerManager.isTimerActive && coordinator.timerLiveActivityEnabled && !vm.hideOnClosed {
                          TimerLiveActivity()
                      }
            """
        XCTAssertEqual(Self.chainProblems(in: planted), [
            "no single timerOwnsClosedNotch definition",
            "the light does not hold steady inside a running timer",
            "an island that hides until hover hides a running timer",
            "Caps Lock's indicator outranks a running timer",
            "the standalone agent light outranks a running timer",
            "the timer's branch is not timerOwnsClosedNotch",
            "the timer does not carry the agent light",
        ])
    }

    /// The light drawn in the timer's centre, in the music pill's place for it.
    func testTheTimerDrawsTheLightInItsCentre() throws {
        let text = try Self.read(Self.timerActivityPath)
        let middle = try XCTUnwrap(Self.body(after: "private func middleSectionView()", in: text), "middleSectionView is gone")
        XCTAssertTrue(middle.contains("if let agentLight") && middle.contains("AgentTrafficLightIndicator()"),
                      "the timer's centre no longer draws the agent light")
        XCTAssertTrue(middle.contains("agentLight?.expandedHeight ?? notchContentHeight"),
                      "below a physical notch the centre must take the agent band's height")
    }

    func testCapsLockFlashesWhileATimerRuns() throws {
        XCTAssertEqual(Self.capsLockProblems(in: try Self.read(Self.capsLockPath)), [])
    }

    func testTheOldCapsLockIsCaught() {
        let planted = """
            if newState {
                coordinator.toggleSneakPeek(
                    status: true,
                    type: .capsLock,
                    duration: .infinity, // Stay visible until deactivated
                    value: 1.0
                )
            }
            """
        XCTAssertEqual(Self.capsLockProblems(in: planted), [
            "Caps Lock holds the notch until released while a timer runs",
            "a timer that starts with Caps Lock on does not end its indicator",
        ])
        // Ending whatever HUD is up is not ending Caps Lock's: a volume change must survive.
        let blind = planted
            .replacingOccurrences(of: "duration: .infinity, // Stay visible until deactivated",
                                  with: "duration: timerHoldsClosedNotch ? Self.flashDuration : .infinity,")
            + """

            timerObserver = TimerManager.shared.$isTimerActive
                .removeDuplicates()
                .sink { [weak self] _ in self?.endHeldIndicatorForTimer() }
            private func endHeldIndicatorForTimer() {
                coordinator.toggleSneakPeek(status: false, type: .capsLock, duration: 0, value: 0, icon: "")
            }
            """
        XCTAssertEqual(Self.capsLockProblems(in: blind), ["the timer ends a sneak peek that is not Caps Lock's"])
    }

    // MARK: - Rules

    static func chainProblems(in text: String) -> [String] {
        var problems: [String] = []
        let owns = body(after: "private var timerOwnsClosedNotch: Bool", in: text) ?? ""
        if !["vm.notchState == .closed", "timerManager.isTimerActive", "coordinator.timerLiveActivityEnabled", "!vm.hideOnClosed"]
            .allSatisfy(owns.contains) {
            problems.append("no single timerOwnsClosedNotch definition")
        }
        let light = body(after: "private var showAgentTrafficLight: Bool", in: text) ?? ""
        if !light.contains("if isClosedMusicPairingEligible || timerOwnsClosedNotch { return true }") {
            problems.append("the light does not hold steady inside a running timer")
        }
        let hide = body(after: "private var shouldHideUntilHover: Bool", in: text) ?? ""
        if !hide.contains("!timerOwnsClosedNotch") {
            problems.append("an island that hides until hover hides a running timer")
        }
        let capsLock = branchCondition(ofLineContaining: "capsLockManager.isCapsLockActive && Defaults[.enableCapsLockIndicator]", in: text) ?? ""
        if !capsLock.contains("!timerOwnsClosedNotch") {
            problems.append("Caps Lock's indicator outranks a running timer")
        }
        let agent = branchCondition(above: "AgentTrafficLightLiveActivity(", in: text) ?? ""
        if !agent.contains("!timerOwnsClosedNotch") {
            problems.append("the standalone agent light outranks a running timer")
        }
        let timer = branchCondition(above: "TimerLiveActivity(", in: text) ?? ""
        if !timer.hasSuffix("&& timerOwnsClosedNotch {") {
            problems.append("the timer's branch is not timerOwnsClosedNotch")
        }
        let call = text.range(of: "TimerLiveActivity(").map { String(text[$0.upperBound...].prefix(200)) } ?? ""
        if !call.contains("agentLight: showAgentTrafficLight") {
            problems.append("the timer does not carry the agent light")
        }
        return problems
    }

    static func capsLockProblems(in text: String) -> [String] {
        var problems: [String] = []
        if !text.contains("duration: timerHoldsClosedNotch ? Self.flashDuration : .infinity") {
            problems.append("Caps Lock holds the notch until released while a timer runs")
        }
        guard text.contains("$isTimerActive"), text.contains("self?.endHeldIndicatorForTimer()"),
              let end = body(after: "private func endHeldIndicatorForTimer()", in: text) else {
            problems.append("a timer that starts with Caps Lock on does not end its indicator")
            return problems
        }
        if !end.contains("coordinator.sneakPeek.type == .capsLock") {
            problems.append("the timer ends a sneak peek that is not Caps Lock's")
        }
        return problems
    }

    // MARK: - Source reading

    private static func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The braces' content after `signature`, matched by depth; nil when the signature is gone.
    static func body(after signature: String, in text: String) -> String? {
        guard let start = text.range(of: signature),
              let open = text[start.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < text.endIndex {
            switch text[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(text[text.index(after: open)..<index]) }
            default: break
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// The `} else if … {` line that opens the branch drawing `call`: the nearest one above it.
    static func branchCondition(above call: String, in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let at = lines.firstIndex(where: { $0.contains(call) }) else { return nil }
        return lines[..<at].last(where: { $0.contains("} else if ") })?.trimmingCharacters(in: .whitespaces)
    }

    /// The `} else if … {` line itself that contains `fragment`.
    static func branchCondition(ofLineContaining fragment: String, in text: String) -> String? {
        text.components(separatedBy: "\n")
            .first(where: { $0.contains(fragment) && $0.contains("} else if ") })?
            .trimmingCharacters(in: .whitespaces)
    }
}
