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

/// What one fetch from a source came to: its items, or the state its failure leaves the source in
/// (the provider maps its own errors: Jira's 400 is a bad filter, GitHub's 403 may be a rate limit).
enum SourceFetch {
    case fetched(RemoteFetch)
    case failed(SourceSyncState)
}

/// What the display copies say about a source right now: what it is connected to (empty when not)
/// and whether its Sync switch is on.
struct SourceConnection: Equatable {
    var scope: String
    var syncOn: Bool
}

/// Whether the task list can take a sync's items.
enum SourceReadiness: Equatable {
    case loading
    case ready
    case failed
}

/// A Connect's check with the source: accepted, with the credential to save — which may carry what
/// the check learned, such as Linear's workspace — and what to write once it is saved (the display
/// copies); or refused, with what to tell the user.
enum ConnectCheck<Credential> {
    case accepted(Credential, commit: () -> Void)
    case refused(String)
}

/// One source's reading side: where a credential may be sent, and one fetch. Nonisolated, so
/// awaiting it from the main actor leaves it. Read-only.
protocol TaskSourceProvider {
    associatedtype Credential
    /// What the fetch depends on besides the credential (Jira's filter; GitLab's user name and
    /// Include merge requests), read on the main actor when a sync starts.
    associatedtype Options

    /// The site, server or account the credential may be sent to, as `RemoteTaskInfo.hostScope`
    /// writes it — checked again here, never trusted from the Keychain alone; nil when it is not
    /// one Kannu would send a request to.
    func scope(of credential: Credential) -> String?
    func fetch(_ credential: Credential, options: Options) async -> SourceFetch
}

/// What a source's sync needs from the task list: whether it is readable, a place to fold the items
/// in, and a way to tell SwiftUI something changed. `TasksManager`.
@MainActor
protocol TaskSourceHost: AnyObject {
    var readiness: SourceReadiness { get }
    func merge(_ fetch: RemoteFetch, from source: TaskSource, scope: String, at now: Date)
    func sourceWillChange()
}

/// The non-generic face of a `SourceSync`, so the manager and views handle any source alike.
@MainActor
protocol SourceSyncing: AnyObject {
    var source: TaskSource { get }
    var state: SourceSyncState { get }
    var tokenRemovalFailed: Bool { get }
    var generation: Int { get }
    var isSyncing: Bool { get }
    var isConnected: Bool { get }
    var isSyncOn: Bool { get }
    func syncIfStale(now: Date)
    func refresh(now: Date)
    func optionsChanged(now: Date)
    func externalChange()
    func disconnect()
    func retryRemovingToken()
    func loadFinished()
    func markRejected(_ generation: Int, status: Int)
}

/// One source's sync: its state, its token and its fetches — the same for every source, so Jira,
/// GitLab, GitHub, Linear, Todoist and Apple Reminders all behave alike (docs/TASK-SOURCES.md).
///
/// - It syncs only when asked: a page appearing (`syncIfStale`, never with the Keychain dialog, and
///   never after the source refused the token — sending a refused token again can lock the
///   account), the user's Refresh (`refresh`), an option that changes what is fetched
///   (`optionsChanged`), the source itself saying it changed (`externalChange`), and right after
///   Connect. No timer, no polling, nothing at launch.
/// - `generation` moves with every Connect and Disconnect: a fetch started before carries the old
///   one, and its result is dropped rather than landing on a setup that has moved on. A refresh
///   asked during a sync runs when that one ends, unless it ended in a refused token, a sign-in to
///   reconnect, or a declined Keychain dialog.
/// - The credential is read off the main actor, and used only with the scope the display copy
///   shows: a Keychain item for anything else means "reconnect", never a request elsewhere.
/// - Connect saves nothing until the source accepted the credential, refuses to save over a
///   Disconnect or another Connect that finished meanwhile, and writes the Keychain and the display
///   copies together. Remove Token waits for any Connect in flight.
///
/// Pure Foundation, so the logic target drives it with a fake provider (`SourceSyncTests`).
@MainActor
final class SourceSync<Provider: TaskSourceProvider>: SourceSyncing {
    /// A sync older than this is redone when a page appears.
    static var staleAfter: TimeInterval { 5 * 60 }

    let source: TaskSource
    private let provider: Provider
    private let store: any CredentialKeeping<Provider.Credential>
    private let connection: () -> SourceConnection
    private let options: () -> Provider.Options
    /// Clears the display copies: what Disconnect forgets besides the token.
    private let forget: () -> Void
    private weak var host: TaskSourceHost?

