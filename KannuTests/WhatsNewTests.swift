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

/// The What's New decision's whole truth table (openspec `whats-new`): an update sees 2.0's welcome once, a fresh
/// install never does and counts it as seen, and an update waits while onboarding runs. Where the app asks the
/// decision, after the Terms of Use, is `WhatsNewRulesTests`'.
final class WhatsNewTests: XCTestCase {
    private let unseen = 0
    private let seen = WhatsNew.currentEdition

    func testAnUpdateOpensItWhenItWasNotSeen() {
        XCTAssertEqual(WhatsNew.decision(isUpgrade: true, onboardingComplete: true, seenEdition: unseen), .show)
    }

    /// Onboarding introduces Kannu on a fresh install, so the welcome is counted as seen there and never opens, even on
    /// the launch after onboarding, when `firstLaunch` has gone false and the install looks like an update.
    func testAFreshInstallNeverOpensItAndCountsItSeen() {
        for onboardingComplete in [false, true] {
            XCTAssertEqual(WhatsNew.decision(isUpgrade: false, onboardingComplete: onboardingComplete, seenEdition: unseen),
                           .markSeen)
        }
        XCTAssertEqual(WhatsNew.decision(isUpgrade: true, onboardingComplete: true, seenEdition: seen), .skip,
                       "the launch after a fresh install's onboarding opened it")
    }

    /// Never over onboarding: an update that meets onboarding again waits, unseen, for a later launch.
    func testAnUpdateWaitsWhileOnboardingRuns() {
        XCTAssertEqual(WhatsNew.decision(isUpgrade: true, onboardingComplete: false, seenEdition: unseen), .skip)
    }

    /// Shown once: once an edition is recorded, nothing opens it again or writes it again.
    func testOnceSeenItNeverOpensAgain() {
        for isUpgrade in [false, true] {
            for onboardingComplete in [false, true] {
                for seenEdition in [seen, seen + 1] {
                    XCTAssertEqual(WhatsNew.decision(isUpgrade: isUpgrade, onboardingComplete: onboardingComplete,
                                                     seenEdition: seenEdition), .skip)
                }
            }
        }
    }

    /// Only an update with onboarding behind it that has not seen this edition opens the window.
    func testOnlyOneRowOpensIt() {
        var opening: [String] = []
        for isUpgrade in [false, true] {
            for onboardingComplete in [false, true] {
                for seenEdition in [unseen, seen] {
                    if WhatsNew.decision(isUpgrade: isUpgrade, onboardingComplete: onboardingComplete,
                                         seenEdition: seenEdition) == .show {
                        opening.append("upgrade=\(isUpgrade) onboarded=\(onboardingComplete) seen=\(seenEdition)")
                    }
                }
            }
        }
        XCTAssertEqual(opening, ["upgrade=true onboarded=true seen=0"])
    }

    func testTheFirstEditionIsKannu2sWelcome() {
        XCTAssertEqual(WhatsNew.currentEdition, 1)
    }
}
