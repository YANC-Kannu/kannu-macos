# Change: The agent light beside the notch

## Why
On a notched MacBook the closed agent light grew a band of about 20 pt below the camera housing, and it stayed lit for
as long as music played or a timer ran, inside their pills. David on 18 Nov: "the pill doesnt grow downwards, instead
extends side ways and shows the icon of app on right side and dot on the left side; the legacy path can continue, maybe
deep in brain, but the setup and main marketing can be this". He chose: sideways for everyone, updaters included; one
still app icon; agent status only on state switches, ahead of persistent activities such as music, with no stacking;
and the lock-screen pill included. Beta.2 waits for it.

## What Changes
- **The sideways pill**, the default on a notched MacBook: the dot (Classic's three, Minimal's one) in a left wing, the
  housing in the middle, and the primary session's app icon in a right wing, all at the closed height, with no band.
  Both wings are `max(dots, icon) + 12` wide (`ClosedAgentPillLayout`, Foundation only, in the logic test target). The
  icon is `closed height − 12` square and never scales, pulses or animates. A pending high finding shows the shield
  glyph beside the dot; the shield-and-title pill stays with the band.
- **Priority, no stacking.** The pill shows only on a state switch, for the existing 7 s reveal. While the reveal is
  live it takes the closed notch ahead of music and a running timer. When it ends they return with no light in their
  centre. Displays without a notch and the Dynamic Island keep their centred dots.
- **The lock-screen pill.** During a reveal while locked, the lit dot replaces the lock icon and the app icon fills the
  other wing; then the lock icon returns. The attention alert's flash carries them too. The pill's window keeps its
  size.
- **The band stays** as `AgentPillLayout.belowNotch`, in Brain › Agents › Traffic light › Advanced ("Agent light
  position"), unchanged: the band, the light in the music and timer centres, and its persistence.
- **Reduce Motion** fades the wings instead of sliding them. VoiceOver reads one label, e.g. "Agent status: working,
  Claude Code".
- **Onboarding** step 4's cards preview the sideways pill, with a symbol stand-in for the icon.
- **The notch-skin prompt** asks for a dark corridor through the middle, where the dot and the icon sit.

## Impact
- Affected specs: `agent-status` (four ADDED requirements).
- Affected code:
  - `Kannu/sizing/ClosedAgentPillLayout.swift` (new, in the test target);
  - `Kannu/components/AgentStatus/AgentTrafficLightLiveActivity.swift` (placements, the pill rows, the still icon);
  - `Kannu/components/AgentStatus/AgentProviderIconView.swift` (the symbol stand-in);
  - `Kannu/ContentView.swift` (the priority branch, no centre light, Reduce Motion);
  - `Kannu/components/LockScreen/LockScreenLiveActivityOverlay.swift` and
    `Kannu/managers/LockScreenLiveActivityWindowManager.swift` (the lock-screen reveal);
  - `Kannu/components/Settings/AgentStatusSettings.swift`, `SettingsView.swift` (the Advanced row, its search entry,
    the preview);
  - `Kannu/components/Onboarding/TrafficLightStyleSelectionView.swift`;
  - `Kannu/enums/generic.swift`, `Kannu/models/Constants.swift`, `Kannu/Localizable.xcstrings`,
    `Kannu/helpers/DebugSnapshot.swift` (the `closedAgentPill` board), `Kannu/models/NotchSkinPrompt.swift`.
- No change to the monitor, the state ladder, the hook script, window creation or the 7 s window.
