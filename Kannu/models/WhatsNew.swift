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

/// Whether a launch opens the What's New window: Kannu 2.0's welcome, shown once to people who update
/// (openspec `whats-new`).
///
/// `AppDelegate.continueLaunch()` asks once per launch, so never before the Terms of Use are accepted. A fresh
/// install never sees the window, because onboarding introduces Kannu there, and an update never sees it while
/// onboarding runs. Closing the window, by any route, records the edition as seen. The decision is here, pure and in
/// the logic target, so `WhatsNewTests` can hold its truth table; `WhatsNewRulesTests` holds where the app asks it.
enum WhatsNew {
    /// Bumped when a release brings news of its own: an install that saw an older edition sees the new one once.
    /// 1 is Kannu 2.0's welcome.
    static let currentEdition = 1

    enum Decision: Equatable {
        /// An update that has not seen this edition: open the window.
        case show
        /// A fresh install: onboarding introduces Kannu, so this edition counts as seen without opening.
        case markSeen
        /// Nothing this launch: the edition was seen, or onboarding runs and the window waits for a later launch.
        case skip
    }

    /// - Parameters:
    ///   - isUpgrade: an earlier version ran here, so its hello has played and cleared `firstLaunch`.
    ///   - onboardingComplete: onboarding does not open this launch (`LaunchPermissionManager.isOnboardingComplete`).
    ///   - seenEdition: the edition last seen (`Defaults[.whatsNewSeenEdition]`); 0 when none was.
    static func decision(isUpgrade: Bool, onboardingComplete: Bool, seenEdition: Int) -> Decision {
        guard seenEdition < currentEdition else { return .skip }
        guard isUpgrade else { return .markSeen }
        return onboardingComplete ? .show : .skip
    }
}
