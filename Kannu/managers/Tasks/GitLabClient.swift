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
import Security

/// Reads from GitLab: the app's side of `GitLabReader`, which does the requests, with the log lines.
/// Read-only: nothing here writes to GitLab.
///
/// Its methods are nonisolated `async`, so awaiting them from the main actor runs the requests off
/// it. Logs carry status codes and counts only: never the token, the server, the user name or a
/// title.
struct GitLabClient {
    private static let log = os.Logger(subsystem: "com.kannu.app", category: "Tasks")

    let reader: GitLabReader

    init(session: URLSession = IntegrationHTTP.shared) {
        reader = GitLabReader(session: session)
    }

    func verify(_ credential: GitLabCredential) async -> GitLabReader.VerifyResult {
        let result = await reader.verify(credential)
        switch result {
        case .verified(_, let scopes):
            Self.log.info("GitLab verify: ok, scopes known \(scopes != nil, privacy: .public)")
        case .failed(let failure):
            Self.log.notice("GitLab verify failed: \(String(describing: failure), privacy: .public)")
        }
        return result
    }

    func closingMergeRequests(_ credential: GitLabCredential, projectID: Int, iid: Int) async -> Result<(items: [LinkedMergeRequest], complete: Bool), GitLabReader.Failure> {
        let result = await reader.closingMergeRequests(credential, projectID: projectID, iid: iid)
        switch result {
        case .success(let read):
            Self.log.info("GitLab linked MRs: \(read.items.count, privacy: .public), complete \(read.complete, privacy: .public)")
        case .failure(let failure):
            Self.log.notice("GitLab linked MRs failed: \(String(describing: failure), privacy: .public)")
        }
        return result
    }

    func fetchItems(_ credential: GitLabCredential, username: String, includeMergeRequests: Bool) async -> GitLabReader.Fetch {
        let fetch = await reader.fetchItems(credential, username: username, includeMergeRequests: includeMergeRequests)
        if let failure = fetch.failure {
            Self.log.notice("GitLab fetch failed: \(String(describing: failure), privacy: .public)")
        } else {
            Self.log.info("GitLab fetch: \(fetch.issueCount, privacy: .public) issues, \(fetch.mergeRequestCount, privacy: .public) merge requests")
        }
        return fetch
    }
}

/// GitLab as a task source (`SourceSync`): the credential's server, checked again, and one fetch
/// of the user's open issues and, with Include merge requests on, the merge requests assigned to
/// them or waiting for their review. Its failures read as the GitLab page says them.
struct GitLabTaskSource: TaskSourceProvider {
    struct Options {
        /// The token owner's user name, for the "waiting for my review" list.
        var username: String
        var includeMergeRequests: Bool
    }

    func scope(of credential: GitLabCredential) -> String? {
        GitLabHost.isValidBase(credential.baseURL) ? credential.baseURL : nil
    }

    func fetch(_ credential: GitLabCredential, options: Options) async -> SourceFetch {
        let fetched = await GitLabClient().fetchItems(credential, username: options.username,
                                                      includeMergeRequests: options.includeMergeRequests)
        guard case .fetched(let fetch) = fetched.outcome else {
            return .failed(Self.syncState(for: fetched.failure, now: Date()))
        }
        return .fetched(fetch)
    }

    static func syncState(for failure: GitLabReader.Failure?, now: Date) -> SourceSyncState {
        switch failure {
        case .http(.offline):
            return .offline
        case .http(.rateLimited(let seconds)):
            return .rateLimited(until: now.addingTimeInterval(seconds))
        case .http(.auth(let status)):
            return .authFailed(status: status)
        case .http(.rejected(403)):
            return .failed(String(localized: "GitLab refused the request (403). The token may lack the read_api scope, or have lost access."))
        case .http(.rejected(let status)):
            return .failed(String(localized: "GitLab refused the request (\(status))."))
        case .http(.redirected(let status)):
            return .failed(String(localized: "The server answered with a redirect (\(status)), which Kannu never follows."))
        case .http(.failedBeforeSend):
            return .failed(String(localized: "Kannu could not reach the GitLab server over a trusted HTTPS connection. Check your connection."))
        case .http(.ambiguous(let status?)):
            return .failed(String(localized: "GitLab did not answer properly (\(status)). Try again later."))
        case .http(.ambiguous(nil)), .http(.ok):
            return .failed(String(localized: "GitLab did not answer in time. Try again later."))
        case .decode:
            return .failed(String(localized: "GitLab's answer could not be read."))
        case .badServer, .badUsername, nil:
            return .needsReconnect
        }
    }

    static func message(for error: GitLabHostError) -> String {
        switch error {
        case .empty:
            return String(localized: "Type your GitLab server, such as https://gitlab.com or https://gitlab.example.com.")
        case .notHTTPS:
            return String(localized: "Kannu connects to GitLab over HTTPS only.")
        case .userInfo:
            return String(localized: "The server has a name and @ before the host. Type just the server, such as https://gitlab.example.com.")
        case .queryOrFragment, .badPath:
            return String(localized: "Type the server's address, not a page on it, such as https://gitlab.example.com or https://example.com/gitlab.")
        case .port:
            return String(localized: "That port is not a valid one.")
        case .malformed:
            return String(localized: "That is not a server address. It looks like https://gitlab.example.com.")
        }
    }

    static func connectMessage(for failure: GitLabReader.Failure, server: String) -> String {
        switch failure {
        case .badServer:
            return message(for: GitLabHostError.malformed)
        case .badUsername, .decode, .http(.ok):
            return String(localized: "\(server) answered, but not the way GitLab does. Check the server.")
        case .http(.auth(let status)):
            return String(localized: "GitLab did not accept that token (\(status)). It may have expired or been revoked: create a new one.")
        case .http(.rejected(403)):
            return String(localized: "GitLab refused the token (403). Create one with the read_api scope, or api to log time later.")
        case .http(.rejected(404)):
            return String(localized: "No GitLab answered at \(server) (404). Check the server, and its path if it has one.")
        case .http(.rejected(let status)):
            return String(localized: "GitLab refused the request (\(status)).")
        case .http(.redirected(let status)):
            return String(localized: "\(server) answered with a redirect (\(status)), which Kannu never follows. Check the server, and its path if it has one.")
        case .http(.rateLimited):
            return String(localized: "GitLab is limiting requests right now. Try again in a minute.")
        case .http(.offline):
            return String(localized: "This Mac is offline.")
        case .http(.failedBeforeSend):
            return String(localized: "Kannu could not reach \(server) over a trusted HTTPS connection. Check the server and your connection. A certificate macOS does not trust, such as a self-signed one, is refused.")
        case .http(.ambiguous):
            return String(localized: "GitLab did not answer. Try again.")
        }
    }
}
