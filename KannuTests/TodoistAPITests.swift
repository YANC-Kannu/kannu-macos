//
//  TodoistAPITests.swift
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

/// Todoist's API v1, from handwritten fixtures shaped like the documented answers (trimmed to the
/// fields Kannu reads, plus a few it ignores): every request's URL and headers, what a task keeps,
/// and a whole sync and Connect through the real `IntegrationHTTP` session against a `URLProtocol`
/// stub. Nothing leaves this Mac and no real token exists.
final class TodoistAPITests: XCTestCase {
    private static let token = "0123456789abcdef-dummy-not-real"
    private static let userID = "2671355"
    private let credential = TodoistCredential(userID: TodoistAPITests.userID, token: TodoistAPITests.token)

    // MARK: - Fixtures

    private static func task(
        _ id: String,
        project: String = "6Jf8VQXxpwv56VQ7",
        content: String = "Task",
        responsible: String = "null",
        checked: Bool = false
    ) -> String {
        """
        {"user_id": "2671355", "id": "\(id)", "project_id": "\(project)", "section_id": null, "parent_id": null,
         "added_by_uid": "2671355", "assigned_by_uid": null, "responsible_uid": \(responsible), "labels": [],
         "deadline": null, "duration": null, "checked": \(checked), "is_deleted": false,
         "added_at": "2026-10-01T09:00:00.000000Z", "completed_at": null, "updated_at": "2026-10-16T09:12:34.567890Z",
         "due": null, "priority": 1, "child_order": 1, "content": "\(content)", "description": "",
         "note_count": 0, "day_order": -1, "is_collapsed": false}
        """
    }

    private static func project(_ id: String, name: String, inbox: Bool = false) -> String {
        #"{"id": "\#(id)", "name": "\#(name)", "color": "charcoal", "parent_id": null, "child_order": 0, "is_shared": false, "is_favorite": false, "is_archived": false, "view_style": "list"\#(inbox ? #", "inbox_project": true"# : "")}"#
    }

    private static func page(_ items: [String], next: String?) -> String {
        let cursor = next.map { "\"\($0)\"" } ?? "null"
        return #"{"results": ["# + items.joined(separator: ",") + #"], "next_cursor": "# + cursor + "}"
    }

    static let fullTask = """
    {
      "user_id": "2671355", "id": "6X7rM8997g3RQmvh", "project_id": "6Jf8VQXxpwv56VQ7",
      "section_id": "3Ty8VQXxpwv28PK3", "parent_id": null, "added_by_uid": "2671355",
      "assigned_by_uid": "2671362", "responsible_uid": "2671355",
      "labels": ["In progress", "bug"],
      "deadline": {"date": "2026-10-31", "lang": "en"},
      "duration": {"amount": 90, "unit": "minute"},
      "checked": false, "is_deleted": false,
      "added_at": "2026-10-01T09:00:00.000000Z", "completed_at": null,
      "updated_at": "2026-10-16T09:12:34.567890Z",
      "due": {"date": "2026-10-20T09:30:00", "timezone": null, "string": "Oct 20 9:30", "lang": "en", "is_recurring": false},
      "priority": 4, "child_order": 1, "content": "Write  the\\nrelease notes", "description": "ignored",
      "note_count": 3, "day_order": -1, "is_collapsed": false
    }
    """

    private func decodedTask(_ json: String) throws -> TodoistTask {
        let page = try XCTUnwrap(TodoistAPI.decodeTasks(Data(Self.page([json], next: nil).utf8)))
        return try XCTUnwrap(page.results.first)
    }

    private let names = ["6Jf8VQXxpwv56VQ7": "Work", "6Jf8VQXxpwv56VQ8": "Inbox"]

    // MARK: - Scope and token

    func testTheAccountScope() {
        XCTAssertEqual(TodoistAPI.scope(userID: "2671355"), "todoist:2671355")
        XCTAssertEqual(TodoistAPI.scope(userID: "6X7rM_89-97g"), "todoist:6X7rM_89-97g")
        for id in ["", "26 71", "a/b", "a:b", "a&b", "dána", "1\n2", String(repeating: "a", count: 65)] {
            XCTAssertNil(TodoistAPI.scope(userID: id), id)
        }
        XCTAssertTrue(TodoistAPI.isValidScope("todoist:2671355"))
        XCTAssertFalse(TodoistAPI.isValidScope("todoist:"))
        XCTAssertFalse(TodoistAPI.isValidScope("todoist:a/b"))
        XCTAssertFalse(TodoistAPI.isValidScope("gitlab:2671355"))
        XCTAssertFalse(TodoistAPI.isValidScope("2671355"))
    }

