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

/// Where a note was made: the one source every note has (David, 2026-11-16: "Made in Apple Notes").
///
/// A note made in Kannu and synced to Apple Notes is still Kannu's, and so is a note in Notes' Kannu
/// folder, which sync already counts as Kannu's (`AppleNotesMergePolicy.madeInAppleNotes`). So with
/// the default Kannu-folder scope every synced note is Kannu's, and Apple Notes appears only for
/// notes made there and shown read-only under whole-account sync.
enum NoteSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case kannu
    case appleNotes
    case wisprFlow

    var id: String { rawValue }

    /// A Wispr Flow meeting is Wispr Flow's. Otherwise `madeInAppleNotes` decides; a note from before
    /// that field (nil) counts as Apple Notes' while it is linked to Notes, as
    /// `NoteItem.isReadOnlyMirror` reads it, and as Kannu's while it is not.
    init(wisprMeetingId: String?, appleNotesId: String?, madeInAppleNotes: Bool?) {
        if wisprMeetingId != nil {
            self = .wisprFlow
        } else if madeInAppleNotes ?? (appleNotesId != nil) {
            self = .appleNotes
        } else {
            self = .kannu
        }
    }

    var name: String {
        switch self {
        case .kannu: return String(localized: "Kannu")
        case .appleNotes: return String(localized: "Apple Notes")
        case .wisprFlow: return String(localized: "Wispr Flow")
        }
    }
}

/// The notch Notes tab's filter: one source, one tag, one colour, each optional. It narrows the list
/// only; no note changes. Pure, in the logic target; the view keeps the three parts in Defaults
/// (`notesNotchSourceFilter`, `notesNotchTagFilter`, `notesNotchColorFilter`) so the list comes back
/// filtered after a note is opened, the notch closes, or Kannu relaunches.
struct NoteFilter: Equatable, Sendable {
    /// What the filter reads from a note.
    struct Facets: Equatable, Sendable {
        var source: NoteSource
        var tags: [String]
        /// Nil for a note with no colour of its own (a Wispr Flow meeting): no colour filter shows it.
        var colorIndex: Int?
    }

    /// Nil is every source.
    var source: NoteSource?
    /// `TaskFacets.anyTag` is every tag; a tag is matched ignoring case.
    var tag: String = TaskFacets.anyTag
    /// Nil is every colour.
    var colorIndex: Int?

    static let all = NoteFilter()

    var isNarrowing: Bool {
        source != nil || tag != TaskFacets.anyTag || colorIndex != nil
    }

    func matches(_ note: Facets) -> Bool {
        if let source, note.source != source { return false }
        if tag != TaskFacets.anyTag, !Self.carries(note, tag) { return false }
        if let colorIndex, note.colorIndex != colorIndex { return false }
        return true
    }

    /// The filter as it applies now: a source the menu does not offer counts as All (the stored choice
    /// is kept for when it is offered again, as a source that is not connected never hides tasks), and
    /// the colour sleeps while colour filtering is off. A picked tag no note has any more still
    /// applies, and the "Filtered" line says why the list is empty.
    func effective(offering sources: [NoteSource], colorFiltering: Bool) -> NoteFilter {
        var effective = self
        if let source, !sources.contains(source) { effective.source = nil }
        if !colorFiltering { effective.colorIndex = nil }
        return effective
    }

    /// The sources the menu offers: those among the listed notes, in `NoteSource` order. None with
    /// fewer than two, since one source is no choice.
    static func sourceChoices(_ notes: [Facets]) -> [NoteSource] {
        let present = Set(notes.map(\.source))
        let choices = NoteSource.allCases.filter(present.contains)
        return choices.count >= 2 ? choices : []
    }

    /// The Tag submenu's choices: the tags on the notes this filter's source and colour show, first
    /// spelling of each, sorted. The tag part itself is ignored, or picking one would hide the rest.
    func tagChoices(_ notes: [Facets]) -> [String] {
        var withoutTag = self
        withoutTag.tag = TaskFacets.anyTag
        return TaskFacets.firstSpellings(notes.filter(withoutTag.matches).flatMap(\.tags))
    }

    /// What "+" starts a note with while this (effective) filter narrows the list, so the new note is
    /// listed: the picked tag, and the picked colour.
    var newNoteTags: [String] { tag == TaskFacets.anyTag ? [] : [tag] }
    var newNoteColorIndex: Int? { colorIndex }

    /// The filter with every part `note` fails cleared, so a note just made never vanishes from the
    /// list it was made in (`TaskOrdering.tagFilter(_:afterAdding:)` is the same rule for tasks).
    func keeping(_ note: Facets) -> NoteFilter {
        var kept = self
        if let source, note.source != source { kept.source = nil }
        if tag != TaskFacets.anyTag, !Self.carries(note, tag) { kept.tag = TaskFacets.anyTag }
        if let colorIndex, note.colorIndex != colorIndex { kept.colorIndex = nil }
        return kept
    }

    /// `keeping`, for a kept filter of which only `effective` applies now: a part that is kept but sleeps
    /// (a source not offered, a colour while colour filtering is off) hides nothing, so it stays.
    func keeping(_ note: Facets, activeAs effective: NoteFilter) -> NoteFilter {
        let kept = effective.keeping(note)
        var result = self
        if effective.source != nil, kept.source == nil { result.source = nil }
        if effective.tag != TaskFacets.anyTag, kept.tag == TaskFacets.anyTag { result.tag = TaskFacets.anyTag }
        if effective.colorIndex != nil, kept.colorIndex == nil { result.colorIndex = nil }
        return result
    }

    private static func carries(_ note: Facets, _ tag: String) -> Bool {
        let wanted = tag.lowercased()
        return note.tags.contains { $0.lowercased() == wanted }
    }
}
