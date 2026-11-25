## ADDED Requirements

### Requirement: A call in another app is detected without a permission
Kannu SHALL recognise a call in a catalog app from CoreAudio's process list alone: which processes are capturing and
which are playing. It SHALL raise no permission prompt for this and SHALL read no audio. A process SHALL belong to a
catalog app when its bundle ID is the app's or starts with the app's followed by a dot. A call SHALL start when one app
both captures and plays, SHALL go on while that app captures, and SHALL end 2 seconds after that app stops capturing.
Output with no input (a ringtone) SHALL NOT start a call. For an app whose calls were measured to capture from a device
they also play to, and whose recordings were measured not to (WhatsApp), a call SHALL start only with such a capture,
so a voice note, which captures and plays for its whole length, SHALL NOT show as a call. A browser SHALL NOT be a
catalog app. The reading SHALL be taken off the main thread, on the default input device's "running somewhere" event,
on a change of default input device and on a change of the process list, and again every 2 seconds while the
microphone is in use, every second while a catalog app is itself capturing, and at no other time. Switching **Show
calls from other apps** off SHALL remove every listener and stop that timer.

#### Scenario: A WhatsApp call connects
- **WHEN** a WhatsApp call connects and WhatsApp both captures and plays audio
- **THEN** Kannu shows a call for WhatsApp, timed from that moment, and no permission dialog appears

#### Scenario: A ringtone plays
- **WHEN** a catalog app plays a ringtone and captures nothing
- **THEN** no call is shown

#### Scenario: A WhatsApp voice note is recorded
- **WHEN** the user records a voice note in WhatsApp on a Mac's own microphone and speakers
- **THEN** no call is shown, although WhatsApp captures and plays for the whole recording

#### Scenario: A call ends
- **WHEN** the calling app stops capturing
- **THEN** the call is gone within about 3 seconds

#### Scenario: The microphone changes mid-call
- **WHEN** the calling app stops capturing and starts again within 2 seconds
- **THEN** the same call goes on with the same elapsed time

#### Scenario: The setting is switched off
- **WHEN** the user switches **Show calls from other apps** off during a call
- **THEN** the pill and the call page go, and Kannu holds no audio listener and no timer for calls

### Requirement: The closed notch shows a call above music only
While a call runs, the closed notch SHALL draw a call pill ahead of the music pill: the calling app's still icon in a
left wing, the housing in the middle, and in a right wing a phone glyph with the elapsed time, plus a camera glyph
while the camera is in use. Both wings SHALL be the same width, so the housing stays centred, and the pill SHALL keep
one width for the whole call. A running timer or a screen recording SHALL keep the closed notch; when a call starts
then, the pill SHALL take the notch for 5 seconds and hand it back. An agent's state switch SHALL still take the notch
for its reveal ahead of the call. The pill SHALL NOT show while the screen is locked or while the notch hides for a
full-screen app. Nothing in the pill SHALL repeat or animate by itself: the elapsed time is one self-updating text.

#### Scenario: A call starts while music plays
- **WHEN** music is playing and a call connects
- **THEN** the call pill replaces the music pill for the whole call, and the music pill returns within about 3 seconds
  of the call ending

#### Scenario: A call starts while a timer runs
- **WHEN** a timer is running and a call connects
- **THEN** the call pill shows for 5 seconds, then the timer has the notch back for the rest of the call

#### Scenario: An agent changes state during a call
- **WHEN** a call is running and an agent's state switches on a MacBook with a notch
- **THEN** the agent pill shows for its 7 seconds, then the call pill returns

### Requirement: The open notch's media screen has a call page during a call
While a call runs, the media screen SHALL have two pages, Call on the left and Media on the right, a "Call · Media"
label pair below it, and a two-finger sideways swipe that turns the page. The call page SHALL show the calling app's
icon where the album art sits, a title (the app's name, or the caller's name when a ring gave one) and the elapsed
time, or "Ringing". The screen SHALL open on the call page, and a call that begins while it is open SHALL turn it to
that page. While a call runs, a sideways swipe SHALL NOT skip a track; the media buttons still do. With no call, the
media screen SHALL be the music player alone, with no labels and no page swipe, and a sideways swipe SHALL skip tracks
as before. The call page SHALL offer no control over the call.

#### Scenario: The notch is opened during a call
- **WHEN** the user hovers or clicks the closed notch during a call
- **THEN** the notch opens on the media screen's call page, whichever tab was open last

#### Scenario: A swipe during a call
- **WHEN** the user swipes sideways with two fingers on the media screen during a call
- **THEN** the page turns between Call and Media and no track is skipped

#### Scenario: A swipe with no call
- **WHEN** no call is running and the user swipes sideways on the media screen
- **THEN** the track skips, and no "Call · Media" labels are shown

#### Scenario: A file is dragged to the notch during a call
- **WHEN** the user drags a file onto the closed notch during a call
- **THEN** the notch opens on the shelf, as it does with no call

### Requirement: Kannu only watches a call
Kannu SHALL NOT open the notch because a call starts, rings or ends. It SHALL NOT draw over, move, hide or replace the
calling app's own call window or notification, and SHALL NOT act on the calling app. It SHALL log no more about a call
than the catalog's own key for the app and whether the call runs or rings.

#### Scenario: A call starts with the notch closed
- **WHEN** a call connects while the notch is closed
- **THEN** the notch stays closed, and the calling app's own call window appears exactly as it does without Kannu

### Requirement: Calls have one setting
Brain › Settings › Live activities SHALL have a **Calls** section with one switch, **Show calls from other apps**, on
by default, a footer that says what is shown and that Kannu reads which app uses the microphone and never the audio,
and one search entry that lands on the switch. The section SHALL show no live status and SHALL NOT observe the call
manager.

#### Scenario: Someone searches for calls
- **WHEN** the user types "call" in Brain's search
- **THEN** **Show calls from other apps** is offered and opens Live activities on that row
