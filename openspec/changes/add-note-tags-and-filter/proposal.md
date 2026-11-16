# Change: Tags on notes, shared with tasks, and one Filter menu in the notch's Notes

## Why
David, 2026-11-16: "where do i see wispr flow notes, I need provision in ui to tag a note and tags will be system
wide concept, i need to filter by tags here and source too, it should be simple."

Wispr Flow's meeting summaries (PR #63) are mixed into the notch's Notes list by date, so they are easy to miss.
Tasks already have tags, colours and a filter menu, while notes have no tags and no notion of where they came from.

## What Changes
- Tags become one Kannu-wide set.
  - A note carries tags, cleaned by tasks' one rule (`TaskItem.cleanedTags`).
  - Every tag field suggests tasks' and notes' tags (`SharedTags.inUse`).
  - A tag has one colour everywhere. The colours stay in tasks.json, so with Tasks off, note tags draw uncoloured.
- Tags are Kannu's alone.
  - They are never written into an Apple note, and never a reason to push one or to move its date.
  - A Wispr Flow meeting's tags are kept by its meeting id. Its title and summary are still never stored.
  - A tag or a pin set while an Apple Notes sync runs now survives the sync (`AppleNotesMergePolicy.reconcile`'s
    `carry`).
- Every note has a source, where it was made: Kannu, Apple Notes or Wispr Flow.
  - A note made in Kannu stays Kannu's when synced.
- The notch's Notes header gets one Filter menu: Source, Tag, Colour and Show all.
  - It is remembered, and a "Filtered · Show all" line shows while it narrows.
  - The magnifying glass only searches, and the colour-chip row is gone.
- The notch note editor gets a one-line tag row, and a `#word` typed into a title becomes a tag.
- Note cards show "#first +N".

## Impact
- Specs: `tags` (one set across tasks and notes), `notes` (tags, sources, the Filter menu).
- Code:
  - `Kannu/models/NoteFilter.swift` (new), `Kannu/managers/SharedTags.swift` (new);
  - `Kannu/components/Notch/NoteFilterMenu.swift` and `NoteTagsRow.swift` (new);
  - `NotchNotesView.swift`, `NotesManager.swift`, `AppleNotesMergePolicy.swift`, `TaskQuickAdd.swift`;
  - `Constants.swift` (`NoteItem.tags`, four Defaults keys);
  - the four task tag-suggestion sites.
- Brain › Notes does not show tags yet; that is a later change.
