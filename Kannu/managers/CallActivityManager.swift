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
import os

/// The call another app is on, for the closed notch's pill and the media screen's call page.
///
/// One published value. `CallAudioProcessMonitor` reads CoreAudio off the main thread and hands
/// over which catalog apps capture and play; `CallActivityResolver` turns that into a call. The
/// value is assigned only when it changes, which is when a call starts or ends, so a view that
/// observes this manager redraws at those two moments and at no other.
///
/// Kannu only watches: it never opens the notch for a call, never touches the calling app, and
/// leaves that app's own call window and notification as they are.
@MainActor
final class CallActivityManager: ObservableObject {
    static let shared = CallActivityManager()

    /// How long the pill takes the closed notch from a running timer or a screen recording when a
    /// call starts, before handing it back.
    static let takeoverDuration: TimeInterval = 5

    @Published private(set) var activity: CallActivity?

    private static let log = os.Logger(subsystem: "com.kannu.app", category: "CallActivity")

    private var monitor: CallAudioProcessMonitor?
    private var resolver = CallActivityResolver()
    private var lastReading: [CallAudioProcess] = []
    /// The one wake at the resolver's `dropDeadline`: with the microphone free no event arrives,
    /// so the call's end has to be asked for.
    private var dropTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    func startMonitoring() {
        guard monitor == nil else { return }
        let monitor = CallAudioProcessMonitor { [weak self] reading in
            // The main queue, not a Task: readings must arrive in the order they were taken.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.apply(reading) }
            }
        }
        self.monitor = monitor
        monitor.start()
    }

    /// Stops the monitor (its listeners and its timer) and clears the call.
    func stopMonitoring() {
        monitor?.stop()
        monitor = nil
        dropTask?.cancel()
        dropTask = nil
        resolver = CallActivityResolver()
        lastReading = []
        publish(nil)
    }

    // MARK: - Resolving

    private func apply(_ reading: [CallAudioProcess]) {
        // A reading that was already on its way when the monitor stopped.
        guard monitor != nil else { return }
        lastReading = reading
        resolve()
    }

    private func resolve() {
        publish(resolver.update(processes: lastReading, now: Date()))
        dropTask?.cancel()
        dropTask = nil
        guard let deadline = resolver.dropDeadline else { return }
        dropTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow) + 0.05))
            guard !Task.isCancelled else { return }
            self?.resolve()
        }
    }

    private func publish(_ next: CallActivity?) {
        guard next != activity else { return }
        // The app's name comes from Kannu's own catalog; nothing about the call itself is logged.
        if let next {
            Self.log.info("Call: \(next.app.id, privacy: .public) \(next.isRinging ? "ringing" : "ongoing", privacy: .public)")
        } else {
            Self.log.info("Call: none")
        }
        activity = next
    }
}
