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

/// Wispr Flow's meeting summaries are shown in the notch's Notes and never stored by Kannu: not in `savedNotes`, so
/// never pushed to Apple Notes, never cleared by Clear Notes, never kept after Wispr deletes them. The notch's editor
/// saves whatever note is open through `NotesManager.save`, which stores an id it does not know as a new note, so the
/// guard has to be in the editor's save paths. The one thing Kannu keeps about a meeting is its tags, by meeting id
/// (`wisprMeetingTags`, 2026-11-16): a map of tags only, written by `NotesManager` alone, never by the meetings
/// manager, and a meeting Wispr no longer lists offers its tags nowhere (`SharedTags.inUse`). Each rule is read from
/// the source and checked against planted offenders.
final class WisprMeetingsNeverStoredRulesTests: XCTestCase {

    private static let managerPath = "Kannu/managers/WisprFlowMeetingsManager.swift"
    private static let notchPath = "Kannu/components/Notch/NotchNotesView.swift"
    private static let modelPath = "Kannu/models/Constants.swift"
    private static let notesManagerPath = "Kannu/managers/NotesManager.swift"
    private static let tagsKeyLine = #"static let wisprMeetingTags = Key<[String: [String]]>("wisprMeetingTags", default: [:])"#

    private static func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private static func body(_ signature: String, in code: String) -> String {
        ClosedNotchTimerRulesTests.body(after: signature, in: code) ?? ""
    }

    // MARK: - Rules

    /// The manager keeps the meetings in memory only: it names no store of notes and writes no Defaults key.
    static func managerViolations(_ source: String) -> [String] {
        // The doc comments say what the manager does not touch; only code counts.
        let code = source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        var found: [String] = []
        for name in ["savedNotes", "NotesManager", "AppleNotesSyncManager", "wisprMeetingTags"] where code.contains(name) {
            found.append("names \(name)")
        }
        if code.range(of: #"Defaults\[[^\]]+\]\s*=[^=]"#, options: .regularExpression) != nil {
            found.append("writes a Defaults key")
        }
        return found
    }

    /// The editor's two save paths return before saving while a Wispr Flow meeting is open.
    static func notchViolations(_ code: String) -> [String] {
        var found: [String] = []
        let persist = body("private func persistNote()", in: code)
        if !persist.contains("!editorIsWisprMeeting") { found.append("persistNote saves a Wispr Flow meeting") }
        let autosave = body("private func scheduleAutoSave()", in: code)
        if !autosave.contains("!editorIsWisprMeeting") { found.append("scheduleAutoSave saves a Wispr Flow meeting") }
        let select = body("private func selectNote(_ note: NoteItem)", in: code)
        if !select.contains("editorIsWisprMeeting = note.isWisprMeeting") { found.append("selectNote does not mark a meeting") }
        return found
    }

    /// `NoteItem` does not encode `wisprMeetingId`: a meeting that reached `savedNotes` by some other path would come
    /// back as an ordinary note rather than as a meeting with Kannu's copy of a summary.
    static func modelViolations(_ code: String) -> [String] {
        guard let start = code.range(of: "struct NoteItem:"),
              let keys = code[start.upperBound...].range(of: "private enum CodingKeys") else { return ["no NoteItem.CodingKeys"] }
        let line = code[keys.upperBound...].prefix { $0 != "}" }
        return line.contains("wisprMeetingId") ? ["encodes wisprMeetingId"] : []
    }

    // MARK: - The sources keep them

    func testTheManagerStoresNothing() throws {
        XCTAssertEqual(Self.managerViolations(try Self.source(Self.managerPath)), [])
    }

    func testTheNotchEditorNeverSavesAMeeting() throws {
        XCTAssertEqual(Self.notchViolations(try Self.source(Self.notchPath)), [])
    }

    func testNoteItemDoesNotEncodeTheMeetingId() throws {
        XCTAssertEqual(Self.modelViolations(try Self.source(Self.modelPath)), [])
    }

    /// The meeting tags' key holds tags only, by meeting id: never a title or a summary.
    func testTheMeetingTagsKeyHoldsTagsOnly() throws {
        XCTAssertTrue(try Self.source(Self.modelPath).contains(Self.tagsKeyLine))
    }

    /// Only `NotesManager` writes the meeting tags, so the one write path stays one.
    static func tagWriters(_ sources: [String: String]) -> [String] {
        sources.filter { $0.value.contains("Defaults[.wisprMeetingTags] =") }.map(\.key).sorted()
    }

    func testOnlyTheNotesManagerWritesMeetingTags() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let kannu = root.appendingPathComponent("Kannu")
        var sources: [String: String] = [:]
        let files = FileManager.default.enumerator(at: kannu, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            sources[url.path.replacingOccurrences(of: root.path + "/", with: "")] = try String(contentsOf: url, encoding: .utf8)
        }
        XCTAssertGreaterThan(sources.count, 100, "the walk no longer reaches Kannu/")
        XCTAssertEqual(Self.tagWriters(sources), [Self.notesManagerPath])
        XCTAssertEqual(Self.tagWriters(sources.merging([Self.notchPath: "Defaults[.wisprMeetingTags] = [:]"]) { _, plant in plant }),
                       [Self.notchPath, Self.notesManagerPath].sorted(), "a planted second writer is caught")
    }

    // MARK: - Planted offenders

    func testPlantedOffendersAreCaught() throws {
        let manager = try Self.source(Self.managerPath)
        XCTAssertFalse(Self.managerViolations(manager + "\nfunc leak() { Defaults[.savedNotes] = [] }\n").isEmpty)
        XCTAssertFalse(Self.managerViolations(manager + "\nfunc leak() { NotesManager.shared.clearAll() }\n").isEmpty)
        XCTAssertFalse(Self.managerViolations(manager + "\nfunc leak() { _ = Defaults[.wisprMeetingTags] }\n").isEmpty)

        let notch = try Self.source(Self.notchPath)
        let unguarded = notch.replacingOccurrences(of: "guard let id = editorNoteId, !editorIsWisprMeeting else { return }",
                                                   with: "guard let id = editorNoteId else { return }")
        XCTAssertNotEqual(unguarded, notch, "the planted offender must change the source")
        XCTAssertFalse(Self.notchViolations(unguarded).isEmpty)
        let unmarked = notch.replacingOccurrences(of: "editorIsWisprMeeting = note.isWisprMeeting", with: "")
        XCTAssertFalse(Self.notchViolations(unmarked).isEmpty)

        let model = try Self.source(Self.modelPath)
        // Anchored at the start of the case list, which stays put as fields are added at its end.
        let encoded = model.replacingOccurrences(of: "case id, title, content, creationDate,",
                                                 with: "case id, wisprMeetingId, title, content, creationDate,")
        XCTAssertNotEqual(encoded, model, "the planted offender must change the source")
        XCTAssertFalse(Self.modelViolations(encoded).isEmpty)
    }
}