    func testTheTokenIsCheckedBeforeItIsSent() {
        XCTAssertTrue(TodoistAPI.isPlausibleToken("0123456789abcdef0123456789abcdef01234567"))
        XCTAssertFalse(TodoistAPI.isPlausibleToken(""))
        XCTAssertFalse(TodoistAPI.isPlausibleToken("abc def"))
        XCTAssertFalse(TodoistAPI.isPlausibleToken("abc\r\nX-Evil: 1"), "no header injection")
        XCTAssertFalse(TodoistAPI.isPlausibleToken("abc€"))
        XCTAssertNil(TodoistAPI.userRequest(token: "abc\r\nX-Evil: 1"))
        XCTAssertNil(TodoistAPI.tasksRequest(token: "", cursor: nil))
        XCTAssertNil(TodoistAPI.projectsRequest(token: "abc def", cursor: nil))
        XCTAssertNil(TodoistAPI.filterRequest(token: "abc def", query: "today", cursor: nil))
    }

    // MARK: - Requests

    private func assertTokenOnlyInItsHeader(_ request: URLRequest, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + Self.token, file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json", file: file, line: line)
        XCTAssertEqual(request.allHTTPHeaderFields?.count, 2, "Accept and Authorization only: \(request.allHTTPHeaderFields ?? [:])", file: file, line: line)
        let url = try XCTUnwrap(request.url?.absoluteString, file: file, line: line)
        XCTAssertFalse(url.contains(Self.token), url, file: file, line: line)
        XCTAssertFalse((request.url?.query ?? "").contains("token"), url, file: file, line: line)
        XCTAssertEqual(request.url?.host, "api.todoist.com", file: file, line: line)
        XCTAssertEqual(request.url?.scheme, "https", file: file, line: line)
        XCTAssertNil(request.url?.user, file: file, line: line)
        XCTAssertEqual(request.httpMethod, "GET", file: file, line: line)
        XCTAssertNil(request.httpBody, file: file, line: line)
        XCTAssertEqual(request.timeoutInterval, IntegrationHTTP.timeout, file: file, line: line)
        XCTAssertFalse(request.httpShouldHandleCookies, file: file, line: line)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData, file: file, line: line)
    }

    func testTheUserRequest() throws {
        let request = try XCTUnwrap(TodoistAPI.userRequest(token: Self.token))
        XCTAssertEqual(request.url?.absoluteString, "https://api.todoist.com/api/v1/user")
        try assertTokenOnlyInItsHeader(request)
    }

    func testTheListRequests() throws {
        let projects = try XCTUnwrap(TodoistAPI.projectsRequest(token: Self.token, cursor: nil))
        XCTAssertEqual(projects.url?.absoluteString, "https://api.todoist.com/api/v1/projects?limit=100")
        try assertTokenOnlyInItsHeader(projects)

        let tasks = try XCTUnwrap(TodoistAPI.tasksRequest(token: Self.token, cursor: nil))
        XCTAssertEqual(tasks.url?.absoluteString, "https://api.todoist.com/api/v1/tasks?limit=100")
        try assertTokenOnlyInItsHeader(tasks)
    }

    func testACursorIsPassedBackAsAQueryValueOnly() throws {
        let tasks = try XCTUnwrap(TodoistAPI.tasksRequest(token: Self.token, cursor: "eyJwYWdlIjoyfQ=="))
        XCTAssertEqual(tasks.url?.absoluteString, "https://api.todoist.com/api/v1/tasks?limit=100&cursor=eyJwYWdlIjoyfQ%3D%3D")
        try assertTokenOnlyInItsHeader(tasks)

        let sneaky = try XCTUnwrap(TodoistAPI.projectsRequest(token: Self.token, cursor: "a&limit=1/../user#x"))
        XCTAssertEqual(sneaky.url?.path, "/api/v1/projects", "a cursor never changes the path")
        XCTAssertEqual(Self.query(sneaky), ["limit": "100", "cursor": "a&limit=1/../user#x"])

        for cursor in ["", "a b", "a\nb", "ü", String(repeating: "a", count: 2049)] {
            XCTAssertNil(TodoistAPI.tasksRequest(token: Self.token, cursor: cursor), cursor)
        }
    }

    func testTheFilterIsPercentEncoded() throws {
        let filter = try XCTUnwrap(TodoistAPI.filterRequest(token: Self.token, query: " today | #Work & p1 + @c++ ", cursor: nil))
        XCTAssertEqual(filter.url?.absoluteString,
                       "https://api.todoist.com/api/v1/tasks/filter?query=today%20%7C%20%23Work%20%26%20p1%20%2B%20%40c%2B%2B&limit=100",
                       "a + stays a plus, not a space; & and # cannot end the value")
        XCTAssertEqual(Self.query(filter), ["query": "today | #Work & p1 + @c++", "limit": "100"])
        try assertTokenOnlyInItsHeader(filter)

        let next = try XCTUnwrap(TodoistAPI.filterRequest(token: Self.token, query: "überfällig", cursor: "c2"))
        XCTAssertEqual(next.url?.absoluteString, "https://api.todoist.com/api/v1/tasks/filter?query=%C3%BCberf%C3%A4llig&limit=100&cursor=c2")

        XCTAssertNil(TodoistAPI.filterRequest(token: Self.token, query: "", cursor: nil))
        XCTAssertNil(TodoistAPI.filterRequest(token: Self.token, query: "  \n ", cursor: nil), "no filter: the plain task list")
    }

    // MARK: - Answers

    func testTheUser() {
        XCTAssertEqual(TodoistAPI.decodeUser(Data(#"{"id": "2671355", "full_name": "Dana  Smith", "email": "x", "inbox_project_id": "6Jf8"}"#.utf8)),
                       TodoistUser(id: "2671355", fullName: "Dana Smith"))
        XCTAssertEqual(TodoistAPI.decodeUser(Data(#"{"id": 2671355, "full_name": "Dana"}"#.utf8)),
                       TodoistUser(id: "2671355", fullName: "Dana"), "an id sent as a number reads as its digits")
        XCTAssertEqual(TodoistAPI.decodeUser(Data(#"{"id": "2671355"}"#.utf8)), TodoistUser(id: "2671355", fullName: nil))
        XCTAssertEqual(TodoistAPI.decodeUser(Data(#"{"id": "2671355", "full_name": 7}"#.utf8)),
                       TodoistUser(id: "2671355", fullName: nil), "a name in another shape costs the name only")
        XCTAssertNil(TodoistAPI.decodeUser(Data(#"{"full_name": "Dana"}"#.utf8)), "no id: not Todoist")
        XCTAssertNil(TodoistAPI.decodeUser(Data(#"{"id": {"x": 1}}"#.utf8)))
        XCTAssertNil(TodoistAPI.decodeUser(Data("<html>".utf8)))
    }

    func testATasksPage() throws {
        let json = Self.page([Self.fullTask, Self.task("6X7rM8997g3RQmvi")], next: "c2")
        let page = try XCTUnwrap(TodoistAPI.decodeTasks(Data(json.utf8)))
        XCTAssertEqual(page.results.map(\.id.value), ["6X7rM8997g3RQmvh", "6X7rM8997g3RQmvi"])
        XCTAssertEqual(page.next, .cursor("c2"))
        let task = page.results[0]
        XCTAssertEqual(task.projectID?.value, TodoistID("6Jf8VQXxpwv56VQ7"))
        XCTAssertEqual(task.responsibleUID?.value, TodoistID("2671355"))
        XCTAssertEqual(task.checked?.value, false)
        XCTAssertEqual(task.priority?.value, 4)
        XCTAssertEqual(task.labels?.value, ["In progress", "bug"])
        XCTAssertEqual(task.duration?.value, TodoistTask.Duration(amount: 90, unit: "minute"))
        XCTAssertEqual(task.due?.value?.date, "2026-10-20T09:30:00")
        XCTAssertEqual(task.noteCount?.value, 3)
        XCTAssertNil(page.results[1].responsibleUID?.value, "null: no one is assigned")
    }

    func testTheEndOfAList() throws {
        XCTAssertEqual(TodoistAPI.decodeTasks(Data(#"{"results": [], "next_cursor": null}"#.utf8))?.next, .end)
        XCTAssertEqual(TodoistAPI.decodeTasks(Data(#"{"results": []}"#.utf8))?.next, .unknown, "not said plainly")
        XCTAssertEqual(TodoistAPI.decodeTasks(Data(#"{"results": [], "next_cursor": 7}"#.utf8))?.next, .unknown)
    }

    func testAnswersThatAreNotAPage() {
        XCTAssertNil(TodoistAPI.decodeTasks(Data(#"[{"id": "1"}]"#.utf8)), "REST v2's bare array")
        XCTAssertNil(TodoistAPI.decodeTasks(Data(#"{"error": "This endpoint is deprecated"}"#.utf8)))
        XCTAssertNil(TodoistAPI.decodeTasks(Data(#"{"results": [{"content": "no id"}], "next_cursor": null}"#.utf8)), "no id: not Todoist")
        XCTAssertNil(TodoistAPI.decodeTasks(Data("<html>".utf8)))
        XCTAssertNil(TodoistAPI.decodeProjects(Data(#"{"results": {}, "next_cursor": null}"#.utf8)))
    }

    func testOddFieldsCostOnlyThemselves() throws {
        let odd = try decodedTask(#"{"id": 42, "project_id": 7, "labels": "bug", "priority": "high", "due": "tomorrow", "duration": 15, "note_count": "three", "checked": "no", "content": null}"#)
        XCTAssertEqual(odd.id.value, "42")
        XCTAssertEqual(odd.projectID?.value?.value, "7")
        let issue = try XCTUnwrap(TodoistAPI.remoteIssue(from: odd, projectNames: [:]))
        XCTAssertNil(issue.labels)
        XCTAssertNil(issue.priority)
        XCTAssertNil(issue.dueDate)
        XCTAssertNil(issue.estimateSeconds)
        XCTAssertNil(issue.commentCount)
        XCTAssertEqual(issue.key, "7", "a project Kannu did not read: its id")
        XCTAssertEqual(issue.title, "7", "no content: the key")
    }

    func testAProjectsPage() throws {
        let json = Self.page([
            Self.project("6Jf8VQXxpwv56VQ7", name: "Work"),
            Self.project("6Jf8VQXxpwv56VQ8", name: "", inbox: true),
            Self.project("6Jf8VQXxpwv56VQ9", name: "  "),
            Self.project("6Jf8VQXxpwv56VQA", name: "Groceries  list"),
        ], next: nil)
        let page = try XCTUnwrap(TodoistAPI.decodeProjects(Data(json.utf8)))
        XCTAssertEqual(page.next, .end)
        XCTAssertEqual(page.results.count, 4)
        XCTAssertEqual(page.results[1].inboxProject?.value, true)
        XCTAssertNil(page.results[0].inboxProject, "sent on the Inbox only")
        XCTAssertEqual(TodoistAPI.projectNames(page.results), [
            "6Jf8VQXxpwv56VQ7": "Work",
            "6Jf8VQXxpwv56VQ8": "Inbox",
            "6Jf8VQXxpwv56VQA": "Groceries list",
        ], "a nameless project is left out, except the Inbox")
    }

    // MARK: - A task as Kannu keeps it

    func testATaskAsATask() throws {
        let issue = try XCTUnwrap(TodoistAPI.remoteIssue(from: try decodedTask(Self.fullTask), projectNames: names))
        XCTAssertEqual(issue.remoteID, "6X7rM8997g3RQmvh")
        XCTAssertEqual(issue.key, "Work", "Todoist has no keys: the key is the project")
        XCTAssertEqual(issue.title, "Write the release notes", "one clean line")
        XCTAssertEqual(issue.status, "")
        XCTAssertFalse(issue.isDoneRemotely)
        XCTAssertNil(issue.gitlab)
        XCTAssertEqual(issue.webURL, "https://app.todoist.com/app/task/6X7rM8997g3RQmvh")
        XCTAssertEqual(issue.labels, ["In progress", "bug"])
        XCTAssertEqual(issue.statusCategory, TaskFacets.inProgressCategory, "a label says it is in progress")
        XCTAssertEqual(issue.priority, "P1", "the API's 4 is the apps' P1")
        XCTAssertEqual(issue.dueDate, RemoteTaskInfo.dayDate("2026-10-20"), "the day, without the time")
        XCTAssertEqual(issue.estimateSeconds, 90 * 60)
        XCTAssertNil(issue.spentSeconds)
        XCTAssertEqual(issue.commentCount, 3)
        XCTAssertEqual(issue.updatedAt, RemoteTaskInfo.serverTimestamp("2026-10-16T09:12:34.567890Z"))
        XCTAssertNotNil(issue.updatedAt)
        XCTAssertNil(issue.assignee)
        XCTAssertNil(issue.weight)
    }

    func testAPlainTask() throws {
        let issue = try XCTUnwrap(TodoistAPI.remoteIssue(from: try decodedTask(Self.task("abc", content: "")), projectNames: names))
        XCTAssertEqual(issue.statusCategory, TaskFacets.toDoCategory)
        XCTAssertEqual(issue.labels, [])
        XCTAssertNil(issue.priority, "1 is no priority")
        XCTAssertNil(issue.dueDate)
        XCTAssertNil(issue.estimateSeconds)
        XCTAssertEqual(issue.commentCount, 0)
        XCTAssertEqual(issue.title, "Work", "no content: the key")
    }

    func testPriorities() {
        XCTAssertEqual(TodoistAPI.priorityName(4), "P1")
        XCTAssertEqual(TodoistAPI.priorityName(3), "P2")
        XCTAssertEqual(TodoistAPI.priorityName(2), "P3")
        XCTAssertNil(TodoistAPI.priorityName(1))
        XCTAssertNil(TodoistAPI.priorityName(0))
        XCTAssertNil(TodoistAPI.priorityName(5))
        XCTAssertNil(TodoistAPI.priorityName(nil))
    }

    func testDueDates() {
        XCTAssertEqual(TodoistAPI.dueDate(TodoistTask.Due(date: "2026-10-20")), RemoteTaskInfo.dayDate("2026-10-20"))
        XCTAssertEqual(TodoistAPI.dueDate(TodoistTask.Due(date: "2026-10-20T09:30:00Z")), RemoteTaskInfo.dayDate("2026-10-20"))
        XCTAssertNotNil(TodoistAPI.dueDate(TodoistTask.Due(date: "2026-10-20")))
        XCTAssertNil(TodoistAPI.dueDate(TodoistTask.Due(date: "tomorrow")))
        XCTAssertNil(TodoistAPI.dueDate(TodoistTask.Due(date: "2026-1")))
        XCTAssertNil(TodoistAPI.dueDate(TodoistTask.Due(date: nil)))
        XCTAssertNil(TodoistAPI.dueDate(nil))
    }

    func testDurationsAsEstimates() {
        XCTAssertEqual(TodoistAPI.estimateSeconds(.init(amount: 15, unit: "minute")), 900)
        XCTAssertEqual(TodoistAPI.estimateSeconds(.init(amount: 2, unit: "day")), 2 * WorkDuration.hoursPerDay * 3600, "a day is a working day")
        XCTAssertEqual(TodoistAPI.estimateSeconds(.init(amount: 1, unit: "day")), 8 * 3600)
        XCTAssertNil(TodoistAPI.estimateSeconds(.init(amount: 0, unit: "minute")))
        XCTAssertNil(TodoistAPI.estimateSeconds(.init(amount: -5, unit: "minute")))
        XCTAssertNil(TodoistAPI.estimateSeconds(.init(amount: 15, unit: "hour")), "a unit this version does not know")
        XCTAssertNil(TodoistAPI.estimateSeconds(.init(amount: 15, unit: nil)))
        XCTAssertNil(TodoistAPI.estimateSeconds(.init(amount: 1e300, unit: "day")), "never an overflow")
        XCTAssertNil(TodoistAPI.estimateSeconds(nil))
    }

    func testTheTaskPageIsBuiltFromASafeIDOnly() {
        XCTAssertEqual(TodoistAPI.webURL(taskID: "6X7rM8997g3RQmvh"), "https://app.todoist.com/app/task/6X7rM8997g3RQmvh")
        XCTAssertEqual(TodoistAPI.webURL(taskID: "2995104339"), "https://app.todoist.com/app/task/2995104339")
        for id in ["", "../../evil", "a?b", "a#b", "a b", "a.b"] {
            XCTAssertNil(TodoistAPI.webURL(taskID: id), id)
        }
    }

    func testTheProjectKey() {
        XCTAssertEqual(TodoistAPI.projectKey(projectID: "6Jf8VQXxpwv56VQ8", names: names), "Inbox")
        XCTAssertEqual(TodoistAPI.projectKey(projectID: "6Jf8VQXxpwv56VQZ", names: names), "6Jf8VQXxpwv56VQZ", "not read: its id")
        XCTAssertEqual(TodoistAPI.projectKey(projectID: "a/b", names: names), "Todoist")
        XCTAssertEqual(TodoistAPI.projectKey(projectID: nil, names: names), "Todoist")
    }

    func testSomeoneElsesTaskIsSkipped() throws {
        let tasks = try [
            decodedTask(Self.task("mine-unassigned")),
            decodedTask(Self.task("mine-assigned", responsible: #""2671355""#)),
            decodedTask(Self.task("mine-as-number", responsible: "2671355")),
            decodedTask(Self.task("theirs", responsible: #""9999999""#)),
            decodedTask(Self.task("done", checked: true)),
            decodedTask(#"{"id": "deleted", "is_deleted": true}"#),
        ]
        let issues = TodoistAPI.remoteIssues(from: tasks, projectNames: names, userID: Self.userID)
        XCTAssertEqual(issues.map(\.remoteID), ["mine-unassigned", "mine-assigned", "mine-as-number"])
        XCTAssertTrue(TodoistAPI.isAssignedToSomeoneElse(tasks[3], userID: Self.userID))
        XCTAssertFalse(TodoistAPI.isAssignedToSomeoneElse(tasks[0], userID: Self.userID))
    }

    // MARK: - Paging

    func testNextCursor() {
        XCTAssertEqual(TodoistAPI.nextStep(.cursor("c2"), previous: nil, pagesFetched: 1), .next("c2"))
        XCTAssertEqual(TodoistAPI.nextStep(.end, previous: nil, pagesFetched: 1), .done(complete: true))
        XCTAssertEqual(TodoistAPI.nextStep(.end, previous: "c2", pagesFetched: 2), .done(complete: true))
        XCTAssertEqual(TodoistAPI.nextStep(.cursor("c3"), previous: "c2", pagesFetched: 2), .done(complete: false), "the cap: incomplete")
        XCTAssertEqual(TodoistAPI.nextStep(.unknown, previous: nil, pagesFetched: 1), .done(complete: false))
        XCTAssertEqual(TodoistAPI.nextStep(.cursor("c2"), previous: "c2", pagesFetched: 1), .done(complete: false), "never loops")
        XCTAssertEqual(TodoistAPI.nextStep(.cursor("a b"), previous: nil, pagesFetched: 1), .done(complete: false), "not a cursor Kannu sends")
    }

    // MARK: - Credential

    func testTheCredentialNeverPrintsItsToken() {
        var dumped = ""
        dump(credential, to: &dumped)
        for text in ["\(credential)", String(reflecting: credential), String(describing: credential), dumped] {
            XCTAssertFalse(text.contains(Self.token), text)
        }
        XCTAssertTrue("\(credential)".contains(Self.userID), "the account id is not a secret")
    }

    func testTheKeychainFormRoundTrips() throws {
        let encoded = try XCTUnwrap(credential.encoded())
        XCTAssertEqual(encoded, #"{"token":"0123456789abcdef-dummy-not-real","userID":"2671355"}"#)
        XCTAssertEqual(TodoistCredential.decoded(encoded), credential)
        XCTAssertNil(TodoistCredential.decoded("not json"))
        XCTAssertNil(TodoistCredential.decoded(#"{"userID":"2671355"}"#))
    }

    // MARK: - What a failure says

    func testSyncStates() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        XCTAssertEqual(TodoistAPI.syncState(for: .http(.auth(401)), now: now), .authFailed(status: 401))
        XCTAssertEqual(TodoistAPI.syncState(for: .http(.auth(403)), now: now), .authFailed(status: 403))
        XCTAssertEqual(TodoistAPI.syncState(for: .http(.rejected(410)), now: now), .failed("Todoist retired this API. Update Kannu."))
        XCTAssertEqual(TodoistAPI.syncState(for: .http(.rateLimited(retryAfter: 30)), now: now), .rateLimited(until: now.addingTimeInterval(30)))
        XCTAssertEqual(TodoistAPI.syncState(for: .http(.offline), now: now), .offline)
        XCTAssertEqual(TodoistAPI.syncState(for: .decode, now: now), .failed("Todoist's answer could not be read."))
        XCTAssertEqual(TodoistAPI.syncState(for: .badCredential, now: now), .needsReconnect)
        XCTAssertEqual(TodoistAPI.syncState(for: nil, now: now), .needsReconnect)
        XCTAssertEqual(TodoistAPI.connectMessage(for: .http(.rejected(410))), "Todoist retired this API. Update Kannu.")
        XCTAssertTrue(TodoistAPI.connectMessage(for: .http(.auth(401))).contains("401"))
    }

    // MARK: - Reader

    struct Answer {
        var status = 200
        var headers: [String: String] = [:]
        var body = #"{"results": [], "next_cursor": null}"#
        /// The request fails with this instead of answering: offline, a timeout.
        var error: URLError.Code?
    }

    final class StubProtocol: URLProtocol {
        private static let lock = NSLock()
        private static var recorded: [URLRequest] = []
        private static var answer: (URLRequest) -> Answer = { _ in Answer() }

        static func reset(_ answer: @escaping (URLRequest) -> Answer) {
            lock.lock()
            recorded = []
            self.answer = answer
            lock.unlock()
        }

        static func requests() -> [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            Self.recorded.append(request)
            let answer = Self.answer(request)
            Self.lock.unlock()
            guard let client, let url = request.url else { return }
            if let code = answer.error {
                client.urlProtocol(self, didFailWithError: URLError(code))
                return
            }
            var headers = answer.headers
            headers["Content-Type"] = "application/json"
            let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: headers)!
            if (300..<400).contains(answer.status), let location = answer.headers["Location"], let target = URL(string: location) {
                var next = URLRequest(url: target)
                next.allHTTPHeaderFields = request.allHTTPHeaderFields
                client.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            }
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data(answer.body.utf8))
            client.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private var session: URLSession!
    private var reader: TodoistReader!

    override func setUp() {
        super.setUp()
        let configuration = IntegrationHTTP.makeConfiguration(base: .ephemeral)
        configuration.protocolClasses = [StubProtocol.self]
        session = IntegrationHTTP.makeSession(configuration: configuration)
        reader = TodoistReader(session: session)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        reader = nil
        super.tearDown()
    }

    private static func query(_ request: URLRequest) -> [String: String] {
        guard let url = request.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    func testASyncReadsTheProjectsThenTheTasks() async throws {
        StubProtocol.reset { request in
            switch request.url?.path ?? "" {
            case "/api/v1/projects":
                return Answer(body: Self.page([Self.project("6Jf8VQXxpwv56VQ7", name: "Work"),
                                               Self.project("6Jf8VQXxpwv56VQ8", name: "Inbox", inbox: true)], next: nil))
            case "/api/v1/tasks":
                return Answer(body: Self.page([
                    Self.task("t1", project: "6Jf8VQXxpwv56VQ7", content: "Mine"),
                    Self.task("t2", project: "6Jf8VQXxpwv56VQ8", content: "Inbox one"),
                    Self.task("t3", content: "Theirs", responsible: #""9999999""#),
                ], next: nil))
            default:
                return Answer(status: 404, body: "{}")
            }
        }

        let fetch = await reader.fetch(credential, filter: "")

        XCTAssertNil(fetch.failure)
        guard case .fetched(let result) = fetch.outcome else { return XCTFail("\(fetch.outcome)") }
        XCTAssertTrue(result.complete, "both lists said null")
        XCTAssertEqual(result.issues.map(\.remoteID), ["t1", "t2"], "someone else's task is skipped")
        XCTAssertEqual(result.issues.map(\.key), ["Work", "Inbox"])
        let requests = StubProtocol.requests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/v1/projects", "/api/v1/tasks"])
        for request in requests {
            XCTAssertEqual(Self.query(request), ["limit": "100"])
            try assertTokenOnlyInItsHeader(request)
        }
    }

    func testTwoPagesOfEachAndNeverAThird() async throws {
        StubProtocol.reset { request in
            let path = request.url?.path ?? ""
            let cursor = Self.query(request)["cursor"]
            let isProjects = path == "/api/v1/projects"
            let prefix = isProjects ? "p" : "t"
            switch cursor {
            case nil:
                let item = isProjects ? Self.project("p1", name: "One") : Self.task("t1", project: "p1")
                return Answer(body: Self.page([item], next: prefix + "-cursor-2"))
            case prefix + "-cursor-2":
                let item = isProjects ? Self.project("p2", name: "Two") : Self.task("t2", project: "p2")
                return Answer(body: Self.page([item], next: prefix + "-cursor-3"))
            default:
                return Answer(body: Self.page([], next: nil))
            }
        }

        let fetch = await reader.fetch(credential, filter: "")

        guard case .fetched(let result) = fetch.outcome else { return XCTFail("\(fetch.outcome)") }
        XCTAssertFalse(result.complete, "there were more: nothing may be marked gone")
        XCTAssertEqual(result.issues.map(\.remoteID), ["t1", "t2"])
        XCTAssertEqual(result.issues.map(\.key), ["One", "Two"], "both project pages name tasks")
        let requests = StubProtocol.requests()
        XCTAssertEqual(requests.count, 4, "never a third page of either list")
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/v1/projects", "/api/v1/projects", "/api/v1/tasks", "/api/v1/tasks"])
        XCTAssertEqual(requests.map { Self.query($0)["cursor"] }, [nil, "p-cursor-2", nil, "t-cursor-2"], "the cursor goes back as it came")
    }

    func testASecondPageThatEndsIsComplete() async throws {
        StubProtocol.reset { request in
            let cursor = Self.query(request)["cursor"]
            let isProjects = request.url?.path == "/api/v1/projects"
            if cursor == nil {
                return Answer(body: Self.page([isProjects ? Self.project("p1", name: "One") : Self.task("t1", project: "p1")], next: "next"))
            }
            return Answer(body: Self.page([isProjects ? Self.project("p2", name: "Two") : Self.task("t2", project: "p2")], next: nil))
        }
        let fetch = await reader.fetch(credential, filter: "")
        guard case .fetched(let result) = fetch.outcome else { return XCTFail("\(fetch.outcome)") }
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.issues.count, 2)
        XCTAssertEqual(StubProtocol.requests().count, 4)
    }

    func testCappedProjectsMakeTheSyncIncomplete() async throws {
        StubProtocol.reset { request in
            request.url?.path == "/api/v1/projects"
                ? Answer(body: Self.page([Self.project("p1", name: "One")], next: "more-\(Self.query(request)["cursor"] ?? "0")"))
                : Answer(body: Self.page([Self.task("t1", project: "p1")], next: nil))
        }
        let fetch = await reader.fetch(credential, filter: "")
        guard case .fetched(let result) = fetch.outcome else { return XCTFail("\(fetch.outcome)") }
        XCTAssertFalse(result.complete, "complete only when both lists ended")
        XCTAssertEqual(StubProtocol.requests().count, 3)
    }

    func testAFilterReadsTheFilterList() async throws {
        StubProtocol.reset { request in
            request.url?.path == "/api/v1/tasks/filter"
                ? Answer(body: Self.page([Self.task("t1")], next: nil))
                : Answer(body: Self.page([], next: nil))
        }
        let fetch = await reader.fetch(credential, filter: " today | overdue ")
        guard case .fetched(let result) = fetch.outcome else { return XCTFail("\(fetch.outcome)") }
        XCTAssertEqual(result.issues.map(\.remoteID), ["t1"])
        let requests = StubProtocol.requests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/v1/projects", "/api/v1/tasks/filter"])
        XCTAssertEqual(Self.query(requests[1]), ["query": "today | overdue", "limit": "100"])
    }

    func testARefusedTokenFailsTheSync() async throws {
        for status in [401, 403] {
            StubProtocol.reset { _ in Answer(status: status, body: #"{"error": "Unauthorized", "error_code": 477}"#) }
            let fetch = await reader.fetch(credential, filter: "")
            XCTAssertEqual(fetch.outcome, .failed)
            XCTAssertEqual(fetch.failure, .http(.auth(status)), "403 is a refused token too")
            XCTAssertEqual(StubProtocol.requests().count, 1, "nothing more is asked after a failure")
            XCTAssertEqual(TodoistAPI.syncState(for: fetch.failure, now: Date()), .authFailed(status: status))
        }
    }

    func testTheRetiredAPIFailsWithItsOwnMessage() async throws {
        StubProtocol.reset { _ in Answer(status: 410, body: "This endpoint is deprecated.") }
        let fetch = await reader.fetch(credential, filter: "")
        XCTAssertEqual(fetch.outcome, .failed)
        XCTAssertEqual(fetch.failure, .http(.rejected(410)))
        XCTAssertEqual(TodoistAPI.syncState(for: fetch.failure, now: Date()), .failed("Todoist retired this API. Update Kannu."))
    }

    func testAFailedTasksPageFailsTheWholeSync() async throws {
        StubProtocol.reset { request in
            request.url?.path == "/api/v1/projects"
                ? Answer(body: Self.page([Self.project("p1", name: "One")], next: nil))
                : Answer(status: 500, body: "{}")
        }
        let fetch = await reader.fetch(credential, filter: "")
        XCTAssertEqual(fetch.outcome, .failed)
        XCTAssertEqual(fetch.failure, .http(.ambiguous(500)))
    }

    func testARateLimitAndAnUnreadableAnswer() async throws {
        StubProtocol.reset { _ in Answer(status: 429, headers: ["Retry-After": "30"], body: "{}") }
        let limited = await reader.fetch(credential, filter: "")
        XCTAssertEqual(limited.failure, .http(.rateLimited(retryAfter: 30)))

        StubProtocol.reset { _ in Answer(body: #"[{"id": "1"}]"#) }
        let unreadable = await reader.fetch(credential, filter: "")
        XCTAssertEqual(unreadable.outcome, .failed)
        XCTAssertEqual(unreadable.failure, .decode)
    }

    func testABadCredentialSendsNothing() async throws {
        StubProtocol.reset { _ in Answer() }
        let badToken = await reader.fetch(TodoistCredential(userID: Self.userID, token: "abc\r\nX-Evil: 1"), filter: "")
        XCTAssertEqual(badToken.failure, .badCredential)
        let badAccount = await reader.fetch(TodoistCredential(userID: "a/b", token: Self.token), filter: "")
        XCTAssertEqual(badAccount.failure, .badCredential)
        let verify = await reader.verify(token: "abc def")
        XCTAssertEqual(verify, .failed(.badCredential))
        XCTAssertTrue(StubProtocol.requests().isEmpty)
    }

    func testARedirectIsNeverFollowed() async throws {
        StubProtocol.reset { request in
            request.url?.host == "api.todoist.com"
                ? Answer(status: 302, headers: ["Location": "https://evil.example/collect"], body: "")
                : Answer(body: #"{"id": "2671355"}"#)
        }
        let result = await reader.verify(token: Self.token)
        XCTAssertEqual(result, .failed(.http(.redirected(302))))
        XCTAssertEqual(StubProtocol.requests().compactMap(\.url?.host), ["api.todoist.com"])
    }

    // MARK: - Connect

    func testVerify() async throws {
        StubProtocol.reset { _ in Answer(body: #"{"id": "2671355", "full_name": "Dana Smith", "email": "dana@example.com"}"#) }
        let result = await reader.verify(token: Self.token)
        XCTAssertEqual(result, .verified(TodoistUser(id: "2671355", fullName: "Dana Smith")))
        let requests = StubProtocol.requests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/v1/user"])
        try assertTokenOnlyInItsHeader(try XCTUnwrap(requests.first))

        StubProtocol.reset { _ in Answer(body: #"{"id": 2671355}"#) }
        let numeric = await reader.verify(token: Self.token)
        XCTAssertEqual(numeric, .verified(TodoistUser(id: "2671355", fullName: nil)))
    }

    func testVerifyFailures() async throws {
        StubProtocol.reset { _ in Answer(status: 401, body: #"{"error": "Unauthorized"}"#) }
        let refused = await reader.verify(token: Self.token)
        XCTAssertEqual(refused, .failed(.http(.auth(401))))

        StubProtocol.reset { _ in Answer(status: 410, body: "This endpoint is deprecated.") }
        let retired = await reader.verify(token: Self.token)
        XCTAssertEqual(retired, .failed(.http(.rejected(410))))

        StubProtocol.reset { _ in Answer(body: #"{"id": "a/b"}"#) }
        let unscoped = await reader.verify(token: Self.token)
        XCTAssertEqual(unscoped, .failed(.decode), "an id Kannu could not keep as a scope")

        StubProtocol.reset { _ in Answer(error: .notConnectedToInternet) }
        let offline = await reader.verify(token: Self.token)
        XCTAssertEqual(offline, .failed(.http(.offline)))
    }
}
