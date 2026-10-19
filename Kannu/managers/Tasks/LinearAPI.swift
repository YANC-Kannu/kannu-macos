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

/// The Linear sign-in: the workspace the key belongs to and a personal API key. Stored as one JSON
/// item in the Keychain, never in Defaults, so the key and the workspace its issue pages must be on
/// cannot be separated.
///
/// It never prints its key: not in `print`, string interpolation, `dump` or the debugger's summary,
/// so a stray log line cannot leak it.
struct LinearCredential: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// `LinearAPI.scope(urlKey:)`'s form: `https://linear.app/acme`. Learned at Connect from the
    /// key's own organization, never typed: a personal API key belongs to one workspace.
    var workspace: String
    var apiKey: String

    var description: String { "LinearCredential(workspace: \(workspace), apiKey: <redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["workspace": workspace]) }

    /// The Keychain form: compact JSON with sorted keys.
    func encoded() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decoded(_ text: String) -> LinearCredential? {
        try? JSONDecoder().decode(LinearCredential.self, from: Data(text.utf8))
    }
}

extension LinearCredential: StoredCredential {}

/// `query { viewer { … } organization { … } }`: whose key it is, and the workspace it belongs to.
/// Only what Kannu shows and scopes by.
struct LinearViewer: Equatable {
    let id: String
    let name: String
    /// The short name Linear shows in its own UI; may be absent.
    let displayName: String?
    /// The workspace's part of every Linear link: `acme` in `https://linear.app/acme/issue/ENG-1`.
    let organizationURLKey: String
    let organizationName: String

    /// The workspace as `LinearCredential.workspace` keeps it; nil for a URL key Kannu would not use.
    var scope: String? { LinearAPI.scope(urlKey: organizationURLKey) }
}

/// One issue from the assigned-issues list. Only `id` and `identifier` are required; the rest is
/// read leniently, each on its own, so a field in a shape this version does not expect costs that
/// field, never the issue (and so never the page).
struct LinearIssue: Decodable, Equatable {
    /// Linear's UUID for the issue. Stable when the issue moves to another team, unlike its key.
    let id: String
    /// `ENG-123`: the team's key and the issue's number within the team.
    let identifier: String
    let title: String?
    /// `https://linear.app/<workspace>/issue/ENG-123/<slug>`.
    let url: String?
    /// 0 no priority, 1 urgent, 2 high, 3 normal, 4 low. A Float in Linear's schema.
    let priority: LenientField<Double>?
    /// "No priority", "Urgent", "High", "Medium", "Low".
    let priorityLabel: LenientField<String>?
    /// `YYYY-MM-DD`, or null.
    let dueDate: LenientField<String>?
    let updatedAt: LenientField<String>?
    let state: LenientField<State>?
    let parent: LenientField<Parent>?
    let cycle: LenientField<Cycle>?
    let labels: LenientField<Labels>?

    struct State: Decodable, Equatable {
        /// The team's own name for it: "In Progress", "In Review", "Todo".
        let name: String?
        /// "triage", "backlog", "unstarted", "started", "completed" or "canceled".
        let type: String?
    }

    struct Parent: Decodable, Equatable {
        let title: String?
    }

    struct Cycle: Decodable, Equatable {
        /// A Float in Linear's schema; whole in practice.
        let number: Double?
        /// Null for a cycle nobody named.
        let name: String?
    }

    /// The label names. Read leniently: a node without a name is skipped, another shape costs the
    /// labels, never the issue.
    struct Labels: Decodable, Equatable {
        let names: [String]

        private struct Node: Decodable {
            let name: String?
        }

        private enum CodingKeys: String, CodingKey {
            case nodes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            names = ((try? container.decode([Node].self, forKey: .nodes)) ?? []).compactMap(\.name)
        }
    }
}

/// One page of the assigned-issues list.
struct LinearIssuePage: Equatable {
    let issues: [LinearIssue]
    let hasNextPage: Bool
    /// The cursor the next page starts after; nil on an empty page.
    let endCursor: String?
}

/// One entry of a GraphQL answer's `errors`, reduced to what Kannu acts on.
struct LinearGraphQLError: Equatable {
    enum Kind: Hashable {
        /// The key was refused: missing, wrong, revoked or expired.
        case authentication
        case rateLimited
        /// The key may not read this.
        case forbidden
        /// Anything else: a query Linear did not accept, an error on its side.
        case other
    }

