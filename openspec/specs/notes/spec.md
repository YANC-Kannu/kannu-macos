# notes Specification

## Purpose
Notes are typed in the notch, listed and created in Brain › Notes, and optionally synced with Apple Notes. This spec
covers Brain's Notes page, the New note sheet, list-detail, live data and the Apple Notes gate. The behaviour is as
built on `super/brain-6-around`.

## Requirements

### Requirement: Brain › Notes lists notes, pinned first
Brain › Notes (`Kannu/components/Settings/NotesOverview.swift`, `NotesSettings.swift`) SHALL list the notes with
pinned notes first. A note's own page SHALL be read-only. At wide windows the page SHALL show beside the list by the
same width rule as Tasks (`ListDetailLayout`, see `tasks`). Narrower, it SHALL take the list's place.

#### Scenario: A note beside the list
- **WHEN** Brain is full screen on a 14-inch Mac and the user selects a note
- **THEN** the note's page shows beside the list

### Requirement: New note sheet
New note SHALL open a small sheet with a title, the text and a colour (`Kannu/components/Settings/NewNoteSheet.swift`).
It SHALL save through `NotesManager.save` (`Kannu/managers/NotesManager.swift:74`), the same path the notch uses.

#### Scenario: Saving a new note
- **WHEN** the user fills the sheet and saves it
- **THEN** the note appears in Brain's list and in the notch

### Requirement: The page reads notes without observing them
The notch autosaves a note about every 1.5 s while it is typed. So Brain › Notes SHALL never observe the notes.
Instead it SHALL copy what it shows into `NotesPageData`, from one throttled subscription that runs only while Brain is
on screen (`NotesPageLiveDataRulesTests`). The page SHALL start no sync of its own. Only a press of its sync settings
SHALL start one.

#### Scenario: Typing in the notch with Brain open
- **WHEN** a note is typed in the notch while Brain › Notes is on screen
- **THEN** Brain's page updates at most twice a second

### Requirement: Apple Notes sync only after permission
Syncing with Apple Notes runs AppleScript, which raises a macOS Automation dialog on first use. So it SHALL run only
after `LaunchPermissionManager.mayTouch(.notesAutomation)` allows it
(`Kannu/managers/AppleNotesSyncManager.swift:82-93`). In Brain, deleting a note made in Apple Notes SHALL ask first
(`Kannu/components/Settings/NotesOverview.swift:42`).

#### Scenario: Permission not given
- **WHEN** the user chose Not now for Notes automation during onboarding
- **THEN** no sync runs and no Automation dialog appears
