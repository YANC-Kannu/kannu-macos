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
import Security

extension SecretSlot {
    /// A `SecureSecretsStore` item: Kannu's own Keychain service, the key's account. An item
    /// another build saved, whose access list no longer matches, reads as needing approval.
    static func keychain(_ key: SecureSecretKey) -> SecretSlot {
        SecretSlot(
            read: { allowInteraction in
                let read = SecureSecretsStore.read(key, allowInteraction: allowInteraction)
                if read.status == errSecItemNotFound { return .missing }
                if KeychainReader.needsUserApproval(read.status) { return .needsApproval }
                guard read.status == errSecSuccess, let value = read.value else { return .unreadable }
                return .value(value)
            },
            write: { SecureSecretsStore.set($0, for: key) },
            remove: { SecureSecretsStore.removeValue(for: key) }
        )
    }
}

/// Each source's sign-in in the Keychain, one item and one serial queue each (`CredentialStore`).
/// The items and their contents are the ones Kannu always saved, so nobody connects again.
enum TaskCredentials {
    static let jira = CredentialStore<JiraCredential>(slot: .keychain(.jiraCredential), queueLabel: "com.kannu.app.tasks.jira-keychain")
    static let gitlab = CredentialStore<GitLabCredential>(slot: .keychain(.gitlabCredential), queueLabel: "com.kannu.app.tasks.gitlab-keychain")
}
