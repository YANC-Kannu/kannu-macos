# Change: Calls in other apps show in the notch

## Why
A call in WhatsApp, or another calling app, shows nowhere in Kannu: the closed notch keeps its music, and the only sign
is the bare microphone dot. David on 24 Nov, after two probe runs on his Mac: "can the call take over the media screen
maybe as swipeable and call geting priority". He chose: the calling app's own notification stays as it is ("no let the
default notification stay on primary screen") and the notch never opens by itself; the call shows on the media screen
when the notch is opened, swipeable with media; on the closed notch the call goes above music only, so a running timer
and a screen recording keep the notch. It lands in 2.0.

What the probes measured on macOS 27.2.1:
- Reading CoreAudio's process list needs no permission and raises no prompt. When a WhatsApp call connected, the
  default input device's "running somewhere" event fired and the list named `net.whatsapp.WhatsApp` with input and
  output both running. A ringtone alone was output with no input.
- A process starting to capture sent no per-process event, 12 times out of 12. Stops did arrive. So the trigger is the
  device-level event with a read of the process list, and a bounded re-read while the microphone is in use.
- A Slack huddle (25 Nov) ran in `com.tinyspeck.slackmacgap.helper`, input and output both running. On leaving, the
  device-level event fired and the helper's input stopped, with no per-process event; its output ran 11 s longer.
- A WhatsApp voice note (25 Nov) captured **and** played for its whole length, exactly as a call does, and a build
  from this change showed it as a call. What differs: a call's capture devices were the microphone and the speakers
  (echo cancellation taking the output as its reference), a voice note's the microphone alone. When the recording was
  deleted, nothing announced that the capture had stopped: the device-level event came 2 s later.

## What Changes
- **Detection, off the main thread** (`CallAudioProcessMonitor`): block listeners on one private serial queue for the
  default input device's "running somewhere" flag, a change of default input device and a change of the process list.
  Each one reads which catalog apps capture and play, and whether a capture draws on a device the app plays to.
  While the microphone is in use, and only then, the reading is retaken every 2 s, and every second while a catalog
  app is itself capturing. `stop()` removes every listener and the timer.
- **The catalog and the rule** (`CallActivity.swift`, pure, in the logic test target): an app matches by its bundle ID
  or a helper's (the ID followed by a dot). A call starts when an app both captures and plays, goes on while it
  captures, and ends 2 s after it stops. For WhatsApp a call also needs a capture from a device it plays to, which
  its voice notes lack. WhatsApp and Slack are verified on a real call and a real huddle. Zoom,
  Microsoft Teams, Discord, Telegram and Signal are matched by their public bundle IDs, unverified. Browsers are
  left out.
- **One published value** (`CallActivityManager`), started in `continueLaunch()` behind a new setting,
  `enableCallActivity` (on), and stopped when the setting goes off.
- **The closed notch.** A call pill: the calling app's still icon in a left wing, the housing, and a phone glyph with
  the elapsed time in a right wing, with a camera glyph while the camera is on (`ClosedCallPillLayout`, pure). It is
  drawn ahead of music for the whole call. A running timer or a screen recording keeps the notch, but for the call's
  first 5 s. An agent's switch still takes its 7 s ahead of it. Hidden while locked or while the notch hides for a
  full-screen app.
- **The open notch.** During a call the media screen has two pages, Call and Media (`HomePage`, pure), with a
  "Call · Media" label pair and a two-finger sideways swipe between them; a sideways swipe skips no track then. Every
  hover or click that opens the notch during a call lands on the media screen's call page. With no call the media
  screen is as it was.
- **Brain › Settings › Live activities › Calls:** one switch and a footer, one search entry.
- **Never:** the notch opening by itself, anything drawn over or in place of the calling app's own notification, or
  any action on the calling app.
- **Not in this change:** a ring. The resolver and the views already take one, and the opt-in observer that sees it
  follows in its own change.

## Impact
- Affected specs: `call-activity` (new capability, five ADDED requirements).
- Affected code:
  - `Kannu/models/CallActivity.swift`, `Kannu/models/HomePage.swift`, `Kannu/sizing/ClosedCallPillLayout.swift` (new,
    in the test target);
  - `Kannu/managers/CallAudioProcessMonitor.swift`, `Kannu/managers/CallActivityManager.swift` (new);
  - `Kannu/components/Calls/CallLiveActivity.swift`, `CallPageView.swift` (new, parameters only);
  - `Kannu/ContentView.swift` (the branch between the agent pill and music, the takeover, the skip-gesture gate, where
    an open lands), `Kannu/KannuViewCoordinator.swift` (`SneakContentType.call` and its pair in the hand-written `==`);
  - `Kannu/components/Notch/NotchHomeView.swift` (the two pages), `HorizontalSwipeMonitor.swift` (takes the page type);
  - `Kannu/KannuApp.swift` (start and stop), `Kannu/models/Constants.swift` (`enableCallActivity`);
  - `Kannu/components/Settings/LiveActivitiesSettings.swift`, `SettingsView.swift`, `Kannu/Localizable.xcstrings`;
  - `Kannu/helpers/DebugSnapshot.swift` (the `closedCallPill` and `homeCallPage` boards).
- No change to the agent light, the timer, the music pill's own drawing, the privacy monitors or window creation. No
  new permission and no new entitlement.
