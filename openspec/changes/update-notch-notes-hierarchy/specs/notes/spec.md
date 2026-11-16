## ADDED Requirements

### Requirement: The notch's Notes header and cards
**Header.** The notch's Notes header (`Kannu/components/Notch/NotchNotesView.swift`) SHALL have "+" as its one filled
control, at its right end. Its other controls SHALL be plain glyphs placed before "+", and none of them SHALL be red or
yellow, which in the notch mean an agent stopped or needs input. While Apple Notes sync is on, the Apple logo beside
the title SHALL be the sync button, turning while a sync runs.

**Card text.** A note card's text SHALL come from `NoteDisplayText` (`Kannu/models/NoteDisplayText.swift`), which
changes only what is displayed:
- a note left as "Untitled Note" shows its first line as its title;
- the preview drops a first line that repeats the title;
- Markdown heading and bullet markers are stripped;
- lines are joined, so one line fills the card;
- at most 600 characters are read.

**Card colour.** A card's bar SHALL be its only colour. A scrim of the notch's fill SHALL sit under the card's text.

#### Scenario: An untitled note
- **WHEN** a note saved without a title has the text "Call example.com support"
- **THEN** its card's title reads "Call example.com support"

#### Scenario: A synced note's preview
- **WHEN** a note from Apple Notes is titled "Acme launch" and its text starts with the line "Acme launch"
- **THEN** its card's preview starts with the next line, not with the title again
