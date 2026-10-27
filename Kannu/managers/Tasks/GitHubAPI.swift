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

/// The GitHub sign-in: the server it belongs to and a personal access token. Stored as one JSON item
/// in the Keychain, never in Defaults, so the token and the server it may be sent to cannot be
/// separated: a plist edit cannot point the token at another server.
///
/// It never prints its token: not in `print`, string interpolation, `dump` or the debugger's
/// summary, so a stray log line cannot leak it.
struct GitHubCredential: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// `GitHubHost.normalize`'s form: `https://github.com`, `https://ghe.acme.com:8443`. The web
    /// address, not the API's: `GitHubHost.apiURL` works that out.
    var baseURL: String
    var token: String

    var description: String { "GitHubCredential(baseURL: \(baseURL), token: <redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["baseURL": baseURL]) }

    /// The Keychain form: compact JSON with sorted keys.
    func encoded() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decoded(_ text: String) -> GitHubCredential? {
        try? JSONDecoder().decode(GitHubCredential.self, from: Data(text.utf8))
    }
}

extension GitHubCredential: StoredCredential {}

/// Why a typed GitHub server was refused.
enum GitHubHostError: Error, Equatable {
    case empty
    /// A scheme other than https.
    case notHTTPS
    /// A user name or password before the host (`a@evil.com`).
    case userInfo
    /// A `?query` or `#fragment`: a server's address has neither.
    case queryOrFragment
    /// Any path but the API's own (`/api/v3`, `/api`): GitHub Enterprise Server always sits at the
    /// root of its host, so a path is a page on it, never part of its address.
    case badPath
    /// A port outside 1–65535, or any port but 443 on github.com.
    case port
    /// Not a host name or an IPv4 address: an IPv6 literal, a bad label, a backslash, whitespace,
    /// a control or non-ASCII character.
    case malformed
}

/// The one server a GitHub token may be sent to. Pure, so the logic target tests every rule.
///
/// Either github.com, or a GitHub Enterprise Server on the company network: any HTTPS host, on its
/// own port if it has one. Unlike a self-managed GitLab, GitHub Enterprise Server has no path prefix,
/// so the shape is tighter: HTTPS only, no user name or password, no query, no fragment, no path.
/// TLS is the system's: a certificate macOS does not trust fails the request, and nothing here
/// relaxes that.
///
/// The normalized form is the server's web address, `https://host[:port]`, lowercase host, no
/// trailing slash, no default port. It is what the Keychain item stores. The API lives elsewhere:
/// `api.github.com` for github.com, `<base>/api/v3` for an Enterprise Server (`apiURL`).
enum GitHubHost {
    static let defaultServer = "https://github.com"
    private static let dotComHost = "github.com"
    /// github.com's API host: never a base of its own, but a pasted API address means github.com.
    private static let dotComAPIRoot = "https://api.github.com"