    private(set) var state: SourceSyncState = .idle {
        willSet { if newValue != state { host?.sourceWillChange() } }
    }
    /// Disconnect could not delete the saved token from the Keychain, so it is still there.
    private(set) var tokenRemovalFailed = false {
        willSet { if newValue != tokenRemovalFailed { host?.sourceWillChange() } }
    }
    /// Moves with every Connect and Disconnect (and an options change during a sync).
    private(set) var generation = 0
    /// The generation of the sync in flight, if any.
    private var inFlight: Int?
    /// A page appeared before the task file was read: sync once it is.
    private var pendingWhenReady = false
    /// Refresh was asked during a sync, which carries the options it started with.
    private var pendingRefresh = false
    /// The source said it changed during a sync: one more, quietly, when it ends.
    private var pendingChange = false
    /// Connects between their first await and their return: until a Connect's save lands the display
    /// copy still says disconnected, so it alone cannot tell Remove Token a token is on its way.
    private var connectsInFlight = 0
    /// When the last sync succeeded. In memory only, so the first visit after launch syncs.
    private var lastSuccess: Date?
    /// The sync running now, for tests to wait on.
    private(set) var running: Task<Void, Never>?

    init(
        source: TaskSource,
        provider: Provider,
        store: any CredentialKeeping<Provider.Credential>,
        connection: @escaping () -> SourceConnection,
        options: @escaping () -> Provider.Options,
        forget: @escaping () -> Void,
        host: TaskSourceHost?
    ) {
        self.source = source
        self.provider = provider
        self.store = store
        self.connection = connection
        self.options = options
        self.forget = forget
        self.host = host
    }

    /// Connected, as far as the display copy says. The Keychain has the final word at sync time.
    var isConnected: Bool { !connection().scope.isEmpty }
    /// Connected and its Sync switch on. Off pauses fetching only: its tasks stay in the order.
    var isSyncOn: Bool { isConnected && connection().syncOn }
    var isSyncing: Bool { inFlight == generation }

    // MARK: - When it syncs

    /// A page appeared. Syncs when the source is on, nothing is in flight, and
    /// `SourceSyncState.allowsSyncOnAppear` agrees: the last sync is stale, no rate limit runs, and
    /// the source has not refused the token. Never shows the Keychain dialog: a read that would
    /// need it ends in `.needsKeychainApproval`, and the user's click retries.
    func syncIfStale(now: Date = Date()) {
        guard isSyncOn, !isSyncing else { return }
        guard host?.readiness == .ready else {
            if host?.readiness == .loading { pendingWhenReady = true }
            return
        }
        guard state.allowsSyncOnAppear(lastSuccess: lastSuccess, now: now, staleAfter: Self.staleAfter) else { return }
        sync(interactive: false, using: nil)
    }

    /// The user asked — Refresh, Allow Keychain Access, a new filter — so the Keychain may ask them
    /// too. Asked during a sync, it is kept: that sync fetches what it started with, and this one
    /// runs, with the current options, when it ends.
    func refresh(now: Date = Date()) {
        guard isSyncOn, host?.readiness == .ready else { return }
        if case .rateLimited(let until) = state, until > now { return }
        guard !isSyncing else {
            pendingRefresh = true
            return
        }
        sync(interactive: true, using: nil)
    }

    /// An option that decides what is fetched was switched (GitLab's Include merge requests). The
    /// task order follows on its own; what is fetched follows now. A sync in flight read the old
    /// option, so its result is dropped. Until a sync succeeds with the new one, the next page visit
    /// syncs again: offline, a rate limit or Sync off only delay it.
    func optionsChanged(now: Date = Date()) {
        if isSyncing {
            generation += 1
            inFlight = nil
            state = .idle
        }
        lastSuccess = nil
        refresh(now: now)
    }

    /// The source said it changed (Apple Reminders' change notification): sync quietly, never with
    /// the Keychain dialog and never after a refusal or during a rate limit. A burst during a sync
    /// comes to one more sync after it.
    func externalChange() {
        guard isSyncOn, host?.readiness == .ready else { return }
        guard !isSyncing else {
            pendingChange = true
            return
        }
        guard state.allowsSyncOnAppear(lastSuccess: nil, now: Date(), staleAfter: 0) else { return }
        sync(interactive: false, using: nil)
    }

    /// The task file was read: a sync a page asked for meanwhile runs now.
    func loadFinished() {
        guard pendingWhenReady else { return }
        pendingWhenReady = false
        syncIfStale()
    }

    // MARK: - Connect and Disconnect

