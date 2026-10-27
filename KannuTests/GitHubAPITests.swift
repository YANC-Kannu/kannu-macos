//
//  GitHubAPITests.swift
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

/// GitHub Issues, read-only, on github.com and on a GitHub Enterprise Server: the one server a token
/// may be sent to, the requests, the answers from handwritten fixtures shaped like the documented
/// API, GitHub's rate limits, and a whole sync and Connect through the real `IntegrationHTTP` session
/// against a `URLProtocol` stub. Nothing leaves this Mac and no real token exists.
final class GitHubAPITests: XCTestCase {
    private static let token = "FAKE-TOKEN"
    private let dotCom = GitHubCredential(baseURL: "https://github.com", token: GitHubAPITests.token)
    private let enterprise = GitHubCredential(baseURL: "https://ghe.acme.com:8443", token: GitHubAPITests.token)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - The server

    private func normalized(_ input: String) -> String? {
        if case .success(let base) = GitHubHost.normalize(input) { return base }
        return nil
    }

    private func error(_ input: String) -> GitHubHostError? {
        if case .failure(let error) = GitHubHost.normalize(input) { return error }
        return nil
    }

    func testGitHubDotComInEveryForm() {
        for input in ["github.com", "https://github.com", "https://github.com/", "  HTTPS://GitHub.com  ", "www.github.com",
                      "https://www.github.com/", "https://api.github.com", "https://github.com:443"] {
            XCTAssertEqual(normalized(input), "https://github.com", input)
        }
        XCTAssertEqual(normalized(GitHubHost.defaultServer), GitHubHost.defaultServer)
    }

    func testEnterpriseServers() {
        XCTAssertEqual(normalized("ghe.acme.com"), "https://ghe.acme.com")
        XCTAssertEqual(normalized("https://ghe.acme.com:8443"), "https://ghe.acme.com:8443", "its own port is kept")
        XCTAssertEqual(normalized("ghe.acme.com:8443/"), "https://ghe.acme.com:8443")
        XCTAssertEqual(normalized("https://ghe.acme.com:443"), "https://ghe.acme.com", "the default port is dropped")
        XCTAssertEqual(normalized("https://ghe.acme.com/api/v3"), "https://ghe.acme.com", "a pasted API address is the server")
        XCTAssertEqual(normalized("https://ghe.acme.com:8443/api/v3/"), "https://ghe.acme.com:8443")
        XCTAssertEqual(normalized("https://GHE.acme.com/API/V3"), "https://ghe.acme.com")
        XCTAssertEqual(normalized("https://ghe.acme.com/api"), "https://ghe.acme.com")
        XCTAssertEqual(normalized("https://10.0.0.5"), "https://10.0.0.5", "a LAN address")
    }

    func testRefusedServers() {
        XCTAssertEqual(error(""), .empty)
        XCTAssertEqual(error("   "), .empty)
        XCTAssertEqual(error("http://github.com"), .notHTTPS)
        XCTAssertEqual(error("http://ghe.acme.com"), .notHTTPS)
        XCTAssertEqual(error("http:/github.com"), .malformed, "a scheme without its slashes is not a host")
        XCTAssertEqual(error("javascript:alert(1)"), .malformed)
        XCTAssertEqual(error("https://user@github.com"), .userInfo)
        XCTAssertEqual(error("https://github.com@evil.example"), .userInfo, "reads as github.com, connects to evil.example")
        XCTAssertEqual(error("https://ghe.acme.com/?next=https://evil.example"), .queryOrFragment)
        XCTAssertEqual(error("https://ghe.acme.com#x"), .queryOrFragment)
        XCTAssertEqual(error("https://github.com/acme/app"), .badPath, "a page, not the server")
        XCTAssertEqual(error("https://ghe.acme.com/acme/app/issues/7"), .badPath)
        XCTAssertEqual(error("https://ghe.acme.com/api/v4"), .badPath)
        XCTAssertEqual(error("https://ghe.acme.com/ap%69"), .badPath)
        XCTAssertEqual(error("https://github.com:8443"), .port, "github.com answers on 443 only")
        XCTAssertEqual(error("https://www.github.com:8443"), .port)
        XCTAssertEqual(error("https://ghe.acme.com:0"), .port)
        XCTAssertEqual(error("https://[::1]"), .malformed, "IPv6 literals are not supported")
        XCTAssertEqual(error("https://gíthub.com"), .malformed, "non-ASCII")
        XCTAssertEqual(error("https://ghe..acme.com"), .malformed)
        XCTAssertEqual(error("https://ghe.acme.com\\@evil.example"), .malformed)
    }

    func testOnlyANormalizedBaseIsValid() {
        XCTAssertTrue(GitHubHost.isValidBase("https://github.com"))
        XCTAssertTrue(GitHubHost.isValidBase("https://ghe.acme.com:8443"))
        XCTAssertFalse(GitHubHost.isValidBase("github.com"), "the stored form carries its scheme")
        XCTAssertFalse(GitHubHost.isValidBase("https://github.com/"))
        XCTAssertFalse(GitHubHost.isValidBase("https://www.github.com"))
        XCTAssertFalse(GitHubHost.isValidBase("https://api.github.com"))
        XCTAssertFalse(GitHubHost.isValidBase("https://ghe.acme.com/api/v3"))
        XCTAssertFalse(GitHubHost.isValidBase("http://github.com"))
        XCTAssertFalse(GitHubHost.isValidBase(""))
    }

