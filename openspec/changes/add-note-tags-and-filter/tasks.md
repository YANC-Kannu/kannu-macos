# Tasks: add-note-tags-and-filter

## 1. Model
- [x] 1.1 `NoteItem.tags` (lossy decode, encoded only when not empty), `source`, `filterFacets`
- [x] 1.2 `NoteSource` and `NoteFilter`, Foundation-only and in the test target
- [x] 1.3 Defaults keys `wisprMeetingTags`, `notesNotchSourceFilter`, `notesNotchTagFilter`, `notesNotchColorFilter`
- [x] 1.4 `SharedTags.inUse()` and `colors()`; `TaskFacets.firstSpellings` made internal

## 2. Writes
- [x] 2.1 `NotesManager.setTags(_:forNote:)` and `setTags(_:forWisprMeeting:)`: no push, no date
- [x] 2.2 `AppleNotesMergePolicy.reconcile` takes a `carry`; the sync carries tags and pins

## 3. Notch
- [x] 3.1 `NoteFilterMenu` in the header's glyph group, the search-only magnifying glass, the Filtered line, the empty states
- [x] 3.2 `NoteTagsRow` in the editor; a pending tag is added on Done, back and close
- [x] 3.3 Title `#word`s become tags (`TaskQuickAdd.takingNewTags`); never on a read-only note
- [x] 3.4 Card chips; a read-only note's paste reaches only the focused field
- [x] 3.5 Task tag fields suggest the shared set, read on focus

## 4. Tests and docs
- [x] 4.1 `NoteFilterTests`, `NoteTagsRulesTests`, and additions to `TaskFacetsTests`, `TaskQuickAddTests`, `AppleNotesMergePolicyTests` and `WisprMeetingsNeverStoredRulesTests`
- [x] 4.2 Pins: `NotchFontRulesTests`, `TimerSideColumnRulesTests`
- [x] 4.3 docs/SETTINGS.md, CHANGELOG.md
- [x] 4.4 `openspec validate --all --strict` (0.23.0)
- [ ] 4.5 Archive after merge