    let kind: Kind
    /// Linear's own text, as sent. Shown only after `LinearAPI.reason(_:redacting:)` cleans it.
    let message: String?
}

/// Building Linear requests and reading their answers. Pure: nothing here sends anything, so the
/// logic target checks every header and body.
///
/// Linear has one endpoint, its GraphQL API, and every request is a POST to it. The key travels
/// only in the `Authorization` header, raw (Linear's form for a personal API key; `Bearer` is for
/// OAuth tokens), and only to `endpoint`. It is never put in a URL or a body. Both queries are
/// Kannu's own constants; a value from an answer (the page cursor) goes only into the JSON
/// variables, never into the query text. Read-only: neither query changes anything in Linear.
enum LinearAPI {
    static let endpoint = URL(string: "https://api.linear.app/graphql")!
    /// The workspace part of every Linear page: `https://linear.app/<urlKey>`.
    static let webBase = "https://linear.app/"
    /// Where a personal API key is made: Settings › Security & access.
    static let createKeyURL = URL(string: "https://linear.app/settings/account/security")!
    static let pageSize = 100
    /// At most two pages per sync: two requests, far below Linear's 2,500 an hour per key. A
    /// bigger list is reported as incomplete, never silently cut.
    static let maxPages = 2
    static let maxKeyLength = 200
    static let maxURLKeyLength = 64
    /// Linear's `RATELIMITED` answer and its 429 say when the hour's quota resets here, in Unix
    /// time in milliseconds.
    static let rateLimitResetHeader = "X-RateLimit-Requests-Reset"
    /// Jira's status-category key for Done, which `RemoteIssue.statusCategory` shares.
    static let doneCategory = "done"

    /// Who the key belongs to and its workspace: the Connect check.
    static let viewerQuery = "query { viewer { id name displayName } organization { urlKey name } }"

    /// The open issues assigned to the key's owner, most recently updated first. Completed and
    /// canceled issues are left out by Linear, so a page holds only work still to do.
    static let assignedIssuesQuery = "query($after: String) { viewer { assignedIssues(first: \(pageSize), after: $after, orderBy: updatedAt, filter: { state: { type: { nin: [\"completed\", \"canceled\"] } } }) { nodes { id identifier title url priority priorityLabel dueDate updatedAt state { name type } parent { title } cycle { number name } labels(first: 20) { nodes { name } } } pageInfo { hasNextPage endCursor } } } }"

    // MARK: - Checks

    /// The workspace for a URL key: `acme` → `https://linear.app/acme`. Nil unless the key is
    /// lowercase letters, digits and `-`, 1 to 64 of them: anything else could change the page
    /// links it is compared with.
    static func scope(urlKey: String) -> String? {
        guard (1...maxURLKeyLength).contains(urlKey.unicodeScalars.count) else { return nil }
        let allowed = urlKey.unicodeScalars.allSatisfy { scalar in
            (97...122).contains(scalar.value) || (48...57).contains(scalar.value) || scalar == "-"
        }
        return allowed ? webBase + urlKey : nil
    }

    /// Whether a saved workspace is one `scope(urlKey:)` makes, so a Keychain edit cannot widen the
    /// links Kannu keeps.
    static func isValidScope(_ scope: String) -> Bool {
        guard scope.hasPrefix(webBase) else { return false }
        let urlKey = String(scope.dropFirst(webBase.count))
        return LinearAPI.scope(urlKey: urlKey) == scope
    }

