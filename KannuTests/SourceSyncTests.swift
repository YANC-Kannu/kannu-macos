//
//  SourceSyncTests.swift
//  KannuTests
//
//  Copyright (C) 2026 Kannu contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import XCTest

/// How every source syncs (`SourceSync`), driven with a fake source whose fetch waits until the test
/// answers it. These replace the rules `JiraSyncRulesTests` read from TasksManager's text: Jira and
/// GitLab — and GitHub, Linear, Todoist and Apple Reminders — now share this one engine, so the
/// rules are pinned by what it does.
@MainActor
final class SourceSyncTests: XCTestCase {
    struct Credential: Equatable {
        var scope: String
        var token: String
    }

    /// What the fake source and store were asked, and how they answer.
    final class Recorder {
        var fetches: [(token: String, options: Int)] = []
        var pending: [CheckedContinuation<SourceFetch, Never>] = []
        var loads: [Bool] = []
        var stored: CredentialLoad<Credential> = .found(Credential(scope: "s1", token: "kept"))
        var saveSucceeds = true
        var saved: [Credential] = []
        var removes = 0
        var removeSucceeds = true
        var checkGate: CheckedContinuation<Void, Never>?
    }

    struct Provider: TaskSourceProvider {
        let recorder: Recorder
        func scope(of credential: Credential) -> String? { credential.scope.isEmpty ? nil : credential.scope }
        @MainActor func fetch(_ credential: Credential, options: Int) async -> SourceFetch {
            recorder.fetches.append((credential.token, options))
            return await withCheckedContinuation { recorder.pending.append($0) }
        }
    }

    struct Store: CredentialKeeping {
        let recorder: Recorder
        @MainActor func load(allowInteraction: Bool) async -> CredentialLoad<Credential> {
            recorder.loads.append(allowInteraction)
            return recorder.stored
        }
        @MainActor func save(_ credential: Credential) async -> Bool {
            recorder.saved.append(credential)
            return recorder.saveSucceeds
        }
        @MainActor func remove() async -> Bool {
            recorder.removes += 1
            return recorder.removeSucceeds
        }
    }

    final class Host: TaskSourceHost {
        var readiness: SourceReadiness = .ready
        var merged: [(fetch: RemoteFetch, scope: String)] = []
        var changes = 0
        func merge(_ fetch: RemoteFetch, from source: TaskSource, scope: String, at now: Date) {
            merged.append((fetch, scope))
        }
        func sourceWillChange() { changes += 1 }
    }

    private var recorder = Recorder()
    private var host = Host()
    private var connection = SourceConnection(scope: "s1", syncOn: true)
    private var options = 1
    private var forgotten = 0
    private var sync: SourceSync<Provider>!

    override func setUp() async throws {
        recorder = Recorder()
        host = Host()
        connection = SourceConnection(scope: "s1", syncOn: true)
        options = 1
        forgotten = 0
        sync = SourceSync(
            source: .linear, provider: Provider(recorder: recorder), store: Store(recorder: recorder),
            connection: { [unowned self] in self.connection }, options: { [unowned self] in self.options },
            forget: { [unowned self] in self.forgotten += 1; self.connection.scope = "" }, host: host
        )
    }

    private let fetched = SourceFetch.fetched(RemoteFetch(issues: [], complete: true))

