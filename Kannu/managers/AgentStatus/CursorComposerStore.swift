import Foundation
import SQLite3

struct ComposerMeta: Equatable {
    let composerID: String
    let status: String?
    let updatedMs: Int64
    let checkpointMs: Int64
    let createdMs: Int64
    let name: String?

    /// This record, with anything it lacks taken from `header`. Status and activity stay this
    /// record's own: a 3.19 header has no status, and its `lastUpdatedAt` can move with no agent
    /// activity (Cursor 3.19.19, read-only: 1 of the 25 newest chats had a header 178 s newer than
    /// its `composerData`; letting that header win dropped the chat's status).
    func filling(from header: ComposerMeta) -> ComposerMeta {
        ComposerMeta(
            composerID: composerID,
            status: status ?? header.status,
            updatedMs: updatedMs > 0 ? updatedMs : header.updatedMs,
            checkpointMs: checkpointMs > 0 ? checkpointMs : header.checkpointMs,
            createdMs: createdMs > 0 ? createdMs : header.createdMs,
            name: name ?? header.name
        )
    }
}

/// The composer headers read in the last few seconds, keyed by the ids asked for. One rescan asks
/// for several different id sets (transcript ids, chat-title ids, one id for a hook session's
/// backing), so a miss adds the missing ids to the cache instead of replacing it; everything
/// expires together when the TTL runs out.
struct ComposerHeaderCache {
    let ttl: TimeInterval
    private(set) var headers: [String: ComposerMeta] = [:]
    /// Every id read since `filledAt`, found or not: an id with no header is not re-read either.
    private(set) var readIDs: Set<String> = []
    private(set) var filledAt: Date?

    init(ttl: TimeInterval) { self.ttl = ttl }

    mutating func headers(
        forIDs ids: Set<String>,
        now: Date,
        load: (Set<String>) -> [String: ComposerMeta]
    ) -> [String: ComposerMeta] {
        if let filledAt, now.timeIntervalSince(filledAt) < ttl {
            let missing = ids.subtracting(readIDs)
            if !missing.isEmpty {
                headers.merge(load(missing)) { _, fresh in fresh }
                readIDs.formUnion(missing)
            }
        } else {
            headers = load(ids)
            readIDs = ids
            filledAt = now
        }
        return headers.filter { ids.contains($0.key) }
    }
}