    /// Checks a credential with the source (`check`), then saves what it accepted and syncs. Nil on
    /// success, or what to tell the user. Nothing is saved until the source accepted it.
    func connect(check: () async -> ConnectCheck<Provider.Credential>) async -> String? {
        // From here on Remove Token refuses: the save below may be on its way to the Keychain.
        let started = generation
        connectsInFlight += 1
        defer { connectsInFlight -= 1 }
        let credential: Provider.Credential
        let commit: () -> Void
        switch await check() {
        case .accepted(let accepted, let write):
            credential = accepted
            commit = write
        case .refused(let message):
            return message
        }
        // A cancel, or another Connect or a Disconnect that finished during the check, owns the
        // Keychain item now: nothing is saved over it. After the save the connect is committed —
        // the Keychain and the display copies change together, with no await between.
        guard !Task.isCancelled, started == generation else { return String(localized: "Cancelled.") }
        guard await store.save(credential) else {
            return String(localized: "\(source.name) accepted the token, but Kannu could not save it in your Keychain.")
        }
        commit()
        generation += 1
        inFlight = nil
        pendingRefresh = false
        pendingChange = false
        lastSuccess = nil
        state = .idle
        // The save replaced whatever a failed Disconnect left in the Keychain.
        tokenRemovalFailed = false
        switch host?.readiness {
        case .ready:
            // The credential is in hand: no Keychain read for the first sync.
            sync(interactive: false, using: credential)
        case .loading:
            pendingWhenReady = true
        case .failed, nil:
            break
        }
        return nil
    }

    /// Forgets the connection and the token, and stops syncing. What happens to the source's tasks
    /// is the manager's (`TasksManager.disconnect`).
    func disconnect() {
        generation += 1
        inFlight = nil
        pendingWhenReady = false
        pendingRefresh = false
        pendingChange = false
        lastSuccess = nil
        state = .idle
        forget()
        removeToken()
    }

    /// Disconnect could not delete the saved token: the user asks again. Not while a Connect is in
    /// flight: the display copy still says disconnected until its save lands, and a delete queued
    /// behind that save would take the new token with it.
    func retryRemovingToken() {
        guard !isConnected, connectsInFlight == 0 else { return }
        removeToken()
    }

    /// A refusal of the token from elsewhere (a worklog's 401) marks the source, unless it was
    /// reconnected or disconnected while that request was out, or a sync is reporting for itself.
    func markRejected(_ generation: Int, status: Int) {
        guard generation == self.generation, !isSyncing else { return }
        state = .authFailed(status: status)
    }

    /// Deletes the saved token off the main actor, and says so when it could not. A result that
    /// lands after a new Connect is dropped: that Connect saved a token of its own.
    private func removeToken() {
        let started = generation
        tokenRemovalFailed = false
        let store = self.store
        Task { [weak self] in
            let removed = await store.remove()
            guard let self, started == self.generation else { return }
            self.tokenRemovalFailed = !removed
        }
    }

    // MARK: - One sync

    private func sync(interactive: Bool, using known: Provider.Credential?) {
        let started = generation
        inFlight = started
        state = .syncing
        let expected = connection().scope
        let options = self.options()
        let provider = self.provider
        let store = self.store
        running = Task { [weak self] in
            let credential: Provider.Credential
            if let known {
                credential = known
            } else {
                switch await store.load(allowInteraction: interactive) {
                case .found(let stored):
                    credential = stored
                case .needsApproval:
                    self?.finish(started, .needsKeychainApproval)
                    return
                case .missing, .broken:
                    self?.finish(started, .needsReconnect)
                    return
                }
            }
            // The Keychain's scope is the only one a token is sent to. A display copy that disagrees
            // means the setup changed under Kannu: reconnect, never a request elsewhere.
            guard let scope = provider.scope(of: credential), scope == expected else {
                self?.finish(started, .needsReconnect)
                return
            }
            let result = await provider.fetch(credential, options: options)
            self?.didFetch(result, scope: scope, generation: started)
        }
    }

    private func didFetch(_ result: SourceFetch, scope: String, generation started: Int) {
        // Connected again or disconnected meanwhile: this result belongs to a setup that is gone.
        guard started == generation else { return }
        switch result {
        case .failed(let failure):
            finish(started, failure)
        case .fetched(let fetch):
            guard let host, host.readiness == .ready else {
                finish(started, .failed(String(localized: "Kannu could not read its task list, so \(source.name) \(source.itemNoun.many) cannot be added to it.")))
                return
            }
            let now = Date()
            host.merge(fetch, from: source, scope: scope, at: now)
            lastSuccess = now
            finish(started, .synced(at: now, count: fetch.issues.count, complete: fetch.complete))
        }
    }

    private func finish(_ started: Int, _ result: SourceSyncState) {
        guard started == generation else { return }
        inFlight = nil
        state = result
        if pendingRefresh {
            pendingRefresh = false
            pendingChange = false
            // What was fetched changed under this sync: the user's Refresh runs now, with its own
            // guards. Not after a refused token or a sign-in to reconnect — new options do not change
            // that answer, and sending the token again can lock the account — nor after a declined
            // Keychain dialog, which would only come straight back. Allow Keychain Access retries.
            switch result {
            case .authFailed, .needsReconnect, .needsKeychainApproval: return
            default: refresh()
            }
        } else if pendingChange {
            pendingChange = false
            externalChange()
        }
    }
}
