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

/// Reads from Todoist: the app's side of `TodoistReader`, which does the requests, with the log
/// lines. Read-only. Logs carry outcomes and counts only: never the token, the account or a title.
struct TodoistClient {
    private static let log = os.Logger(subsystem: "com.kannu.app", category: "Tasks")

    let reader: TodoistReader

    init(session: URLSession = IntegrationHTTP.shared) {
        reader = TodoistReader(session: session)
    }

    func verify(token: String) async -> TodoistReader.VerifyResult {
        let result = await reader.verify(token: token)
        if case .failed(let failure) = result {
            Self.log.notice("Todoist verify failed: \(String(describing: failure), privacy: .public)")
        }
        return result
    }

    func fetch(_ credential: TodoistCredential, filter: String) async -> (outcome: SyncOutcome, failure: TodoistReader.Failure?) {
        let result = await reader.fetch(credential, filter: filter)
        if let failure = result.failure {
            Self.log.notice("Todoist fetch failed: \(String(describing: failure), privacy: .public)")
        }
        return result
    }
}

/// Todoist as a task source (`SourceSync`): the credential's account, checked again, and one fetch of
/// the open tasks — all of them, or those a Todoist filter matches — skipping tasks assigned to
/// someone else.
struct TodoistTaskSource: TaskSourceProvider {
    func scope(of credential: TodoistCredential) -> String? {
        TodoistAPI.scope(userID: credential.userID)
    }

    func fetch(_ credential: TodoistCredential, options filter: String) async -> SourceFetch {
        let result = await TodoistClient().fetch(credential, filter: filter)
        guard case .fetched(let fetch) = result.outcome else {
            return .failed(TodoistAPI.syncState(for: result.failure, now: Date()))
        }
        return .fetched(fetch)
    }
}
