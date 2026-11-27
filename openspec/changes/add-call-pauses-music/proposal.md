# Change: A call pauses the music

## Why
Music keeps playing over a call. On 27 Nov a WhatsApp call connected at 04:03:58 IST while Spotify was playing, and
Spotify played on through the whole call: Kannu sent no command, which was correct then, because the calls feature
(`add-call-live-activity`) only watches and every play/pause command Kannu sends comes from a click. David: "when
whatsapp call starts i think music starts and donot stop in kannu". He chose on by default, and had no preference on
resuming, so this change takes the narrow reading: pause only.

## What Changes
- **The trigger:** `CallActivityManager.activity` becomes an ongoing call, from none or from a ring (rings are not
  produced yet).
- **The conditions:** the new setting `pauseMusicDuringCalls` (on) and `enableCallActivity` are both on, Kannu's music
  state says playing, and the music's source is not the calling app (WhatsApp is the Now Playing app for its own voice
  notes).
- **The action:** one explicit `MusicManager.pause()`, never a toggle or a play.
- **Once per call:** nothing while the call goes on, nothing when it ends, and no resume.
- `CallMusicPolicy` (pure, in the logic test target) decides; `CallMusicPauser` follows `CallActivityManager.$activity`,
  asks the policy and sends the pause. It is started beside the call monitor in `continueLaunch()` and when either
  switch changes, and has an explicit `stop()` (docs/REGRESSIONS.md, entry 19).
- **Brain › Settings › Live activities › Calls:** a "Pause music during calls" switch with a footer, greyed out while
  calls are off, and one search entry.
- **Not in this change:** resuming the music after a call, and pausing on a ring. Each would be its own opt-in.

## Impact
- Affected specs: `call-activity` (one ADDED requirement).
- Affected code:
  - `Kannu/models/CallMusicPolicy.swift` (new, in the test target), `Kannu/managers/CallMusicPauser.swift` (new);
  - `Kannu/KannuApp.swift` (start and stop), `Kannu/models/Constants.swift` (`pauseMusicDuringCalls`),
    `Kannu/managers/CallActivityManager.swift` (its doc comment);
  - `Kannu/components/Settings/LiveActivitiesSettings.swift`, `SettingsView.swift`, `Kannu/Localizable.xcstrings`.
- No change to call detection, the pill, the call page or any music controller. No new permission: the pause goes
  through the music source's controller exactly as the notch's own pause button does.
