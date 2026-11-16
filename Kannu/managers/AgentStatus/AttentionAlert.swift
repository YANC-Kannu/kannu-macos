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

/// The attention alert's rules, with no AppKit in them so the logic target can pin them.
/// `AttentionAlertManager` applies them; `AttentionAlertOverlay` draws what they decide.

/// What an alert draws. Reduce Motion swaps the moving sweep for a still glow.
enum AttentionAlertVisual: Equatable {
    case shimmer
    case glow

    static func forReduceMotion(_ reduceMotion: Bool) -> AttentionAlertVisual {
        reduceMotion ? .glow : .shimmer
    }
}

/// The macOS system sounds in `/System/Library/Sounds`, by the name `NSSound(named:)` takes. The same
/// fourteen ship from macOS 14 to 27. They are proper names, shown as macOS shows them.
enum AttentionAlertSound: String, CaseIterable, Identifiable {
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    var id: String { rawValue }

    /// The sound's own name. Not catalog text: macOS shows these names untranslated too.
    var localizedName: String { rawValue }
}

/// One alert per session per yellow episode.
///
/// An episode starts when a visible, non-simulated session is first seen `awaitingInput`, and ends
/// when it leaves yellow or stops being visible; coming back is a new episode. Every update records
/// the yellow set, whether or not it may alert, so yellows that were already showing when the alert
/// is switched on, or when Kannu starts, are never announced late. Sessions that turn yellow within
/// `coalesceWindow` of an alert share it: several agents asking at once are one alert.
struct AttentionAlertTracker: Equatable {
    /// Yellows this close behind an alert are covered by it.
    static let coalesceWindow: TimeInterval = 3
    /// After start, yellows are recorded, not announced: a relaunch never alerts for a wait that
    /// was already open, and the monitor's first scans land inside this.
    static let quietStart: TimeInterval = 10
    /// How long a flash stays on the notch. The shimmer's sweeps finish inside it.
    static let flashDuration: TimeInterval = 2.4

    private(set) var yellow: Set<String> = []
    private(set) var lastAlertAt: Date?

    /// Whether the alert may sound at all. The source only starts inside `continueLaunch()`, after
    /// the Terms, and the terms are checked here too so the rule does not lean on call order.
    static func mayAlert(enabled: Bool, termsAccepted: Bool, onboardingComplete: Bool, quiet: Bool) -> Bool {
        enabled && termsAccepted && onboardingComplete && !quiet
    }

    /// Records the sessions now yellow; true when this update should alert.
    mutating func update(_ sessions: [AgentSessionStatus], now: Date, mayAlert: Bool) -> Bool {
        let current = Set(sessions.lazy
            .filter { $0.isVisible && $0.displayState == .awaitingInput && !AgentTrafficLightMapper.isSimulationSession($0) }
            .map(\.id))
        let fresh = current.subtracting(yellow)
        yellow = current
        guard mayAlert, !fresh.isEmpty else { return false }
        if let lastAlertAt, now.timeIntervalSince(lastAlertAt) < Self.coalesceWindow { return false }
        lastAlertAt = now
        return true
    }
}
