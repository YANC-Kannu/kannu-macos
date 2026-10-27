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

/// The Todoist sign-in: the account it belongs to and a personal API token. Stored as one JSON item
/// in the Keychain, never in Defaults, so the token and the account it was checked against cannot be
/// separated: a plist edit cannot make Kannu file one account's tasks under another.
///
/// It never prints its token: not in `print`, string interpolation, `dump` or the debugger's
/// summary, so a stray log line cannot leak it.
struct TodoistCredential: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The account's id, as `/user` sent it at Connect. Tasks assigned to anyone else are skipped.
    var userID: String
    var token: String

    var description: String { "TodoistCredential(userID: \(userID), token: <redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["userID": userID]) }

    /// The Keychain form: compact JSON with sorted keys.
    func encoded() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decoded(_ text: String) -> TodoistCredential? {
        try? JSONDecoder().decode(TodoistCredential.self, from: Data(text.utf8))
    }
}

extension TodoistCredential: StoredCredential {}

/// A Todoist id. API v1 sends ids as strings (`"6X7rM8997g3RQmvh"`, `"2671355"`); a number is read
/// as its digits too, so an answer that sends one costs nothing.
struct TodoistID: Decodable, Equatable, Hashable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = text
        } else {
            value = String(try container.decode(Int64.self))
        }
    }
}

/// `GET /user`: whose token it is. Only what Kannu keeps: the id, which scopes the account and tells
/// the user's own tasks from the rest, and the name Brain shows beside it.
struct TodoistUser: Decodable, Equatable {
    let id: String
    let fullName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
    }
}

extension TodoistUser {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(TodoistID.self, forKey: .id).value
        // A name in another shape costs the name, never the check.
        fullName = (try? container.decodeIfPresent(String.self, forKey: .fullName)).flatMap(TaskItem.cleanedTitle)
    }
}

/// One project from `GET /projects`: only what names a task's project.
struct TodoistProject: Decodable, Equatable {
    let id: TodoistID
    let name: LenientField<String>?
    /// Sent as true on the Inbox only.
    let inboxProject: LenientField<Bool>?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case inboxProject = "inbox_project"
    }
}

/// One task from `GET /tasks` or `GET /tasks/filter`. Only the id is required; everything else is
/// read leniently, each on its own: a field in a shape this version does not expect costs that
/// field, never the task (and so never the page).
struct TodoistTask: Decodable, Equatable {
    let id: TodoistID
    let content: LenientField<String>?
    let projectID: LenientField<TodoistID>?
    /// Completed. `/tasks` lists open tasks only, so this is a second guard.
    let checked: LenientField<Bool>?
    let isDeleted: LenientField<Bool>?
    /// Who the task is assigned to in a shared project; null when no one is.
    let responsibleUID: LenientField<TodoistID>?
    /// The label names.
    let labels: LenientField<[String]>?
    /// 4 is the most urgent (P1 in Todoist's apps), 1 is none (P4).
    let priority: LenientField<Int>?
    let due: LenientField<Due>?
    let duration: LenientField<Duration>?
    /// The number of comments.
    let noteCount: LenientField<Int>?
    let updatedAt: LenientField<String>?

    struct Due: Decodable, Equatable {
        /// `2026-10-20`, or `2026-10-20T09:00:00` (and a `Z` for a fixed time zone) for a task with
        /// a time.
        let date: String?
    }

    struct Duration: Decodable, Equatable {
        let amount: Double?
        /// "minute" or "day".
        let unit: String?
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, checked, labels, priority, due, duration
        case projectID = "project_id"
        case isDeleted = "is_deleted"
        case responsibleUID = "responsible_uid"
        case noteCount = "note_count"
        case updatedAt = "updated_at"
    }
}

/// What a page's `next_cursor` said.
enum TodoistNextCursor: Equatable {
    /// `null`: the list ended here.
    case end
    /// More to read, from this cursor.
    case cursor(String)
    /// Missing, or in a shape Todoist does not send: the list may go on, so it is incomplete.
    case unknown
}

