# Change: Alert when an agent turns yellow, on the lock screen too

## Why
The traffic light is ambient: a session that needs an answer turns the notch's light yellow and waits. Away from the
screen, or with the Mac locked, nothing calls the user back. Mobile pushes exist, but they need a provider and a phone.
David decided on 16 Nov that 2.0's beta.2 gets a local attention alert: a short sound and a shimmer across the notch
when an agent turns yellow, also while the Mac is locked. Yellow only.

## What Changes
- A new **attention alert**, off by default. When a visible agent session enters `awaitingInput`, Kannu plays a named
  system sound and runs one shimmer across the notch.
- **One alert per session per yellow episode.** A session that stays yellow never alerts again. Leaving yellow and
  coming back is a new episode. Several sessions that turn yellow together give one alert.
- **The lock screen.** While the Mac is locked, the main notch windows are hidden and the only Kannu window there is
  the lock-screen pill (`LockScreenLiveActivityOverlay`, a black pill with the lock icon). The shimmer draws on that
  pill as well as on the notch.
- **Reduce Motion** turns the shimmer into a static glow. The shimmer is a bounded, two-sweep animation, with no
  repeating timer and no `TimelineView`.
- **Nothing before the Terms and onboarding.** The alert's source starts inside `continueLaunch()`, and it stays silent
  until onboarding is complete. Yellows already on screen at launch, or when the setting turns on, never alert.
- **A setting** in Brain › Agents: "Alert when an agent needs you", with a sound picker and a preview button. It has a
  `Defaults` key, localized strings in all 17 languages, and a `settingsSearchIndex` entry whose `highlightID` matches
  the row's `.settingsHighlight(id:)`.

## Impact
- Affected specs: `agent-status` (new capability).
- Affected code:
  - `Kannu/managers/AgentStatus/AttentionAlert.swift` (new, pure logic, in the test target);
  - `Kannu/managers/AgentStatus/AttentionAlertManager.swift` (new);
  - `Kannu/components/AgentStatus/AttentionAlertOverlay.swift` (new);
  - `Kannu/managers/AgentStatus/AgentStatusNotificationBridge.swift` (feeds the manager the session list);
  - `Kannu/ContentView.swift` (the overlay in the notch's body fill);
  - `Kannu/components/LockScreen/LockScreenLiveActivityOverlay.swift` (the overlay on the lock-screen pill);
  - `Kannu/components/Settings/AgentStatusSettings.swift` and `SettingsView.swift` (the row and its search entry);
  - `Kannu/models/Constants.swift`, `Kannu/Localizable.xcstrings`, `Kannu/helpers/DebugSnapshot.swift`.
- No change to the hook script, the state ladder or the monitor.