    /// The base URL, or why it was refused. `www.github.com` and `api.github.com` are github.com, and
    /// a pasted `…/api/v3` (or `…/api`) is the server too.
    static func normalize(_ input: String) -> Result<String, GitHubHostError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        // Printable ASCII only, with no space and no backslash: a homoglyph, a control character
        // or a backslash is how a look-alike gets past one parser and not another.
        guard trimmed.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }),
              !trimmed.contains("\\") else { return .failure(.malformed) }

        let text: String
        if let schemeEnd = trimmed.range(of: "://") {
            guard trimmed[..<schemeEnd.lowerBound].lowercased() == "https" else { return .failure(.notHTTPS) }
            text = trimmed
        } else {
            // Without "://", a colon can only start a port ("ghe.acme.com:8443"). Anything else is a
            // scheme typed without its slashes ("http:/github…"), which would otherwise read as a host.
            if let colon = trimmed.firstIndex(of: ":") {
                let afterColon = trimmed[trimmed.index(after: colon)...].prefix { $0 != "/" }
                guard !afterColon.isEmpty, afterColon.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) else {
                    return .failure(.malformed)
                }
            }
            text = "https://" + trimmed
        }
        guard !text.contains("?"), !text.contains("#") else { return .failure(.queryOrFragment) }
        let afterScheme = text.range(of: "://").map { text[$0.upperBound...] } ?? Substring(text)
        let authority = afterScheme.prefix { $0 != "/" }
        // Any "@" in the authority, even an empty user name: parsers disagree about these, and a
        // server never needs one.
        guard !authority.contains("@") else { return .failure(.userInfo) }
        guard !authority.contains("["), !authority.contains("]") else { return .failure(.malformed) }
        guard let components = URLComponents(string: text) else { return .failure(.malformed) }
        guard components.user == nil, components.password == nil else { return .failure(.userInfo) }
        guard var host = components.host?.lowercased(), GitLabHost.isValidHostName(host) else { return .failure(.malformed) }
        if host == "www." + dotComHost || host == "api." + dotComHost { host = dotComHost }
        var port: Int?
        if let typed = components.port {
            guard (1...65535).contains(typed) else { return .failure(.port) }
            port = typed == 443 ? nil : typed
        }
        // github.com answers on 443 only: another port is a typo, or another server posing as it.
        if host == dotComHost, port != nil { return .failure(.port) }

        let path = components.percentEncodedPath
        guard !path.contains("%") else { return .failure(.badPath) }
        var segments = path.split(separator: "/", omittingEmptySubsequences: false)
        // "https://host/" and "https://host/api/v3/": the slashes around the path carry nothing.
        if segments.first == "" { segments.removeFirst() }
        while segments.last == "" { segments.removeLast() }
        let lowered = segments.map { $0.lowercased() }
        guard lowered.isEmpty || lowered == ["api", "v3"] || lowered == ["api"] else { return .failure(.badPath) }

        var base = "https://" + host
        if let port { base += ":\(port)" }
        return .success(base)
    }

    /// Exactly a base URL `normalize` returns. Checked again before every URL is built, so a value
    /// that reached the Keychain some other way still cannot be used.
    static func isValidBase(_ base: String) -> Bool {
        normalize(base) == .success(base)
    }

    /// Where the REST API lives for this server: `https://api.github.com` for github.com,
    /// `<base>/api/v3` for an Enterprise Server. Nil when the base is not one `normalize` returns.
    static func apiRoot(base: String) -> String? {
        guard isValidBase(base) else { return nil }
        return base == defaultServer ? dotComAPIRoot : base + "/api/v3"
    }

    /// `<API root><path>?<query>`, or nil when the base is not one `normalize` returns or the path
    /// is not a plain absolute path. The query is built here, from Kannu's own values, never copied
    /// from an answer.
    static func apiURL(base: String, path: String, query: [URLQueryItem] = []) -> URL? {
        guard let root = apiRoot(base: base), path.hasPrefix("/"), !path.contains("?"), !path.contains("#"),
              !path.contains(".."), !path.contains("//"), !path.contains("\\"), !path.contains("%"),
              var components = URLComponents(string: root + path) else { return nil }
        if !query.isEmpty { components.queryItems = query }
        return components.url
    }

    /// The server as the Sources row names it: `github.com`, `ghe.acme.com:8443`.
    static func displayName(_ base: String) -> String {
        base.hasPrefix("https://") ? String(base.dropFirst("https://".count)) : base
    }

    /// Where the user makes a personal access token on this server.
    static func createTokenURL(base: String) -> URL? {
        guard isValidBase(base) else { return nil }
        return URL(string: base + "/settings/tokens")
    }

    /// Whether a link from an answer (an item's `html_url`) points at this server: https, the same
    /// host and port, a page under it, no user name or password. On github.com that is
    /// `https://github.com/…` only: not `www.`, not the API host. Anything else is never opened, so
    /// an answer cannot send the user somewhere else.
    static func isWebURL(_ text: String, onServer base: String) -> Bool {
        guard isValidBase(base), let server = URLComponents(string: base),
              text.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }), !text.contains("\\"),
              let link = URLComponents(string: text), link.scheme?.lowercased() == "https",
              link.user == nil, link.password == nil,
              let host = link.host?.lowercased(), host == server.host,
              (link.port == 443 ? nil : link.port) == server.port else { return false }
        let path = link.percentEncodedPath
        return path.hasPrefix("/") && path.count > 1 && !path.contains("/../") && !path.hasSuffix("/..")
    }
}

