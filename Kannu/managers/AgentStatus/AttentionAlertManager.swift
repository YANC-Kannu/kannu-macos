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

import AppKit
import Defaults
import SwiftUI

extension AttentionAlertSound: Defaults.Serializable {}

/// One flash of the attention alert: what the notch and the lock-screen pill draw while it lasts.
struct AttentionAlertFlash: Equatable, Identifiable {
    let id: Int
    let visual: AttentionAlertVisual
}

/// The attention alert: a system sound and one shimmer across the notch when an agent turns yellow.
///
/// `AgentStatusNotificationBridge` feeds it the session list from the subscription it already holds,
/// so it starts and stops with the bridge, inside `continueLaunch()` and never before the Terms. The
/// rules live in `AttentionAlertTracker`. `flash` publishes twice per alert, on and off, and the only
/// observer is `AttentionAlertOverlay`, a leaf.
@MainActor
final class AttentionAlertManager: ObservableObject {
    static let shared = AttentionAlertManager()

    @Published private(set) var flash: AttentionAlertFlash?

    private var tracker = AttentionAlertTracker()
    /// Silent until `start()`, then for `AttentionAlertTracker.quietStart` after it.
    private var quietUntil: Date = .distantFuture
    private var flashCount = 0
    private var clearTask: Task<Void, Never>?

    private init() {}

    func start(now: Date = Date()) {
        tracker = AttentionAlertTracker()
        quietUntil = now.addingTimeInterval(AttentionAlertTracker.quietStart)
    }

    func stop() {
        clearTask?.cancel()
        clearTask = nil
        flash = nil
        tracker = AttentionAlertTracker()
        quietUntil = .distantFuture
    }

    /// Every publish of the monitor's session list. Cheap: one set of ids per call.
    func handle(_ sessions: [AgentSessionStatus], now: Date = Date()) {
        let mayAlert = AttentionAlertTracker.mayAlert(
            enabled: Defaults[.attentionAlertEnabled],
            termsAccepted: TermsOfUse.isAccepted(acceptedVersion: Defaults[.termsAcceptedVersion]),
            onboardingComplete: LaunchPermissionManager.isOnboardingComplete,
            quiet: now < quietUntil
        )
        guard tracker.update(sessions, now: now, mayAlert: mayAlert) else { return }
        alert()
    }

    /// The setting's preview button, and the alert itself. None plays nothing.
    func playSound(_ sound: AttentionAlertSound) {
        switch sound.playback {
        case .silent:
            return
        case .bundled(let name, let fileExtension):
            // Once, never looped. A second press restarts it rather than playing over it.
            bundledSound?.stop()
            bundledSound = bundledPlayer.play(fileName: name, fileExtension: fileExtension)
        case .system(let name):
            guard let player = NSSound(named: NSSound.Name(name)) else { return }
            // `NSSound(named:)` hands back one shared instance per name: restart it if it is still playing.
            player.stop()
            player.play()
        }
    }

    private let bundledPlayer = AudioPlayer()
    private var bundledSound: NSSound?

    private func alert() {
        playSound(Defaults[.attentionAlertSound])
        // Locked, the notch windows are hidden. With the lock-screen live activity on its pill is already
        // there and the overlay shimmers it; with it off, the pill shows for this one flash.
        if LockScreenManager.shared.isLocked {
            LockScreenLiveActivityWindowManager.shared.flashForAttentionAlert(duration: AttentionAlertTracker.flashDuration)
        }
        flashCount += 1
        let visual = AttentionAlertVisual.forReduceMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        withAnimation(.easeOut(duration: 0.2)) {
            flash = AttentionAlertFlash(id: flashCount, visual: visual)
        }
        // One sleep per alert, not a timer: the flash ends by itself.
        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(AttentionAlertTracker.flashDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                self?.flash = nil
            }
        }
    }
}
