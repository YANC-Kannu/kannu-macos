//
//  LinearAPITests.swift
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

/// Linear from Kannu's side: the workspace and key checks, every request's headers and body, the
/// answers decoded from handwritten fixtures shaped like Linear's schema, what a task keeps of them,
/// how errors read (Linear refuses and limits with GraphQL errors, often on a 400), and a whole sync
/// and Connect through the real `IntegrationHTTP` session against a `URLProtocol` stub that records
/// every request. Nothing leaves this Mac and the key is a fake.
final class LinearAPITests: XCTestCase {
    private static let key = "lin_api_FAKE"
    private static let workspace = "https://linear.app/acme"
    private let credential = LinearCredential(workspace: LinearAPITests.workspace, apiKey: LinearAPITests.key)

    struct Answer {
        var status = 200
        var headers: [String: String] = [:]
        var body = "{}"
        /// The request fails with this instead of answering: offline, a timeout.
        var error: URLError.Code?
    }

    final class StubProtocol: URLProtocol {
        private static let lock = NSLock()
        private static var recorded: [(request: URLRequest, body: Data)] = []
        private static var answer: (URLRequest, Data) -> Answer = { _, _ in Answer() }

        static func reset(_ answer: @escaping (URLRequest, Data) -> Answer) {
            lock.lock()
            recorded = []
            self.answer = answer
            lock.unlock()
        }

        static func requests() -> [(request: URLRequest, body: Data)] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        /// A POST's body reaches a `URLProtocol` as a stream; read it once, here.
        private static func bodyData(_ request: URLRequest) -> Data {
            if let body = request.httpBody { return body }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            return data
        }

        override func startLoading() {
            let body = Self.bodyData(request)
            Self.lock.lock()
            Self.recorded.append((request, body))
            let answer = Self.answer(request, body)
            Self.lock.unlock()
            guard let client, let url = request.url else { return }
            if let code = answer.error {
                client.urlProtocol(self, didFailWithError: URLError(code))
                return
            }
            var headers = answer.headers
            headers["Content-Type"] = "application/json"
            let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data(answer.body.utf8))
            client.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private var session: URLSession!
    private var reader: LinearReader!