/// `GET /user`: who the token belongs to. Only what Kannu shows.
struct GitHubUser: Decodable, Equatable {
    let login: String
    let name: String?
}

/// One item from `GET /issues`: an issue, or a pull request, which GitHub lists as an issue with a
/// `pull_request` object. Only the fields Kannu keeps.
struct GitHubItem: Decodable, Equatable {
    /// The global id: unique on the server, shared by issues and pull requests.
    let id: Int
    /// The number within its repository (`#7`), shared by issues and pull requests.
    let number: Int
    let title: String?
    /// "open" or "closed".
    let state: String?
    let htmlURL: String?
    /// The label names. Read leniently: another shape costs the labels, never the item.
    let labels: Labels?
    /// Present, whatever it holds, only on a pull request.
    let pullRequest: Presence?
    // The rest is read leniently, each on its own: a field in a shape this version does not
    // expect costs that field, never the item (and so never the page).
    /// `owner/repo`: present in `/issues` answers.
    let repository: LenientField<Repository>?
    /// `<API root>/repos/<owner>/<repo>`: where the repository is named when `repository` is not.
    let repositoryURL: LenientField<String>?
    let assignee: LenientField<Person>?
    let assignees: Assignees?
    let milestone: LenientField<Milestone>?
    let comments: LenientField<Int>?
    let updatedAt: LenientField<String>?
    /// Pull requests only.
    let draft: LenientField<Bool>?
    /// Who opened it.
    let user: LenientField<Person>?

    var isPullRequest: Bool { pullRequest != nil }

    /// A value that is there: any JSON but null. What `pull_request` holds does not matter, only
    /// that GitHub sent it.
    struct Presence: Decodable, Equatable {
        init(from decoder: Decoder) throws {}
    }

    struct Person: Decodable, Equatable {
        let login: String?
    }

    struct Milestone: Decodable, Equatable {
        let title: String?
    }

    struct Repository: Decodable, Equatable {
        let fullName: String?

        private enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
        }
    }

    /// GitHub sends labels as objects (`{"name": "bug", …}`), and documents plain strings too.
    struct Labels: Decodable, Equatable {
        let names: [String]

        init(from decoder: Decoder) throws {
            let entries = (try? decoder.singleValueContainer().decode([Label].self)) ?? []
            names = entries.compactMap(\.name)
        }

        /// One label, never failing: a string, an object with a name, or nothing usable.
        private struct Label: Decodable {
            let name: String?

            private enum CodingKeys: String, CodingKey {
                case name
            }

            init(from decoder: Decoder) throws {
                if let text = try? decoder.singleValueContainer().decode(String.self) {
                    name = text
                } else {
                    name = (try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .name)) ?? nil
                }
            }
        }
    }

    /// The people assigned, logins only. Read leniently, like the labels.
    struct Assignees: Decodable, Equatable {
        let logins: [String]

        init(from decoder: Decoder) throws {
            let people = (try? decoder.singleValueContainer().decode([LenientField<Person>].self)) ?? []
            logins = people.compactMap { $0.value?.login }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, title, state, labels, repository, assignee, assignees, milestone, comments, draft, user
        case htmlURL = "html_url"
        case pullRequest = "pull_request"
        case repositoryURL = "repository_url"
        case updatedAt = "updated_at"
    }
}

/// Building GitHub requests and reading their answers. Pure: nothing here sends anything, so the
/// logic target checks every header and URL.
///
/// The token travels only in the `Authorization` header, and only to the server in the credential
/// (`GitHubHost.apiURL` refuses any other). It is never put in a URL, so it cannot end up in a log, a
/// cache key or a proxy's access log. Every query is built here from Kannu's own values; a URL from
/// an answer (a `Link` header) is never followed: it only says whether there is a next page, and
/// Kannu asks for that page by number itself.
enum GitHubAPI {
    static let pageSize = 100
    /// At most two pages: two requests per sync, far below GitHub's 5,000 an hour. A bigger result
    /// is reported as incomplete, never silently cut.
    static let maxPages = 2
    static let apiVersion = "2022-11-28"
    static let linkHeader = "Link"

