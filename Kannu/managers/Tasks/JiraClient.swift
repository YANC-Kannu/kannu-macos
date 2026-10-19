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

/// Reads from Jira Cloud. Read-only: nothing here writes to Jira.
///
/// Its methods are nonisolated `async`, so awaiting them from the main actor runs the requests off
/// it (the `CursorUsageEventsClient` shape, with the session injected). Every request goes through
/// `IntegrationHTTP`: ephemeral, 20 s, no redirects.
struct JiraClient {
    enum Failure: Equatable {
        /// The credential's site is not one Kannu would send a request to.
        case badSite
        case http(HTTPOutcome)
        /// A 2xx whose body was not what Jira sends.
        case decode
    }

    enum VerifyResult: Equatable {
        case verified(JiraMyself)
        case failed(Failure)
    }

    private static let log = os.Logger(subsystem: "com.kannu.app", category: "Tasks")

    let session: URLSession

    init(session: URLSession = IntegrationHTTP.shared) {
        self.session = session
    }

    /// `GET /rest/api/3/myself`: whether the site accepts this email and token, and whose they are.
    func verify(_ credential: JiraCredential) async -> VerifyResult {
        guard let request = JiraAPI.myselfRequest(credential) else { return .failed(.badSite) }
        let exchange = await IntegrationHTTP.send(request, session: session)
        guard case .ok = exchange.outcome else {
            Self.log.notice("Jira verify failed: \(String(describing: exchange.outcome), privacy: .public)")
            return .failed(.http(exchange.outcome))
        }
        guard let data = exchange.data, let myself = JiraAPI.decodeMyself(data) else { return .failed(.decode) }
        return .verified(myself)
    }

    /// The issues the filter selects: at most `JiraAPI.maxPages` pages. Any page that fails fails
    /// the whole sync, so a half-read list never marks the other half gone.
    func fetchIssues(_ credential: JiraCredential, jql: String) async -> (outcome: SyncOutcome, failure: Failure?) {
        var issues: [RemoteIssue] = []
        var pageToken: String?
        var pages = 0
        while true {
            guard let request = JiraAPI.searchRequest(credential, jql: jql, nextPageToken: pageToken) else {
                return (.failed, .badSite)
            }
            let exchange = await IntegrationHTTP.send(request, session: session)
            guard case .ok = exchange.outcome else {
                Self.log.notice("Jira search page \(pages + 1, privacy: .public) failed: \(String(describing: exchange.outcome), privacy: .public)")
                return (.failed, .http(exchange.outcome))
            }
            guard let data = exchange.data, let page = JiraAPI.decodeSearchPage(data) else {
                Self.log.notice("Jira search page \(pages + 1, privacy: .public) did not decode")
                return (.failed, .decode)
            }
            pages += 1
            issues += page.issues.map(JiraAPI.remoteIssue(from:))
            switch JiraAPI.nextStep(after: page, pagesFetched: pages) {
            case .next(let next):
                pageToken = next
            case .done(let complete):
                return (.fetched(RemoteFetch(issues: issues, complete: complete)), nil)
            case .capped:
                return (.fetched(RemoteFetch(issues: issues, complete: false)), nil)
            }
        }
    }
}

/// Jira Cloud as a task source (`SourceSync`): the credential's site, checked again, and one fetch
/// of the user's issues by the issue filter. Its failures read as the Jira page says them.
struct JiraTaskSource: TaskSourceProvider {
    func scope(of credential: JiraCredential) -> String? {
        JiraSite.isValidHost(credential.site) ? credential.site : nil
    }

    func fetch(_ credential: JiraCredential, options jql: String) async -> SourceFetch {
        let result = await JiraClient().fetchIssues(credential, jql: jql)
        guard case .fetched(let fetch) = result.outcome else {
            return .failed(Self.syncState(for: result.failure, now: Date()))
        }
        return .fetched(fetch)
    }

    static func syncState(for failure: JiraClient.Failure?, now: Date) -> SourceSyncState {
        switch failure {
        case .http(.offline):
            return .offline
        case .http(.rateLimited(let seconds)):
            return .rateLimited(until: now.addingTimeInterval(seconds))
        case .http(.auth(let status)):
            return .authFailed(status: status)
        case .http(.rejected(400)):
            return .failed(String(localized: "Jira refused the issue filter (400). Check it under Advanced, or reset it."))
        case .http(.rejected(let status)):
            return .failed(String(localized: "Jira refused the request (\(status)). The account may have lost access to this site."))
        case .http(.redirected(let status)):
            return .failed(String(localized: "The site answered with a redirect (\(status)), which Kannu never follows."))
        case .http(.failedBeforeSend):
            return .failed(String(localized: "Kannu could not reach the Jira site. Check your connection."))
        case .http(.ambiguous(let status?)):
            return .failed(String(localized: "Jira did not answer properly (\(status)). Try again later."))
        case .http(.ambiguous(nil)), .http(.ok):
            return .failed(String(localized: "Jira did not answer in time. Try again later."))
        case .decode:
            return .failed(String(localized: "Jira's answer could not be read."))
        case .badSite, nil:
            return .needsReconnect
        }
    }

    static func message(for error: JiraSiteError) -> String {
        switch error {
        case .empty:
            return String(localized: "Type your Jira site, such as acme or acme.atlassian.net.")
        case .notHTTPS:
            return String(localized: "Kannu connects to Jira over HTTPS only.")
        case .userInfo:
            return String(localized: "The site has a name and @ before the host. Type just the site, such as acme.atlassian.net.")
        case .port:
            return String(localized: "Jira Cloud uses the standard HTTPS port. Remove the port from the site.")
        case .notAtlassianCloud, .malformed:
            return String(localized: "That is not a Jira Cloud site. It looks like acme.atlassian.net.")
        }
    }

    static func connectMessage(for failure: JiraClient.Failure, host: String) -> String {
        switch failure {
        case .badSite:
            return message(for: .notAtlassianCloud)
        case .decode, .http(.ok):
            return String(localized: "\(host) answered, but not the way Jira Cloud does. Check the site.")
        case .http(.auth(let status)):
            return String(localized: "Jira did not accept that email and token (\(status)). Check both, or create a new token.")
        case .http(.rejected(404)):
            return String(localized: "No Jira site answered at \(host) (404). Check the site.")
        case .http(.rejected(let status)):
            return String(localized: "Jira refused the request (\(status)).")
        case .http(.redirected(let status)):
            return String(localized: "\(host) answered with a redirect (\(status)), which Kannu never follows. Check the site.")
        case .http(.rateLimited):
            return String(localized: "Jira is limiting requests right now. Try again in a minute.")
        case .http(.offline):
            return String(localized: "This Mac is offline.")
        case .http(.failedBeforeSend):
            return String(localized: "Kannu could not reach \(host). Check the site and your connection.")
        case .http(.ambiguous):
            return String(localized: "Jira did not answer. Try again.")
        }
    }
}
