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

/// A source's sign-in, kept in the Keychain as one text item: the token together with the one site,
/// server or account it may be sent to (`JiraCredential`, `GitLabCredential`…). Its description
/// never prints the token.
protocol StoredCredential {
    func encoded() -> String?
    static func decoded(_ text: String) -> Self?
}

/// The Keychain item a credential lives in, as three calls, so `CredentialStore` is tested without
/// the Keychain. The app's are `SecretSlot.keychain(_:)` (`TaskCredentials`).
struct SecretSlot {
    enum Read: Equatable {
        case value(String)
        case missing
        /// The item is there, but macOS wants the user to approve the read.
        case needsApproval
        /// The item is there but could not be read.
        case unreadable
    }

    /// `allowInteraction: false` never shows the Keychain dialog: a read that would need it comes
    /// back `.needsApproval`.
    let read: (_ allowInteraction: Bool) -> Read
    /// Saves the text, replacing what was there; false when it could not.
    let write: (String) -> Bool
    /// Deletes the item; true when it is gone (or was never there).
    let remove: () -> Bool
}

/// What reading a credential came to.
enum CredentialLoad<C> {
    case found(C)
    case missing
    /// The item is there, but macOS wants the user to approve the read.
    case needsApproval
    /// The item is there but could not be read or did not decode.
    case broken
}

/// Where a source's credential is kept: the Keychain for a token, macOS's permission for Apple
/// Reminders. Nonisolated, so awaiting it from the main actor leaves it.
protocol CredentialKeeping<Credential> {
    associatedtype Credential
    func load(allowInteraction: Bool) async -> CredentialLoad<Credential>
    func save(_ credential: Credential) async -> Bool
    /// False when it is still there. Never discard that: the user was told the token is gone.
    func remove() async -> Bool
}

/// One source's credential in the Keychain. Every call runs on the store's own serial queue, never on
/// the caller's thread: a Keychain read can show the SecurityAgent dialog (an interactive read, or an
/// item whose access list no longer matches this build) and blocks until it is answered — on the
/// main thread that freezes Kannu (docs/REGRESSIONS.md entry 11). Serial, so a save and a read cannot
/// cross. One per source (`TaskCredentials`), each with its own item and queue.
final class CredentialStore<C: StoredCredential>: CredentialKeeping {
    private let slot: SecretSlot
    private let queue: DispatchQueue

    init(slot: SecretSlot, queueLabel: String) {
        self.slot = slot
        queue = DispatchQueue(label: queueLabel, qos: .userInitiated)
    }

    private func onQueue<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// `allowInteraction: false` (a background sync) never shows the dialog; a read that would need
    /// it comes back `.needsApproval`, and the user's own click retries with `true`.
    func load(allowInteraction: Bool) async -> CredentialLoad<C> {
        let slot = self.slot
        return await onQueue {
            switch slot.read(allowInteraction) {
            case .missing: return .missing
            case .needsApproval: return .needsApproval
            case .unreadable: return .broken
            case .value(let text): return C.decoded(text).map { .found($0) } ?? .broken
            }
        }
    }

    func save(_ credential: C) async -> Bool {
        guard let encoded = credential.encoded() else { return false }
        let slot = self.slot
        return await onQueue { slot.write(encoded) }
    }

    func remove() async -> Bool {
        let slot = self.slot
        return await onQueue { slot.remove() }
    }
}
