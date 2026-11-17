## ADDED Requirements

### Requirement: Notes carry Kannu-only tags
Every note in the notch's list SHALL take tags, read-only ones included: Apple Notes copies and Wispr Flow meetings.
- A note's tags SHALL be set only through `NotesManager.setTags`.
- They SHALL never be written into an Apple note.
- Setting them SHALL never push a note or change its modification date.
- A Wispr Flow meeting's tags SHALL be kept by its meeting id (`wisprMeetingTags`), and its title and summary still
  never stored.
- A tag or pin set while an Apple Notes sync runs SHALL survive the sync.

#### Scenario: Tagging a Wispr Flow meeting
- **WHEN** the user adds "acme" to a meeting in the notch editor
- **THEN** the meeting's card shows "#acme", and nothing is written to Wispr Flow or Apple Notes

### Requirement: A note's source is where it was made
Every note SHALL have one source (`NoteSource`):
- Wispr Flow for a meeting;
- Apple Notes for a note made in Apple Notes;
- Kannu otherwise.

A note made in Kannu SHALL stay Kannu's when synced. A note in Notes' Kannu folder SHALL count as Kannu's.

#### Scenario: A synced Kannu note
- **WHEN** a note made in the notch is synced to Apple Notes
- **THEN** its source stays Kannu

### Requirement: One Filter menu in the notch's Notes
The notch's Notes header SHALL show one Filter menu (`Kannu/components/Notch/NoteFilterMenu.swift`).
- **Contents:**
  - Source, offered only with two or more sources listed;
  - Tag;
  - Colour, only while "Enable color filtering" is on;
  - Show all, while it narrows.
- **Remembering:** the choices SHALL be kept in Defaults (`notesNotchSourceFilter`, `notesNotchTagFilter`,
  `notesNotchColorFilter`). While the filter narrows the list, a "Filtered · Show all" line SHALL show.
- **Search and colour chips:** the magnifying glass SHALL only search, and the colour-chip row SHALL be gone.
- **New notes:** a note made while filtered SHALL start with the filtered tag and colour. Any part it still fails SHALL
  clear once it is saved.
- **Holds:** the menu SHALL hold nothing open itself.

#### Scenario: Only Wispr Flow
- **WHEN** the user picks Filter › Source › Wispr Flow and closes the notch
- **THEN** reopening Notes lists only the meetings, under "Filtered · Show all"

### Requirement: A `#word` in a title becomes a tag
In the notch editor, a `#word` typed into a note's title SHALL become a tag:
- once a space ends it, on Return, when the title loses focus, and on Done, back or close;
- never from the autosave;
- never on a read-only note.

A `#word` the title had when the note opened SHALL stay in the title, so Apple Notes' own tags survive a sync.

#### Scenario: Typing a tag into a title
- **WHEN** the user types "Plan #acme " into a Kannu note's title
- **THEN** the title reads "Plan" and the note carries "acme"
