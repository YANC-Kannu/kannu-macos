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

import XCTest

/// When Kannu may let macOS prompt for another tool's keychain item ("Codex Auth",
/// "cursor-access-token"), and that one Cursor refresh reads its token once. The reads are stand-ins
/// that record each `allowInteraction`: no keychain is touched.
final class KeychainReadPolicyTests: XCTestCase {
    private typealias Outcome = KeychainReadPolicy.Outcome

    /// Records every read the policy makes and answers from a script.
    private final class ScriptedKeychain: @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [Bool: Outcome]
        private(set) var reads: [Bool] = []

        init(silent: Outcome, prompted: Outcome = Outcome()) {
            answers = [false: silent, true: prompted]
        }

        func read(_ allowInteraction: Bool) -> Outcome {
            lock.lock()
            defer { lock.unlock() }
            reads.append(allowInteraction)
            return answers[allowInteraction] ?? Outcome()
        }
    }

    private static let approval = Outcome(value: nil, needsApproval: true)

    func testASilentReadThatWorksIsTheOnlyRead() {
        let keychain = ScriptedKeychain(silent: Outcome(value: "token"))
        var fallbackCalls = 0
        let resolution = KeychainReadPolicy.resolve(interactive: true, fallback: { fallbackCalls += 1; return nil },
                                                    read: keychain.read)
        XCTAssertEqual(resolution, .found("token"))
        XCTAssertEqual(keychain.reads, [false])
        XCTAssertEqual(fallbackCalls, 0)
    }

    func testAnAutomaticRefreshNeverPromptsAndReportsTheApprovalItNeeds() {
        let keychain = ScriptedKeychain(silent: Self.approval, prompted: Outcome(value: "token"))
        XCTAssertEqual(KeychainReadPolicy.resolve(interactive: false, read: keychain.read), .needsApproval)
        XCTAssertEqual(keychain.reads, [false], "no prompting read outside a user-initiated refresh")
    }

    func testAMissingItemIsMissingWithoutAPrompt() {
        let keychain = ScriptedKeychain(silent: Outcome())
        XCTAssertEqual(KeychainReadPolicy.resolve(interactive: false, read: keychain.read), .missing)
        XCTAssertEqual(keychain.reads, [false])
    }

    func testAUserInitiatedRefreshPromptsExactlyOnce() {
        let keychain = ScriptedKeychain(silent: Self.approval, prompted: Outcome(value: "token"))
        XCTAssertEqual(KeychainReadPolicy.resolve(interactive: true, read: keychain.read), .found("token"))
        XCTAssertEqual(keychain.reads, [false, true])
    }

    func testADeniedPromptKeepsTheButtonAndIsNotRetried() {
        // Denying the dialog returns a status that is not "needs approval"; the item is still there.
        let keychain = ScriptedKeychain(silent: Self.approval, prompted: Outcome())
        XCTAssertEqual(KeychainReadPolicy.resolve(interactive: true, read: keychain.read), .needsApproval)
        XCTAssertEqual(keychain.reads, [false, true])
    }

    func testASilentFallbackAnswersBeforeAnyPrompt() {
        // Cursor: a state.vscdb token means the cursor-agent item is never read with a dialog.
        let keychain = ScriptedKeychain(silent: Self.approval, prompted: Outcome(value: "keychain-token"))
        let resolution = KeychainReadPolicy.resolve(interactive: true, fallback: { "database-token" }, read: keychain.read)
        XCTAssertEqual(resolution, .found("database-token"))
        XCTAssertEqual(keychain.reads, [false])
    }

    // MARK: - One read per refresh

    private static let service = "cursor-access-token"

    func testOneScopeReadsOnceForEveryRequestInside() async {
        let keychain = ScriptedKeychain(silent: Outcome(value: "token"))
        let read = { KeychainReadPolicy.resolve(interactive: false, read: keychain.read) }
        let values = await CredentialReadScope.withSingleRead(service: Self.service, read: read) { () async -> [String?] in
            var values: [String?] = []
            for _ in 0..<12 {
                values.append(CredentialReadScope.resolution(service: Self.service, orRead: read).value)
            }
            // A nested scope (the quota client inside the provider) reuses the outer read.
            let nested = await CredentialReadScope.withSingleRead(service: Self.service, read: read) {
                CredentialReadScope.resolution(service: Self.service, orRead: read).value
            }
            values.append(nested)
            // So do child tasks.
            async let child = CredentialReadScope.resolution(service: Self.service, orRead: read).value
            values.append(await child)
            return values
        }
        XCTAssertEqual(values.count, 14)
        XCTAssertTrue(values.allSatisfy { $0 == "token" })
        XCTAssertEqual(keychain.reads, [false], "one read for the whole refresh")
    }

    func testOutsideAScopeEveryCallReads() {
        let keychain = ScriptedKeychain(silent: Outcome(value: "token"))
        let read = { KeychainReadPolicy.resolve(interactive: false, read: keychain.read) }
        _ = CredentialReadScope.resolution(service: Self.service, orRead: read)
        _ = CredentialReadScope.resolution(service: Self.service, orRead: read)
        XCTAssertEqual(keychain.reads, [false, false])
    }

    func testAScopeNeverAnswersForAnotherService() async {
        let cursor = ScriptedKeychain(silent: Outcome(value: "cursor-token"))
        let other = ScriptedKeychain(silent: Outcome(value: "other-token"))
        let value = await CredentialReadScope.withSingleRead(
            service: Self.service,
            read: { KeychainReadPolicy.resolve(interactive: false, read: cursor.read) }
        ) {
            CredentialReadScope.resolution(service: "Codex Auth") {
                KeychainReadPolicy.resolve(interactive: false, read: other.read)
            }.value
        }
        XCTAssertEqual(value, "other-token")
        XCTAssertEqual(cursor.reads, [false])
        XCTAssertEqual(other.reads, [false])
    }

    func testAnInteractiveScopePromptsOnceAndSharesTheResult() async {
        let keychain = ScriptedKeychain(silent: Self.approval, prompted: Outcome(value: "token"))
        let values = await CredentialReadScope.withSingleRead(
            service: Self.service,
            read: { KeychainReadPolicy.resolve(interactive: true, read: keychain.read) }
        ) { () -> [String?] in
            (0..<5).map { _ in
                CredentialReadScope.resolution(service: Self.service) {
                    KeychainReadPolicy.resolve(interactive: false, read: keychain.read)
                }.value
            }
        }
        XCTAssertEqual(values, Array(repeating: "token", count: 5))
        XCTAssertEqual(keychain.reads, [false, true], "the dialog appears once per tap, not once per request")
    }
}