    override func setUp() {
        super.setUp()
        let configuration = IntegrationHTTP.makeConfiguration(base: .ephemeral)
        configuration.protocolClasses = [StubProtocol.self]
        session = IntegrationHTTP.makeSession(configuration: configuration)
        reader = LinearReader(session: session)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        reader = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private static let viewerJSON = #"{"data":{"viewer":{"id":"user-1","name":"Dana Example","displayName":"dana"},"organization":{"urlKey":"acme","name":"Acme Inc"}}}"#

    /// Trimmed to the fields Kannu asks for, shaped like Linear's schema.
    private static let issuesPage = #"""
    {
      "data": {
        "viewer": {
          "assignedIssues": {
            "nodes": [
              {
                "id": "3f2a9c1e-0b7d-4e5f-9a1b-2c3d4e5f6a7b",
                "identifier": "ENG-123",
                "title": "Login  redirect\nloops",
                "url": "https://linear.app/acme/issue/ENG-123/login-redirect-loops",
                "priority": 2,
                "priorityLabel": "High",
                "dueDate": "2026-10-20",
                "updatedAt": "2026-10-16T09:12:34.567Z",
                "state": {"name": "In Progress", "type": "started"},
                "parent": {"title": "Auth  revamp"},
                "cycle": {"number": 12, "name": null},
                "labels": {"nodes": [{"name": "Bug"}, {"name": "Frontend"}]}
              },
              {
                "id": "8c7b6a5d-4e3f-4a2b-8c1d-0e9f8a7b6c5d",
                "identifier": "OPS-7",
                "title": "Rotate certificates",
                "url": "https://linear.app/other/issue/OPS-7/rotate-certificates",
                "priority": 0,
                "priorityLabel": "No priority",
                "dueDate": null,
                "updatedAt": "2026-10-15T08:00:00.000Z",
                "state": {"name": "Todo", "type": "unstarted"},
                "parent": null,
                "cycle": {"number": 3, "name": "Sprint 7"},
                "labels": {"nodes": []}
              }
            ],
            "pageInfo": {"hasNextPage": false, "endCursor": "8c7b6a5d-4e3f-4a2b-8c1d-0e9f8a7b6c5d"}
          }
        }
      }
    }
    """#

    private static func issue(_ number: Int) -> String {
        #"{"id":"issue-\#(number)","identifier":"ENG-\#(number)","title":"Issue \#(number)","url":"https://linear.app/acme/issue/ENG-\#(number)/issue","priority":0,"priorityLabel":"No priority","dueDate":null,"updatedAt":"2026-10-16T09:12:34.567Z","state":{"name":"Todo","type":"unstarted"},"parent":null,"cycle":null,"labels":{"nodes":[]}}"#
    }

    private static func page(_ issues: [String], hasNextPage: Bool, endCursor: String?) -> String {
        let cursor = endCursor.map { "\"\($0)\"" } ?? "null"
        return #"{"data":{"viewer":{"assignedIssues":{"nodes":["# + issues.joined(separator: ",")
            + #"],"pageInfo":{"hasNextPage":\#(hasNextPage),"endCursor":\#(cursor)}}}}}"#
    }

    private static func json(_ body: Data) -> [String: Any] {
        ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any]) ?? [:]
    }

    private static func variables(_ body: Data) -> [String: String] {
        (json(body)["variables"] as? [String: String]) ?? [:]
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// An answer as `IntegrationHTTP.send` hands it over.
    private static func exchange(status: Int, headers: [String: String] = [:], body: String) -> HTTPExchange {
        HTTPExchange(
            outcome: HTTPOutcome.classify(status: status, retryAfter: headers["Retry-After"], now: now),
            data: Data(body.utf8),
            response: HTTPURLResponse(url: LinearAPI.endpoint, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        )
    }

    private static let authError = #"{"errors":[{"message":"Authentication required, not authenticated","extensions":{"type":"authentication error","code":"AUTHENTICATION_ERROR","userError":true}}]}"#
    private static let rateLimitError = #"{"errors":[{"message":"Rate limit exceeded","extensions":{"code":"RATELIMITED"}}]}"#
    private static let forbiddenError = #"{"errors":[{"message":"Forbidden","extensions":{"code":"FORBIDDEN"}}],"data":null}"#

    // MARK: - Checks

    func testTheWorkspaceIsItsLinearLink() {
        XCTAssertEqual(LinearAPI.scope(urlKey: "acme"), "https://linear.app/acme")
        XCTAssertEqual(LinearAPI.scope(urlKey: "acme-2"), "https://linear.app/acme-2")
        XCTAssertEqual(LinearAPI.scope(urlKey: String(repeating: "a", count: 64)), "https://linear.app/" + String(repeating: "a", count: 64))
        for bad in ["", "Acme", "acme corp", "acme/evil", "acme.evil", "acme?x=1", "acmé", String(repeating: "a", count: 65)] {
            XCTAssertNil(LinearAPI.scope(urlKey: bad), bad)
        }

        XCTAssertTrue(LinearAPI.isValidScope("https://linear.app/acme"))
        for bad in ["http://linear.app/acme", "https://linear.app/acme/", "https://linear.app/", "https://linear.app.evil.example/acme",
                    "https://linear.app/Acme", "https://linear.app/acme/issue", "linear.app/acme", ""] {
            XCTAssertFalse(LinearAPI.isValidScope(bad), bad)
        }
    }

    func testTheKeyMustBeAbleToTravelInAHeader() {
        XCTAssertTrue(LinearAPI.isPlausibleKey(Self.key))
        XCTAssertTrue(LinearAPI.isPlausibleKey(String(repeating: "k", count: 200)))
        for bad in ["", "lin_api FAKE", "lin_api_FAKE\n", " lin_api_FAKE", "lin_api_FAKÉ", String(repeating: "k", count: 201)] {
            XCTAssertFalse(LinearAPI.isPlausibleKey(bad), bad)
        }
    }

    func testOnlyIssuePagesInTheWorkspaceAreKept() {
        XCTAssertTrue(LinearAPI.isIssueURL("https://linear.app/acme/issue/ENG-1/title", in: Self.workspace))
        for bad in ["https://linear.app/other/issue/ENG-1/title", "https://linear.app/acme-evil/issue/ENG-1",
                    "https://linear.app/acme/settings", "http://linear.app/acme/issue/ENG-1", "https://linear.app.evil.example/acme/issue/ENG-1",
                    "https://linear.app/acme/issue/ENG 1"] {
            XCTAssertFalse(LinearAPI.isIssueURL(bad, in: Self.workspace), bad)
        }
        XCTAssertFalse(LinearAPI.isIssueURL("https://linear.app/acme/issue/ENG-1", in: "https://linear.app/acme/"), "a scope Kannu would not make keeps nothing")
    }

    // MARK: - Requests

    func testTheRequestCarriesTheRawKeyOnlyInItsHeader() throws {
        let request = try XCTUnwrap(LinearAPI.viewerRequest(apiKey: Self.key))
        XCTAssertEqual(request.url, URL(string: "https://api.linear.app/graphql"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), Self.key, "a personal API key is sent raw, never as Bearer")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.timeoutInterval, IntegrationHTTP.timeout)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.allHTTPHeaderFields?.count, 3, "nothing else")

        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(body, #"{"query":"query { viewer { id name displayName } organization { urlKey name } }","variables":{}}"#)
        XCTAssertFalse(body.contains(Self.key))
        XCTAssertFalse(request.url?.absoluteString.contains(Self.key) ?? true)
    }

    func testTheIssuesRequestPagesByCursorInItsVariables() throws {
        let first = try XCTUnwrap(LinearAPI.issuesRequest(apiKey: Self.key, after: nil))
        let firstBody = Self.json(try XCTUnwrap(first.httpBody))
        XCTAssertEqual(firstBody["query"] as? String, LinearAPI.assignedIssuesQuery)
        XCTAssertEqual(firstBody["variables"] as? [String: String], [:], "no cursor: GraphQL reads the missing variable as null")

        let second = try XCTUnwrap(LinearAPI.issuesRequest(apiKey: Self.key, after: #"cursor" } evil"#))
        let secondBody = Self.json(try XCTUnwrap(second.httpBody))
        XCTAssertEqual(secondBody["query"] as? String, LinearAPI.assignedIssuesQuery, "a value from an answer never enters the query text")
        XCTAssertEqual(secondBody["variables"] as? [String: String], ["after": #"cursor" } evil"#])

        let query = LinearAPI.assignedIssuesQuery
        for part in ["assignedIssues(first: 100, after: $after, orderBy: updatedAt", #"nin: ["completed", "canceled"]"#,
                     "identifier", "priorityLabel", "dueDate", "cycle { number name }", "labels(first: 20)", "pageInfo { hasNextPage endCursor }"] {
            XCTAssertTrue(query.contains(part), part)
        }
    }

    func testNoRequestIsBuiltForAKeyThatCannotTravel() {
        XCTAssertNil(LinearAPI.request(apiKey: "lin_api FAKE", query: LinearAPI.viewerQuery))
        XCTAssertNil(LinearAPI.issuesRequest(apiKey: "", after: nil))
    }

    // MARK: - Answers

    func testTheViewerDecodes() throws {
        let viewer = try XCTUnwrap(LinearAPI.decodeViewer(Data(Self.viewerJSON.utf8)))
        XCTAssertEqual(viewer, LinearViewer(id: "user-1", name: "Dana Example", displayName: "dana", organizationURLKey: "acme", organizationName: "Acme Inc"))
        XCTAssertEqual(viewer.scope, Self.workspace)
        XCTAssertNil(LinearAPI.decodeViewer(Data(Self.authError.utf8)))
    }

    func testAnIssuePageDecodes() throws {
        let page = try XCTUnwrap(LinearAPI.decodeIssuePage(Data(Self.issuesPage.utf8)))
        XCTAssertFalse(page.hasNextPage)
        XCTAssertEqual(page.endCursor, "8c7b6a5d-4e3f-4a2b-8c1d-0e9f8a7b6c5d")
        XCTAssertEqual(page.issues.map(\.identifier), ["ENG-123", "OPS-7"])
        XCTAssertEqual(page.issues.first?.labels?.value?.names, ["Bug", "Frontend"])
        XCTAssertNil(LinearAPI.decodeIssuePage(Data(Self.viewerJSON.utf8)))
        XCTAssertNil(LinearAPI.decodeIssuePage(Data(#"{"data":{"viewer":{"assignedIssues":{"nodes":[]}}}}"#.utf8)), "no pageInfo: whether it is complete is unknown")
    }

    func testAStartedIssueIsInProgressWithItsFacts() throws {
        let page = try XCTUnwrap(LinearAPI.decodeIssuePage(Data(Self.issuesPage.utf8)))
        let issue = LinearAPI.remoteIssue(from: page.issues[0], scope: Self.workspace)
        XCTAssertEqual(issue.remoteID, "3f2a9c1e-0b7d-4e5f-9a1b-2c3d4e5f6a7b")
        XCTAssertEqual(issue.key, "ENG-123")
        XCTAssertEqual(issue.title, "Login redirect loops")
        XCTAssertEqual(issue.status, "In Progress")
        XCTAssertEqual(issue.statusCategory, TaskFacets.inProgressCategory)
        XCTAssertFalse(issue.isDoneRemotely)
        XCTAssertEqual(issue.labels, ["Bug", "Frontend"])
        XCTAssertEqual(issue.priority, "High")
        XCTAssertEqual(issue.parentTitle, "Auth revamp")
        XCTAssertEqual(issue.iteration, "Cycle 12", "an unnamed cycle reads by its number")
        XCTAssertEqual(issue.dueDate, RemoteTaskInfo.dayDate("2026-10-20"))
        XCTAssertNotNil(issue.dueDate)
        XCTAssertEqual(issue.updatedAt, RemoteTaskInfo.serverTimestamp("2026-10-16T09:12:34.567Z"))
        XCTAssertNotNil(issue.updatedAt)
        XCTAssertEqual(issue.webURL, "https://linear.app/acme/issue/ENG-123/login-redirect-loops")
        XCTAssertNil(issue.estimateSeconds, "Linear estimates are points, not time")
        XCTAssertNil(issue.spentSeconds)
        XCTAssertNil(issue.gitlab)
    }

    func testATodoIssueAndALinkToAnotherWorkspace() throws {
        let page = try XCTUnwrap(LinearAPI.decodeIssuePage(Data(Self.issuesPage.utf8)))
        let issue = LinearAPI.remoteIssue(from: page.issues[1], scope: Self.workspace)
        XCTAssertEqual(issue.key, "OPS-7")
        XCTAssertEqual(issue.status, "Todo")
        XCTAssertEqual(issue.statusCategory, TaskFacets.toDoCategory)
        XCTAssertNil(issue.priority, "priority 0 is no priority, whatever its label says")
        XCTAssertEqual(issue.iteration, "Sprint 7")
        XCTAssertNil(issue.parentTitle)
        XCTAssertNil(issue.dueDate)
        XCTAssertEqual(issue.labels, [])
        XCTAssertNil(issue.webURL, "a page in another workspace is not kept")
    }

    func testEveryStateTypeHasACategory() {
        XCTAssertEqual(LinearAPI.statusCategory(stateType: "started"), "indeterminate")
        XCTAssertEqual(LinearAPI.statusCategory(stateType: "completed"), "done")
        XCTAssertEqual(LinearAPI.statusCategory(stateType: "canceled"), "done")
        for type in ["triage", "backlog", "unstarted", "something-new", nil] {
            XCTAssertEqual(LinearAPI.statusCategory(stateType: type), "new", String(describing: type))
        }
    }

    func testOddFieldsCostTheFieldNotTheIssue() throws {
        let odd = #"{"data":{"viewer":{"assignedIssues":{"nodes":[{"id":"issue-9","identifier":"ENG-9","title":"  ","priority":"high","priorityLabel":"High","dueDate":"soon","updatedAt":7,"state":{"name":"Done","type":"completed"},"parent":"none","cycle":{"number":1.5,"name":null},"labels":"none","url":"https://evil.example/acme/issue/ENG-9"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}"#
        let page = try XCTUnwrap(LinearAPI.decodeIssuePage(Data(odd.utf8)))
        let issue = LinearAPI.remoteIssue(from: try XCTUnwrap(page.issues.first), scope: Self.workspace)
        XCTAssertEqual(issue.key, "ENG-9")
        XCTAssertEqual(issue.title, "ENG-9", "no title: titled by its key")
        XCTAssertNil(issue.priority)
        XCTAssertNil(issue.dueDate)
        XCTAssertNil(issue.updatedAt)
        XCTAssertNil(issue.parentTitle)
        XCTAssertNil(issue.iteration, "a cycle number that is not whole is not shown")
        XCTAssertNil(issue.labels)
        XCTAssertNil(issue.webURL)
        XCTAssertTrue(issue.isDoneRemotely)
        XCTAssertEqual(issue.statusCategory, "done")
    }

    // MARK: - Errors

    func testAnAuthenticationErrorIsARefusedKeyOnAnyStatus() {
        XCTAssertEqual(LinearAPI.outcome(Self.exchange(status: 400, body: Self.authError), now: Self.now), .auth(401))
        XCTAssertEqual(LinearAPI.outcome(Self.exchange(status: 200, body: Self.authError), now: Self.now), .auth(401))
        let typeOnly = #"{"errors":[{"message":"nope","extensions":{"type":"authentication error"}}]}"#
        XCTAssertEqual(LinearAPI.outcome(Self.exchange(status: 400, body: typeOnly), now: Self.now), .auth(401), "the type is read when the code is missing")
        XCTAssertEqual(LinearAPI.outcome(Self.exchange(status: 401, body: "{}"), now: Self.now), .auth(401))
        XCTAssertEqual(LinearAPI.read(Self.exchange(status: 400, body: Self.authError), apiKey: Self.key, now: Self.now), .failure(.http(.auth(401))))
    }

    func testARateLimitWaitsUntilLinearsResetInMilliseconds() {
        let reset = String(Int64(Self.now.timeIntervalSince1970 * 1000) + 120_000)
        let limited = Self.exchange(status: 400, headers: ["x-ratelimit-requests-reset": reset], body: Self.rateLimitError)
        XCTAssertEqual(LinearAPI.outcome(limited, now: Self.now), .rateLimited(retryAfter: 120))
        XCTAssertEqual(LinearAPI.read(limited, apiKey: Self.key, now: Self.now), .failure(.http(.rateLimited(retryAfter: 120))))

        let noHeader = Self.exchange(status: 400, body: Self.rateLimitError)
        XCTAssertEqual(LinearAPI.outcome(noHeader, now: Self.now), .rateLimited(retryAfter: HTTPOutcome.defaultRetryAfter))

        let farOff = String(Int64(Self.now.timeIntervalSince1970 * 1000) + 86_400_000)
        let clamped = Self.exchange(status: 400, headers: ["X-RateLimit-Requests-Reset": farOff], body: Self.rateLimitError)
        XCTAssertEqual(LinearAPI.outcome(clamped, now: Self.now), .rateLimited(retryAfter: HTTPOutcome.retryAfterRange.upperBound), "a day is clamped to an hour")

        let past = String(Int64(Self.now.timeIntervalSince1970 * 1000) - 5_000)
        let elapsed = Self.exchange(status: 400, headers: ["X-RateLimit-Requests-Reset": past], body: Self.rateLimitError)
        XCTAssertEqual(LinearAPI.outcome(elapsed, now: Self.now), .rateLimited(retryAfter: HTTPOutcome.retryAfterRange.lowerBound), "never a busy loop")
    }

    func testA429IsARateLimitToo() {
        let reset = String(Int64(Self.now.timeIntervalSince1970 * 1000) + 300_000)
        XCTAssertEqual(LinearAPI.outcome(Self.exchange(status: 429, headers: ["X-RateLimit-Requests-Reset": reset], body: ""), now: Self.now),
                       .rateLimited(retryAfter: 300))
        XCTAssertEqual(LinearAPI.outcome(Self.exchange(status: 429, body: "{}"), now: Self.now), .rateLimited(retryAfter: HTTPOutcome.defaultRetryAfter))
    }

    func testForbiddenIsA403() {
        XCTAssertEqual(LinearAPI.outcome(Self.exchange(status: 400, body: Self.forbiddenError), now: Self.now), .rejected(403))
        XCTAssertEqual(LinearAPI.read(Self.exchange(status: 200, body: Self.forbiddenError), apiKey: Self.key, now: Self.now), .failure(.http(.rejected(403))))
    }

    func testAnyOtherGraphQLErrorIsADecodeFailureWithLinearsMessage() {
        let invalid = #"{"errors":[{"message":"Variable \"$after\" got invalid value 5;\nString cannot represent a non string value","extensions":{"code":"GRAPHQL_VALIDATION_FAILED"}}]}"#
        let expected = LinearReader.Failure.decode(#"Variable "$after" got invalid value 5; String cannot represent a non string value"#)
        XCTAssertEqual(LinearAPI.read(Self.exchange(status: 400, body: invalid), apiKey: Self.key, now: Self.now), .failure(expected))
        XCTAssertEqual(LinearAPI.read(Self.exchange(status: 200, body: invalid), apiKey: Self.key, now: Self.now), .failure(expected))

        let echoing = #"{"errors":[{"message":"Bad header lin_api_FAKE, also lin_api_OTHER123 and lin_oauth_abc","extensions":{"code":"INVALID_INPUT"}}],"data":null}"#
        XCTAssertEqual(LinearAPI.read(Self.exchange(status: 200, body: echoing), apiKey: Self.key, now: Self.now),
                       .failure(.decode("Bad header <redacted>, also <redacted> and <redacted>")), "a key is never echoed")

        let long = #"{"errors":[{"message":""# + String(repeating: "x", count: 500) + #""}]}"#
        guard case .failure(.decode(let reason?)) = LinearAPI.read(Self.exchange(status: 200, body: long), apiKey: Self.key, now: Self.now) else {
            return XCTFail("a long message is still a decode failure")
        }
        XCTAssertLessThanOrEqual(reason.count, 200)

        XCTAssertEqual(LinearAPI.read(Self.exchange(status: 400, body: "not json"), apiKey: Self.key, now: Self.now), .failure(.http(.rejected(400))))
        XCTAssertEqual(LinearAPI.read(Self.exchange(status: 200, body: #"{"errors":[{}]}"#), apiKey: Self.key, now: Self.now), .failure(.decode(nil)))
    }

    func testAnAnswerWithDataIsReadDespiteErrors() throws {
        let partial = #"{"data":{"viewer":{"id":"user-1"}},"errors":[{"message":"labels failed","extensions":{"code":"INTERNAL_SERVER_ERROR"}}]}"#
        let read = LinearAPI.read(Self.exchange(status: 200, body: partial), apiKey: Self.key, now: Self.now)
        XCTAssertEqual(read, .success(Data(partial.utf8)))
        XCTAssertEqual(LinearAPI.decodeFailure(Data(partial.utf8), apiKey: Self.key), .decode("labels failed"), "when the data is not what the query asks for, Linear's reason goes with it")
    }

    func testServerErrorsStayHTTPFailures() {
        let error = #"{"errors":[{"message":"Internal error","extensions":{"code":"INTERNAL_SERVER_ERROR"}}]}"#
        XCTAssertEqual(LinearAPI.read(Self.exchange(status: 500, body: error), apiKey: Self.key, now: Self.now), .failure(.http(.ambiguous(500))))
        XCTAssertEqual(LinearAPI.read(HTTPExchange(outcome: .offline, data: nil), apiKey: Self.key, now: Self.now), .failure(.http(.offline)))
    }

    // MARK: - Sync

    private func assertSentProperly(_ sent: [(request: URLRequest, body: Data)], file: StaticString = #filePath, line: UInt = #line) {
        for (request, body) in sent {
            XCTAssertEqual(request.url, LinearAPI.endpoint, file: file, line: line)
            XCTAssertEqual(request.httpMethod, "POST", file: file, line: line)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), Self.key, file: file, line: line)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json", file: file, line: line)
            XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(Self.key), file: file, line: line)
        }
    }

    func testASyncReadsUntilLinearSaysThereIsNoNextPage() async throws {
        StubProtocol.reset { _, body in
            switch Self.variables(body)["after"] {
            case nil: return Answer(body: Self.page([Self.issue(1), Self.issue(2)], hasNextPage: true, endCursor: "cursor-1"))
            case "cursor-1": return Answer(body: Self.page([Self.issue(3)], hasNextPage: false, endCursor: "cursor-2"))
            default: return Answer(status: 500, body: "{}")
            }
        }

        let fetch = await reader.fetch(credential)

        XCTAssertNil(fetch.failure)
        guard case .fetched(let result) = fetch.outcome else { return XCTFail("\(fetch.outcome)") }
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.issues.map(\.key), ["ENG-1", "ENG-2", "ENG-3"])
        XCTAssertEqual(result.issues.map(\.webURL), (1...3).map { "https://linear.app/acme/issue/ENG-\($0)/issue" })
        let sent = StubProtocol.requests()
        XCTAssertEqual(sent.map { Self.variables($0.body) }, [[:], ["after": "cursor-1"]])
        assertSentProperly(sent)
    }

    func testASyncStopsAtTwoPages() async throws {
        StubProtocol.reset { _, body in
            let page = Self.variables(body)["after"] == nil ? 1 : 2
            return Answer(body: Self.page([Self.issue(page * 10), Self.issue(page * 10 + 1)], hasNextPage: true, endCursor: "cursor-\(page)"))
        }
        let fetch = await reader.fetch(credential)
        guard case .fetched(let result) = fetch.outcome else { return XCTFail("\(fetch.outcome)") }
        XCTAssertFalse(result.complete, "there were more: nothing may be marked gone")
        XCTAssertEqual(result.issues.map(\.key), ["ENG-10", "ENG-11", "ENG-20", "ENG-21"])
        XCTAssertEqual(StubProtocol.requests().count, LinearAPI.maxPages, "never a third request")
    }

    func testMorePagesWithoutACursorIsIncomplete() async throws {
        StubProtocol.reset { _, _ in Answer(body: Self.page([Self.issue(1)], hasNextPage: true, endCursor: nil)) }
        let fetch = await reader.fetch(credential)
        guard case .fetched(let result) = fetch.outcome else { return XCTFail("\(fetch.outcome)") }
        XCTAssertFalse(result.complete, "Linear has more, but said nothing to ask for it by")
        XCTAssertEqual(result.issues.map(\.key), ["ENG-1"])
        XCTAssertEqual(StubProtocol.requests().count, 1)
    }

    func testAFailedPageFailsTheWholeSync() async throws {
        StubProtocol.reset { _, body in
            Self.variables(body)["after"] == nil
                ? Answer(body: Self.page([Self.issue(1)], hasNextPage: true, endCursor: "cursor-1"))
                : Answer(status: 502, body: "{}")
        }
        let fetch = await reader.fetch(credential)
        XCTAssertEqual(fetch.outcome, .failed, "the first page already read is not used")
        XCTAssertEqual(fetch.failure, .http(.ambiguous(502)))
    }

    func testARateLimitedSyncSaysWhenToComeBack() async throws {
        let reset = String(Int64((Date().timeIntervalSince1970 + 120) * 1000))
        StubProtocol.reset { _, _ in Answer(status: 400, headers: ["X-RateLimit-Requests-Reset": reset], body: Self.rateLimitError) }
        let fetch = await reader.fetch(credential)
        XCTAssertEqual(fetch.outcome, .failed)
        guard case .http(.rateLimited(let wait))? = fetch.failure else { return XCTFail("\(String(describing: fetch.failure))") }
        XCTAssertTrue((100...121).contains(wait), "Linear's reset, as a wait: \(wait)")
        XCTAssertEqual(StubProtocol.requests().count, 1)
    }

    func testAnAnswerThatIsNotAPageFailsTheSync() async throws {
        StubProtocol.reset { _, _ in Answer(body: Self.viewerJSON) }
        let fetch = await reader.fetch(credential)
        XCTAssertEqual(fetch.outcome, .failed)
        XCTAssertEqual(fetch.failure, .decode(nil))
    }

    func testACredentialKannuWouldNotSendNeedsReconnectingAndSendsNothing() async throws {
        StubProtocol.reset { _, _ in Answer(body: Self.page([], hasNextPage: false, endCursor: nil)) }
        for bad in [LinearCredential(workspace: "https://evil.example/acme", apiKey: Self.key),
                    LinearCredential(workspace: Self.workspace, apiKey: "lin_api FAKE")] {
            let fetch = await reader.fetch(bad)
            XCTAssertEqual(fetch.outcome, .failed)
            XCTAssertNil(fetch.failure)
            XCTAssertEqual(LinearAPI.syncState(for: fetch.failure, now: Self.now), .needsReconnect)
        }
        XCTAssertTrue(StubProtocol.requests().isEmpty)
    }

    // MARK: - Connect

    func testVerifyReadsTheViewerAndWorkspace() async throws {
        StubProtocol.reset { _, _ in Answer(body: Self.viewerJSON) }
        let result = await reader.verify(apiKey: Self.key)
        XCTAssertEqual(result, .verified(LinearViewer(id: "user-1", name: "Dana Example", displayName: "dana", organizationURLKey: "acme", organizationName: "Acme Inc")))
        let sent = StubProtocol.requests()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(Self.json(try XCTUnwrap(sent.first?.body))["query"] as? String, LinearAPI.viewerQuery)
        assertSentProperly(sent)
    }

    func testVerifyFailsForARefusedKey() async throws {
        StubProtocol.reset { _, _ in Answer(status: 400, body: Self.authError) }
        let result = await reader.verify(apiKey: Self.key)
        XCTAssertEqual(result, .failed(.http(.auth(401))))
        XCTAssertEqual(LinearAPI.connectMessage(for: .http(.auth(401))),
                       "Linear did not accept that API key (401). Create a new one in Linear's Settings › Security & access.")
    }

    func testVerifyRefusesAWorkspaceKannuWouldNotUse() async throws {
        let odd = #"{"data":{"viewer":{"id":"user-1","name":"Dana"},"organization":{"urlKey":"Acme/../evil","name":"Acme"}}}"#
        StubProtocol.reset { _, _ in Answer(body: odd) }
        let result = await reader.verify(apiKey: Self.key)
        XCTAssertEqual(result, .failed(.decode(nil)))
    }

    func testAKeyThatCannotTravelNeverLeaves() async throws {
        StubProtocol.reset { _, _ in Answer(body: Self.viewerJSON) }
        let result = await reader.verify(apiKey: "lin_api FAKE")
        XCTAssertEqual(result, .failed(.http(.auth(401))))
        XCTAssertTrue(StubProtocol.requests().isEmpty)
    }

    func testVerifyOfflineIsOffline() async throws {
        StubProtocol.reset { _, _ in Answer(error: .notConnectedToInternet) }
        let result = await reader.verify(apiKey: Self.key)
        XCTAssertEqual(result, .failed(.http(.offline)))
        XCTAssertEqual(LinearAPI.connectMessage(for: .http(.offline)), "This Mac is offline.")
    }

    // MARK: - States and messages

    func testSyncStates() {
        XCTAssertEqual(LinearAPI.syncState(for: nil, now: Self.now), .needsReconnect)
        XCTAssertEqual(LinearAPI.syncState(for: .http(.offline), now: Self.now), .offline)
        XCTAssertEqual(LinearAPI.syncState(for: .http(.auth(401)), now: Self.now), .authFailed(status: 401))
        XCTAssertEqual(LinearAPI.syncState(for: .http(.rateLimited(retryAfter: 120)), now: Self.now), .rateLimited(until: Self.now.addingTimeInterval(120)))
        XCTAssertEqual(LinearAPI.syncState(for: .http(.ambiguous(503)), now: Self.now), .failed("Linear did not answer properly (503). Try again later."))
        XCTAssertEqual(LinearAPI.syncState(for: .decode("Boom"), now: Self.now), .failed("Linear's answer could not be read: Boom"))
        XCTAssertEqual(LinearAPI.syncState(for: .decode(nil), now: Self.now), .failed("Linear's answer could not be read."))
    }

    func testConnectMessagesNeverEchoTheKey() {
        let failures: [LinearReader.Failure] = [
            .http(.auth(401)), .http(.rejected(403)), .http(.rejected(404)), .http(.redirected(302)), .http(.rateLimited(retryAfter: 60)),
            .http(.offline), .http(.failedBeforeSend), .http(.ambiguous(nil)), .http(.ok(200)), .decode(nil), .decode("why"),
        ]
        for failure in failures {
            let message = LinearAPI.connectMessage(for: failure)
            XCTAssertFalse(message.isEmpty, "\(failure)")
            XCTAssertFalse(message.contains(Self.key), "\(failure)")
            XCTAssertTrue(message.contains("Linear") || message.contains("Mac"), message)
        }
    }

    // MARK: - The credential

    func testTheCredentialNeverPrintsItsKey() {
        var dumped = ""
        dump(credential, to: &dumped)
        let printed = [credential.description, credential.debugDescription, "\(credential)", String(describing: credential), String(reflecting: credential), dumped]
        for text in printed {
            XCTAssertFalse(text.contains(Self.key), text)
            XCTAssertTrue(text.contains("acme"), text)
        }
        XCTAssertEqual(Mirror(reflecting: credential).children.map(\.label), ["workspace"])
    }

    func testTheCredentialRoundTripsThroughItsKeychainForm() throws {
        let encoded = try XCTUnwrap(credential.encoded())
        XCTAssertEqual(encoded, #"{"apiKey":"lin_api_FAKE","workspace":"https://linear.app/acme"}"#)
        XCTAssertEqual(LinearCredential.decoded(encoded), credential)
        XCTAssertNil(LinearCredential.decoded("lin_api_FAKE"))
        XCTAssertNil(LinearCredential.decoded(#"{"workspace":"https://linear.app/acme"}"#))
    }
}