    /// A personal API key as it can travel in a header: printable ASCII, no spaces, at most
    /// `maxKeyLength` characters.
    static func isPlausibleKey(_ key: String) -> Bool {
        !key.isEmpty && key.unicodeScalars.count <= maxKeyLength
            && key.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value < 0x7F }
    }

    /// A page cursor from an answer, before it goes into the next request's variables. It is JSON
    /// there, never query text, so this only bounds it.
    static func isPlausibleCursor(_ cursor: String) -> Bool {
        !cursor.isEmpty && cursor.utf8.count <= 1024
    }

    /// Whether `url` is an issue page in the workspace, so a link from an answer is kept only when
    /// it opens Linear, and the right workspace in it. Printable ASCII only: `URL(string:)` would
    /// quietly percent-encode a space rather than refuse it.
    static func isIssueURL(_ url: String, in scope: String) -> Bool {
        isValidScope(scope) && url.hasPrefix(scope + "/issue/") && url.utf8.count <= 2048
            && url.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value < 0x7F } && URL(string: url) != nil
    }

    // MARK: - Requests

    /// The JSON every request sends.
    private struct Body: Encodable {
        let query: String
        let variables: [String: String]
    }

    /// A POST of `query` to `endpoint` with the key, or nil for a key that cannot travel in a header.
    /// A nil variable is left out, which GraphQL reads as null.
    static func request(apiKey: String, query: String, variables: [String: String] = [:]) -> URLRequest? {
        guard isPlausibleKey(apiKey) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let body = try? encoder.encode(Body(query: query, variables: variables)) else { return nil }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: IntegrationHTTP.timeout)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }

    static func viewerRequest(apiKey: String) -> URLRequest? {
        request(apiKey: apiKey, query: viewerQuery)
    }

    /// The first page with no cursor; a later one after the previous page's `endCursor`.
    static func issuesRequest(apiKey: String, after cursor: String?) -> URLRequest? {
        request(apiKey: apiKey, query: assignedIssuesQuery, variables: cursor.map { ["after": $0] } ?? [:])
    }

    // MARK: - Answers

    /// Every GraphQL answer: `data`, `errors`, or both when part of a query failed.
    private struct Envelope<Payload: Decodable>: Decodable {
        let data: Payload?
    }

    private struct ViewerPayload: Decodable {
        let viewer: Viewer
        let organization: Organization

        struct Viewer: Decodable {
            let id: String
            let name: String
            let displayName: String?
        }

        struct Organization: Decodable {
            let urlKey: String
            let name: String
        }
    }

    private struct IssuesPayload: Decodable {
        let viewer: Viewer

        struct Viewer: Decodable {
            let assignedIssues: Connection
        }

        struct Connection: Decodable {
            let nodes: [LinearIssue]
            let pageInfo: PageInfo
        }

        struct PageInfo: Decodable {
            let hasNextPage: Bool
            let endCursor: String?
        }
    }

    static func decodeViewer(_ data: Data) -> LinearViewer? {
        guard let payload = (try? JSONDecoder().decode(Envelope<ViewerPayload>.self, from: data))?.data else { return nil }
        return LinearViewer(
            id: payload.viewer.id,
            name: payload.viewer.name,
            displayName: payload.viewer.displayName,
            organizationURLKey: payload.organization.urlKey,
            organizationName: payload.organization.name
        )
    }

    static func decodeIssuePage(_ data: Data) -> LinearIssuePage? {
        guard let connection = (try? JSONDecoder().decode(Envelope<IssuesPayload>.self, from: data))?.data?.viewer.assignedIssues else {
            return nil
        }
        return LinearIssuePage(issues: connection.nodes, hasNextPage: connection.pageInfo.hasNextPage, endCursor: connection.pageInfo.endCursor)
    }

    /// The answer's `errors`, each with what it means. Read with `JSONSerialization`, so any shape
    /// is tolerated: a body that is not GraphQL has none.
    ///
    /// Linear names the kind in `extensions.code` and, in some answers, `extensions.type`; both are
    /// read, compared without regard to case, spaces or dashes (`AUTHENTICATION_ERROR`,
    /// "authentication error").
    static func graphQLErrors(_ data: Data?) -> [LinearGraphQLError] {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = object["errors"] as? [Any] else { return [] }
        return errors.compactMap { entry in
            guard let error = entry as? [String: Any] else { return nil }
            let extensions = error["extensions"] as? [String: Any]
            let names = [extensions?["code"], extensions?["type"]].compactMap { $0 as? String }.map(normalizedCode)
            return LinearGraphQLError(kind: kind(of: names), message: error["message"] as? String)
        }
    }

    private static func normalizedCode(_ code: String) -> String {
        code.uppercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
    }

    private static func kind(of names: [String]) -> LinearGraphQLError.Kind {
        if names.contains(where: { ["AUTHENTICATION_ERROR", "UNAUTHENTICATED"].contains($0) }) { return .authentication }
        if names.contains(where: { ["RATELIMITED", "RATE_LIMITED"].contains($0) }) { return .rateLimited }
        if names.contains("FORBIDDEN") { return .forbidden }
        return .other
    }

    /// Whether the answer carries `data` at all. Linear may answer part of a query and fail the
    /// rest; only an answer with no data is failed for its errors alone.
    static func hasData(_ data: Data?) -> Bool {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["data"] else { return false }
        return !(payload is NSNull)
    }

    /// What an answer means, read from its GraphQL `errors` on any status: Linear refuses a key, or
    /// limits it, with a 400 (or a 200) whose errors say so, not with a 401 or a 429.
    ///
    /// - An authentication error is `.auth(401)`, whatever the status.
    /// - `RATELIMITED`, or a 429, is `.rateLimited`, waiting until `X-RateLimit-Requests-Reset`.
    /// - `FORBIDDEN` is `.rejected(403)`.
    /// - Anything else is the status's own meaning (`HTTPOutcome.classify`).
    static func outcome(_ exchange: HTTPExchange, now: Date) -> HTTPOutcome {
        let kinds = Set(graphQLErrors(exchange.data).map(\.kind))
        if kinds.contains(.authentication) { return .auth(401) }
        if kinds.contains(.rateLimited) || exchange.response?.statusCode == 429 {
            return .rateLimited(retryAfter: rateLimitWait(exchange.response, now: now))
        }
        if kinds.contains(.forbidden) { return .rejected(403) }
        return exchange.outcome
    }

    /// How long a rate limit asks Kannu to wait: `Retry-After` if Linear ever sends one, else until
    /// `X-RateLimit-Requests-Reset`, else `HTTPOutcome.defaultRetryAfter`; always clamped to
    /// `HTTPOutcome.retryAfterRange`. Linear's reset is Unix time in milliseconds: as seconds it
    /// reads like GitLab's `RateLimit-Reset`, so `HTTPOutcome`'s own reading and clamp apply.
    static func rateLimitWait(_ response: HTTPURLResponse?, now: Date) -> TimeInterval {
        let resetSeconds = response?.value(forHTTPHeaderField: rateLimitResetHeader)
            .flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .flatMap { $0.isFinite ? String($0 / 1000) : nil }
        return HTTPOutcome.rateLimitWait(
            retryAfter: response?.value(forHTTPHeaderField: "Retry-After"),
            rateLimitReset: resetSeconds,
            now: now
        )
    }

    /// The first error's message as the user may see it: the key (and anything shaped like a Linear
    /// key or token) replaced, then one line of at most 200 characters (`WorklogDrafts.displayReason`).
    /// Nil when no error had a message.
    static func reason(_ errors: [LinearGraphQLError], redacting apiKey: String) -> String? {
        guard var text = errors.lazy.compactMap(\.message).first else { return nil }
        if !apiKey.isEmpty { text = text.replacingOccurrences(of: apiKey, with: "<redacted>") }
        text = text.replacingOccurrences(of: #"lin_(api|oauth)_[A-Za-z0-9_]+"#, with: "<redacted>", options: .regularExpression)
        return WorklogDrafts.displayReason(text)
    }

    /// One answer, read: its body when it holds data to decode, or why not. An error Kannu has no
    /// meaning for, in an answer with no data (on a 200, or the 400 GraphQL sends for a query it
    /// refuses), is a decode failure carrying Linear's message.
    static func read(_ exchange: HTTPExchange, apiKey: String, now: Date) -> Result<Data, LinearReader.Failure> {
        let outcome = outcome(exchange, now: now)
        switch outcome {
        case .ok:
            guard let data = exchange.data else { return .failure(.decode(nil)) }
            let errors = graphQLErrors(data)
            if !errors.isEmpty && !hasData(data) { return .failure(.decode(reason(errors, redacting: apiKey))) }
            return .success(data)
        case .rejected(400):
            let errors = graphQLErrors(exchange.data)
            return .failure(errors.isEmpty ? .http(outcome) : .decode(reason(errors, redacting: apiKey)))
        default:
            return .failure(.http(outcome))
        }
    }

    /// A body that held data, but not what the query asks for: Linear's message when it sent one.
    static func decodeFailure(_ data: Data, apiKey: String) -> LinearReader.Failure {
        .decode(reason(graphQLErrors(data), redacting: apiKey))
    }

    // MARK: - Tasks

    /// "indeterminate" (In Progress) for a started issue, "done" for a completed or canceled one,
    /// "new" (To Do) for the rest: triage, backlog, unstarted, and a type this version does not know.
    static func statusCategory(stateType: String?) -> String {
        switch stateType {
        case "started": return TaskFacets.inProgressCategory
        case "completed", "canceled": return doneCategory
        default: return TaskFacets.toDoCategory
        }
    }

    /// An issue as a task keeps it. The key is its identifier (`ENG-123`); an issue with no title is
    /// titled by its key. Its page is kept only when it is in `scope`. No estimate: Linear's are
    /// points, not time.
    static func remoteIssue(from issue: LinearIssue, scope: String) -> RemoteIssue {
        let key = TaskItem.cleanedTitle(issue.identifier) ?? issue.id
        let state = issue.state?.value
        let priority = issue.priority?.value.flatMap { $0 > 0 ? issue.priorityLabel?.value.flatMap(TaskItem.cleanedTitle) : nil }
        return RemoteIssue(
            remoteID: issue.id,
            key: key,
            title: TaskItem.cleanedTitle(issue.title ?? "") ?? key,
            status: state?.name.flatMap(TaskItem.cleanedTitle) ?? "",
            isDoneRemotely: state?.type == "completed" || state?.type == "canceled",
            estimateSeconds: nil,
            spentSeconds: nil,
            webURL: issue.url.flatMap { isIssueURL($0, in: scope) ? $0 : nil },
            statusCategory: statusCategory(stateType: state?.type),
            labels: issue.labels?.value.map { TaskFacets.keptLabels($0.names) },
            dueDate: RemoteTaskInfo.dayDate(issue.dueDate?.value),
            parentTitle: issue.parent?.value?.title.flatMap(TaskItem.cleanedTitle),
            priority: priority,
            updatedAt: RemoteTaskInfo.serverTimestamp(issue.updatedAt?.value),
            iteration: cycleName(issue.cycle?.value)
        )
    }

    /// A cycle's name, or "Cycle 12" for one nobody named.
    private static func cycleName(_ cycle: LinearIssue.Cycle?) -> String? {
        if let name = cycle?.name.flatMap(TaskItem.cleanedTitle) { return name }
        guard let number = cycle?.number, number.isFinite, (1...1_000_000).contains(number), number == number.rounded() else {
            return nil
        }
        return String(localized: "Cycle \(Int(number))")
    }
}

