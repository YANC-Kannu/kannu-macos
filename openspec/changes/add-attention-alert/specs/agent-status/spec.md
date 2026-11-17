## ADDED Requirements

### Requirement: The attention alert is off by default
Kannu SHALL ship the attention alert switched off (`Defaults[.attentionAlertEnabled]`, default `false`). Brain › Agents
SHALL offer a switch for it, a sound picker (`Defaults[.attentionAlertSound]`) and a button that previews the chosen
sound. The picker SHALL list None, then Kannu alarm (the timer's bundled `timer.mp3`), then the 14 macOS system sounds by
name, with Glass as the default. A saved system sound's stored value SHALL keep loading. The preview button SHALL be
disabled while None is chosen. Settings search SHALL land on the switch's row.

#### Scenario: A fresh install stays quiet
- **WHEN** a new user finishes onboarding and an agent turns yellow
- **THEN** Kannu plays no sound and runs no shimmer

#### Scenario: Previewing a sound
- **WHEN** the user picks a sound and presses the preview button
- **THEN** Kannu plays that sound once, whether or not the alert is on

#### Scenario: None gives the shimmer only
- **WHEN** the sound is None and an agent turns yellow
- **THEN** Kannu plays nothing and runs the shimmer

#### Scenario: Kannu alarm plays once
- **WHEN** the sound is Kannu alarm and an agent turns yellow
- **THEN** Kannu plays `timer.mp3` once, never looped

### Requirement: One alert per session per yellow episode
With the alert on, Kannu SHALL alert when a visible, non-simulated agent session enters `awaitingInput`. A session
that stays yellow SHALL NOT alert again. A session that leaves yellow (or stops being visible) and turns yellow again
SHALL start a new episode. Sessions that turn yellow within 3 seconds of an alert SHALL be covered by that alert.

#### Scenario: A session stays yellow
- **WHEN** a session turns yellow, alerts, and the monitor republishes it yellow many times
- **THEN** Kannu alerts once

#### Scenario: Several sessions turn yellow together
- **WHEN** two sessions turn yellow in the same rescan, or a second one within 3 seconds of the first
- **THEN** Kannu alerts once

#### Scenario: A session asks again
- **WHEN** a session that alerted goes green after the user answers, and later turns yellow again
- **THEN** Kannu alerts again

### Requirement: The alert shows on the notch and on the lock screen
An alert SHALL play the chosen sound and draw one shimmer across the notch's body. While the Mac is locked, the same
shimmer SHALL draw on the lock-screen pill (`LockScreenLiveActivityOverlay`), the only Kannu window shown there. When
the lock-screen live activity is off, the pill SHALL show for the alert alone
(`LockScreenLiveActivityWindowManager.flashForAttentionAlert`) and go when the flash ends, through one sleep that
unlocking cancels.
The shimmer SHALL end by itself: a bounded animation with no repeating timer, no `repeatForever` and no
`TimelineView`.

#### Scenario: Locked Mac
- **WHEN** the Mac is locked, the lock-screen pill is shown, and an agent turns yellow
- **THEN** the sound plays and the shimmer runs across the pill

#### Scenario: Locked Mac with the lock-screen live activity off
- **WHEN** the Mac is locked, the lock-screen live activity is off, and an agent turns yellow
- **THEN** the pill appears, the shimmer runs across it, and the pill goes when the flash ends

#### Scenario: Unlocking during the flash
- **WHEN** the pill is showing for an alert and the user unlocks the Mac
- **THEN** the pill's pending hide is cancelled and the pill goes with the unlock

### Requirement: Reduce Motion gives a static glow
When the system's Reduce Motion setting is on at the moment of the alert, Kannu SHALL draw a static glow in the
awaiting-input colour instead of the moving shimmer.

#### Scenario: Reduce Motion on
- **WHEN** Reduce Motion is on and an agent turns yellow
- **THEN** the notch shows a still glow for the alert's duration, with no sweep

### Requirement: Nothing alerts before the Terms and onboarding
The alert's source SHALL start only inside `continueLaunch()`, after the Terms of Use are accepted. It SHALL NOT alert
until onboarding is complete. Yellows already showing when it starts, or when the switch turns on, SHALL be recorded
and SHALL NOT alert.

#### Scenario: Onboarding not finished
- **WHEN** the Terms are accepted, onboarding is still open, the switch is on and an agent turns yellow
- **THEN** Kannu does not alert

#### Scenario: Relaunch with a waiting agent
- **WHEN** Kannu relaunches while an agent is already yellow
- **THEN** Kannu does not alert for that agent's current wait