    /// A personal access token as it can travel in a header: printable ASCII, no spaces, at most
    /// 255 characters (GitHub's own ceiling).
    static func isPlausibleToken(_ token: String) -> Bool {
        !token.isEmpty && token.count <= 255 && token.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value < 0x7F }
    }

    /// `owner/repo`: two plain segments of letters, digits, `-`, `_` and `.`, never `.` or `..`.
    /// Checked before it becomes a key, so an answer cannot put a path or a line break in one.
    static func isRepositoryName(_ name: String) -> Bool {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { part in
            guard (1...100).contains(part.count), part != ".", part != ".." else { return false }
            return part.unicodeScalars.allSatisfy { scalar in
                (65...90).contains(scalar.value) || (97...122).contains(scalar.value) || (48...57).contains(scalar.value)
                    || scalar == "-" || scalar == "_" || scalar == "."
            }
        }
    }

    // MARK: - Requests

    /// `GET /user`: whose token it is.
    static func userRequest(_ credential: GitHubCredential) -> URLRequest? {
        GitHubHost.apiURL(base: credential.baseURL, path: "/user").flatMap { request(url: $0, credential: credential) }
    }

    /// `GET /issues?filter=assigned&state=open`: the open issues and pull requests assigned to the
    /// user across every repository the token can see, most recently updated first. Nil for a page
    /// Kannu never reads, or a server it would not send to.
    static func issuesRequest(_ credential: GitHubCredential, page: Int) -> URLRequest? {
        guard (1...maxPages).contains(page) else { return nil }
        let query = [
            URLQueryItem(name: "filter", value: "assigned"),
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "per_page", value: String(pageSize)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        return GitHubHost.apiURL(base: credential.baseURL, path: "/issues", query: query).flatMap { request(url: $0, credential: credential) }
    }

    /// Nil for a token that could not travel in a header: one read from the Keychain is checked
    /// again, so it can never add a header line of its own.
    private static func request(url: URL, credential: GitHubCredential) -> URLRequest? {
        guard isPlausibleToken(credential.token) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: IntegrationHTTP.timeout)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub refuses a request without one.
        request.setValue("Kannu", forHTTPHeaderField: "User-Agent")
        return request
    }

    // MARK: - Answers

    static func decodeUser(_ data: Data) -> GitHubUser? {
        try? JSONDecoder().decode(GitHubUser.self, from: data)
    }

    static func decodeItems(_ data: Data) -> [GitHubItem]? {
        try? JSONDecoder().decode([GitHubItem].self, from: data)
    }

    /// What an answer means, with GitHub's rate limits read from its own headers. GitHub refuses an
    /// exhausted quota with a 403 as often as a 429, so a 403 alone would read as "the token lacks
    /// access" and send the user to reconnect for nothing:
    ///
    /// - a 403 or 429 with `x-ratelimit-remaining: 0` waits until `x-ratelimit-reset` (Unix seconds);
    /// - one with `Retry-After` (a secondary limit) waits that long, which wins over the reset;
    /// - a 403 whose message says "rate limit" with neither header waits the default minute.
    ///
    /// Every wait is clamped like any other (`HTTPOutcome.rateLimitWait`). Anything else is the
    /// exchange's own outcome.
    static func outcome(_ exchange: HTTPExchange, now: Date) -> HTTPOutcome {
        guard let response = exchange.response, response.statusCode == 403 || response.statusCode == 429 else {
            return exchange.outcome
        }
        let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining")?.trimmingCharacters(in: .whitespaces)
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
        let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset")
        if remaining == "0" || retryAfter != nil {
            return .rateLimited(retryAfter: HTTPOutcome.rateLimitWait(retryAfter: retryAfter, rateLimitReset: remaining == "0" ? reset : nil, now: now))
        }
        if response.statusCode == 403, mentionsRateLimit(exchange.data) {
            return .rateLimited(retryAfter: HTTPOutcome.defaultRetryAfter)
        }
        return exchange.outcome
    }

    /// Whether GitHub's `message` says a rate limit refused the request.
    private static func mentionsRateLimit(_ data: Data?) -> Bool {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String else { return false }
        return message.lowercased().contains("rate limit")
    }

    enum PageStep: Equatable {
        /// Fetch this page.
        case next(Int)
        /// No more pages. `complete` is false when GitHub did not say so plainly.
        case done(complete: Bool)
        /// There are more pages, but Kannu has fetched all it will.
        case capped
    }

    /// What follows page `page`, which held `itemCount` items. A short page is the last. A full one
    /// is the last only when a `Link` header came without `rel="next"`: GitHub sends one on every
    /// page of a list longer than a page, so a full page with no `Link` at all may have more behind
    /// it (exactly a page of items, or a proxy that dropped the header), and the next page is asked
    /// for. The link's URL is never read: Kannu builds the next page's request itself.
    static func nextStep(linkHeader: String?, page: Int, itemCount: Int) -> PageStep {
        if itemCount < pageSize { return .done(complete: true) }
        if let linkHeader, !hasNextLink(linkHeader) { return .done(complete: true) }
        return page >= maxPages ? .capped : .next(page + 1)
    }

    /// Whether a `Link` header has a `rel="next"` link. Split on `<`, which a URL cannot hold
    /// unescaped, so a comma inside a URL cannot break a link in two.
    static func hasNextLink(_ header: String) -> Bool {
        header.split(separator: "<").contains { link in
            guard let end = link.firstIndex(of: ">") else { return false }
            return link[link.index(after: end)...].split(separator: ";").contains { parameter in
                let pair = parameter.split(separator: "=", maxSplits: 1)
                guard pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "rel" else { return false }
                let value = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: " ,\"")).lowercased()
                return value.split(separator: " ").contains("next")
            }
        }
    }

    /// The item's repository, `owner/repo`: its `repository.full_name`, else the end of its
    /// `repository_url` when that is on this server's API (`<API root>/repos/<owner>/<repo>`). Nil
    /// when neither names one: such an item has no key, and is left out.
    static func repositoryName(of item: GitHubItem, base: String) -> String? {
        if let fullName = item.repository?.value?.fullName, isRepositoryName(fullName) { return fullName }
        guard let url = item.repositoryURL?.value, let root = GitHubHost.apiRoot(base: base) else { return nil }
        let prefix = root + "/repos/"
        guard url.hasPrefix(prefix) else { return nil }
        let name = String(url.dropFirst(prefix.count))
        return isRepositoryName(name) ? name : nil
    }

    /// An item as a task keeps it, or nil when its repository cannot be named. The key is
    /// `owner/repo#7` for an issue and a pull request alike, as GitHub writes both; an item with no
    /// title is titled by its key. Its page is kept only when it is on `base`. A pull request is In
    /// Progress; an issue is when a label says so.
    static func remoteIssue(from item: GitHubItem, base: String) -> RemoteIssue? {
        guard let repository = repositoryName(of: item, base: base) else { return nil }
        let key = "\(repository)#\(item.number)"
        let labels = TaskFacets.keptLabels(item.labels?.names ?? [])
        let isPullRequest = item.isPullRequest
        let assignee = item.assignee?.value?.login ?? item.assignees?.logins.first
        return RemoteIssue(
            remoteID: String(item.id),
            key: key,
            title: TaskItem.cleanedTitle(item.title ?? "") ?? key,
            status: item.state.flatMap(TaskItem.cleanedTitle) ?? "",
            isDoneRemotely: item.state == "closed",
            estimateSeconds: nil,
            spentSeconds: nil,
            webURL: item.htmlURL.flatMap { GitHubHost.isWebURL($0, onServer: base) ? $0 : nil },
            statusCategory: isPullRequest ? TaskFacets.inProgressCategory : TaskFacets.labelCategory(labels),
            labels: labels,
            milestone: item.milestone?.value?.title.flatMap(TaskItem.cleanedTitle),
            assignee: assignee.flatMap(TaskItem.cleanedTitle),
            updatedAt: RemoteTaskInfo.serverTimestamp(item.updatedAt?.value),
            commentCount: item.comments?.value,
            isDraft: isPullRequest ? item.draft?.value : nil,
            author: isPullRequest ? item.user?.value?.login.flatMap(TaskItem.cleanedTitle) : nil
        )
    }

    // MARK: - Messages

    /// Where a failed sync leaves the source, in the words GitHub's page shows.
    static func syncState(for failure: GitHubReader.Failure?, now: Date) -> SourceSyncState {
        switch failure {
        case .http(.offline):
            return .offline
        case .http(.rateLimited(let seconds)):
            return .rateLimited(until: now.addingTimeInterval(seconds))
        case .http(.auth(let status)):
            return .authFailed(status: status)
        case .http(.rejected(403)):
            return .failed(String(localized: "GitHub refused the request (403). The token may lack read access to issues, or need SSO authorisation for your organisation."))
        case .http(.rejected(let status)):
            return .failed(String(localized: "GitHub refused the request (\(status))."))
        case .http(.redirected(let status)):
            return .failed(String(localized: "The server answered with a redirect (\(status)), which Kannu never follows."))
        case .http(.failedBeforeSend):
            return .failed(String(localized: "Kannu could not reach the GitHub server over a trusted HTTPS connection. Check your connection."))
        case .http(.ambiguous(let status?)):
            return .failed(String(localized: "GitHub did not answer properly (\(status)). Try again later."))
        case .http(.ambiguous(nil)), .http(.ok):
            return .failed(String(localized: "GitHub did not answer in time. Try again later."))
        case .decode:
            return .failed(String(localized: "GitHub's answer could not be read."))
        case .badServer, nil:
            return .needsReconnect
        }
    }

    /// Why a typed server was refused, for the Connect sheet.
    static func message(for error: GitHubHostError) -> String {
        switch error {
        case .empty:
            return String(localized: "Type your GitHub server: github.com, or your GitHub Enterprise Server, such as https://github.example.com.")
        case .notHTTPS:
            return String(localized: "Kannu connects to GitHub over HTTPS only.")
        case .userInfo:
            return String(localized: "The server has a name and @ before the host. Type just the server, such as https://github.example.com.")
        case .queryOrFragment, .badPath:
            return String(localized: "Type the server's address, not a page on it, such as https://github.com or https://github.example.com.")
        case .port:
            return String(localized: "That port is not a valid one. github.com needs no port.")
        case .malformed:
            return String(localized: "That is not a server address. It looks like https://github.com or https://github.example.com.")
        }
    }

    /// Why Connect's check failed, for the Connect sheet. `server` is `GitHubHost.displayName`.
    static func connectMessage(for failure: GitHubReader.Failure, server: String) -> String {
        switch failure {
        case .badServer:
            return message(for: GitHubHostError.malformed)
        case .decode, .http(.ok):
            return String(localized: "\(server) answered, but not the way GitHub does. Check the server.")
        case .http(.auth(let status)):
            return String(localized: "GitHub did not accept that token (\(status)). It may have expired or been revoked: create a new one.")
        case .http(.rejected(403)):
            return String(localized: "GitHub refused the token (403). It may need SSO authorisation for your organisation, or read access to issues.")
        case .http(.rejected(404)):
            return String(localized: "No GitHub answered at \(server) (404). Check the server.")
        case .http(.rejected(let status)):
            return String(localized: "GitHub refused the request (\(status)).")
        case .http(.redirected(let status)):
            return String(localized: "\(server) answered with a redirect (\(status)), which Kannu never follows. Check the server.")
        case .http(.rateLimited):
            return String(localized: "GitHub is limiting requests right now. Try again in a minute.")
        case .http(.offline):
            return String(localized: "This Mac is offline.")
        case .http(.failedBeforeSend):
            return String(localized: "Kannu could not reach \(server) over a trusted HTTPS connection. Check the server and your connection. A certificate macOS does not trust, such as a self-signed one, is refused.")
        case .http(.ambiguous):
            return String(localized: "GitHub did not answer. Try again.")
        }
    }
}