/// One page of a Todoist list: `{"results": [...], "next_cursor": "..."}`.
struct TodoistPage<Item: Decodable & Equatable>: Decodable, Equatable {
    typealias Next = TodoistNextCursor

    let results: [Item]
    let next: Next

    private enum CodingKeys: String, CodingKey {
        case results
        case nextCursor = "next_cursor"
    }

    init(results: [Item], next: Next) {
        self.results = results
        self.next = next
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decode([Item].self, forKey: .results)
        if !container.contains(.nextCursor) {
            next = .unknown
        } else if (try? container.decodeNil(forKey: .nextCursor)) == true {
            next = .end
        } else if let cursor = try? container.decode(String.self, forKey: .nextCursor) {
            next = .cursor(cursor)
        } else {
            next = .unknown
        }
    }
}

/// Building Todoist requests and reading their answers. Pure: nothing here sends anything, so the
/// logic target checks every header and URL.
///
/// Todoist's REST API v2 is shut down (every request answers 410 Gone); this is the unified API v1.
/// There is one server, so the token only ever goes to `https://api.todoist.com`, in the
/// `Authorization` header. It is never put in a URL, so it cannot end up in a log, a cache key or a
/// proxy's access log. Every query is built here from Kannu's own values; a URL from an answer is
/// never followed, and a cursor is only ever passed back as a query value.
enum TodoistAPI {
    static let host = "api.todoist.com"
    static let basePath = "/api/v1"
    /// One page: 100, within every limit Todoist documents for these lists (its own tools page tasks
    /// by 100), so a page is never refused for its size.
    static let pageSize = 100
    /// At most two pages per list: two lists, four requests per sync, far below Todoist's limits. A
    /// bigger result is reported as incomplete, never silently cut.
    static let maxPages = 2
    static let scopePrefix = "todoist:"
    /// Where a task opens in the browser or the app.
    static let taskPageBase = "https://app.todoist.com/app/task/"

    // MARK: - Checks

    /// The account scope, `todoist:2671355`, written to `RemoteTaskInfo.hostScope` and the display
    /// copy; nil for an id Kannu would not keep.
    static func scope(userID: String) -> String? {
        isIdentifier(userID) ? scopePrefix + userID : nil
    }

    static func isValidScope(_ scope: String) -> Bool {
        guard scope.hasPrefix(scopePrefix) else { return false }
        return isIdentifier(String(scope.dropFirst(scopePrefix.count)))
    }