/// Reading from Linear over `IntegrationHTTP`: ephemeral, 20 s, no redirects. Read-only: nothing
/// here writes to Linear. Foundation only, so the logic target runs it against a `URLProtocol` stub;
/// the app wraps it with logging.
struct LinearReader {
    enum Failure: Error, Equatable {
        case http(HTTPOutcome)
        /// An answer that was not what the query asks for, or a GraphQL error Kannu has no meaning
        /// for: Linear's own message, cleaned (`LinearAPI.reason`), when it sent one.
        case decode(String?)
    }

    enum VerifyResult: Equatable {
        /// Always with a workspace Kannu would use (`LinearViewer.scope` is not nil).
        case verified(LinearViewer)
        case failed(Failure)
    }

    let session: URLSession

    init(session: URLSession = IntegrationHTTP.shared) {
        self.session = session
    }

    /// Whether Linear accepts this key, whose it is, and its workspace. One request.
    ///
    /// A key that cannot travel in a header never leaves this Mac and fails as Linear would fail it,
    /// `.auth(401)`: the fix is the same, a new key. An organization whose URL key Kannu would not
    /// use fails as an answer it could not read.
    func verify(apiKey: String) async -> VerifyResult {
        guard let request = LinearAPI.viewerRequest(apiKey: apiKey) else { return .failed(.http(.auth(401))) }
        switch await send(request, apiKey: apiKey) {
        case .failure(let failure):
            return .failed(failure)
        case .success(let data):
            guard let viewer = LinearAPI.decodeViewer(data) else { return .failed(LinearAPI.decodeFailure(data, apiKey: apiKey)) }
            guard viewer.scope != nil else { return .failed(.decode(nil)) }
            return .verified(viewer)
        }
    }