// Main-actor isolated: the static caches below are unguarded mutable state, and every
// caller today is the @MainActor monitor. The annotation turns any future off-main call
// into a compile error instead of a data race.
@MainActor
enum CursorComposerStore {
    private static let globalDBPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
            .path
    }()

    private static let workspaceStorageRoot: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage", isDirectory: true)
    }()

    private static var headersCache = ComposerHeaderCache(ttl: 3.0)

    private static let planRegistryCacheTTL: TimeInterval = 10.0
    private static var cachedPlanNames: Set<String> = []
    private static var cachedPlanNamesAt: Date?

    static func loadPlanRegistryNames() -> Set<String> {
        let now = Date()
        if let cachedPlanNamesAt, now.timeIntervalSince(cachedPlanNamesAt) < planRegistryCacheTTL {
            return cachedPlanNames
        }
        let fresh = loadPlanRegistryNamesFromDB()
        cachedPlanNames = fresh
        cachedPlanNamesAt = now
        return fresh
    }

    static func loadComposerMeta(
        forIDs ids: Set<String>,
        includeWorkspaceDatabases: Bool = false
    ) -> [String: ComposerMeta] {
        guard !ids.isEmpty else { return [:] }

        var merged = combine(
            composerData: loadComposerDataFromDiskKV(forIDs: ids),
            headers: headersCache.headers(forIDs: ids, now: Date()) {
                loadComposerHeaders(atPath: globalDBPath, forIDs: $0)
            }
        )

        if includeWorkspaceDatabases {
            for meta in loadFromDatabase(path: globalDBPath) where ids.contains(meta.composerID) {
                mergeMeta(&merged, meta)
            }

            if let workspaceDirs = try? FileManager.default.contentsOfDirectory(
                at: workspaceStorageRoot,
                includingPropertiesForKeys: nil
            ) {
                for dir in workspaceDirs where dir.hasDirectoryPath {
                    let dbPath = dir.appendingPathComponent("state.vscdb").path
                    for meta in loadFromDatabase(path: dbPath) where ids.contains(meta.composerID) {
                        mergeMeta(&merged, meta)
                    }
                }
            }
        }

        return filter(merged, ids: ids)
    }

    /// `composerData` is the record of a conversation: its status and activity time win. A header
    /// fills only what that record lacks (the name, mostly), and stands in for a conversation that
    /// has no `composerData` at all, so it still has a name and a backing record.
    nonisolated static func combine(
        composerData: [ComposerMeta],
        headers: [String: ComposerMeta]
    ) -> [String: ComposerMeta] {
        var merged: [String: ComposerMeta] = [:]
        for meta in composerData {
            mergeMeta(&merged, meta)
        }
        for (id, header) in headers {
            merged[id] = merged[id].map { $0.filling(from: header) } ?? header
        }
        return merged
    }

    private static func filter(_ merged: [String: ComposerMeta], ids: Set<String>) -> [String: ComposerMeta] {
        merged.filter { ids.contains($0.key) }
    }

    private nonisolated static func mergeMeta(_ merged: inout [String: ComposerMeta], _ meta: ComposerMeta) {
        if let existing = merged[meta.composerID] {
            if meta.updatedMs >= existing.updatedMs {
                merged[meta.composerID] = meta
            }
        } else {
            merged[meta.composerID] = meta
        }
    }

    private static func loadComposerDataFromDiskKV(forIDs ids: Set<String>) -> [ComposerMeta] {
        guard !ids.isEmpty, FileManager.default.fileExists(atPath: globalDBPath) else { return [] }

        var db: OpaquePointer?
        guard sqlite3_open_v2(globalDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return [] }
        defer { sqlite3_close(db) }

        var results: [ComposerMeta] = []
        for id in ids {
            let key = "composerData:\(id)"
            var stmt: OpaquePointer?
            let sql = "SELECT value FROM cursorDiskKV WHERE key = ?"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { continue }
            defer { sqlite3_finalize(stmt) }

            _ = key.withCString { cKey in
                sqlite3_bind_text(stmt, 1, cKey, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }

            guard sqlite3_step(stmt) == SQLITE_ROW, let valueText = sqlite3_column_text(stmt, 0) else { continue }
            let jsonString = String(cString: valueText)
            if let meta = parseDiskKVComposerData(composerID: id, jsonString: jsonString) {
                results.append(meta)
            }
        }
        return results
    }

    private static func parseDiskKVComposerData(composerID: String, jsonString: String) -> ComposerMeta? {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let checkpoint = int64(from: dict["conversationCheckpointLastUpdatedAt"])
        let updated = max(int64(from: dict["lastUpdatedAt"]), checkpoint)
        return ComposerMeta(
            composerID: composerID,
            status: dict["status"] as? String,
            updatedMs: updated,
            checkpointMs: checkpoint,
            createdMs: int64(from: dict["createdAt"]),
            name: dict["name"] as? String
        )
    }

    private static func loadPlanRegistryNamesFromDB() -> Set<String> {
        guard FileManager.default.fileExists(atPath: globalDBPath) else { return [] }

        var db: OpaquePointer?
        guard sqlite3_open_v2(globalDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return [] }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key='composer.planRegistry'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW, let valueText = sqlite3_column_text(stmt, 0) else {
            return []
        }

        let jsonString = String(cString: valueText)
        guard let data = jsonString.data(using: .utf8),
              let registry = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var names: Set<String> = []
        for entry in registry.values {
            guard let dict = entry as? [String: Any],
                  let name = dict["name"] as? String else { continue }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                names.insert(trimmed)
            }
        }
        return names
    }

    /// Composer headers (name, timestamps) for `ids` from one `state.vscdb`.
    ///
    /// Cursor 3.x keeps one row per composer in a `composerHeaders` table; on Cursor 3.19.19 the
    /// table is populated and the old `ItemTable` key `composer.composerHeaders` has no row at all,
    /// so reading only the key lost every header name and timestamp. Earlier versions kept every
    /// header in that key's `allComposers` array, which is still read when the table is absent, and
    /// for any id the table does not hold, so a half-migrated profile keeps its names.
    ///
    /// The table is read by primary key, one row per requested id — never scanned: the global
    /// database runs to gigabytes and Cursor holds it open.
    static func loadComposerHeaders(atPath path: String, forIDs ids: Set<String>) -> [String: ComposerMeta] {
        guard !ids.isEmpty, FileManager.default.fileExists(atPath: path) else { return [:] }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return [:] }
        defer { sqlite3_close(db) }

        var results = hasComposerHeadersTable(db) ? loadComposerHeaderRows(db, forIDs: ids) : [:]
        let unresolved = ids.subtracting(results.keys)
        guard !unresolved.isEmpty else { return results }
        for (id, meta) in loadLegacyComposerHeaders(db) where unresolved.contains(id) {
            results[id] = meta
        }
        return results
    }

    private static func hasComposerHeadersTable(_ db: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'composerHeaders' LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    /// One primary-key lookup per id. The timestamp columns mirror the same keys inside `value`
    /// (milliseconds); the name and status exist only inside `value`.
    private static func loadComposerHeaderRows(_ db: OpaquePointer, forIDs ids: Set<String>) -> [String: ComposerMeta] {
        var stmt: OpaquePointer?
        let sql = "SELECT lastUpdatedAt, checkpointAt, createdAt, value FROM composerHeaders WHERE composerId = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [:] }
        defer { sqlite3_finalize(stmt) }

        var results: [String: ComposerMeta] = [:]
        for id in ids {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            _ = id.withCString { cID in
                sqlite3_bind_text(stmt, 1, cID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard sqlite3_step(stmt) == SQLITE_ROW else { continue }

            var value: [String: Any] = [:]
            if let valueText = sqlite3_column_text(stmt, 3),
               let data = String(cString: valueText).data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                value = dict
            }
            let checkpoint = max(sqlite3_column_int64(stmt, 1), int64(from: value["conversationCheckpointLastUpdatedAt"]))
            let updated = max(sqlite3_column_int64(stmt, 0), int64(from: value["lastUpdatedAt"]), checkpoint)
            let createdColumn = sqlite3_column_int64(stmt, 2)
            results[id] = ComposerMeta(
                composerID: id,
                status: value["status"] as? String,
                updatedMs: updated,
                checkpointMs: checkpoint,
                createdMs: createdColumn > 0 ? createdColumn : int64(from: value["createdAt"]),
                name: value["name"] as? String
            )
        }
        return results
    }

    /// The pre-table layout: every header in one JSON array under one `ItemTable` key.
    private static func loadLegacyComposerHeaders(_ db: OpaquePointer) -> [String: ComposerMeta] {
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key='composer.composerHeaders'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [:] }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW, let valueText = sqlite3_column_text(stmt, 0) else {
            return [:]
        }

        let jsonString = String(cString: valueText)
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let composers = root["allComposers"] as? [[String: Any]] else {
            return [:]
        }

        var results: [String: ComposerMeta] = [:]
        for entry in composers {
            guard let meta = parseComposerHeaderEntry(entry) else { continue }
            results[meta.composerID] = meta
        }
        return results
    }

    private static func parseComposerHeaderEntry(_ dict: [String: Any]) -> ComposerMeta? {
        guard let id = dict["composerId"] as? String, !id.isEmpty else { return nil }
        let checkpoint = int64(from: dict["conversationCheckpointLastUpdatedAt"])
        let updated = max(int64(from: dict["lastUpdatedAt"]), checkpoint)
        return ComposerMeta(
            composerID: id,
            status: dict["status"] as? String,
            updatedMs: updated,
            checkpointMs: checkpoint,
            createdMs: int64(from: dict["createdAt"]),
            name: dict["name"] as? String
        )
    }

    private static func loadFromDatabase(path: String) -> [ComposerMeta] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else { return [] }
        defer { sqlite3_close(db) }

        var results: [ComposerMeta] = []
        // Narrow key filter — avoid loading every composer-related blob.
        let sql = """
        SELECT key, value FROM ItemTable
        WHERE key = 'composer.composerHeaders'
           OR key LIKE 'composerData:%'
        LIMIT 200
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let valueText = sqlite3_column_text(stmt, 1) else { continue }
            let jsonString = String(cString: valueText)
            results.append(contentsOf: parseComposerJSON(jsonString))
        }

        return results
    }

    private static func parseComposerJSON(_ jsonString: String) -> [ComposerMeta] {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let array = root as? [[String: Any]] {
            return array.compactMap(parseComposerEntry)
        }

        if let dict = root as? [String: Any] {
            if let allComposers = dict["allComposers"] as? [[String: Any]] {
                return allComposers.compactMap(parseComposerEntry)
            }
            if let composerID = dict["composerId"] as? String ?? dict["composerID"] as? String {
                if let entry = parseComposerEntry(dict) {
                    return [entry]
                }
                return [ComposerMeta(
                    composerID: composerID,
                    status: dict["status"] as? String,
                    updatedMs: int64(from: dict["lastUpdatedAt"] ?? dict["updatedAt"] ?? dict["updated_ms"]),
                    checkpointMs: int64(from: dict["checkpointMs"] ?? dict["checkpoint_ms"]),
                    createdMs: int64(from: dict["createdAt"] ?? dict["created_ms"]),
                    name: dict["name"] as? String
                )]
            }
        }

        return []
    }

    private static func parseComposerEntry(_ dict: [String: Any]) -> ComposerMeta? {
        let id = (dict["composerId"] as? String)
            ?? (dict["composerID"] as? String)
            ?? (dict["id"] as? String)
        guard let id, !id.isEmpty else { return nil }

        return ComposerMeta(
            composerID: id,
            status: dict["status"] as? String ?? dict["composerStatus"] as? String,
            updatedMs: int64(from: dict["lastUpdatedAt"] ?? dict["updatedAt"] ?? dict["updated_ms"]),
            checkpointMs: int64(from: dict["checkpointMs"] ?? dict["checkpoint_ms"]),
            createdMs: int64(from: dict["createdAt"] ?? dict["created_ms"]),
            name: dict["name"] as? String
        )
    }

    private static func int64(from value: Any?) -> Int64 {
        switch value {
        case let number as NSNumber:
            return number.int64Value
        case let string as String:
            return Int64(string) ?? 0
        default:
            return 0
        }
    }
}
