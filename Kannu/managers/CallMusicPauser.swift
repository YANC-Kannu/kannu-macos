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

import Combine
import Defaults
import Foundation
import os

/// Pauses the music app that is playing when a call starts ("Pause music during calls").
///
/// It follows `CallActivityManager.activity` and asks `CallMusicPolicy` about every change. On a
/// `.pause` it sends one explicit `MusicManager.pause()`: never a toggle, which would start music
/// that had stopped by itself, and never a play, so nothing resumes after the call.
///
/// Runs only while both "Show calls from other apps" and "Pause music during calls" are on.
/// `AppDelegate` calls `sync()` in `continueLaunch()` and when either switch changes, and `stop()`
/// drops the subscription (docs/REGRESSIONS.md, entry 19).
@MainActor
final class CallMusicPauser {
    static let shared = CallMusicPauser()

    private static let log = os.Logger(subsystem: "com.kannu.app", category: "CallActivity")

    private var subscription: AnyCancellable?
    /// The call as of the last change seen, so the policy can tell a start from an update.
    private var lastCall: CallActivity?

    private init() {}

    /// Whether both switches are on.
    static var isEnabled: Bool {
        Defaults[.enableCallActivity] && Defaults[.pauseMusicDuringCalls]
    }

    /// Starts or stops to match the two switches.
    func sync() {
        if Self.isEnabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard subscription == nil else { return }
        // A call already running when this starts is not a start: the first value the publisher
        // hands over equals this one.
        lastCall = CallActivityManager.shared.activity
        subscription = CallActivityManager.shared.$activity.sink { [weak self] next in
            // `CallActivityManager` assigns on the main actor, and `@Published` delivers there.
            MainActor.assumeIsolated { self?.handle(next) }
        }
    }

    /// Drops the subscription and forgets the call.
    func stop() {
        subscription?.cancel()
        subscription = nil
        lastCall = nil
    }

    private func handle(_ next: CallActivity?) {
        let previous = lastCall
        lastCall = next
        let music = MusicManager.shared
        let decision = CallMusicPolicy.decide(previous: previous,
                                              next: next,
                                              isEnabled: Self.isEnabled,
                                              isPlaying: music.isPlaying,
                                              sourceBundleID: music.bundleIdentifier)
        guard decision == .pause, let next else { return }
        // The app's name comes from Kannu's own catalog; nothing about the music is logged.
        Self.log.info("Call: \(next.app.id, privacy: .public) started, pausing music")
        music.pause()
    }
}