    /// An id as Kannu puts it in a scope or a link: letters, digits, `_` and `-`, at most 64.
    static func isIdentifier(_ text: String) -> Bool {
        guard (1...64).contains(text.unicodeScalars.count) else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            (65...90).contains(scalar.value) || (97...122).contains(scalar.value) || (48...57).contains(scalar.value)
                || scalar == "_" || scalar == "-"
        }
    }

    /// A personal API token as it can travel in a header: printable ASCII, no spaces. A line break
    /// would let a pasted value add a header of its own.
    static func isPlausibleToken(_ token: String) -> Bool {
        !token.isEmpty && token.count <= 1024 && token.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value < 0x7F }
    }

    /// A cursor Kannu will pass back: printable ASCII, not absurdly long. Opaque otherwise; it is
    /// percent-encoded into the query, so it cannot change the path or add a parameter.
    static func isUsableCursor(_ cursor: String) -> Bool {
        (1...2048).contains(cursor.unicodeScalars.count) && cursor.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value < 0x7F }
    }

    // MARK: - Requests

    /// `GET /user`. Nil for a token Kannu would not send.
    static func userRequest(token: String) -> URLRequest? {
        request(path: "/user", query: [], token: token)
    }

    /// `GET /projects?limit=100[&cursor=]`: one page of the projects, to name each task's project.
    static func projectsRequest(token: String, cursor: String?) -> URLRequest? {
        listRequest(path: "/projects", query: [], token: token, cursor: cursor)
    }

    /// `GET /tasks?limit=100[&cursor=]`: one page of every open task the account can see.
    static func tasksRequest(token: String, cursor: String?) -> URLRequest? {
        listRequest(path: "/tasks", query: [], token: token, cursor: cursor)
    }

    /// `GET /tasks/filter?query=<filter>&limit=100[&cursor=]`: one page of the open tasks a Todoist
    /// filter query matches ("today | overdue", "#Work & p1"). Nil for an empty query.
    static func filterRequest(token: String, query: String, cursor: String?) -> URLRequest? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return listRequest(path: "/tasks/filter", query: [("query", trimmed)], token: token, cursor: cursor)
    }

    private static func listRequest(path: String, query: [(String, String)], token: String, cursor: String?) -> URLRequest? {
        var items = query + [("limit", String(pageSize))]
        if let cursor {
            guard isUsableCursor(cursor) else { return nil }
            items.append(("cursor", cursor))
        }
        return request(path: path, query: items, token: token)
    }

    private static func request(path: String, query: [(String, String)], token: String) -> URLRequest? {
        guard isPlausibleToken(token) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = basePath + path
        if !query.isEmpty {
            components.percentEncodedQuery = query.map { "\(queryEncoded($0.0))=\(queryEncoded($0.1))" }.joined(separator: "&")
        }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: IntegrationHTTP.timeout)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        return request
    }

    /// RFC 3986's unreserved characters stay; everything else is percent-encoded. Stricter than
    /// `URLQueryItem`, which leaves `+` alone: a server reads that as a space, and `+` belongs in
    /// some filters.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func queryEncoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// What an answer means for Todoist. `HTTPOutcome` already reads 401 as a refused token and 429
    /// as a rate limit. Todoist also answers 403 on these account-wide reads when the token is well
    /// formed but not valid for the account (revoked, or an app token without access): sending it
    /// again changes nothing, so it is a refused token too, and the page never resends it on its own.
    static func normalized(_ outcome: HTTPOutcome) -> HTTPOutcome {
        if case .rejected(403) = outcome { return .auth(403) }
        return outcome
    }

    // MARK: - Answers

    static func decodeUser(_ data: Data) -> TodoistUser? {
        try? JSONDecoder().decode(TodoistUser.self, from: data)
    }

    static func decodeProjects(_ data: Data) -> TodoistPage<TodoistProject>? {
        try? JSONDecoder().decode(TodoistPage<TodoistProject>.self, from: data)
    }

    static func decodeTasks(_ data: Data) -> TodoistPage<TodoistTask>? {
        try? JSONDecoder().decode(TodoistPage<TodoistTask>.self, from: data)
    }

    enum PageStep: Equatable {
        /// Fetch the next page from this cursor.
        case next(String)
        /// No more pages. `complete` is false when Todoist did not say so plainly, or Kannu has
        /// fetched all it will.
        case done(complete: Bool)
    }

    /// What `next_cursor` says after `pagesFetched` pages, the last one asked for with `previous`.
    /// Null is the end. A cursor Kannu would not send, or the same one again, is not trusted: the list
    /// is incomplete, so nothing is marked gone. A cursor after `maxPages` is the cap.
    static func nextStep(_ next: TodoistNextCursor, previous: String?, pagesFetched: Int) -> PageStep {
        switch next {
        case .end:
            return .done(complete: true)
        case .unknown:
            return .done(complete: false)
        case .cursor(let cursor):
            guard isUsableCursor(cursor), cursor != previous, pagesFetched < maxPages else { return .done(complete: false) }
            return .next(cursor)
        }
    }

    /// Project id to name. The Inbox is "Inbox" when Todoist sends it without a name; a project with
    /// no name is left out.
    static func projectNames(_ projects: [TodoistProject]) -> [String: String] {
        var names: [String: String] = [:]
        for project in projects where names[project.id.value] == nil {
            if let name = project.name?.value.flatMap(TaskItem.cleanedTitle) {
                names[project.id.value] = name
            } else if project.inboxProject?.value == true {
                names[project.id.value] = String(localized: "Inbox")
            }
        }
        return names
    }

    /// The task's key, which for Todoist is its project (`TaskSource.KeyStyle.list`): the project's
    /// name; its id when the projects read did not include it (more than two pages of them); the
    /// source's name when the task names no project at all.
    static func projectKey(projectID: String?, names: [String: String]) -> String {
        if let projectID, let name = names[projectID] { return name }
        if let projectID, isIdentifier(projectID) { return projectID }
        return TaskSource.todoist.name
    }

    /// Whether the task is someone else's: assigned, in a shared project, to another person.
    /// Unassigned tasks are the user's.
    static func isAssignedToSomeoneElse(_ task: TodoistTask, userID: String) -> Bool {
        guard let responsible = task.responsibleUID?.value?.value, !responsible.isEmpty else { return false }
        return responsible != userID
    }

    /// The tasks a sync keeps: open, not deleted, not assigned to someone else, with an id.
    static func remoteIssues(from tasks: [TodoistTask], projectNames names: [String: String], userID: String) -> [RemoteIssue] {
        tasks.compactMap { task in
            guard task.checked?.value != true, task.isDeleted?.value != true,
                  !isAssignedToSomeoneElse(task, userID: userID) else { return nil }
            return remoteIssue(from: task, projectNames: names)
        }
    }

    /// A task as Kannu keeps it; nil for one without an id. Todoist has no status of its own beyond
    /// done, so the category comes from the labels ("In progress", "doing").
    static func remoteIssue(from task: TodoistTask, projectNames names: [String: String]) -> RemoteIssue? {
        let id = task.id.value
        guard !id.isEmpty else { return nil }
        let key = projectKey(projectID: task.projectID?.value?.value, names: names)
        let labels = (task.labels?.value).map(TaskFacets.keptLabels)
        return RemoteIssue(
            remoteID: id,
            key: key,
            title: TaskItem.cleanedTitle(task.content?.value ?? "") ?? key,
            status: "",
            isDoneRemotely: task.checked?.value == true,
            estimateSeconds: estimateSeconds(task.duration?.value),
            spentSeconds: nil,
            webURL: webURL(taskID: id),
            statusCategory: TaskFacets.labelCategory(labels ?? []),
            labels: labels,
            dueDate: dueDate(task.due?.value),
            priority: priorityName(task.priority?.value),
            updatedAt: RemoteTaskInfo.serverTimestamp(task.updatedAt?.value),
            commentCount: (task.noteCount?.value).flatMap { $0 >= 0 ? $0 : nil }
        )
    }

    /// Todoist's API counts priority backwards from its apps: 4 is P1, the most urgent. 1 is the
    /// default, "no priority", and shows nothing.
    static func priorityName(_ priority: Int?) -> String? {
        switch priority {
        case 4: return "P1"
        case 3: return "P2"
        case 2: return "P3"
        default: return nil
        }
    }

    /// The due day. A task with a time sends `2026-10-20T09:00:00`; the card shows the day only.
    static func dueDate(_ due: TodoistTask.Due?) -> Date? {
        guard let date = due?.date, date.count >= 10 else { return nil }
        return RemoteTaskInfo.dayDate(String(date.prefix(10)))
    }

    /// A duration as an estimate in seconds: minutes as they are, a day as a working day
    /// (`WorkDuration.hoursPerDay`), as Kannu reads "1d" everywhere. Nil for none, a unit this
    /// version does not know, or more than `WorkDuration.maxSeconds`.
    static func estimateSeconds(_ duration: TodoistTask.Duration?) -> Int? {
        guard let amount = duration?.amount, amount.isFinite, amount > 0 else { return nil }
        let unitSeconds: Double
        switch duration?.unit {
        case "minute": unitSeconds = 60
        case "day": unitSeconds = Double(WorkDuration.hoursPerDay) * 3600
        default: return nil
        }
        let seconds = (amount * unitSeconds).rounded()
        guard seconds >= 1, seconds <= Double(WorkDuration.maxSeconds) else { return nil }
        return Int(seconds)
    }

    /// The task's page, built from its id; only for an id that cannot change the path.
    static func webURL(taskID: String) -> String? {
        isIdentifier(taskID) ? taskPageBase + taskID : nil
    }

    // MARK: - What a failure says

    /// The state a failed sync leaves Todoist in, for its row in Brain and the notch's caption.
    static func syncState(for failure: TodoistReader.Failure?, now: Date) -> SourceSyncState {
        switch failure {
        case .http(.offline):
            return .offline
        case .http(.rateLimited(let seconds)):
            return .rateLimited(until: now.addingTimeInterval(seconds))
        case .http(.auth(let status)):
            return .authFailed(status: status)
        case .http(.rejected(410)):
            return .failed(String(localized: "Todoist retired this API. Update Kannu."))
        case .http(.rejected(400)):
            return .failed(String(localized: "Todoist did not accept the request (400). If a filter is set, check it in Todoist."))
        case .http(.rejected(let status)):
            return .failed(String(localized: "Todoist refused the request (\(status))."))
        case .http(.redirected(let status)):
            return .failed(String(localized: "Todoist answered with a redirect (\(status)), which Kannu never follows."))
        case .http(.failedBeforeSend):
            return .failed(String(localized: "Kannu could not reach Todoist over a trusted HTTPS connection. Check your connection."))
        case .http(.ambiguous(let status?)):
            return .failed(String(localized: "Todoist did not answer properly (\(status)). Try again later."))
        case .http(.ambiguous(nil)), .http(.ok):
            return .failed(String(localized: "Todoist did not answer in time. Try again later."))
        case .decode:
            return .failed(String(localized: "Todoist's answer could not be read."))
        case .badCredential, nil:
            return .needsReconnect
        }
    }

    /// What Connect tells the user when Todoist did not accept the token.
    static func connectMessage(for failure: TodoistReader.Failure) -> String {
        switch failure {
        case .badCredential:
            return String(localized: "That is not a Todoist API token. Copy it from Todoist, under Integrations › Developer.")
        case .decode, .http(.ok):
            return String(localized: "Todoist answered, but not the way it should. Try again later.")
        case .http(.auth(let status)):
            return String(localized: "Todoist did not accept that token (\(status)). Copy it again from Todoist, under Integrations › Developer.")
        case .http(.rejected(410)):
            return String(localized: "Todoist retired this API. Update Kannu.")
        case .http(.rejected(let status)):
            return String(localized: "Todoist refused the request (\(status)).")
        case .http(.redirected(let status)):
            return String(localized: "Todoist answered with a redirect (\(status)), which Kannu never follows.")
        case .http(.rateLimited):
            return String(localized: "Todoist is limiting requests right now. Try again in a minute.")
        case .http(.offline):
            return String(localized: "This Mac is offline.")
        case .http(.failedBeforeSend):
            return String(localized: "Kannu could not reach Todoist over a trusted HTTPS connection. Check your connection.")
        case .http(.ambiguous):
            return String(localized: "Todoist did not answer. Try again.")
        }
    }
}

