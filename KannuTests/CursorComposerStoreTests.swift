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

import SQLite3
import XCTest

/// Cursor's composer headers (chat name, timestamps) moved from one `ItemTable` JSON key into a
/// `composerHeaders` table. On Cursor 3.19.19 the table is populated and the key has no row, so a
/// reader of the key alone lost every name. These build a throwaway `state.vscdb` in each layout;
/// the schemas are the ones read from a real Cursor 3.19.19 profile.
@MainActor
final class CursorComposerStoreTests: XCTestCase {
    private var databaseURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kannu-cursor-composer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        databaseURL = dir.appendingPathComponent("state.vscdb")
        try exec("CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent())
    }

    // MARK: - Helpers

    private func exec(_ sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK, let db else { throw NSError(domain: "sqlite", code: 1) }
        defer { sqlite3_close(db) }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "?"
            sqlite3_free(error)
            throw NSError(domain: "sqlite", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func createHeadersTable() throws {
        try exec("""
        CREATE TABLE composerHeaders (composerId TEXT PRIMARY KEY, workspaceId TEXT, createdAt INTEGER,
            lastUpdatedAt INTEGER, isArchived INTEGER, isSubagent INTEGER, recency INTEGER, checkpointAt INTEGER,
            value TEXT, subagentTypeName TEXT);
        CREATE INDEX idx_composerHeaders_0 ON composerHeaders (workspaceId, isSubagent, isArchived, recency);
        CREATE INDEX idx_composerHeaders_1 ON composerHeaders (recency, composerId);
        """)
    }

    private func insertHeaderRow(
        _ id: String,
        name: String,
        created: Int64 = 1_760_000_000_000,
        updated: Int64,
        checkpoint: Int64 = 0,
        value: String? = nil
    ) throws {
        let json = value ?? #"{"type":"head","composerId":"\#(id)","name":"\#(name)","lastUpdatedAt":\#(updated),"conversationCheckpointLastUpdatedAt":\#(checkpoint),"createdAt":\#(created),"isArchived":false}"#
        try exec("""
        INSERT INTO composerHeaders (composerId, workspaceId, createdAt, lastUpdatedAt, isArchived, isSubagent,
            recency, checkpointAt, value, subagentTypeName)
        VALUES ('\(id)', 'ws', \(created), \(updated), 0, 0, \(updated), \(checkpoint), '\(json)', NULL);
        """)
    }

    private func insertLegacyHeaders(_ entries: [(id: String, name: String, updated: Int64)]) throws {
        let composers = entries.map {
            #"{"composerId":"\#($0.id)","name":"\#($0.name)","lastUpdatedAt":\#($0.updated),"createdAt":1760000000000}"#
        }
        try exec("""
        INSERT INTO ItemTable (key, value)
        VALUES ('composer.composerHeaders', '{"allComposers":[\(composers.joined(separator: ","))]}');
        """)
    }

    private func load(_ ids: Set<String>) -> [String: ComposerMeta] {
        CursorComposerStore.loadComposerHeaders(atPath: databaseURL.path, forIDs: ids)
    }

    // MARK: - Layouts

    func testTheTableIsReadByComposerID() throws {
        try createHeadersTable()
        try insertHeaderRow("a", name: "Fix the notch", updated: 1_760_000_500_000, checkpoint: 1_760_000_400_000)
        try insertHeaderRow("b", name: "Not asked for", updated: 1_760_000_600_000)

        let meta = load(["a", "missing"])

        XCTAssertEqual(Set(meta.keys), ["a"], "only requested ids come back; an unknown id is simply absent")
        XCTAssertEqual(meta["a"]?.name, "Fix the notch")
        XCTAssertEqual(meta["a"]?.updatedMs, 1_760_000_500_000)
        XCTAssertEqual(meta["a"]?.checkpointMs, 1_760_000_400_000)
        XCTAssertEqual(meta["a"]?.createdMs, 1_760_000_000_000)
        XCTAssertNil(meta["a"]?.status, "a 3.19 header carries no status; that still comes from composerData")
    }

    func testTheLegacyKeyIsReadWhenThereIsNoTable() throws {
        try insertLegacyHeaders([("a", "Old layout chat", 1_760_000_500_000), ("b", "Other", 1_760_000_600_000)])

        let meta = load(["a"])

        XCTAssertEqual(Set(meta.keys), ["a"])
        XCTAssertEqual(meta["a"]?.name, "Old layout chat")
        XCTAssertEqual(meta["a"]?.updatedMs, 1_760_000_500_000)
    }

    /// Cursor 3.19.19 as measured: the table holds the headers and the key has no row.
    func testAnEmptyLegacyKeyDoesNotHideTheTable() throws {
        try createHeadersTable()
        try insertHeaderRow("a", name: "New layout chat", updated: 1_760_000_500_000)

        XCTAssertEqual(load(["a"])["a"]?.name, "New layout chat")
    }

    func testTheTableWinsAndTheLegacyKeyFillsOnlyWhatItLacks() throws {
        try createHeadersTable()
        try insertHeaderRow("a", name: "From the table", updated: 1_760_000_500_000)
        try insertLegacyHeaders([("a", "Stale legacy name", 1_760_000_900_000), ("b", "Only in legacy", 1_760_000_100_000)])

        let meta = load(["a", "b"])

        XCTAssertEqual(meta["a"]?.name, "From the table")
        XCTAssertEqual(meta["a"]?.updatedMs, 1_760_000_500_000)
        XCTAssertEqual(meta["b"]?.name, "Only in legacy")
    }

    // MARK: - Row contents

    func testTheNewestTimestampWinsBetweenColumnsAndValue() throws {
        try createHeadersTable()
        // The column moved on after the JSON was written, and a checkpoint is newer still.
        try insertHeaderRow(
            "a", name: "Chat", updated: 1_760_000_500_000, checkpoint: 1_760_000_700_000,
            value: #"{"composerId":"a","name":"Chat","lastUpdatedAt":1760000200000}"#
        )

        let meta = try XCTUnwrap(load(["a"])["a"])

        XCTAssertEqual(meta.checkpointMs, 1_760_000_700_000)
        XCTAssertEqual(meta.updatedMs, 1_760_000_700_000, "updated covers the checkpoint, as in the legacy parser")
    }

    func testAnUnreadableValueKeepsTheColumnTimestamps() throws {
        try createHeadersTable()
        try insertHeaderRow("a", name: "unused", updated: 1_760_000_500_000, value: "not json")

        let meta = try XCTUnwrap(load(["a"])["a"])

        XCTAssertNil(meta.name)
        XCTAssertEqual(meta.updatedMs, 1_760_000_500_000)
        XCTAssertEqual(meta.createdMs, 1_760_000_000_000)
    }

    // MARK: - Bounds

    func testNoIDsReadNothing() throws {
        try createHeadersTable()
        try insertHeaderRow("a", name: "Chat", updated: 1_760_000_500_000)

        XCTAssertTrue(load([]).isEmpty)
    }

    func testAMissingDatabaseIsNotCreated() {
        let missing = databaseURL.deletingLastPathComponent().appendingPathComponent("absent.vscdb")

        XCTAssertTrue(CursorComposerStore.loadComposerHeaders(atPath: missing.path, forIDs: ["a"]).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path),
                       "a missing path is never opened, so nothing is created")
    }

    // MARK: - Header and composerData

    private func meta(
        _ id: String,
        status: String? = nil,
        updated: Int64,
        checkpoint: Int64 = 0,
        created: Int64 = 0,
        name: String? = nil
    ) -> ComposerMeta {
        ComposerMeta(composerID: id, status: status, updatedMs: updated, checkpointMs: checkpoint,
                     createdMs: created, name: name)
    }

    /// Cursor 3.19.19, read-only: a header's `lastUpdatedAt` can run ahead of `composerData` with
    /// no agent activity, and the header has no status. Letting the newer header win dropped
    /// "aborted", so the abortedIdle rule never fired and the chat could light green.
    func testANewerHeaderKeepsComposerDataStatusAndActivity() {
        let data = meta("a", status: "aborted", updated: 1_760_000_500_000, checkpoint: 1_760_000_400_000)
        let header = meta("a", updated: 1_760_000_678_000, created: 1_760_000_000_000, name: "Fix the notch")

        let merged = CursorComposerStore.combine(composerData: [data], headers: ["a": header])

        XCTAssertEqual(merged["a"]?.status, "aborted")
        XCTAssertEqual(merged["a"]?.updatedMs, 1_760_000_500_000, "a header bump is not activity")
        XCTAssertEqual(merged["a"]?.checkpointMs, 1_760_000_400_000)
        XCTAssertEqual(merged["a"]?.name, "Fix the notch", "the header still supplies the name composerData lacks")
        XCTAssertEqual(merged["a"]?.createdMs, 1_760_000_000_000)
    }

    func testComposerDataKeepsItsOwnNameAndAHeaderAloneStillBacksTheChat() {
        let data = meta("a", status: "generating", updated: 1_760_000_500_000, name: "Data name")
        let headers = [
            "a": meta("a", updated: 1_760_000_400_000, name: "Header name"),
            "b": meta("b", updated: 1_760_000_300_000, name: "Only a header"),
        ]

        let merged = CursorComposerStore.combine(composerData: [data], headers: headers)

        XCTAssertEqual(merged["a"]?.name, "Data name")
        XCTAssertEqual(merged["a"]?.status, "generating")
        XCTAssertEqual(merged["b"], headers["b"], "a chat with no composerData keeps its header as its record")
    }

    // MARK: - Header cache

    func testTheHeaderCacheAddsNewIDsWithinItsTTLAndRereadsOnlyThose() {
        var cache = ComposerHeaderCache(ttl: 3)
        var loads: [Set<String>] = []
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        func read(_ ids: Set<String>, at seconds: Double) -> [String: ComposerMeta] {
            cache.headers(forIDs: ids, now: start.addingTimeInterval(seconds)) { requested in
                loads.append(requested)
                return Dictionary(uniqueKeysWithValues: requested.filter { $0 != "none" }.map {
                    ($0, self.meta($0, updated: 1, name: "name-\($0)"))
                })
            }
        }

        XCTAssertEqual(Set(read(["a"], at: 0.0).keys), ["a"])
        let second = read(["a", "b"], at: 1.0)
        XCTAssertEqual(second["b"]?.name, "name-b", "an id the cache has not read resolves inside the TTL")
        XCTAssertEqual(Set(second.keys), ["a", "b"])
        XCTAssertEqual(Set(read(["a"], at: 2.0).keys), ["a"], "a subset is a hit and returns only what was asked")
        XCTAssertTrue(read(["none"], at: 2.0).isEmpty)
        XCTAssertTrue(read(["none"], at: 2.5).isEmpty, "an id with no header is not re-read inside the TTL")
        XCTAssertEqual(loads, [["a"], ["b"], ["none"]])

        _ = read(["a"], at: 3.5)
        XCTAssertEqual(loads.last, ["a"], "after the TTL everything is read again")
        XCTAssertEqual(cache.readIDs, ["a"], "and the ids from before the TTL are forgotten")
    }
}