/// Reading from GitHub over `IntegrationHTTP`: ephemeral, 20 s, no redirects. Read-only: nothing
/// here writes to GitHub. Foundation only, so the logic target runs it against a `URLProtocol` stub;
/// the app wraps it with logging.
struct GitHubReader {
    enum Failure: Error, Equatable {
        /// The credential's server or token is not one Kannu would send a request with.
        case badServer
        case http(HTTPOutcome)
        /// A 2xx whose body was not what GitHub sends.
        case decode
    }

    enum VerifyResult: Equatable {
        case verified(GitHubUser)
        case failed(Failure)
    }

    /// What a sync read: the items, and how many of each kind, for the log line and the caption.
    struct Fetch: Equatable {
        var outcome: SyncOutcome
        var failure: Failure?
        var issueCount = 0
        var pullRequestCount = 0
    }

    let session: URLSession

    init(session: URLSession = IntegrationHTTP.shared) {
        self.session = session
    }

    /// `GET /user`: whether the server accepts this token, and whose it is.
    func verify(_ credential: GitHubCredential) async -> VerifyResult {
        guard let request = GitHubAPI.userRequest(credential) else { return .failed(.badServer) }
        let exchange = await IntegrationHTTP.send(request, session: session)
        let outcome = GitHubAPI.outcome(exchange, now: Date())
        guard case .ok = outcome else { return .failed(.http(outcome)) }
        guard let data = exchange.data, let user = GitHubAPI.decodeUser(data) else { return .failed(.decode) }
        return .verified(user)
    }

