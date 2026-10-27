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

/// Reads from Linear: the app's side of `LinearReader`, which does the requests, with the log lines.
/// Read-only. Logs carry outcomes and counts only: never the key, the workspace or a title.
struct LinearClient {
    private static let log = os.Logger(subsystem: "com.kannu.app", category: "Tasks")

    let reader: LinearReader

    init(session: URLSession = IntegrationHTTP.shared) {
        reader = LinearReader(session: session)
    }

    func verify(apiKey: String) async -> LinearReader.VerifyResult {
        let result = await reader.verify(apiKey: apiKey)
        if case .failed(let failure) = result {
            Self.log.notice("Linear verify failed: \(String(describing: failure), privacy: .public)")
        }
        return result
    }

    func fetch(_ credential: LinearCredential) async -> (outcome: SyncOutcome, failure: LinearReader.Failure?) {
        let result = await reader.fetch(credential)
        if let failure = result.failure {
            Self.log.notice("Linear fetch failed: \(String(describing: failure), privacy: .public)")
        }
        return result
    }
}

/// Linear as a task source (`SourceSync`): the credential's workspace, checked again, and one fetch
/// of the issues assigned to the user that are not done or canceled.
struct LinearTaskSource: TaskSourceProvider {
    func scope(of credential: LinearCredential) -> String? {
        LinearAPI.isValidScope(credential.workspace) ? credential.workspace : nil
    }

    func fetch(_ credential: LinearCredential, options: Void) async -> SourceFetch {
        let result = await LinearClient().fetch(credential)
        guard case .fetched(let fetch) = result.outcome else {
            return .failed(LinearAPI.syncState(for: result.failure, now: Date()))
        }
        return .fetched(fetch)
    }
}
