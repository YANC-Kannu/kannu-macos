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

/// The attention alert's rules: one alert per session per yellow episode, one for several sessions at
/// once, nothing for yellows that were already showing, nothing until every gate is open, and a still
/// glow under Reduce Motion.
final class AttentionAlertTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_788_000_000)

    private func session(_ id: String, _ state: AgentTrafficLightState = .awaitingInput, visible: Bool = true,
                         provider: String = "claude") -> AgentSessionStatus {
        AgentSessionStatus(id: "\(provider)-\(id)", provider: provider, conversationID: id, chatName: "PROJ-123 fix",
                           projectName: "acme", rawState: "awaiting_input", displayState: state, updatedAt: t0,
                           isVisible: visible, executionStartedAt: nil, cwd: nil, hostPID: nil)
    }

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: - One alert per episode

    func testASessionThatStaysYellowAlertsOnce() {
        var tracker = AttentionAlertTracker()
        XCTAssertFalse(tracker.update([session("a", .executing)], now: at(0), mayAlert: true))
        XCTAssertTrue(tracker.update([session("a")], now: at(1), mayAlert: true))
        for second in 2...120 {
            XCTAssertFalse(tracker.update([session("a")], now: at(TimeInterval(second)), mayAlert: true),
                           "still the same yellow at \(second) s")
        }
    }

    func testLeavingYellowAndComingBackIsANewEpisode() {
        var tracker = AttentionAlertTracker()
        XCTAssertTrue(tracker.update([session("a")], now: at(0), mayAlert: true))
        XCTAssertFalse(tracker.update([session("a", .executing)], now: at(20), mayAlert: true))
        XCTAssertTrue(tracker.update([session("a")], now: at(40), mayAlert: true), "the agent asks again")
    }

    func testHidingAndShowingAgainIsANewEpisode() {
        var tracker = AttentionAlertTracker()
        XCTAssertTrue(tracker.update([session("a")], now: at(0), mayAlert: true))
        XCTAssertFalse(tracker.update([session("a", visible: false)], now: at(20), mayAlert: true))
        XCTAssertTrue(tracker.update([session("a")], now: at(40), mayAlert: true))
    }

    // MARK: - Several at once

    func testSeveralSessionsTurningYellowTogetherAlertOnce() {
        var tracker = AttentionAlertTracker()
        XCTAssertTrue(tracker.update([session("a"), session("b"), session("c", provider: "cursor")], now: at(0), mayAlert: true))
        XCTAssertFalse(tracker.update([session("a"), session("b"), session("c", provider: "cursor")], now: at(1), mayAlert: true))
    }

    func testASecondSessionInsideTheWindowSharesTheAlert() {
        var tracker = AttentionAlertTracker()
        XCTAssertTrue(tracker.update([session("a")], now: at(0), mayAlert: true))
        XCTAssertFalse(tracker.update([session("a"), session("b")], now: at(AttentionAlertTracker.coalesceWindow - 0.5), mayAlert: true),
                       "b turned yellow with a: one alert")
        XCTAssertFalse(tracker.update([session("a"), session("b")], now: at(30), mayAlert: true), "b's episode was covered")
    }

    func testASecondSessionAfterTheWindowAlertsOnItsOwn() {
        var tracker = AttentionAlertTracker()
        XCTAssertTrue(tracker.update([session("a")], now: at(0), mayAlert: true))
        XCTAssertTrue(tracker.update([session("a"), session("b")], now: at(AttentionAlertTracker.coalesceWindow + 1), mayAlert: true))
    }

    // MARK: - Recorded, not announced

    func testYellowsSeenWhileItMayNotAlertAreNeverAnnouncedLate() {
        var tracker = AttentionAlertTracker()
        // Off, before onboarding, or in the quiet start: recorded only.
        XCTAssertFalse(tracker.update([session("a")], now: at(0), mayAlert: false))
        // The switch turns on, or the gate opens: the wait that was already open stays quiet.
        XCTAssertFalse(tracker.update([session("a")], now: at(60), mayAlert: true))
        // A new one alerts.
        XCTAssertTrue(tracker.update([session("a"), session("b")], now: at(61), mayAlert: true))
    }

    func testNothingButAVisibleRealYellowAlerts() {
        var tracker = AttentionAlertTracker()
        XCTAssertFalse(tracker.update([session("a", .executing), session("b", .thinking), session("c", .stopped),
                                       session("d", .inactive), session("e", visible: false),
                                       session("kannu-test-1")], now: at(0), mayAlert: true))
        XCTAssertEqual(tracker.yellow, [])
    }

    // MARK: - Gates

    func testItMayAlertOnlyWithEveryGateOpen() {
        XCTAssertTrue(AttentionAlertTracker.mayAlert(enabled: true, termsAccepted: true, onboardingComplete: true, quiet: false))
        XCTAssertFalse(AttentionAlertTracker.mayAlert(enabled: false, termsAccepted: true, onboardingComplete: true, quiet: false),
                       "off")
        XCTAssertFalse(AttentionAlertTracker.mayAlert(enabled: true, termsAccepted: false, onboardingComplete: true, quiet: false),
                       "before the Terms")
        XCTAssertFalse(AttentionAlertTracker.mayAlert(enabled: true, termsAccepted: true, onboardingComplete: false, quiet: false),
                       "before onboarding")
        XCTAssertFalse(AttentionAlertTracker.mayAlert(enabled: true, termsAccepted: true, onboardingComplete: true, quiet: true),
                       "in the quiet start")
    }

    func testTheFlashOutlastsTheSweepsAndTheQuietStartCoversTheFirstScans() {
        // `AttentionAlertFlashView` runs 2 sweeps of 1 s; the flash must not be cut off mid-sweep.
        XCTAssertGreaterThan(AttentionAlertTracker.flashDuration, 2.0)
        XCTAssertGreaterThanOrEqual(AttentionAlertTracker.quietStart, 5)
    }

    // MARK: - Reduce Motion

    func testReduceMotionGivesTheStillGlow() {
        XCTAssertEqual(AttentionAlertVisual.forReduceMotion(true), .glow)
        XCTAssertEqual(AttentionAlertVisual.forReduceMotion(false), .shimmer)
    }

    // MARK: - Sounds

    func testEverySoundIsAMacOSSystemSound() {
        XCTAssertEqual(AttentionAlertSound.allCases.count, 14)
        for sound in AttentionAlertSound.allCases {
            XCTAssertTrue(FileManager.default.fileExists(atPath: "/System/Library/Sounds/\(sound.rawValue).aiff"),
                          "\(sound.rawValue) is not in /System/Library/Sounds")
        }
    }
}