    /// The open issues assigned to the user and, with `includePullRequests`, the open pull requests
    /// assigned to them: up to `GitHubAPI.maxPages` pages of one list, which holds both. A pull
    /// request left out still counts toward a full page, so leaving them out never makes a capped
    /// list look complete. Any page that fails fails the whole sync, so a half-read list never marks
    /// the other half gone. An item on both pages (it moved while they were read) counts once.
    func fetch(_ credential: GitHubCredential, includePullRequests: Bool) async -> Fetch {
        let base = credential.baseURL
        var items: [RemoteIssue] = []
        var seen = Set<Int>()
        var issueCount = 0
        var pullRequestCount = 0
        var page = 1
        while true {
            guard let request = GitHubAPI.issuesRequest(credential, page: page) else {
                return Fetch(outcome: .failed, failure: .badServer)
            }
            let exchange = await IntegrationHTTP.send(request, session: session)
            let outcome = GitHubAPI.outcome(exchange, now: Date())
            guard case .ok = outcome else { return Fetch(outcome: .failed, failure: .http(outcome)) }
            guard let data = exchange.data, let read = GitHubAPI.decodeItems(data) else {
                return Fetch(outcome: .failed, failure: .decode)
            }
            for item in read where (includePullRequests || !item.isPullRequest) && seen.insert(item.id).inserted {
                guard let issue = GitHubAPI.remoteIssue(from: item, base: base) else { continue }
                items.append(issue)
                if item.isPullRequest { pullRequestCount += 1 } else { issueCount += 1 }
            }
            let link = exchange.response?.value(forHTTPHeaderField: GitHubAPI.linkHeader)
            let complete: Bool
            switch GitHubAPI.nextStep(linkHeader: link, page: page, itemCount: read.count) {
            case .next(let next):
                page = next
                continue
            case .done(let done):
                complete = done
            case .capped:
                complete = false
            }
            return Fetch(
                outcome: .fetched(RemoteFetch(issues: items, complete: complete)),
                failure: nil,
                issueCount: issueCount,
                pullRequestCount: pullRequestCount
            )
        }
    }
}
