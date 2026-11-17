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

import XCTest

/// Notes' tags and the notch Notes filter (David, 2026-11-16). Tags are Kannu's alone: never written into an Apple
/// note, never a reason to push one or to move its date, and a tag set while a sync runs survives it. The filter is
/// one native menu that holds nothing open, a plain glyph beside the search glyph, which now only searches. Each rule
/// is read from the source and checked against a planted offender.
final class NoteTagsRulesTests: XCTestCase {

    private static let syncPath = "Kannu/managers/AppleNotesSyncManager.swift"
    private static let managerPath = "Kannu/managers/NotesManager.swift"
    private static let notchPath = "Kannu/components/Notch/NotchNotesView.swift"
    private static let menuPath = "Kannu/components/Notch/NoteFilterMenu.swift"
    private static let rowPath = "Kannu/components/Notch/NoteTagsRow.swift"

    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Code only: the doc comments say what a file does not touch.
    private static func code(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private static func body(_ signature: String, in code: String) -> String {
        ClosedNotchTimerRulesTests.body(after: signature, in: code) ?? ""
    }

    private static func count(_ needle: String, in code: String) -> Int {
        code.components(separatedBy: needle).count - 1
    }

    // MARK: - Rules

    /// Nothing the sync writes into Notes names a note's tags.
    static func syncProblems(_ source: String) -> [String] {
        code(source).range(of: #"\btags\b"#, options: .regularExpression) == nil ? [] : ["the Apple Notes sync reads tags"]
    }

    /// Tagging is not an edit: no push, no date; and the sync carries tags over its synced copy.
    static func managerProblems(_ source: String) -> [String] {
        let code = code(source)
        var found: [String] = []
        for signature in ["func setTags(_ tags: [String], forNote id: UUID)",
                          "func setTags(_ tags: [String], forWisprMeeting meetingId: String)"] {
            let body = body(signature, in: code)
            if body.isEmpty { found.append("\(signature) is gone") }
            if body.contains("pushToAppleNotes") { found.append("\(signature) pushes to Apple Notes") }
            if body.contains("modificationDate") { found.append("\(signature) moves the note's date") }
        }
        let sync = body("func syncWithAppleNotes()", in: code)
        if !(sync.contains("carry: { now, synced in") && sync.contains("carried.tags = now.tags")) {
            found.append("the sync does not carry tags set while it ran")
        }
        return found
    }

    /// The notch: the editor saves through `persistNote` alone, the glyph group starts with the filter menu, the
    /// magnifying glass only searches, and the colour-chip row is gone. Its alerts keep their holds and nothing else
    /// takes one (REGRESSIONS entry 23).
    static func notchProblems(_ source: String) -> [String] {
        let code = code(source)
        var found: [String] = []
        if count("NotesManager.shared.save(", in: code) != 1
            || !body("private func persistNote()", in: code).contains("NotesManager.shared.save(") {
            found.append("a note is saved outside persistNote")
        }
        if !code.contains("HStack(spacing: 2) {\n                    if showsFilterMenu {\n                        NoteFilterMenu(") {
            found.append("the glyph group does not start with the filter menu")
        }
        if !code.contains("if enableNoteSearch {\n                        Button(action: {") { found.append("the magnifying glass does more than search") }
        if code.contains("selectedColorFilter") { found.append("the colour-chip row is back") }
        if !code.contains("if title.count == previous.count + 1, title.hasPrefix(previous), let last = title.last, last.isWhitespace {") {
            found.append("a title's #word is taken by more than a space typed at its end")
        }
        if count("setAutoCloseSuppression(", in: code) != 6 { found.append("a hold other than the alerts'") }
        return found
    }

    /// The new views: no hold of their own, and the menu has its tooltip and no traffic-light colour.
    static func viewProblems(menu: String, row: String) -> [String] {
        var found: [String] = []
        for (name, source) in [("menu", menu), ("row", row)] where code(source).contains("setAutoCloseSuppression(") {
            found.append("the \(name) holds the notch open")
        }
        let menuCode = code(menu)
        if !menuCode.contains(".hoverTooltip(") { found.append("the menu has no tooltip") }
        if menuCode.contains(".red") || menuCode.contains(".yellow") { found.append("the menu uses red or yellow") }
        return found
    }

    // MARK: - The sources keep them

    func testTagsNeverReachAppleNotes() throws {
        XCTAssertEqual(Self.syncProblems(try Self.source(Self.syncPath)), [])
    }

    func testTaggingIsNotAnEditAndSurvivesASync() throws {
        XCTAssertEqual(Self.managerProblems(try Self.source(Self.managerPath)), [])
    }

    func testTheNotchKeepsOneFilterAndOneSavePath() throws {
        XCTAssertEqual(Self.notchProblems(try Self.source(Self.notchPath)), [])
    }

    func testTheNewViewsHoldNothingOpen() throws {
        XCTAssertEqual(Self.viewProblems(menu: try Self.source(Self.menuPath), row: try Self.source(Self.rowPath)), [])
    }

    // MARK: - Planted offenders

    func testPlantedOffendersAreCaught() throws {
        let sync = try Self.source(Self.syncPath)
        XCTAssertFalse(Self.syncProblems(sync + "\nlet leak = note.tags\n").isEmpty)

        let manager = try Self.source(Self.managerPath)
        let pushing = manager.replacingOccurrences(of: "        notes[index].tags = cleaned\n",
                                                   with: "        notes[index].tags = cleaned\n        pushToAppleNotes(id)\n")
        XCTAssertNotEqual(pushing, manager, "the planted offender must change the source")
        XCTAssertFalse(Self.managerProblems(pushing).isEmpty)
        let uncarried = manager.replacingOccurrences(of: "carried.tags = now.tags", with: "")
        XCTAssertNotEqual(uncarried, manager)
        XCTAssertFalse(Self.managerProblems(uncarried).isEmpty)

        let notch = try Self.source(Self.notchPath)
        XCTAssertFalse(Self.notchProblems(notch + "\nfunc leak() { NotesManager.shared.save(draft) }\n").isEmpty)
        XCTAssertFalse(Self.notchProblems(notch + "\n@State private var selectedColorFilter: Int? = nil\n").isEmpty)
        let anyEnding = notch.replacingOccurrences(of: "if title.count == previous.count + 1, title.hasPrefix(previous), let last = title.last, last.isWhitespace {",
                                                   with: "if let last = title.last, last.isWhitespace {")
        XCTAssertNotEqual(anyEnding, notch)
        XCTAssertFalse(Self.notchProblems(anyEnding).isEmpty)
        XCTAssertFalse(Self.notchProblems(notch + "\nfunc hold() { vm.setAutoCloseSuppression(true, token: t) }\n").isEmpty)
        let bothGlyph = notch.replacingOccurrences(of: "if enableNoteSearch {\n                        Button(action: {",
                                                   with: "if enableNoteSearch || enableNoteColorFiltering {\n                        Button(action: {")
        XCTAssertNotEqual(bothGlyph, notch)
        XCTAssertFalse(Self.notchProblems(bothGlyph).isEmpty)

        let menu = try Self.source(Self.menuPath)
        let row = try Self.source(Self.rowPath)
        XCTAssertFalse(Self.viewProblems(menu: menu, row: row + "\nfunc hold() { vm.setAutoCloseSuppression(true, token: t) }\n").isEmpty)
        XCTAssertFalse(Self.viewProblems(menu: menu.replacingOccurrences(of: ".hoverTooltip(", with: ".help("), row: row).isEmpty)
        XCTAssertFalse(Self.viewProblems(menu: menu + "\nlet c = Color.red\n", row: row).isEmpty)
    }
}
