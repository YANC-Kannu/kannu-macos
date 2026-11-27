# Tasks: add-call-pauses-music

Tags: **[Mac]** needs a Mac to build, test or run; **[David]** his decision, his check or his yes.
Nothing is committed, pushed or opened as a PR without David's yes in the current chat turn.

## 1. The rule and the pauser
- [x] 1.1 `CallMusicPolicy` (pure, in the test target): previous and next call, the switches, playing, the source's
  bundle ID; `.pause` only on a start to ongoing.
- [x] 1.2 `CallMusicPauser`: follows `CallActivityManager.$activity`, sends one `MusicManager.pause()`, has `stop()`.
- [x] 1.3 `KannuApp`: `sync()` beside the call monitor in `continueLaunch()`; `stop()` when Calls goes off; `sync()`
  when "Pause music during calls" changes.
- [x] 1.4 `CallActivityManager`'s doc comment says a call may pause the music.

## 2. Settings and strings
- [x] 2.1 `pauseMusicDuringCalls` (on) in `Constants.swift`.
- [x] 2.2 Live activities › Calls: the switch and its footer, greyed out while Calls is off; one search entry; the
  highlight inventory moved to the measured counts.
- [x] 2.3 Both new strings in all 17 languages.

## 3. Tests and docs
- [x] 3.1 `CallMusicPolicyTests`; `CallMusicPauseRulesTests`, each rule failing with its offender planted.
- [x] 3.2 docs/SETTINGS.md, docs/release-notes/2.0.0.md, CHANGELOG.
- [x] 3.3 [Mac] Full KannuTests, the Debug build, `.githooks/pre-commit`, `openspec validate --all --strict`.

## 4. David's check
- [ ] 4.1 [David] Spotify playing, then a WhatsApp call: it pauses within about 2 s of connecting and stays paused.
- [ ] 4.2 [David] The switch off: the music keeps playing through a call.
- [ ] 4.3 [David] Music already paused: nothing happens.
- [ ] 4.4 [David] A WhatsApp voice note: no pause.
- [ ] 4.5 [David] His yes for the commit, the push and the PR into `development`.
