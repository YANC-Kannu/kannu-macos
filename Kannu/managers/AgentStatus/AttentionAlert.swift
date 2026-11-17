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

/// What an alert sound is, to play it.
enum AttentionAlertPlayback: Equatable {
    /// None: the shimmer alone.
    case silent
    /// A file in the app bundle, played once.
    case bundled(name: String, fileExtension: String)
    /// A macOS system sound, by the name `NSSound(named:)` takes.
    case system(name: String)
}

/// The alert's sound: None, Kannu's own alarm, then the macOS system sounds in `/System/Library/Sounds`.
/// The fourteen system sounds ship from macOS 14 to 27; their raw values are what `Defaults` stores, so they
/// never change (a saved "Glass" still loads). They are proper names, shown as macOS shows them.
enum AttentionAlertSound: String, CaseIterable, Identifiable {
    case none
    case kannuAlarm
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

    /// None and Kannu alarm are catalog text. A system sound shows its own name, untranslated, as macOS does.
    var localizedName: String {
        switch self {
        case .none: return String(localized: "None")
        case .kannuAlarm: return String(localized: "Kannu alarm")
        default: return rawValue
        }
    }

    /// Kannu alarm is the timer's own `timer.mp3`, never looped here (only the timer's alarm loops) and cut
    /// to the flash: it fades out and stops at `AttentionAlertTracker.flashDuration`.
    var playback: AttentionAlertPlayback {
        switch self {
        case .none: return .silent
        case .kannuAlarm: return .bundled(name: "timer", fileExtension: "mp3")
        default: return .system(name: rawValue)
        }
    }
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
    /// Kannu alarm is a 12 s file: it fades over this long and stops as the flash ends.
    static let alarmFadeDuration: TimeInterval = 0.4
    /// When the Kannu alarm starts to fade, so it is silent exactly at `flashDuration`.
    static var alarmFadeStart: TimeInterval { flashDuration - alarmFadeDuration }

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
