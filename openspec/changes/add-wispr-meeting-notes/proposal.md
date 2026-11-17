# Change: Wispr Flow's meeting summaries in the notch's Notes, read-only

## Why
David, 2026-11-16: "I have wispr flow installed, see if we can connect that notes to kannu notes". He chose meeting
summaries only (Wispr Flow's Notetaker), shown as a read-only live mirror. Kannu never writes to Wispr.

Wispr Flow is an Electron app, not sandboxed, and keeps its data in a Sequelize SQLite database in WAL mode at
`~/Library/Application Support/Wispr Flow/flow.sqlite`. Its official MCP endpoint was not used: it needs a cloud OAuth
sign-in, network access and stored tokens to reach data already on the Mac, and Kannu runs locally.

## What Changes
- `WisprFlowMeetingsStore` (Foundation and SQLite only) reads the `Meetings` table with `mode=ro`.
  - It never uses `immutable=1`, so the WAL is read.
  - It checks the schema first.
  - It returns live meetings with a summary, newest first, at most 50.
- `WisprFlowMeetingsManager` keeps them in memory only, as `NoteItem`s with a `wisprMeetingId`.
  - It reads them off the main actor as the notch's Notes tab appears and on its sync button.
  - There is no timer or file watcher.
  - The log records counts and error cases only.
- The notch's Notes list shows the meetings after Kannu's notes.
  - Each has a waveform glyph and a neutral bar, and its hover offers Copy only.
  - Opened, a meeting is read-only, with "Open in Wispr Flow".
  - The editor's save paths return before saving one.
- A Brain › Notes › Wispr Flow switch, "Show Wispr Flow meeting summaries", off by default.

## Impact
- Specs: `notes` (ADDED: Wispr Flow meeting summaries, read-only).
- Code:
  - `Kannu/managers/WisprFlowMeetingsStore.swift` and `WisprFlowMeetingsManager.swift` (new);
  - `Kannu/components/Notch/NotchNotesView.swift`, `Kannu/components/Settings/NotesSettings.swift`, `SettingsView.swift`;
  - `Kannu/models/Constants.swift` (`NoteItem.wisprMeetingId`, `enableWisprFlowMeetings`).
- Brain › Notes' own list does not show the meetings; that is a later change.
