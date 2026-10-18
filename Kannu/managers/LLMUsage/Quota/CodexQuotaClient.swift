import Foundation
import os

// Codex/ChatGPT rate-limit usage from chatgpt.com/backend-api/wham/usage; request+response shape per OpenUsage.
struct CodexQuotaClient {
    private static let log = os.Logger(subsystem: "com.kannu.app", category: "CodexQuota")
    let session: URLSession
    init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    private struct AuthFile: Decodable {
        struct Tokens: Decodable {
            let accessToken: String
            let accountId: String?
        }
        let tokens: Tokens
    }

    private struct RateLimitWindow: Decodable {
        let usedPercent: Double
        let resetAt: Double?
        let resetAfterSeconds: Double?
    }

    private struct RateLimit: Decodable {
        let primaryWindow: RateLimitWindow?
        let secondaryWindow: RateLimitWindow?
    }

    private struct UsageResponse: Decodable {
        let rateLimit: RateLimit?
    }

    // Never throws: any credential/network/parse failure yields (nil, nil).
    /// `interactive` is true only for a refresh the user asked for; only then may the keychain
    /// read show macOS's "allow access" dialog. Automatic refreshes and the background poll read
    /// silently.
    func fetchLimits(interactive: Bool = false) async -> QuotaFetchResult {
        let creds: (accessToken: String, accountId: String?)
        switch loadCredentials(interactive: interactive) {
        case .found(let accessToken, let accountId):
            creds = (accessToken, accountId)
        case .keychainNeedsApproval:
            Self.log.notice("Codex Auth keychain item needs approval; not prompting outside a user-initiated refresh")
            return QuotaFetchResult(
                errorMessage: String(localized: "Codex keeps its sign-in in the keychain. Allow access to show usage limits."),
                action: .grantCodexKeychainAccess
            )
        case .missing:
            Self.log.notice("no credentials: auth.json/Keychain missing or unparseable")
            return QuotaFetchResult(errorMessage: "Codex not signed in", isAuthFailure: true)
        }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Kannu", forHTTPHeaderField: "User-Agent")
        if let accountId = creds.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Self.log.error("wham/usage HTTP \(code) — \(code == 401 || code == 403 ? "auth/credential" : "request") failure")
                let isAuth = code == 401 || code == 403
                // 429 = rate-limited, 500+ = server error — transient, not a configuration problem.
                return QuotaFetchResult(errorMessage: "Codex quota API HTTP \(code)", isAuthFailure: isAuth)
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let now = Date()
            if let decoded = try? decoder.decode(UsageResponse.self, from: data) {
                let sessionLimit = decoded.rateLimit?.primaryWindow.map { limit(from: $0, now: now) }
                let weekLimit = decoded.rateLimit?.secondaryWindow.map { limit(from: $0, now: now) }
                if sessionLimit != nil || weekLimit != nil {
                    return QuotaFetchResult(session: sessionLimit, week: weekLimit, accountTier: Self.planType(fromJWT: creds.accessToken))
                }
            }
            let sessionLimit = headerFallback(http, key: "x-codex-primary-used-percent")
            let weekLimit = headerFallback(http, key: "x-codex-secondary-used-percent")
            if sessionLimit == nil && weekLimit == nil {
                Self.log.error("wham/usage 200 but no usage found — response shape may have changed (\(data.count) bytes)")
                return QuotaFetchResult(errorMessage: "Codex quota response missing usage data")
            }
            return QuotaFetchResult(session: sessionLimit, week: weekLimit, accountTier: Self.planType(fromJWT: creds.accessToken))
        } catch {
            Self.log.error("wham/usage request errored: \(error.localizedDescription, privacy: .public)")
            return QuotaFetchResult(errorMessage: error.localizedDescription)
        }
    }

    private func limit(from window: RateLimitWindow, now: Date) -> UsageLimit {
        let resets = window.resetAt.map { Date(timeIntervalSince1970: $0) } ?? window.resetAfterSeconds.map { now.addingTimeInterval($0) }
        return UsageLimit(used: window.usedPercent, limit: 100, resetsAt: resets)
    }

    private func headerFallback(_ http: HTTPURLResponse, key: String) -> UsageLimit? {
        guard let raw = http.value(forHTTPHeaderField: key), let percent = Double(raw) else { return nil }
        return UsageLimit(used: percent, limit: 100)
    }

    /// ChatGPT plan tier from the access-token JWT claim — no extra network call.
    private static func planType(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["https://api.openai.com/auth"] as? [String: Any],
              let plan = auth["chatgpt_plan_type"] as? String, !plan.isEmpty else { return nil }
        return plan.capitalized
    }

    private enum Credentials {
        case found(accessToken: String, accountId: String?)
        /// The keychain item exists but macOS wants the user to approve the read.
        case keychainNeedsApproval
        case missing
    }

    // auth.json ($CODEX_HOME, ~/.codex, ~/.config/codex), then Keychain "Codex Auth" holding the same JSON payload.
    // Kannu is not on the item's access list, so a read allowed to prompt raised an unasked dialog
    // on every automatic refresh. `KeychainReadPolicy` reads it silently and lets only a
    // user-initiated refresh prompt, once.
    private func loadCredentials(interactive: Bool) -> Credentials {
        for path in authPaths() {
            if let data = try? Data(contentsOf: path), let creds = parseAuth(data) {
                return .found(accessToken: creds.accessToken, accountId: creds.accountId)
            }
        }
        let resolution = KeychainReadPolicy.resolve(interactive: interactive) { allowInteraction in
            let read = KeychainReader.read(service: "Codex Auth", allowInteraction: allowInteraction)
            return .init(value: read.value, needsApproval: KeychainReader.needsUserApproval(read.status))
        }
        if let value = resolution.value, let creds = parseAuth(Data(value.utf8)) {
            return .found(accessToken: creds.accessToken, accountId: creds.accountId)
        }
        return resolution == .needsApproval ? .keychainNeedsApproval : .missing
    }

    private func authPaths() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHome.isEmpty {
            return [URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json")]
        }
        return [
            home.appendingPathComponent(".codex/auth.json"),
            home.appendingPathComponent(".config/codex/auth.json"),
        ]
    }

    private func parseAuth(_ data: Data) -> (accessToken: String, accountId: String?)? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let parsed = try? decoder.decode(AuthFile.self, from: data) else { return nil }
        return (parsed.tokens.accessToken, parsed.tokens.accountId)
    }
}
