## ADDED Requirements

### Requirement: Wispr Flow meeting summaries, read-only
The notch's Notes list SHALL show Wispr Flow's Notetaker meeting summaries beside Kannu's notes
(`Kannu/components/Notch/NotchNotesView.swift`) while "Show Wispr Flow meeting summaries" (`enableWisprFlowMeetings`,
off by default) is on.

**How they are read.** `WisprFlowMeetingsStore` (`Kannu/managers/WisprFlowMeetingsStore.swift`) SHALL:
- read Wispr Flow's local database at `~/Library/Application Support/Wispr Flow/flow.sqlite` with SQLite's `mode=ro`;
- never write to it, and never open it with `immutable=1`;
- check every `Meetings` column it reads before reading;
- return only meetings that are not deleted and have a summary, newest first, at most 50.

`WisprFlowMeetingsManager` (`Kannu/managers/WisprFlowMeetingsManager.swift`) SHALL:
- keep the meetings in memory only, never in `savedNotes`, so they never reach Apple Notes sync or Clear Notes;
- read them off the main actor as the Notes tab appears and on its sync button, with no timer or file watcher;
- log counts and error cases only, never a title or a summary.

**How they behave.** A meeting SHALL be read-only, with Copy and "Open in Wispr Flow" and no pin, delete or colour.
The notch editor's save and autosave SHALL return before saving one.

#### Scenario: Off by default
- **WHEN** Kannu is installed and the user has not turned the switch on
- **THEN** Kannu never reads Wispr Flow's files, and the Notes list shows Kannu's notes only

#### Scenario: Reading the database
- **WHEN** the switch is on and the notch's Notes tab appears while Wispr Flow is running
- **THEN** the meetings with a summary are listed, read with `mode=ro`, and Wispr Flow's database file is left unchanged

#### Scenario: Wispr Flow not installed, or nothing to show
- **WHEN** the database file is missing, its `Meetings` table is missing a column Kannu reads, or no meeting has a summary
- **THEN** no meeting is listed and nothing is guessed; Kannu's notes are listed as before

#### Scenario: A meeting is never saved
- **WHEN** the user opens a meeting in the notch editor and goes back, or the notch closes
- **THEN** nothing is saved to `savedNotes`, and the meeting is gone from the list once Wispr Flow deletes it
