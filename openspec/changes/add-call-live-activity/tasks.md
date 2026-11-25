# Tasks: add-call-live-activity

Tags: **[Mac]** needs a Mac to build, test or render; **[David]** his decision, his check or his yes.
Nothing is committed, pushed or opened as a PR without David's yes in the current chat turn.

## 1. Detection and state
- [x] 1.1 `CallActivity.swift` (pure, in the test target): the catalog with helper matching by bundle-ID prefix, and
  the resolver to none, ringing or ongoing-since, with a 2 s grace.
- [x] 1.2 `CallAudioProcessMonitor`: block listeners on one private serial queue, the re-read only while the
  microphone is in use (2 s, and 1 s while a catalog app captures), and `stop()`.
- [x] 1.4 A WhatsApp voice note is not a call (David, 2026-11-25: "incorrectly detected voice note"): the monitor reads
  whether a capture draws on a device the app plays to, and WhatsApp's calls need it.
- [x] 1.3 `CallActivityManager`: one published value; started in `continueLaunch()` behind `enableCallActivity`, stopped
  when the setting goes off.

## 2. The closed notch
- [x] 2.1 `ClosedCallPillLayout` (pure, in the test target) and `CallLiveActivity`.
- [x] 2.2 `ContentView`: the branch between the agent pill and music; a timer or a recording keeps the notch but for
  the 5 s takeover; one line in the empty-state check.
- [x] 2.3 `SneakContentType.call` and its pair in the hand-written `==`; the takeover is never drawn or sized as a HUD.

## 3. The open notch
- [x] 3.1 `HomePage` (pure, in the test target) and `CallPageView`; `HorizontalSwipeMonitor` takes the page type.
- [x] 3.2 `NotchHomeView`: the call page, the swipe and the "Call · Media" labels, only while a call exists.
- [x] 3.3 `ContentView`: no track skip while a call has a page; a hover, a click or a wing opens on the media screen
  during a call; a dragged file still opens the shelf.

## 4. Settings and strings
- [x] 4.1 Live activities › Calls: the switch, the footer, one search entry; the highlight inventory to 248 / 279 / 273.
- [x] 4.2 Every new string in all 17 languages.

## 5. Gates
- [x] 5.1 Unit tests for the catalog, the resolver, the layout, the pages and the swipe; `ClosedCallPillRulesTests` and
  `HomeCallPageRulesTests`, each rule against a planted offender. [Mac]
- [x] 5.2 Full KannuTests and the Debug build, with compile tasks confirmed. [Mac]
- [x] 5.3 The `closedCallPill` and `homeCallPage` boards, and `closedAgentPill` before and after. [Mac]
- [x] 5.4 `bash .githooks/pre-commit` and `openspec validate --all --strict`. [Mac]
- [x] 5.5 A Slack huddle with David while a probe ran (2026-11-25): joined, unmuted, left. The helper captured and
  played, and the capture stopped on leaving, so Slack is listed. [Mac] [David]
- [x] 5.5b A WhatsApp voice note and three WhatsApp calls with David while a device probe ran (2026-11-25): the
  difference in 1.4, and the clock that ran on after Delete (re-read to 1 s, grace to 2 s). [Mac] [David]
- [ ] 5.5a Still to measure: a muted huddle or call; a clip recorded in Slack; a call and a voice note on a headset
  that is microphone and speaker in one, where the two cannot be told apart. If a mute reads as a hang-up for an app,
  that app is dropped until it can be told apart. [Mac] [David]
- [ ] 5.6 David's yes to commit, push and open the PR into `development`. [David]
- [ ] 5.7 David's checks on a build from the branch: a WhatsApp call with music playing; with a timer running; opening
  the notch mid-call and swiping; a swipe with no call still skips a track; WhatsApp's own call window unchanged and
  the notch never opening by itself; no permission dialog; CPU near idle over a 5 minute call; hidden when locked or
  full screen. [Mac] [David]

## 6. Later, in its own change
- [ ] 6.1 The ring: an opt-in Accessibility observer for the catalog apps with a known ring window, WhatsApp first.
- [ ] 6.2 FaceTime, once its capturing process is measured.