    /// The open issues assigned to the key's owner: up to `LinearAPI.maxPages` pages. Complete only
    /// when Linear says there is no next page. Any page that fails fails the whole sync, so a
    /// half-read list never marks the other half gone.
    ///
    /// `failure` is nil with `.failed` when the credential is not one Kannu would send (a workspace
    /// `scope(urlKey:)` would not make, a key that cannot travel in a header): it needs reconnecting,
    /// and no request is made.
    func fetch(_ credential: LinearCredential) async -> (outcome: SyncOutcome, failure: Failure?) {
        guard LinearAPI.isValidScope(credential.workspace) else { return (.failed, nil) }
        var issues: [RemoteIssue] = []
        var cursor: String?
        for page in 1...LinearAPI.maxPages {
            guard let request = LinearAPI.issuesRequest(apiKey: credential.apiKey, after: cursor) else { return (.failed, nil) }
            let data: Data
            switch await send(request, apiKey: credential.apiKey) {
            case .failure(let failure):
                return (.failed, failure)
            case .success(let body):
                data = body
            }
            guard let read = LinearAPI.decodeIssuePage(data) else {
                return (.failed, LinearAPI.decodeFailure(data, apiKey: credential.apiKey))
            }
            issues += read.issues.map { LinearAPI.remoteIssue(from: $0, scope: credential.workspace) }
            guard read.hasNextPage else {
                return (.fetched(RemoteFetch(issues: issues, complete: true)), nil)
            }
            // More pages: past the cap, or with no cursor to ask for the next, the list is incomplete.
            guard page < LinearAPI.maxPages, let next = read.endCursor, LinearAPI.isPlausibleCursor(next) else { break }
            cursor = next
        }
        return (.fetched(RemoteFetch(issues: issues, complete: false)), nil)
    }

