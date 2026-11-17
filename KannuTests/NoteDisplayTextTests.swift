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

/// The notch's note cards: a title that says something and a preview that does not repeat it. Made-up notes only.
final class NoteDisplayTextTests: XCTestCase {
    private let untitled = "Untitled Note"

    // MARK: - Title

    func testAStoredTitleIsShownAsItIs() {
        XCTAssertEqual(NoteDisplayText.title(title: "Acme launch", content: "Ship PROJ-123", untitled: untitled), "Acme launch")
    }

    func testTheDefaultTitleGivesWayToTheFirstLine() {
        XCTAssertEqual(NoteDisplayText.title(title: untitled, content: "\n1. Call example.com support\n2. Book room",
                                             untitled: untitled), "1. Call example.com support")
    }

    func testAnEmptyTitleGivesWayToTheFirstLineWithoutItsMarker() {
        XCTAssertEqual(NoteDisplayText.title(title: "  ", content: "### Decisions\n- Ship PROJ-123", untitled: untitled),
                       "Decisions")
    }

    func testANoteWithNoTextKeepsTheDefaultTitle() {
        XCTAssertEqual(NoteDisplayText.title(title: untitled, content: " \n ", untitled: untitled), untitled)
        XCTAssertEqual(NoteDisplayText.title(title: "", content: "", untitled: untitled), untitled)
    }

    // MARK: - Preview

    func testAFirstLineThatRepeatsTheTitleIsDropped() {
        XCTAssertEqual(NoteDisplayText.preview(title: "Acme launch", content: "acme launch\nShip PROJ-123\nTell the team"),
                       "Ship PROJ-123 Tell the team")
    }

    func testAFirstLineThatDiffersIsKept() {
        XCTAssertEqual(NoteDisplayText.preview(title: "Acme launch", content: "Ship PROJ-123"), "Ship PROJ-123")
    }

    func testLinesAreJoinedSoOneLineFillsTheCard() {
        XCTAssertEqual(NoteDisplayText.preview(title: "Todo", content: "1. Call support\n\n2. Book room"),
                       "1. Call support 2. Book room")
    }

    func testMarkdownMarkersAreDropped() {
        XCTAssertEqual(NoteDisplayText.preview(title: "Acme kickoff", content: "### Decisions\n- Ship PROJ-123\n* Retire PROJ-7\n> Quoted"),
                       "Decisions Ship PROJ-123 Retire PROJ-7 Quoted")
    }

    func testATitleTakenFromTheFirstLineIsNotRepeated() {
        let content = "Call example.com support\nAsk about PROJ-123"
        let title = NoteDisplayText.title(title: untitled, content: content, untitled: untitled)
        XCTAssertEqual(NoteDisplayText.preview(title: title, content: content), "Ask about PROJ-123")
    }

    func testOnlyTheStartOfALongNoteIsRead() {
        let content = String(repeating: "a", count: NoteDisplayText.previewSourceLimit) + "\nnever shown"
        XCTAssertFalse(NoteDisplayText.preview(title: "Long", content: content).contains("never shown"))
    }

    func testMarkersNeedASpaceAndNumbersStay() {
        XCTAssertEqual(NoteDisplayText.stripMarkers("#hashtag"), "#hashtag")
        XCTAssertEqual(NoteDisplayText.stripMarkers("-5 degrees"), "-5 degrees")
        XCTAssertEqual(NoteDisplayText.stripMarkers("  1. First"), "1. First")
        XCTAssertEqual(NoteDisplayText.stripMarkers("## Heading "), "Heading")
    }
}
