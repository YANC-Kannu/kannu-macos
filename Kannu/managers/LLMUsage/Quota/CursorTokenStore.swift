import Foundation
import SQLite3

enum CursorTokenStore {
    private static let keychainService = "cursor-access-token"

    /// Runs `body` with the token read once, up front (`CredentialReadScope`). A refresh used to
    /// read it once per request — the quota guard, usage-summary, the connect fallback, the events
    /// check and every events page, up to a dozen reads — and each read could reach the keychain. A
    /// nested scope reuses the outer read.
    static func withSingleRead<T>(interactive: Bool, _ body: () async throws -> T) async rethrows -> T {
        try await CredentialReadScope.withSingleRead(
            service: keychainService,
            read: { resolveToken(interactive: interactive) },
            body
        )
    }

    static func accessToken() -> String? { resolution().value }

    /// True when no token was found and the cursor-agent keychain item needs the user's approval.
    static func keychainNeedsApproval() -> Bool { resolution() == .needsApproval }

    private static func resolution() -> KeychainReadPolicy.Resolution {
        CredentialReadScope.resolution(service: keychainService) { resolveToken(interactive: false) }
    }

    /// The keychain is read silently; Kannu is not on cursor-agent's access list for the item, so a
    /// prompting read raised an unasked "allow access" dialog on every automatic refresh. A
    /// user-initiated refresh may prompt, and only once state.vscdb has no token either, so the
    /// dialog never appears for something the database answers silently. The keychain stays first
    /// so a cursor-agent token keeps winning over an IDE token, as before; the silent read cannot
    /// show a dialog (`KeychainReader.read`).
    private static func resolveToken(interactive: Bool) -> KeychainReadPolicy.Resolution {
        KeychainReadPolicy.resolve(interactive: interactive, fallback: readTokenFromStateDB) { allowInteraction in
            let read = KeychainReader.read(service: keychainService, allowInteraction: allowInteraction)
            return .init(value: read.value, needsApproval: KeychainReader.needsUserApproval(read.status))
        }
    }

    // Cookie for cursor.com/api/usage: WorkosCursorSessionToken value is "<userId>::<jwt>", userId is the JWT sub.
    static func sessionCookie() -> (userId: String, cookieToken: String)? {
        guard let jwt = accessToken(), let userId = userId(fromJWT: jwt) else { return nil }
        return (userId, "\(userId)::\(jwt)")
    }

    private static func userId(fromJWT jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else { return nil }
        return sub.contains("|") ? String(sub.split(separator: "|").last ?? "") : sub
    }

    private static func readTokenFromStateDB() -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: text)
    }
}
