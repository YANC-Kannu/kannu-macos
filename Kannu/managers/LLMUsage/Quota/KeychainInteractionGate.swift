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

/// Keeps a Keychain call that may show a dialog from running while a silent read has user interaction
/// turned off, and a silent read from turning it off while such a call runs.
///
/// `SecKeychainSetUserInteractionAllowed` is one switch for the whole process. A silent read turns it
/// off for its call: for a file-based login-keychain item it is the only thing that keeps the access
/// dialog from appearing (`KeychainReader.read`). Any other Keychain call made while it is off cannot
/// show its dialog either — it fails as if the user had declined, without the user ever seeing it.
/// So calls come in two kinds, and each kind only ever waits for the other:
///
/// - `.silent` reads share the switch. The first to enter turns it off, the last to leave puts back
///   what it was. They never wait for each other.
/// - `.mayPrompt` calls (a read that may ask, a save, a delete) never wait for each other — two
///   dialogs can be open at once — but wait for the silent reads in flight, which take milliseconds
///   since they cannot show anything. While one runs, which can be as long as the user leaves a dialog
///   open, new silent reads wait, or with `wait: false` give up at once.
///
/// A waiting `.mayPrompt` call holds back new silent reads, so a steady stream of background silent
/// reads cannot keep a dialog the user asked for from opening.
final class KeychainInteractionGate: @unchecked Sendable {
    enum Kind: Equatable {
        case silent
        case mayPrompt
    }

    private let condition = NSCondition()
    private var silentInFlight = 0
    private var promptingInFlight = 0
    private var promptingWaiting = 0
    /// What the switch was before the first silent read in flight turned it off.
    private var savedInteraction = true
    private let turnInteractionOff: () -> Bool
    private let restoreInteraction: (Bool) -> Void

    /// `turnInteractionOff` turns the switch off and returns what it was; `restoreInteraction` puts
    /// that back. Both are called with the gate held, once per run of overlapping silent reads.
    init(turnInteractionOff: @escaping () -> Bool, restoreInteraction: @escaping (Bool) -> Void) {
        self.turnInteractionOff = turnInteractionOff
        self.restoreInteraction = restoreInteraction
    }

    /// Runs `body` as a call of `kind`. A silent read with `wait: false` returns nil instead of
    /// waiting for a `.mayPrompt` call; a `.mayPrompt` call always waits.
    func run<T>(_ kind: Kind, wait: Bool = true, _ body: () -> T) -> T? {
        guard enter(kind, wait: wait) else { return nil }
        defer { leave(kind) }
        return body()
    }

    private func enter(_ kind: Kind, wait: Bool) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        switch kind {
        case .silent:
            while promptingInFlight > 0 || promptingWaiting > 0 {
                guard wait else { return false }
                condition.wait()
            }
            if silentInFlight == 0 { savedInteraction = turnInteractionOff() }
            silentInFlight += 1
        case .mayPrompt:
            promptingWaiting += 1
            while silentInFlight > 0 { condition.wait() }
            promptingWaiting -= 1
            promptingInFlight += 1
        }
        return true
    }

    private func leave(_ kind: Kind) {
        condition.lock()
        defer { condition.unlock() }
        switch kind {
        case .silent:
            silentInFlight -= 1
            if silentInFlight == 0 { restoreInteraction(savedInteraction) }
        case .mayPrompt:
            promptingInFlight -= 1
        }
        condition.broadcast()
    }
}