/// Reading from Todoist over `IntegrationHTTP`: ephemeral, 20 s, no redirects. Read-only: nothing
/// here writes to Todoist. Foundation only, so the logic target runs it against a `URLProtocol` stub;
/// the app wraps it with logging.
struct TodoistReader {
    enum Failure: Error, Equatable {
        /// The token, or the saved account id, is not one Kannu would send or compare. Nothing was
        /// sent.
        case badCredential
        case http(HTTPOutcome)
        /// A 2xx whose body was not what Todoist sends.
        case decode
    }

    enum VerifyResult: Equatable {
        case verified(TodoistUser)
        case failed(Failure)
    }

    let session: URLSession

    init(session: URLSession = IntegrationHTTP.shared) {
        self.session = session
    }

    /// `GET /user`: whether Todoist accepts this token, and whose it is. An id Kannu could not keep
    /// as a scope fails the check, so nothing is saved under it.
    func verify(token: String) async -> VerifyResult {
        guard let request = TodoistAPI.userRequest(token: token) else { return .failed(.badCredential) }
        let exchange = await IntegrationHTTP.send(request, session: session)
        let outcome = TodoistAPI.normalized(exchange.outcome)
        guard case .ok = outcome else { return .failed(.http(outcome)) }
        guard let data = exchange.data, let user = TodoistAPI.decodeUser(data), TodoistAPI.scope(userID: user.id) != nil else {
            return .failed(.decode)
        }
        return .verified(user)
    }

