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
import SQLite3

/// One Wispr Flow Notetaker meeting that has a summary, as Wispr's own database holds it.
struct WisprMeeting: Equatable, Sendable {
    let id: String
    let title: String
    /// Markdown, as Wispr writes it: `### ` headings and `- ` bullets.
    let summary: String
    let created: Date
    let modified: Date
}

/// Why no meetings could be read. Each case hides the source; none is shown to the user.
enum WisprStoreError: Error, Equatable, Sendable {
    /// Wispr Flow is not installed, or has never written its database.
    case missingFile
    /// The file is there but SQLite could not open or query it.
    case unreadable
    /// Wispr changed its schema: a column this reader needs is gone. Nothing is guessed.
    case unsupportedSchema
}

/// Reads Wispr Flow's meeting summaries from the SQLite file Wispr keeps on this Mac, read-only.
///
/// Wispr Flow (an Electron app, not sandboxed) stores its Notetaker meetings in a Sequelize database
/// in WAL mode. Kannu opens it with `mode=ro` and never writes to it. `immutable=1` is never used: it
/// would skip the WAL and miss whatever Wispr wrote since its last checkpoint. The schema is private
/// to Wispr, so every column read is checked first and a missing one hides the source instead of
/// guessing. Foundation and SQLite only, so the tests run it against a database of their own.
enum WisprFlowMeetingsStore {
    static let bundleIdentifier = "com.electron.wispr-flow"

    /// At most this many meetings, newest first: the notch lists notes, it is not an archive.
    static let defaultLimit = 50

    /// Every `Meetings` column the query reads or filters on.
    static let requiredColumns: Set<String> = ["id", "title", "summary", "createdAt", "modifiedAt", "isDeleted"]

    static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Wispr Flow/flow.sqlite")
    }

    /// The meetings with a summary that Wispr has not deleted, newest first.
    static func meetings(at url: URL = defaultDatabaseURL, limit: Int = defaultLimit) -> Result<[WisprMeeting], WisprStoreError> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .failure(.missingFile) }

        var db: OpaquePointer?
        let uri = url.absoluteString + "?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return .failure(.unreadable)
        }
        defer { sqlite3_close(db) }
        // Wispr may be mid-write; wait briefly rather than fail, never long enough to be felt.
        sqlite3_busy_timeout(db, 250)

        guard let columns = columnNames(of: "Meetings", in: db) else { return .failure(.unreadable) }
        guard requiredColumns.isSubset(of: columns) else { return .failure(.unsupportedSchema) }

        // Text dates sort by their text here, which is their order while the offset stays the same;
        // the dates parsed below put the result in true order.
        let sql = """
        SELECT id, title, summary, createdAt, modifiedAt FROM Meetings
        WHERE isDeleted = 0 AND length(summary) > 0
        ORDER BY modifiedAt DESC
        LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return .failure(.unreadable) }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(clamping: max(0, limit)))

        var meetings: [WisprMeeting] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { return .failure(.unreadable) }
            guard let id = text(stmt, 0),
                  let summary = text(stmt, 2),
                  let created = date(fromWispr: text(stmt, 3) ?? ""),
                  let modified = date(fromWispr: text(stmt, 4) ?? "") else { continue }
            meetings.append(WisprMeeting(id: id, title: text(stmt, 1) ?? "", summary: summary,
                                         created: created, modified: modified))
        }
        return .success(meetings.sorted { $0.modified > $1.modified })
    }

    /// Sequelize's SQLite date text, `2026-11-14 12:00:00.000 +05:30`, with or without the
    /// milliseconds. Nil for anything else.
    static func date(fromWispr text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        for format in ["yyyy-MM-dd HH:mm:ss.SSS xxx", "yyyy-MM-dd HH:mm:ss xxx"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    /// The table's column names, empty when the table is missing. Nil when the PRAGMA itself fails.
    private static func columnNames(of table: String, in db: OpaquePointer) -> Set<String>? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        var names: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = text(stmt, 1) { names.insert(name) }
        }
        return names
    }

    private static func text(_ stmt: OpaquePointer, _ column: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: cString)
    }
}