    func testAPIURLs() {
        XCTAssertEqual(GitHubHost.apiURL(base: "https://github.com", path: "/user")?.absoluteString, "https://api.github.com/user")
        XCTAssertEqual(GitHubHost.apiURL(base: "https://ghe.acme.com:8443", path: "/user")?.absoluteString,
                       "https://ghe.acme.com:8443/api/v3/user")
        XCTAssertEqual(GitHubHost.apiURL(base: "https://ghe.acme.com", path: "/issues")?.absoluteString, "https://ghe.acme.com/api/v3/issues")
        XCTAssertNil(GitHubHost.apiURL(base: "http://github.com", path: "/user"))
        XCTAssertNil(GitHubHost.apiURL(base: "https://api.github.com", path: "/user"), "not a base normalize returns")
        XCTAssertNil(GitHubHost.apiURL(base: "https://github.com", path: "user"))
        XCTAssertNil(GitHubHost.apiURL(base: "https://github.com", path: "/../user"))
        XCTAssertNil(GitHubHost.apiURL(base: "https://github.com", path: "/user?access_token=x"))
        XCTAssertNil(GitHubHost.apiURL(base: "https://github.com", path: "//evil.example/user"))
    }

    func testDisplayAndTokenPage() {
        XCTAssertEqual(GitHubHost.displayName("https://github.com"), "github.com")
        XCTAssertEqual(GitHubHost.displayName("https://ghe.acme.com:8443"), "ghe.acme.com:8443")
        XCTAssertEqual(GitHubHost.createTokenURL(base: "https://github.com")?.absoluteString, "https://github.com/settings/tokens")
        XCTAssertEqual(GitHubHost.createTokenURL(base: "https://ghe.acme.com:8443")?.absoluteString,
                       "https://ghe.acme.com:8443/settings/tokens")
        XCTAssertNil(GitHubHost.createTokenURL(base: "http://github.com"))
    }

    func testAWebURLIsOpenedOnlyOnItsOwnServer() {
        let dotCom = "https://github.com"
        XCTAssertTrue(GitHubHost.isWebURL("https://github.com/acme/app/issues/7", onServer: dotCom))
        XCTAssertTrue(GitHubHost.isWebURL("https://GitHub.com/acme/app/pull/12", onServer: dotCom))
        XCTAssertFalse(GitHubHost.isWebURL("https://www.github.com/acme/app/issues/7", onServer: dotCom), "github.com only")
        XCTAssertFalse(GitHubHost.isWebURL("https://api.github.com/repos/acme/app/issues/7", onServer: dotCom))
        XCTAssertFalse(GitHubHost.isWebURL("https://github.com.evil.example/acme/app/issues/7", onServer: dotCom))
        XCTAssertFalse(GitHubHost.isWebURL("http://github.com/acme/app/issues/7", onServer: dotCom), "plain http")
        XCTAssertFalse(GitHubHost.isWebURL("https://github.com:8443/acme/app/issues/7", onServer: dotCom), "another port")
        XCTAssertFalse(GitHubHost.isWebURL("https://user@github.com/acme/app/issues/7", onServer: dotCom))
        XCTAssertFalse(GitHubHost.isWebURL("https://github.com/", onServer: dotCom), "no page")
        XCTAssertFalse(GitHubHost.isWebURL("javascript:alert(1)", onServer: dotCom))

        let enterprise = "https://ghe.acme.com:8443"
        XCTAssertTrue(GitHubHost.isWebURL("https://ghe.acme.com:8443/acme/app/pull/12", onServer: enterprise))
        XCTAssertFalse(GitHubHost.isWebURL("https://ghe.acme.com/acme/app/pull/12", onServer: enterprise), "another port")
        XCTAssertFalse(GitHubHost.isWebURL("https://ghe.acme.com:8443/acme/../admin", onServer: enterprise))
        XCTAssertFalse(GitHubHost.isWebURL("https://github.com/acme/app/pull/12", onServer: enterprise), "another server")
        XCTAssertFalse(GitHubHost.isWebURL("https://ghe.acme.com:8443/acme/app/pull/12", onServer: "http://ghe.acme.com:8443"))
    }

    // MARK: - Requests