    /// The user's open tasks: the projects first (up to `TodoistAPI.maxPages` pages), to name each
    /// task's project, then the tasks (as many pages), all of them or those `filter` matches. Tasks
    /// assigned to someone else are skipped. Complete only when both lists ended; any page that
    /// fails fails the whole sync, so a half-read list never marks the other half gone.
    func fetch(_ credential: TodoistCredential, filter: String) async -> (outcome: SyncOutcome, failure: Failure?) {
        guard TodoistAPI.isPlausibleToken(credential.token), TodoistAPI.scope(userID: credential.userID) != nil else {
            return (.failed, .badCredential)
        }
        let projects: (items: [TodoistProject], complete: Bool)
        switch await fetchList(.projects, token: credential.token, decode: TodoistAPI.decodeProjects) {
        case .failure(let failure): return (.failed, failure)
        case .success(let read): projects = read
        }
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let tasks: (items: [TodoistTask], complete: Bool)
        switch await fetchList(query.isEmpty ? .tasks : .filter(query), token: credential.token, decode: TodoistAPI.decodeTasks) {
        case .failure(let failure): return (.failed, failure)
        case .success(let read): tasks = read
        }
        let issues = TodoistAPI.remoteIssues(from: tasks.items, projectNames: TodoistAPI.projectNames(projects.items),
                                             userID: credential.userID)
        return (.fetched(RemoteFetch(issues: issues, complete: projects.complete && tasks.complete)), nil)
    }