    private func send(_ request: URLRequest, apiKey: String) async -> Result<Data, Failure> {
        let exchange = await IntegrationHTTP.send(request, session: session)
        return LinearAPI.read(exchange, apiKey: apiKey, now: Date())
    }
}

// MARK: - Messages

extension LinearAPI {
    /// Where Linear's syncing stands after a fetch that failed (`failure`), or needs reconnecting
    /// (nil), worded as the Linear page says it.
    static func syncState(for failure: LinearReader.Failure?, now: Date) -> SourceSyncState {
        switch failure {
        case .http(.offline):
            return .offline
        case .http(.rateLimited(let seconds)):
            return .rateLimited(until: now.addingTimeInterval(seconds))
        case .http(.auth(let status)):
            return .authFailed(status: status)
        case .http(.rejected(403)):
            return .failed(String(localized: "Linear refused the request (403). The API key may lack read access, or have lost access to the workspace."))
        case .http(.rejected(let status)):
            return .failed(String(localized: "Linear refused the request (\(status))."))
        case .http(.redirected(let status)):
            return .failed(String(localized: "Linear answered with a redirect (\(status)), which Kannu never follows."))
        case .http(.failedBeforeSend):
            return .failed(String(localized: "Kannu could not reach Linear over a trusted HTTPS connection. Check your connection."))
        case .http(.ambiguous(let status?)):
            return .failed(String(localized: "Linear did not answer properly (\(status)). Try again later."))
        case .http(.ambiguous(nil)), .http(.ok):
            return .failed(String(localized: "Linear did not answer in time. Try again later."))
        case .decode(let reason?):
            return .failed(String(localized: "Linear's answer could not be read: \(reason)"))
        case .decode(nil):
            return .failed(String(localized: "Linear's answer could not be read."))
        case nil:
            return .needsReconnect
        }
    }

    /// What Connect tells the user when the check failed.
    static func connectMessage(for failure: LinearReader.Failure) -> String {
        switch failure {
        case .http(.auth(let status)):
            return String(localized: "Linear did not accept that API key (\(status)). Create a new one in Linear, under Security & access.")
        case .http(.rejected(403)):
            return String(localized: "Linear refused that API key (403). Create one with read access in Linear, under Security & access.")
        case .http(.rejected(let status)):
            return String(localized: "Linear refused the request (\(status)).")
        case .http(.redirected(let status)):
            return String(localized: "Linear answered with a redirect (\(status)), which Kannu never follows.")
        case .http(.rateLimited):
            return String(localized: "Linear is limiting requests right now. Try again in a minute.")
        case .http(.offline):
            return String(localized: "This Mac is offline.")
        case .http(.failedBeforeSend):
            return String(localized: "Kannu could not reach Linear over a trusted HTTPS connection. Check your connection.")
        case .http(.ambiguous):
            return String(localized: "Linear did not answer. Try again.")
        case .decode(let reason?):
            return String(localized: "Linear answered, but Kannu could not read it: \(reason)")
        case .decode(nil), .http(.ok):
            return String(localized: "Linear answered, but not in a way Kannu could read. Try again.")
        }
    }

    /// What Connect says, before any request, about a key that cannot travel in a header.
    static var implausibleKeyMessage: String {
        String(localized: "That is not a Linear API key. Copy it again from Linear, under Security & access.")
    }
}
