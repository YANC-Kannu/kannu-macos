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

/// `WisprFlowMeetingsStore` against databases shaped like Wispr Flow's: a Sequelize SQLite file in WAL mode whose
/// `Meetings` table holds the Notetaker's summaries. Every row here is made up.
final class WisprFlowMeetingsStoreTests: XCTestCase {

    private var directory: URL!
    /// The writer, held open with checkpoints off so the rows stay in the WAL, as they do while Wispr runs.
    private var writer: OpaquePointer?

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("WisprStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        sqlite3_close(writer)
        writer = nil
        try? FileManager.default.removeItem(at: directory)
    }

    /// Wispr's columns, the ones read and a few that are not.
    private static let wisprColumns = """
        `id` VARCHAR(36) NOT NULL UNIQUE PRIMARY KEY, `title` VARCHAR(255) NOT NULL, `createdAt` DATETIME NOT NULL,
        `modifiedAt` DATETIME NOT NULL, `synced` TINYINT(1) NOT NULL DEFAULT 1, `isDeleted` TINYINT(1) NOT NULL DEFAULT 0,
        `finalized` TINYINT(1) NOT NULL DEFAULT 0, `notes` TEXT, `summary` TEXT, `summaryReady` TINYINT(1)
        """

    private struct Row {
        var id = UUID().uuidString.lowercased()
        var title = "Acme kickoff"
        var summary: String? = "### Decisions\n- Ship PROJ-123"
        var modifiedAt = "2026-11-14 12:00:00.000 +05:30"
        var isDeleted = 0
    }

    @discardableResult
    private func makeDatabase(columns: String = wisprColumns, rows: [Row]) throws -> URL {
        let url = directory.appendingPathComponent("flow.sqlite")
        XCTAssertEqual(sqlite3_open(url.path, &writer), SQLITE_OK)
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA wal_autocheckpoint=0")
        try exec("CREATE TABLE `Meetings` (\(columns))")
        for row in rows {
            let summary = row.summary.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" } ?? "NULL"
            try exec("""
                INSERT INTO Meetings (id, title, createdAt, modifiedAt, isDeleted, summary)
                VALUES ('\(row.id)', '\(row.title)', '2026-11-14 11:00:00.000 +05:30', '\(row.modifiedAt)', \(row.isDeleted), \(summary))
                """)
        }
        return url
    }

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(writer, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw NSError(domain: "WisprFlowMeetingsStoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func meetings(_ url: URL, limit: Int = WisprFlowMeetingsStore.defaultLimit) throws -> [WisprMeeting] {
        try WisprFlowMeetingsStore.meetings(at: url, limit: limit).get()
    }

    // MARK: - Reading

    func testReadsLiveSummariesNewestFirstFromAnUncheckpointedWAL() throws {
        let older = Row(title: "Acme kickoff", modifiedAt: "2026-11-14 10:00:00.000 +05:30")
        let newer = Row(title: "Example review", modifiedAt: "2026-11-14 11:30:00.000 +05:30")
        let url = try makeDatabase(rows: [
            older,
            Row(title: "Deleted", isDeleted: 1),
            Row(title: "Empty summary", summary: ""),
            Row(title: "No summary", summary: nil),
            newer,
        ])
        let wal = directory.appendingPathComponent("flow.sqlite-wal")
        let walSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: wal.path)[.size] as? Int)
        XCTAssertGreaterThan(walSize, 0, "the rows must still be in the WAL for this test to mean anything")

        let result = try meetings(url)

        XCTAssertEqual(result.map(\.title), ["Example review", "Acme kickoff"])
        XCTAssertEqual(result.first?.id, newer.id)
        XCTAssertEqual(result.first?.summary, "### Decisions\n- Ship PROJ-123")
    }

    func testStopsAtTheLimit() throws {
        let url = try makeDatabase(rows: (0..<3).map { Row(title: "Meeting \($0)", modifiedAt: "2026-11-1\($0) 09:00:00.000 +00:00") })
        XCTAssertEqual(try meetings(url, limit: 2).map(\.title), ["Meeting 2", "Meeting 1"])
    }

    func testSkipsARowWhoseDateItCannotRead() throws {
        let url = try makeDatabase(rows: [Row(title: "Readable"), Row(title: "Unreadable", modifiedAt: "yesterday")])
        XCTAssertEqual(try meetings(url).map(\.title), ["Readable"])
    }

    func testReadingLeavesTheDatabaseFileAsItWas() throws {
        let url = try makeDatabase(rows: [Row()])
        try exec("PRAGMA wal_checkpoint(TRUNCATE)")
        let before = try FileManager.default.attributesOfItem(atPath: url.path)

        _ = try meetings(url)

        let after = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(before[.size] as? Int, after[.size] as? Int)
        XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + "-journal"))
    }

    // MARK: - What hides the source

    func testAMissingFileIsMissingFile() {
        let url = directory.appendingPathComponent("absent.sqlite")
        XCTAssertEqual(WisprFlowMeetingsStore.meetings(at: url), .failure(.missingFile))
    }

    func testAMissingColumnIsAnUnsupportedSchema() throws {
        let url = directory.appendingPathComponent("flow.sqlite")
        XCTAssertEqual(sqlite3_open(url.path, &writer), SQLITE_OK)
        try exec("CREATE TABLE `Meetings` (`id` VARCHAR(36) PRIMARY KEY, `title` TEXT, `createdAt` DATETIME, `modifiedAt` DATETIME, `isDeleted` TINYINT(1))")
        XCTAssertEqual(WisprFlowMeetingsStore.meetings(at: url), .failure(.unsupportedSchema))
    }

    func testAMissingTableIsAnUnsupportedSchema() throws {
        let url = directory.appendingPathComponent("flow.sqlite")
        XCTAssertEqual(sqlite3_open(url.path, &writer), SQLITE_OK)
        try exec("CREATE TABLE `Notes` (`id` VARCHAR(36) PRIMARY KEY)")
        XCTAssertEqual(WisprFlowMeetingsStore.meetings(at: url), .failure(.unsupportedSchema))
    }

    func testAFileThatIsNotADatabaseIsUnreadable() throws {
        let url = directory.appendingPathComponent("flow.sqlite")
        try Data("not a database".utf8).write(to: url)
        XCTAssertEqual(WisprFlowMeetingsStore.meetings(at: url), .failure(.unreadable))
    }

    // MARK: - Dates

    func testParsesSequelizeDatesWithTheirOffset() throws {
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-14T06:30:00Z"))
        XCTAssertEqual(WisprFlowMeetingsStore.date(fromWispr: "2026-11-14 12:00:00.000 +05:30"), expected)
        XCTAssertEqual(WisprFlowMeetingsStore.date(fromWispr: "2026-11-14 06:30:00 +00:00"), expected)
        XCTAssertEqual(WisprFlowMeetingsStore.date(fromWispr: "2026-11-14 06:30:00.250 +00:00"), expected.addingTimeInterval(0.25))
    }

    func testRejectsTextThatIsNotASequelizeDate() {
        for text in ["", "yesterday", "2026-11-14", "2026-11-14T06:30:00Z"] {
            XCTAssertNil(WisprFlowMeetingsStore.date(fromWispr: text), text)
        }
    }
}
