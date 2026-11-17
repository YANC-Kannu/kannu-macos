# Change: One primary control and one colour per card in the notch's Notes

## Why
David, 2026-11-16, on a screenshot of the notch's Notes over a red skin: "I don't like the design here, review that
based on golden triangle rules".

The open panel is about 732 × 226 pt, so its golden-triangle power points sit about 9 % in from each corner. The review
found five problems:
1. The top-right point held five equal filled circles, with a red trash next to "+".
2. The top-left card, where the eye lands first, read "Untitled Note".
3. Previews repeated their titles and stopped at the first line break.
4. Seven accent uses gave the eye nothing to follow. Yellow and red among them mean "needs input" and "stopped" in
   Kannu's traffic light.
5. A textured skin's streaks ran under the translucent cards.

## What Changes
- **Header:**
  - "+" is the one filled control, alone at the right end.
  - Search, Create from Clipboard and Clear Notes are plain neutral glyphs before it, and nothing in the header is red
    or yellow.
  - Sync folds into the Apple logo by the title.
- **Cards:** `NoteDisplayText` (Foundation only) drives what each card shows. Display only; stored notes are unchanged.
  - An untitled note shows its first line.
  - A first line that repeats the title is dropped.
  - Markdown heading and bullet markers are stripped.
  - Lines are joined so one line fills the card.
- **Card colour:**
  - The bar is each card's only colour; pins and borders are neutral.
  - A scrim of the notch's fill sits under each card, so its text keeps contrast over a skin.

## Impact
- Specs: `notes` (ADDED: the notch's note cards and header).
- Code: `Kannu/models/NoteDisplayText.swift` (new), `Kannu/components/Notch/NotchNotesView.swift`.
