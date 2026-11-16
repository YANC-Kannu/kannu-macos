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

/// The notch Notes tab's filter: where a note was made, and the source, tag and colour parts. Made-up
/// tags only.
final class NoteFilterTests: XCTestCase {

    private func note(_ source: NoteSource, tags: [String] = [], color: Int? = 0) -> NoteFilter.Facets {
        NoteFilter.Facets(source: source, tags: tags, colorIndex: color)
    }

    // MARK: - Source

    func testAWisprFlowMeetingIsWisprFlowsWhateverElseItSays() {
        XCTAssertEqual(NoteSource(wisprMeetingId: "m", appleNotesId: "x", madeInAppleNotes: true), .wisprFlow)
    }

    func testWhereANoteWasMadeDecides() {
        XCTAssertEqual(NoteSource(wisprMeetingId: nil, appleNotesId: "x", madeInAppleNotes: true), .appleNotes)
        XCTAssertEqual(NoteSource(wisprMeetingId: nil, appleNotesId: "x", madeInAppleNotes: false), .kannu,
                       "made in Kannu and synced to Notes: still Kannu's")
        XCTAssertEqual(NoteSource(wisprMeetingId: nil, appleNotesId: nil, madeInAppleNotes: false), .kannu)
    }

    func testANoteFromBeforeTheFieldCountsByItsLink() {
        XCTAssertEqual(NoteSource(wisprMeetingId: nil, appleNotesId: "x", madeInAppleNotes: nil), .appleNotes,
                       "linked and undecided reads as made in Notes, as a read-only mirror does")
        XCTAssertEqual(NoteSource(wisprMeetingId: nil, appleNotesId: nil, madeInAppleNotes: nil), .kannu)
    }

    // MARK: - Matching

    func testEveryNoteMatchesNoFilter() {
        XCTAssertFalse(NoteFilter.all.isNarrowing)
        XCTAssertTrue(NoteFilter.all.matches(note(.wisprFlow, color: nil)))
    }

    func testEachPartNarrows() {
        XCTAssertTrue(NoteFilter(source: .wisprFlow).matches(note(.wisprFlow)))
        XCTAssertFalse(NoteFilter(source: .wisprFlow).matches(note(.kannu)))
        XCTAssertTrue(NoteFilter(tag: "Acme").matches(note(.kannu, tags: ["docs", "acme"])), "a tag matches ignoring case")
        XCTAssertFalse(NoteFilter(tag: "acme").matches(note(.kannu, tags: ["docs"])))
        XCTAssertTrue(NoteFilter(colorIndex: 2).matches(note(.kannu, color: 2)))
        XCTAssertFalse(NoteFilter(colorIndex: 2).matches(note(.kannu, color: 1)))
        XCTAssertFalse(NoteFilter(colorIndex: 0).matches(note(.wisprFlow, color: nil)), "a meeting has no colour to match")
        XCTAssertFalse(NoteFilter(source: .kannu, tag: "acme").matches(note(.kannu, tags: [])), "the parts combine")
    }

    // MARK: - What applies

    func testASourceNotOfferedCountsAsEverySource() {
        let kept = NoteFilter(source: .wisprFlow, tag: "acme")
        let effective = kept.effective(offering: [.kannu, .appleNotes], colorFiltering: true)
        XCTAssertNil(effective.source)
        XCTAssertEqual(effective.tag, "acme", "the other parts still apply")
        XCTAssertEqual(kept.effective(offering: [.kannu, .wisprFlow], colorFiltering: true).source, .wisprFlow)
    }

    func testTheColourSleepsWhileColourFilteringIsOff() {
        let kept = NoteFilter(colorIndex: 3)
        XCTAssertNil(kept.effective(offering: [], colorFiltering: false).colorIndex)
        XCTAssertEqual(kept.effective(offering: [], colorFiltering: true).colorIndex, 3)
    }

    func testALingeringTagStillApplies() {
        XCTAssertEqual(NoteFilter(tag: "gone").effective(offering: [], colorFiltering: false).tag, "gone",
                       "the Filtered line says why the list is empty")
    }

    // MARK: - Choices

    func testOneSourceIsNoChoice() {
        XCTAssertEqual(NoteFilter.sourceChoices([note(.kannu), note(.kannu)]), [])
        XCTAssertEqual(NoteFilter.sourceChoices([note(.wisprFlow), note(.kannu)]), [.kannu, .wisprFlow],
                       "present sources, in NoteSource order")
    }

    func testTagChoicesAreTheShownNotesTagsIgnoringTheTagPart() {
        let notes = [note(.kannu, tags: ["Acme", "docs"]), note(.wisprFlow, tags: ["acme", "PROJ-123"], color: nil)]
        XCTAssertEqual(NoteFilter(tag: "docs").tagChoices(notes), ["Acme", "docs", "PROJ-123"],
                       "picking a tag never hides the others; first spelling of each")
        XCTAssertEqual(NoteFilter(source: .wisprFlow).tagChoices(notes), ["acme", "PROJ-123"],
                       "only the tags the source shows")
    }

    // MARK: - A new note while filtered

    func testANewNoteStartsWithThePickedTagAndColour() {
        XCTAssertEqual(NoteFilter(tag: "acme", colorIndex: 2).newNoteTags, ["acme"])
        XCTAssertEqual(NoteFilter(tag: "acme", colorIndex: 2).newNoteColorIndex, 2)
        XCTAssertEqual(NoteFilter.all.newNoteTags, [])
        XCTAssertNil(NoteFilter.all.newNoteColorIndex)
    }

    func testKeepingClearsOnlyWhatTheNewNoteFails() {
        let filter = NoteFilter(source: .wisprFlow, tag: "acme", colorIndex: 2)
        let made = note(.kannu, tags: ["ACME"], color: 2)
        XCTAssertEqual(filter.keeping(made), NoteFilter(source: nil, tag: "acme", colorIndex: 2),
                       "a new note is Kannu's, so the Wispr Flow source goes; its tag and colour still match")
        XCTAssertEqual(NoteFilter(tag: "acme").keeping(note(.kannu, tags: ["docs"])), .all)
        XCTAssertEqual(NoteFilter(colorIndex: 1).keeping(note(.kannu, color: 4)), .all)
    }

    func testKeepingLeavesAPartThatSleeps() {
        let kept = NoteFilter(source: .wisprFlow, tag: "acme", colorIndex: 2)
        let effective = kept.effective(offering: [.kannu, .appleNotes], colorFiltering: false)
        let made = note(.kannu, tags: ["docs"], color: 0)
        XCTAssertEqual(kept.keeping(made, activeAs: effective), NoteFilter(source: .wisprFlow, tag: TaskFacets.anyTag, colorIndex: 2),
                       "only the tag applied and was failed; the source not offered and the sleeping colour stay")
        XCTAssertEqual(kept.keeping(note(.kannu, tags: ["acme"]), activeAs: effective), kept, "a note that passes clears nothing")
    }
}