    /// Lets the main actor run until `count` fetches wait for an answer.
    private func waitForFetches(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if recorder.pending.count >= count { return }
            await Task.yield()
        }
        XCTFail("expected \(count) fetches waiting, have \(recorder.pending.count)", file: file, line: line)
    }

    /// Answers the oldest waiting fetch and lets its sync finish. Never waits on `running`: that is
    /// the newest sync, which may be another fetch still waiting for its answer.
    private func answer(_ result: SourceFetch) async {
        recorder.pending.removeFirst().resume(returning: result)
        for _ in 0..<50 { await Task.yield() }
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    // MARK: - When it syncs

    func testAPageSyncsQuietlyAndOnlyWhenStale() async {
        let now = Date()
        sync.syncIfStale(now: now)
        await waitForFetches(1)
        XCTAssertEqual(recorder.loads, [false], "a page appearing never shows the Keychain dialog")
        XCTAssertEqual(sync.state, .syncing)
        await answer(fetched)
        guard case .synced = sync.state else { return XCTFail("\(sync.state)") }
        XCTAssertEqual(host.merged.map(\.scope), ["s1"])
        sync.syncIfStale(now: Date())
        await settle()
        XCTAssertEqual(recorder.fetches.count, 1, "fresh: nothing to do")
        sync.syncIfStale(now: Date().addingTimeInterval(SourceSync<Provider>.staleAfter + 1))
        await waitForFetches(1)
        XCTAssertEqual(recorder.fetches.count, 2, "stale: synced again")
    }

    func testSyncOffOrDisconnectedFetchesNothing() async {
        connection.syncOn = false
        sync.syncIfStale(now: Date())
        sync.refresh(now: Date())
        connection = SourceConnection(scope: "", syncOn: true)
        sync.syncIfStale(now: Date())
        await settle()
        XCTAssertTrue(recorder.fetches.isEmpty)
        XCTAssertFalse(sync.isConnected)
    }

    func testARefusedTokenIsNeverSentAgainOnItsOwn() async {
        sync.syncIfStale(now: Date())
        await waitForFetches(1)
        await answer(.failed(.authFailed(status: 401)))
        XCTAssertEqual(sync.state, .authFailed(status: 401))
        sync.syncIfStale(now: Date().addingTimeInterval(3600))
        sync.externalChange()
        await settle()
        XCTAssertEqual(recorder.fetches.count, 1, "neither a page nor a change notice sends it again")
        sync.refresh(now: Date())
        await waitForFetches(1)
        XCTAssertEqual(recorder.loads.last, true, "the user's Refresh may ask the Keychain")
    }

    func testARateLimitHoldsRefreshUntilItEnds() async {
        let now = Date()
        sync.refresh(now: now)
        await waitForFetches(1)
        await answer(.failed(.rateLimited(until: now.addingTimeInterval(60))))
        sync.refresh(now: now.addingTimeInterval(30))
        await settle()
        XCTAssertEqual(recorder.fetches.count, 1)
        sync.refresh(now: now.addingTimeInterval(61))
        await waitForFetches(1)
        XCTAssertEqual(recorder.fetches.count, 2)
    }

    func testARefreshDuringASyncRunsOnceAfterItWithTheNewOptions() async {
        sync.refresh(now: Date())
        await waitForFetches(1)
        options = 2
        sync.refresh(now: Date())
        sync.refresh(now: Date())
        await settle()
        XCTAssertEqual(recorder.fetches.count, 1, "kept, not started alongside")
        await answer(fetched)
        await waitForFetches(1)
        XCTAssertEqual(recorder.fetches.map(\.options), [1, 2], "once, with the options as they are now")
        await answer(fetched)
        await settle()
        XCTAssertEqual(recorder.fetches.count, 2, "only once")
    }

    func testAKeptRefreshDoesNotRunAfterARefusalOrADeclinedDialog() async throws {
        for ending in [SourceSyncState.authFailed(status: 401), .needsReconnect, .needsKeychainApproval] {
            try await setUp()
            sync.refresh(now: Date())
            await waitForFetches(1)
            sync.refresh(now: Date())
            await answer(.failed(ending))
            await settle()
            XCTAssertEqual(recorder.fetches.count, 1, "\(ending)")
        }
    }

    func testOptionsChangedDropsTheSyncThatReadTheOldOnes() async {
        sync.refresh(now: Date())
        await waitForFetches(1)
        options = 2
        sync.optionsChanged(now: Date())
        await waitForFetches(2)
        await answer(fetched)
        XCTAssertTrue(host.merged.isEmpty, "the old options' result never lands")
        XCTAssertEqual(sync.state, .syncing)
        await answer(fetched)
        XCTAssertEqual(host.merged.count, 1)
    }

    func testChangeNoticesDuringASyncComeToOneMoreSync() async {
        sync.externalChange()
        await waitForFetches(1)
        sync.externalChange()
        sync.externalChange()
        sync.externalChange()
        await answer(fetched)
        await waitForFetches(1)
        await answer(fetched)
        await settle()
        XCTAssertEqual(recorder.fetches.count, 2)
        XCTAssertEqual(recorder.loads, [false, false], "quietly, never with the Keychain dialog")
    }

    func testAPageVisitWhileTheListLoadsSyncsOnceItIsRead() async {
        host.readiness = .loading
        sync.syncIfStale(now: Date())
        await settle()
        XCTAssertTrue(recorder.fetches.isEmpty)
        host.readiness = .ready
        sync.loadFinished()
        await waitForFetches(1)
    }

    func testAListThatCannotBeReadTakesNothing() async {
        sync.refresh(now: Date())
        await waitForFetches(1)
        host.readiness = .failed
        await answer(fetched)
        XCTAssertTrue(host.merged.isEmpty)
        guard case .failed = sync.state else { return XCTFail("\(sync.state)") }
    }

    // MARK: - The credential

    func testAKeychainItemForAnotherScopeMeansReconnect() async {
        recorder.stored = .found(Credential(scope: "elsewhere", token: "kept"))
        sync.refresh(now: Date())
        await settle()
        XCTAssertTrue(recorder.fetches.isEmpty, "never a request to another site or server")
        XCTAssertEqual(sync.state, .needsReconnect)
    }

    func testTheKeychainsAnswersReadAsStates() async {
        recorder.stored = .needsApproval
        sync.syncIfStale(now: Date())
        await settle()
        XCTAssertEqual(sync.state, .needsKeychainApproval)
        recorder.stored = .missing
        sync.refresh(now: Date())
        await settle()
        XCTAssertEqual(sync.state, .needsReconnect)
        XCTAssertTrue(recorder.fetches.isEmpty)
    }

    // MARK: - Connect and Disconnect

    func testConnectSavesOnlyAfterTheCheckAndSyncsWithoutTheKeychain() async {
        connection = SourceConnection(scope: "", syncOn: false)
        recorder.stored = .missing
        let fresh = Credential(scope: "s2", token: "new")
        var committed = 0
        let failure = await sync.connect {
            XCTAssertTrue(self.recorder.saved.isEmpty, "nothing saved before the source accepted it")
            return .accepted(fresh) { committed += 1; self.connection = SourceConnection(scope: "s2", syncOn: true) }
        }
        XCTAssertNil(failure)
        XCTAssertEqual(recorder.saved, [fresh])
        XCTAssertEqual(committed, 1)
        await waitForFetches(1)
        XCTAssertEqual(recorder.loads, [], "the first sync uses the credential in hand")
        XCTAssertEqual(recorder.fetches.map(\.token), ["new"])
    }

    func testARefusedCheckOrAFailedSaveKeepsNothing() async {
        let refused = await sync.connect { .refused("Token rejected.") }
        XCTAssertEqual(refused, "Token rejected.")
        XCTAssertTrue(recorder.saved.isEmpty)
        recorder.saveSucceeds = false
        var committed = false
        let unsaved = await sync.connect { .accepted(Credential(scope: "s2", token: "new")) { committed = true } }
        XCTAssertNotNil(unsaved)
        XCTAssertFalse(committed, "the display copies change only with the Keychain")
    }

    func testADisconnectDuringTheCheckCancelsTheConnect() async {
        let connecting = Task { @MainActor in
            await self.sync.connect {
                await withCheckedContinuation { self.recorder.checkGate = $0 }
                return .accepted(Credential(scope: "s2", token: "new")) {}
            }
        }
        for _ in 0..<200 where recorder.checkGate == nil { await Task.yield() }
        sync.retryRemovingToken()
        XCTAssertEqual(recorder.removes, 0, "Remove Token waits while a Connect may be saving")
        sync.disconnect()
        recorder.checkGate?.resume()
        let result = await connecting.value
        XCTAssertEqual(result, String(localized: "Cancelled."))
        XCTAssertTrue(recorder.saved.isEmpty, "nothing saved over the Disconnect")
    }

    func testDisconnectDropsTheSyncInFlightAndForgetsTheToken() async {
        sync.refresh(now: Date())
        await waitForFetches(1)
        recorder.removeSucceeds = false
        sync.disconnect()
        await settle()
        XCTAssertEqual(forgotten, 1)
        XCTAssertEqual(recorder.removes, 1)
        XCTAssertTrue(sync.tokenRemovalFailed, "the user is told the token is still there")
        await answer(fetched)
        XCTAssertTrue(host.merged.isEmpty, "a result for the old connection never lands")
        XCTAssertEqual(sync.state, .idle)
        recorder.removeSucceeds = true
        sync.retryRemovingToken()
        await settle()
        XCTAssertEqual(recorder.removes, 2)
        XCTAssertFalse(sync.tokenRemovalFailed)
    }

    func testARefusalFromElsewhereMarksOnlyTheConnectionItCameFrom() async {
        let old = sync.generation
        sync.disconnect()
        connection = SourceConnection(scope: "s1", syncOn: true)
        sync.markRejected(old, status: 401)
        XCTAssertEqual(sync.state, .idle, "a 401 for the old token says nothing of the new connection")
        sync.markRejected(sync.generation, status: 401)
        XCTAssertEqual(sync.state, .authFailed(status: 401))
    }
}
