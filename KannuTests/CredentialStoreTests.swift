//
//  CredentialStoreTests.swift
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

/// One credential store for every source (`CredentialStore`) in place of Jira's and GitLab's twins.
/// What they saved must read back unchanged, so nobody connects again after the update.
final class CredentialStoreTests: XCTestCase {
    /// A Keychain item in memory.
    final class Item {
        var read: SecretSlot.Read = .missing
        var written: [String] = []
        var removed = 0
        var removeSucceeds = true
        var lastAllowInteraction: Bool?

        var slot: SecretSlot {
            SecretSlot(
                read: { allow in self.lastAllowInteraction = allow; return self.read },
                write: { self.written.append($0); return true },
                remove: { self.removed += 1; return self.removeSucceeds }
            )
        }
    }

    func testTheItemsKannuAlreadySavedReadBack() async {
        let item = Item()
        item.read = .value(#"{"email":"dana@example.com","site":"acme.atlassian.net","token":"FAKE-TOKEN"}"#)
        let jira = CredentialStore<JiraCredential>(slot: item.slot, queueLabel: "test.jira")
        guard case .found(let credential) = await jira.load(allowInteraction: false) else { return XCTFail("did not read") }
        XCTAssertEqual(credential, JiraCredential(site: "acme.atlassian.net", email: "dana@example.com", token: "FAKE-TOKEN"))
        XCTAssertEqual(item.lastAllowInteraction, false)

        item.read = .value(#"{"baseURL":"https://gitlab.com","token":"FAKE-TOKEN"}"#)
        let gitlab = CredentialStore<GitLabCredential>(slot: item.slot, queueLabel: "test.gitlab")
        guard case .found(let other) = await gitlab.load(allowInteraction: true) else { return XCTFail("did not read") }
        XCTAssertEqual(other, GitLabCredential(baseURL: "https://gitlab.com", token: "FAKE-TOKEN"))
        XCTAssertEqual(item.lastAllowInteraction, true)
    }

    func testASaveWritesTheSameTextAsBefore() async {
        let item = Item()
        let jira = CredentialStore<JiraCredential>(slot: item.slot, queueLabel: "test.jira")
        let saved = await jira.save(JiraCredential(site: "acme.atlassian.net", email: "dana@example.com", token: "FAKE-TOKEN"))
        XCTAssertTrue(saved)
        XCTAssertEqual(item.written, [#"{"email":"dana@example.com","site":"acme.atlassian.net","token":"FAKE-TOKEN"}"#],
                       "sorted keys, slashes unescaped: byte for byte what the old store wrote")
        let gitlab = CredentialStore<GitLabCredential>(slot: item.slot, queueLabel: "test.gitlab")
        _ = await gitlab.save(GitLabCredential(baseURL: "https://gitlab.com", token: "FAKE-TOKEN"))
        XCTAssertEqual(item.written.last, #"{"baseURL":"https://gitlab.com","token":"FAKE-TOKEN"}"#)
    }

    func testTheKeychainsOtherAnswers() async {
        let item = Item()
        let store = CredentialStore<JiraCredential>(slot: item.slot, queueLabel: "test.jira")
        let cases: [(SecretSlot.Read, String)] = [(.missing, "missing"), (.needsApproval, "needsApproval"),
                                                  (.unreadable, "broken"), (.value("not json"), "broken")]
        for (read, expected) in cases {
            item.read = read
            switch await store.load(allowInteraction: false) {
            case .found: XCTFail("\(read) read as found")
            case .missing: XCTAssertEqual(expected, "missing")
            case .needsApproval: XCTAssertEqual(expected, "needsApproval")
            case .broken: XCTAssertEqual(expected, "broken")
            }
        }
        item.removeSucceeds = false
        let removed = await store.remove()
        XCTAssertFalse(removed, "a token still there is never reported gone")
        XCTAssertEqual(item.removed, 1)
    }
}