    func testTheRequestsCarryTheTokenInTheirHeaderOnly() throws {
        let user = try XCTUnwrap(GitHubAPI.userRequest(dotCom))
        XCTAssertEqual(user.url?.absoluteString, "https://api.github.com/user")
        let issues = try XCTUnwrap(GitHubAPI.issuesRequest(dotCom, page: 1))
        XCTAssertEqual(issues.url?.absoluteString,
                       "https://api.github.com/issues?filter=assigned&state=open&sort=updated&direction=desc&per_page=100&page=1")
        XCTAssertEqual(GitHubAPI.issuesRequest(enterprise, page: 2)?.url?.absoluteString,
                       "https://ghe.acme.com:8443/api/v3/issues?filter=assigned&state=open&sort=updated&direction=desc&per_page=100&page=2")
        for request in [user, issues] {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer FAKE-TOKEN")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Kannu")
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.timeoutInterval, IntegrationHTTP.timeout)
            XCTAssertFalse(request.url?.absoluteString.contains(Self.token) ?? true)
        }
    }

    func testNoRequestIsBuiltThatKannuWouldNotSend() {
        XCTAssertNil(GitHubAPI.issuesRequest(dotCom, page: 0))
        XCTAssertNil(GitHubAPI.issuesRequest(dotCom, page: 3), "never a third page")
        XCTAssertNil(GitHubAPI.userRequest(GitHubCredential(baseURL: "http://github.com", token: Self.token)))
        XCTAssertNil(GitHubAPI.userRequest(GitHubCredential(baseURL: "https://api.github.com", token: Self.token)))
        XCTAssertNil(GitHubAPI.userRequest(GitHubCredential(baseURL: "https://github.com", token: "FAKE\r\nX-Evil: 1")), "no header injection")
        XCTAssertNil(GitHubAPI.userRequest(GitHubCredential(baseURL: "https://github.com", token: "")))
    }

    func testTheTokenIsCheckedBeforeItIsSent() {
        XCTAssertTrue(GitHubAPI.isPlausibleToken("ghp_FAKEfakeFAKEfake0123"))
        XCTAssertTrue(GitHubAPI.isPlausibleToken("github_pat_FAKE_0123456789"))
        XCTAssertTrue(GitHubAPI.isPlausibleToken(String(repeating: "a", count: 255)))
        XCTAssertFalse(GitHubAPI.isPlausibleToken(String(repeating: "a", count: 256)))
        XCTAssertFalse(GitHubAPI.isPlausibleToken(""))
        XCTAssertFalse(GitHubAPI.isPlausibleToken("ghp abc"))
        XCTAssertFalse(GitHubAPI.isPlausibleToken("ghp_abc\n"))
        XCTAssertFalse(GitHubAPI.isPlausibleToken("ghp_ab€"))
    }

    // MARK: - Answers

    static let issuesPage = #"""
    [
      {
        "id": 2500000001, "node_id": "I_kwDOFAKE", "number": 7,
        "url": "https://api.github.com/repos/acme/app/issues/7",
        "repository_url": "https://api.github.com/repos/acme/app",
        "html_url": "https://github.com/acme/app/issues/7",
        "title": "Login  redirect\nloops", "state": "open", "locked": false,
        "user": {"login": "kim", "id": 2, "type": "User"},
        "labels": [{"id": 1, "name": "bug", "color": "d73a4a", "default": true}, {"id": 2, "name": "In progress", "color": "fbca04"}],
        "assignee": {"login": "dana", "id": 1},
        "assignees": [{"login": "dana", "id": 1}, {"login": "kim", "id": 2}],
        "milestone": {"id": 3, "number": 1, "title": "Sprint  42", "state": "open"},
        "comments": 3, "created_at": "2026-10-01T10:00:00Z", "updated_at": "2026-10-16T09:12:34Z", "closed_at": null,
        "author_association": "MEMBER", "body": "ignored",
        "repository": {"id": 9, "name": "app", "full_name": "acme/app", "private": true, "owner": {"login": "acme"}}
      },
      {
        "id": 2500000002, "number": 12,
        "repository_url": "https://api.github.com/repos/acme/app",
        "html_url": "https://github.com/acme/app/pull/12",
        "title": "Fix the redirect", "state": "open", "draft": true,
        "user": {"login": "kim", "id": 2},
        "labels": [], "assignee": null, "assignees": [{"login": "dana", "id": 1}], "milestone": null,
        "comments": 4, "updated_at": "2026-10-16T08:00:00Z",
        "pull_request": {"url": "https://api.github.com/repos/acme/app/pulls/12", "html_url": "https://github.com/acme/app/pull/12",
                         "diff_url": "https://github.com/acme/app/pull/12.diff", "merged_at": null},
        "repository": {"full_name": "acme/app"}
      },
      {
        "id": 2500000003, "number": 8,
        "repository_url": "https://api.github.com/repos/acme/tools",
        "html_url": "https://evil.example/acme/tools/issues/8",
        "title": "", "state": "open",
        "labels": ["wip", 5], "milestone": 5, "comments": "three", "updated_at": 12, "draft": "yes",
        "assignees": "nobody"
      },
      {
        "id": 2500000004, "number": 9,
        "repository_url": "https://evil.example/repos/acme/app",
        "html_url": "https://github.com/acme/app/issues/9",
        "title": "Not on this server", "state": "open"
      }
    ]
    """#

    private func items(_ json: String) throws -> [GitHubItem] {
        try XCTUnwrap(GitHubAPI.decodeItems(Data(json.utf8)))
    }

    func testAnIssuesPageDecodes() throws {
        let items = try items(Self.issuesPage)
        XCTAssertEqual(items.count, 4, "a field in an unexpected shape costs that field, never the item")
        let issue = items[0]
        XCTAssertEqual(issue.id, 2_500_000_001, "ids past 2^31")
        XCTAssertEqual(issue.number, 7)
        XCTAssertFalse(issue.isPullRequest)
        XCTAssertEqual(issue.labels?.names, ["bug", "In progress"])
        XCTAssertEqual(issue.repository?.value?.fullName, "acme/app")
        XCTAssertEqual(issue.milestone?.value?.title, "Sprint  42")
        XCTAssertEqual(issue.assignees?.logins, ["dana", "kim"])
        XCTAssertTrue(items[1].isPullRequest)
        XCTAssertEqual(items[1].draft?.value, true)
        XCTAssertEqual(items[2].labels?.names, ["wip"], "plain strings are labels too; a number is not")
        XCTAssertNil(items[2].comments?.value)
        XCTAssertNil(items[2].milestone?.value)
        XCTAssertEqual(items[2].assignees?.logins, [])
        XCTAssertNil(GitHubAPI.decodeItems(Data(#"{"message":"Bad credentials"}"#.utf8)), "not a list")
        XCTAssertNil(GitHubAPI.decodeItems(Data(#"[{"number": 1}]"#.utf8)), "an item without its id")
    }

    func testAnIssueAsATaskKeepsIt() throws {
        let items = try items(Self.issuesPage)
        let issue = try XCTUnwrap(GitHubAPI.remoteIssue(from: items[0], base: "https://github.com"))
        XCTAssertEqual(issue.remoteID, "2500000001")
        XCTAssertEqual(issue.key, "acme/app#7")
        XCTAssertEqual(issue.title, "Login redirect loops")
        XCTAssertEqual(issue.status, "open")
        XCTAssertFalse(issue.isDoneRemotely)
        XCTAssertEqual(issue.statusCategory, TaskFacets.inProgressCategory, "an In progress label")
        XCTAssertEqual(issue.labels, ["bug", "In progress"])
        XCTAssertEqual(issue.milestone, "Sprint 42")
        XCTAssertEqual(issue.assignee, "dana")
        XCTAssertEqual(issue.commentCount, 3)
        XCTAssertEqual(issue.updatedAt, Date(timeIntervalSince1970: 1_792_141_954))
        XCTAssertEqual(issue.webURL, "https://github.com/acme/app/issues/7")
        XCTAssertNil(issue.isDraft, "issues have no draft")
        XCTAssertNil(issue.author, "only a pull request names its author")
        XCTAssertNil(issue.gitlab)
        XCTAssertNil(issue.estimateSeconds)
        XCTAssertNil(issue.spentSeconds)
    }

    func testAPullRequestAsATask() throws {
        let items = try items(Self.issuesPage)
        let pull = try XCTUnwrap(GitHubAPI.remoteIssue(from: items[1], base: "https://github.com"))
        XCTAssertEqual(pull.key, "acme/app#12", "GitHub numbers pull requests with #, as issues")
        XCTAssertEqual(pull.statusCategory, TaskFacets.inProgressCategory)
        XCTAssertEqual(pull.isDraft, true)
        XCTAssertEqual(pull.author, "kim")
        XCTAssertEqual(pull.assignee, "dana", "the first assignee when there is no assignee")
        XCTAssertEqual(pull.labels, [])
        XCTAssertNil(pull.milestone)
    }

    func testTheRepositoryIsNamedOnlyFromThisServer() throws {
        let items = try items(Self.issuesPage)
        let derived = try XCTUnwrap(GitHubAPI.remoteIssue(from: items[2], base: "https://github.com"))
        XCTAssertEqual(derived.key, "acme/tools#8", "from repository_url on the API host")
        XCTAssertEqual(derived.title, "acme/tools#8", "an item with no title is titled by its key")
        XCTAssertNil(derived.webURL, "a page on another host is never kept")
        XCTAssertEqual(derived.statusCategory, TaskFacets.inProgressCategory, "a wip label")
        XCTAssertNil(derived.commentCount)
        XCTAssertNil(derived.updatedAt)
        XCTAssertNil(GitHubAPI.remoteIssue(from: items[3], base: "https://github.com"), "a repository_url elsewhere names nothing")
        XCTAssertNil(GitHubAPI.remoteIssue(from: items[2], base: "https://ghe.acme.com"), "github.com's API is not this server's")
    }

    func testAnEnterpriseItemKeepsItsPage() throws {
        let json = #"""
        [{"id": 41, "number": 3, "title": "On the company server", "state": "open", "labels": [{"name": "docs"}],
          "repository_url": "https://ghe.acme.com:8443/api/v3/repos/team/site",
          "html_url": "https://ghe.acme.com:8443/team/site/issues/3"},
         {"id": 42, "number": 4, "title": "Other port", "state": "closed",
          "repository": {"full_name": "team/site"},
          "html_url": "https://ghe.acme.com/team/site/issues/4"},
         {"id": 43, "number": 5, "title": "A bad name", "state": "open",
          "repository": {"full_name": "team/../site"}}]
        """#
        let items = try items(json)
        let first = try XCTUnwrap(GitHubAPI.remoteIssue(from: items[0], base: "https://ghe.acme.com:8443"))
        XCTAssertEqual(first.key, "team/site#3")
        XCTAssertEqual(first.webURL, "https://ghe.acme.com:8443/team/site/issues/3")
        XCTAssertEqual(first.statusCategory, TaskFacets.toDoCategory)
        let second = try XCTUnwrap(GitHubAPI.remoteIssue(from: items[1], base: "https://ghe.acme.com:8443"))
        XCTAssertNil(second.webURL, "another port is another server")
        XCTAssertTrue(second.isDoneRemotely)
        XCTAssertNil(GitHubAPI.remoteIssue(from: items[2], base: "https://ghe.acme.com:8443"), "a name with a path in it is no key")
    }

    func testTheUserDecodes() {
        XCTAssertEqual(GitHubAPI.decodeUser(Data(#"{"login": "dana", "id": 1, "name": "Dana Example", "type": "User"}"#.utf8)),
                       GitHubUser(login: "dana", name: "Dana Example"))
        XCTAssertEqual(GitHubAPI.decodeUser(Data(#"{"login": "dana", "name": null}"#.utf8)), GitHubUser(login: "dana", name: nil))
        XCTAssertNil(GitHubAPI.decodeUser(Data(#"{"name": "No login"}"#.utf8)))
    }

    // MARK: - Paging

    func testTheLinkHeaderSaysOnlyWhetherThereIsMore() {
        XCTAssertTrue(GitHubAPI.hasNextLink(#"<https://api.github.com/issues?filter=assigned&page=2>; rel="next", <https://api.github.com/issues?filter=assigned&page=5>; rel="last""#))
        XCTAssertFalse(GitHubAPI.hasNextLink(#"<https://api.github.com/issues?page=1>; rel="prev", <https://api.github.com/issues?page=1>; rel="first""#))
        XCTAssertTrue(GitHubAPI.hasNextLink(#"<https://x.example/issues?labels=a,b&page=2>; rel="next""#), "a comma inside a URL")
        XCTAssertTrue(GitHubAPI.hasNextLink("<https://x.example/issues?page=2>; rel=next"))
        XCTAssertFalse(GitHubAPI.hasNextLink(#"<https://x.example/issues?page=2>; rel="nextish""#))
        XCTAssertFalse(GitHubAPI.hasNextLink(""))
    }

    func testTheNextStep() {
        let full = GitHubAPI.pageSize
        let next = #"<https://api.github.com/issues?page=2>; rel="next""#
        let last = #"<https://api.github.com/issues?page=1>; rel="prev""#
        XCTAssertEqual(GitHubAPI.nextStep(linkHeader: nil, page: 1, itemCount: 30), .done(complete: true))
        XCTAssertEqual(GitHubAPI.nextStep(linkHeader: next, page: 1, itemCount: 30), .done(complete: true), "a short page is the last")
        XCTAssertEqual(GitHubAPI.nextStep(linkHeader: next, page: 1, itemCount: full), .next(2))
        XCTAssertEqual(GitHubAPI.nextStep(linkHeader: nil, page: 1, itemCount: full), .next(2), "no Link on a full page: ask")
        XCTAssertEqual(GitHubAPI.nextStep(linkHeader: last, page: 2, itemCount: full), .done(complete: true))
        XCTAssertEqual(GitHubAPI.nextStep(linkHeader: next, page: 2, itemCount: full), .capped)
        XCTAssertEqual(GitHubAPI.nextStep(linkHeader: nil, page: 2, itemCount: full), .capped)
    }

    // MARK: - Rate limits

    private func exchange(_ status: Int, _ headers: [String: String] = [:], body: String = "{}") -> HTTPExchange {
        let response = HTTPURLResponse(url: URL(string: "https://api.github.com/issues")!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        return HTTPExchange(
            outcome: HTTPOutcome.classify(status: status, retryAfter: headers["Retry-After"], now: now),
            data: Data(body.utf8),
            response: response
        )
    }

    func testAnExhaustedQuotaIsARateLimitNotARefusal() {
        let reset = String(Int(now.timeIntervalSince1970) + 600)
        XCTAssertEqual(GitHubAPI.outcome(exchange(403, ["x-ratelimit-remaining": "0", "x-ratelimit-reset": reset]), now: now),
                       .rateLimited(retryAfter: 600))
        XCTAssertEqual(GitHubAPI.outcome(exchange(429, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": reset]), now: now),
                       .rateLimited(retryAfter: 600), "headers in any case")
        XCTAssertEqual(GitHubAPI.outcome(exchange(403, ["Retry-After": "30"]), now: now), .rateLimited(retryAfter: 30), "a secondary limit")
        XCTAssertEqual(GitHubAPI.outcome(exchange(403, ["Retry-After": "45", "x-ratelimit-remaining": "0", "x-ratelimit-reset": reset]), now: now),
                       .rateLimited(retryAfter: 45), "Retry-After wins")
        let farOff = String(Int(now.timeIntervalSince1970) + 86_400)
        XCTAssertEqual(GitHubAPI.outcome(exchange(403, ["x-ratelimit-remaining": "0", "x-ratelimit-reset": farOff]), now: now),
                       .rateLimited(retryAfter: HTTPOutcome.retryAfterRange.upperBound), "clamped")
        XCTAssertEqual(GitHubAPI.outcome(exchange(403, body: #"{"message":"You have exceeded a secondary rate limit."}"#), now: now),
                       .rateLimited(retryAfter: HTTPOutcome.defaultRetryAfter))
    }

    func testAPlainRefusalStaysOne() {
        XCTAssertEqual(GitHubAPI.outcome(exchange(403), now: now), .rejected(403))
        XCTAssertEqual(GitHubAPI.outcome(exchange(403, ["x-ratelimit-remaining": "4999"], body: #"{"message":"Resource not accessible by personal access token"}"#), now: now),
                       .rejected(403))
        XCTAssertEqual(GitHubAPI.outcome(exchange(404, ["x-ratelimit-remaining": "0"]), now: now), .rejected(404), "only 403 and 429")
        XCTAssertEqual(GitHubAPI.outcome(exchange(200, ["x-ratelimit-remaining": "0"]), now: now), .ok(200), "the last request of the hour still arrived")
        XCTAssertEqual(GitHubAPI.outcome(HTTPExchange(outcome: .offline, data: nil), now: now), .offline)
    }

    // MARK: - Messages

    func testWhatAFailedSyncLeaves() {
        XCTAssertEqual(GitHubAPI.syncState(for: .http(.offline), now: now), .offline)
        XCTAssertEqual(GitHubAPI.syncState(for: .http(.rateLimited(retryAfter: 600)), now: now), .rateLimited(until: now.addingTimeInterval(600)))
        XCTAssertEqual(GitHubAPI.syncState(for: .http(.auth(401)), now: now), .authFailed(status: 401))
        XCTAssertEqual(GitHubAPI.syncState(for: .badServer, now: now), .needsReconnect)
        XCTAssertEqual(GitHubAPI.syncState(for: nil, now: now), .needsReconnect)
        guard case .failed(let forbidden) = GitHubAPI.syncState(for: .http(.rejected(403)), now: now) else { return XCTFail() }
        XCTAssertTrue(forbidden.contains("SSO"), forbidden)
        for failure: GitHubReader.Failure in [.http(.rejected(410)), .http(.redirected(302)), .http(.failedBeforeSend),
                                              .http(.ambiguous(502)), .http(.ambiguous(nil)), .decode] {
            guard case .failed(let message) = GitHubAPI.syncState(for: failure, now: now) else { return XCTFail("\(failure)") }
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testConnectMessagesNameTheServer() {
        XCTAssertTrue(GitHubAPI.connectMessage(for: .http(.failedBeforeSend), server: "ghe.acme.com:8443").contains("ghe.acme.com:8443"))
        XCTAssertTrue(GitHubAPI.connectMessage(for: .decode, server: "ghe.acme.com").contains("ghe.acme.com"))
        XCTAssertTrue(GitHubAPI.connectMessage(for: .http(.auth(401)), server: "github.com").contains("401"))
        XCTAssertEqual(GitHubAPI.connectMessage(for: .badServer, server: "x"), GitHubAPI.message(for: .malformed))
        for error: GitHubHostError in [.empty, .notHTTPS, .userInfo, .queryOrFragment, .badPath, .port, .malformed] {
            XCTAssertFalse(GitHubAPI.message(for: error).isEmpty)
        }
    }

    // MARK: - The credential

    func testTheCredentialNeverPrintsItsToken() {
        var dumped = ""
        dump(dotCom, to: &dumped)
        for text in ["\(dotCom)", String(reflecting: dotCom), String(describing: dotCom), dumped] {
            XCTAssertFalse(text.contains(Self.token), text)
        }
        XCTAssertTrue("\(dotCom)".contains("github.com"), "the server is not a secret")
    }

    func testTheKeychainFormRoundTrips() throws {
        let encoded = try XCTUnwrap(enterprise.encoded())
        XCTAssertEqual(encoded, #"{"baseURL":"https://ghe.acme.com:8443","token":"FAKE-TOKEN"}"#)
        XCTAssertEqual(GitHubCredential.decoded(encoded), enterprise)
        XCTAssertNil(GitHubCredential.decoded("not json"))
        XCTAssertNil(GitHubCredential.decoded(#"{"baseURL":"https://github.com"}"#))
    }

    // MARK: - Through the session

    struct Answer {
        var status = 200
        var headers: [String: String] = [:]
        var body = "[]"
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
    private var reader: GitHubReader!

    override func setUp() {
        super.setUp()
        let configuration = IntegrationHTTP.makeConfiguration(base: .ephemeral)
        configuration.protocolClasses = [StubProtocol.self]
        session = IntegrationHTTP.makeSession(configuration: configuration)
        reader = GitHubReader(session: session)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        reader = nil
        super.tearDown()
    }

    private static func item(_ id: Int, pullRequest: Bool = false) -> String {
        let kind = pullRequest ? "pull" : "issues"
        let marker = pullRequest ? #", "pull_request": {"url": "https://api.github.com/repos/acme/app/pulls/\#(id)"}"# : ""
        return """
        {"id": \(id), "number": \(id), "title": "Item \(id)", "state": "open",
         "html_url": "https://github.com/acme/app/\(kind)/\(id)",
         "repository_url": "https://api.github.com/repos/acme/app",
         "repository": {"full_name": "acme/app"}\(marker)}
        """
    }

    private static func page(_ items: [String]) -> String { "[" + items.joined(separator: ",") + "]" }

    private static func pageNumber(_ request: URLRequest) -> String? {
        guard let url = request.url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value
    }

    private static let nextLink = #"<https://api.github.com/issues?page=2>; rel="next", <https://api.github.com/issues?page=9>; rel="last""#
    private static let lastLink = #"<https://api.github.com/issues?page=1>; rel="prev", <https://api.github.com/issues?page=1>; rel="first""#

    func testAShortSecondPageCompletesTheList() async throws {
        StubProtocol.reset { request in
            Self.pageNumber(request) == "1"
                ? Answer(headers: ["Link": Self.nextLink], body: Self.page((1...100).map { Self.item($0) }))
                : Answer(headers: ["Link": Self.lastLink], body: Self.page((101...130).map { Self.item($0) }))
        }
        let fetch = await reader.fetch(dotCom, includePullRequests: false)
        XCTAssertNil(fetch.failure)
        guard case .fetched(let result) = fetch.outcome else { return XCTFail("\(fetch.outcome)") }
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.issues.count, 130)
        XCTAssertEqual(result.issues.first?.key, "acme/app#1")
        XCTAssertEqual(fetch.issueCount, 130)
        let requests = StubProtocol.requests()
        XCTAssertEqual(requests.map(Self.pageNumber), ["1", "2"])
        for request in requests {
            XCTAssertEqual(request.url?.host, "api.github.com")
            XCTAssertEqual(request.url?.path, "/issues")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer FAKE-TOKEN")
            XCTAssertFalse(request.url?.absoluteString.contains(Self.token) ?? true)
        }
    }

    func testTwoFullPagesAreIncompleteAndNoThirdIsAsked() async throws {
        StubProtocol.reset { request in
            let page = Int(Self.pageNumber(request) ?? "") ?? 0
            return Answer(headers: ["Link": Self.nextLink], body: Self.page((0..<100).map { Self.item(page * 1000 + $0) }))
        }
        let fetch = await reader.fetch(dotCom, includePullRequests: true)
        guard case .fetched(let result) = fetch.outcome else { return XCTFail("\(fetch.outcome)") }
        XCTAssertFalse(result.complete, "there were more: nothing may be marked gone")
        XCTAssertEqual(result.issues.count, 200)
        XCTAssertEqual(StubProtocol.requests().map(Self.pageNumber), ["1", "2"], "never a third page")
    }

    func testAFullPageWithoutALinkAsksForTheNext() async throws {
        StubProtocol.reset { request in
            Self.pageNumber(request) == "1"
                ? Answer(body: Self.page((1...100).map { Self.item($0) }))
                : Answer(headers: ["Link": Self.lastLink], body: "[]")
        }
        let fetch = await reader.fetch(dotCom, includePullRequests: false)
        guard case .fetched(let result) = fetch.outcome else { return XCTFail("\(fetch.outcome)") }
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.issues.count, 100)
        XCTAssertEqual(StubProtocol.requests().count, 2)
    }

    func testPullRequestsAreLeftOutWhenOffButStillFillThePage() async throws {
        StubProtocol.reset { request in
            Self.pageNumber(request) == "1"
                ? Answer(headers: ["Link": Self.nextLink], body: Self.page((1...100).map { Self.item($0, pullRequest: $0 <= 40) }))
                : Answer(headers: ["Link": Self.lastLink], body: Self.page((101...110).map { Self.item($0) }))
        }
        let off = await reader.fetch(dotCom, includePullRequests: false)
        guard case .fetched(let issuesOnly) = off.outcome else { return XCTFail("\(off.outcome)") }
        XCTAssertEqual(issuesOnly.issues.count, 70)
        XCTAssertTrue(issuesOnly.complete)
        XCTAssertEqual(off.pullRequestCount, 0)
        XCTAssertEqual(StubProtocol.requests().map(Self.pageNumber), ["1", "2"], "the first page was full, pull requests and all")

        let on = await reader.fetch(dotCom, includePullRequests: true)
        guard case .fetched(let both) = on.outcome else { return XCTFail("\(on.outcome)") }
        XCTAssertEqual(both.issues.count, 110)
        XCTAssertEqual(on.issueCount, 70)
        XCTAssertEqual(on.pullRequestCount, 40)
        XCTAssertEqual(both.issues.first?.statusCategory, TaskFacets.inProgressCategory)
    }

    func testAnEnterpriseServerIsAskedAtItsOwnAPI() async throws {
        StubProtocol.reset { _ in Answer(body: "[]") }
        let fetch = await reader.fetch(enterprise, includePullRequests: false)
        XCTAssertEqual(fetch.outcome, .fetched(RemoteFetch(issues: [], complete: true)))
        let request = try XCTUnwrap(StubProtocol.requests().first)
        XCTAssertEqual(request.url?.host, "ghe.acme.com")
        XCTAssertEqual(request.url?.port, 8443)
        XCTAssertEqual(request.url?.path, "/api/v3/issues")
    }

    func testARefusedTokenFailsTheSync() async throws {
        StubProtocol.reset { _ in Answer(status: 401, body: #"{"message":"Bad credentials"}"#) }
        let fetch = await reader.fetch(dotCom, includePullRequests: true)
        XCTAssertEqual(fetch.outcome, .failed)
        XCTAssertEqual(fetch.failure, .http(.auth(401)))
        XCTAssertEqual(GitHubAPI.syncState(for: fetch.failure, now: now), .authFailed(status: 401))
        XCTAssertEqual(StubProtocol.requests().count, 1, "nothing more is asked after a failure")
    }

    func testAFailedSecondPageFailsTheWholeSync() async throws {
        StubProtocol.reset { request in
            Self.pageNumber(request) == "1"
                ? Answer(headers: ["Link": Self.nextLink], body: Self.page((1...100).map { Self.item($0) }))
                : Answer(status: 502, body: "{}")
        }
        let fetch = await reader.fetch(dotCom, includePullRequests: false)
        XCTAssertEqual(fetch.outcome, .failed, "the first page is not used")
        XCTAssertEqual(fetch.failure, .http(.ambiguous(502)))
    }

    func testAnExhaustedQuotaThroughTheSession() async throws {
        let reset = Int(Date().timeIntervalSince1970) + 120
        StubProtocol.reset { _ in
            Answer(status: 403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": String(reset)],
                   body: #"{"message":"API rate limit exceeded for user ID 1."}"#)
        }
        let fetch = await reader.fetch(dotCom, includePullRequests: false)
        guard case .http(.rateLimited(let wait))? = fetch.failure else { return XCTFail("\(String(describing: fetch.failure))") }
        XCTAssertTrue((100...121).contains(wait), "the Unix time GitHub gave, as a wait: \(wait)")

        StubProtocol.reset { _ in Answer(status: 403, headers: ["x-ratelimit-remaining": "4999"], body: #"{"message":"Resource protected by organization SAML enforcement."}"#) }
        let refused = await reader.fetch(dotCom, includePullRequests: false)
        XCTAssertEqual(refused.failure, .http(.rejected(403)))
    }

    func testAnAnswerThatIsNotAListFailsTheSync() async throws {
        StubProtocol.reset { _ in Answer(body: #"{"message":"weird"}"#) }
        let fetch = await reader.fetch(dotCom, includePullRequests: false)
        XCTAssertEqual(fetch.outcome, .failed)
        XCTAssertEqual(fetch.failure, .decode)
    }

    func testVerifyReadsTheUser() async throws {
        StubProtocol.reset { _ in Answer(body: #"{"login": "dana", "id": 1, "name": "Dana Example"}"#) }
        let result = await reader.verify(dotCom)
        XCTAssertEqual(result, .verified(GitHubUser(login: "dana", name: "Dana Example")))
        XCTAssertEqual(StubProtocol.requests().map { $0.url?.absoluteString }, ["https://api.github.com/user"])

        StubProtocol.reset { _ in Answer(status: 401, body: #"{"message":"Bad credentials"}"#) }
        let refused = await reader.verify(dotCom)
        XCTAssertEqual(refused, .failed(.http(.auth(401))))
    }

    func testARedirectNeverCarriesTheToken() async throws {
        StubProtocol.reset { request in
            request.url?.host == "api.github.com"
                ? Answer(status: 302, headers: ["Location": "https://evil.example/collect"], body: "")
                : Answer(body: #"{"login": "dana"}"#)
        }
        let result = await reader.verify(dotCom)
        XCTAssertEqual(result, .failed(.http(.redirected(302))))
        XCTAssertEqual(StubProtocol.requests().compactMap(\.url?.host), ["api.github.com"], "the redirect target was never asked")
    }

    func testNoRequestLeavesForAServerOrTokenKannuWouldNotUse() async throws {
        StubProtocol.reset { _ in Answer(body: #"{"login": "dana"}"#) }
        let plain = GitHubCredential(baseURL: "http://github.com", token: Self.token)
        let verified = await reader.verify(plain)
        let fetched = await reader.fetch(plain, includePullRequests: true)
        let badToken = await reader.fetch(GitHubCredential(baseURL: "https://github.com", token: "FAKE TOKEN"), includePullRequests: true)
        XCTAssertEqual(verified, .failed(.badServer))
        XCTAssertEqual(fetched.failure, .badServer)
        XCTAssertEqual(badToken.failure, .badServer)
        XCTAssertTrue(StubProtocol.requests().isEmpty)
    }
}
