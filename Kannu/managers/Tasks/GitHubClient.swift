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

/// Reads from GitHub or a GitHub Enterprise Server: the app's side of `GitHubReader`, which does the
/// requests, with the log lines. Read-only. Logs carry status codes and counts only: never the
/// token, the server, the user name or a title.
struct GitHubClient {
    private static let log = os.Logger(subsystem: "com.kannu.app", category: "Tasks")

    let reader: GitHubReader

    init(session: URLSession = IntegrationHTTP.shared) {
        reader = GitHubReader(session: session)
    }

    func verify(_ credential: GitHubCredential) async -> GitHubReader.VerifyResult {
        let result = await reader.verify(credential)
        if case .failed(let failure) = result {
            Self.log.notice("GitHub verify failed: \(String(describing: failure), privacy: .public)")
        }
        return result
    }

    func fetch(_ credential: GitHubCredential, includePullRequests: Bool) async -> GitHubReader.Fetch {
        let fetch = await reader.fetch(credential, includePullRequests: includePullRequests)
        if let failure = fetch.failure {
            Self.log.notice("GitHub fetch failed: \(String(describing: failure), privacy: .public)")
        } else {
            Self.log.info("GitHub fetch: \(fetch.issueCount, privacy: .public) issues, \(fetch.pullRequestCount, privacy: .public) pull requests")
        }
        return fetch
    }
}

/// GitHub as a task source (`SourceSync`): the credential's server, checked again, and one fetch of
/// the open issues assigned to the user — and, with Include pull requests on, the pull requests.
struct GitHubTaskSource: TaskSourceProvider {
    func scope(of credential: GitHubCredential) -> String? {
        GitHubHost.isValidBase(credential.baseURL) ? credential.baseURL : nil
    }

    func fetch(_ credential: GitHubCredential, options includePullRequests: Bool) async -> SourceFetch {
        let fetched = await GitHubClient().fetch(credential, includePullRequests: includePullRequests)
        guard case .fetched(let fetch) = fetched.outcome else {
            return .failed(GitHubAPI.syncState(for: fetched.failure, now: Date()))
        }
        return .fetched(fetch)
    }
}
