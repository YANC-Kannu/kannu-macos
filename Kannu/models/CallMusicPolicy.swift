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

/// Whether a change of call pauses the music. Pure, in the logic target; `CallMusicPauser` feeds it
/// every change of `CallActivityManager.activity` and acts on its answer.
///
/// Music pauses once, when a call starts: the call goes from none or ringing to ongoing. Nothing
/// happens while the call goes on, and nothing when it ends. There is no resume: what the user
/// starts again during or after the call is theirs.
enum CallMusicPolicy {
    enum Decision: Equatable {
        case pause
        case none
    }

    /// - Parameters:
    ///   - previous: the call before the change, nil for none.
    ///   - next: the call after it. Its app is the calling app.
    ///   - isEnabled: "Pause music during calls" and "Show calls from other apps" both on.
    ///   - isPlaying: Kannu's music state says playing.
    ///   - sourceBundleID: the bundle ID of the app the music state belongs to.
    static func decide(previous: CallActivity?,
                       next: CallActivity?,
                       isEnabled: Bool,
                       isPlaying: Bool,
                       sourceBundleID: String?) -> Decision {
        guard isEnabled, isPlaying, let next, next.startedAt != nil else { return .none }
        // An ongoing call that is the same call as before is an update, not a start. A ring that
        // connects, no call before, or a different call that replaced the last one is a start.
        guard previous != next else { return .none }
        // The calling app as the music source is its own audio, a voice note in WhatsApp for one.
        // Pausing it would stop what the user is listening to in the call's own app.
        if let sourceBundleID, next.app.matches(processBundleID: sourceBundleID) { return .none }
        return .pause
    }
}