    private enum List {
        case projects
        case tasks
        case filter(String)
    }

    private func fetchList<Item: Decodable & Equatable>(
        _ list: List,
        token: String,
        decode: (Data) -> TodoistPage<Item>?
    ) async -> Result<(items: [Item], complete: Bool), Failure> {
        var items: [Item] = []
        var cursor: String?
        var pages = 0
        while true {
            let built: URLRequest?
            switch list {
            case .projects: built = TodoistAPI.projectsRequest(token: token, cursor: cursor)
            case .tasks: built = TodoistAPI.tasksRequest(token: token, cursor: cursor)
            case .filter(let query): built = TodoistAPI.filterRequest(token: token, query: query, cursor: cursor)
            }
            guard let request = built else { return .failure(.badCredential) }
            let exchange = await IntegrationHTTP.send(request, session: session)
            let outcome = TodoistAPI.normalized(exchange.outcome)
            guard case .ok = outcome else { return .failure(.http(outcome)) }
            guard let data = exchange.data, let page = decode(data) else { return .failure(.decode) }
            pages += 1
            items += page.results
            switch TodoistAPI.nextStep(page.next, previous: cursor, pagesFetched: pages) {
            case .next(let value):
                cursor = value
            case .done(let complete):
                return .success((items, complete))
            }
        }
    }
}
