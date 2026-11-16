# Tasks: add-attention-alert

Tags: **[Mac]** needs a Mac to build, test or render; **[David]** his decision or his yes.
Nothing is committed, pushed or opened as a PR without David's yes in the current chat turn.

## 1. Logic
- [x] 1.1 `AttentionAlertTracker` (pure, in the test target): per-session yellow episodes, the 3-second coalesce, the
  quiet start, and the Reduce Motion style.
- [x] 1.2 `AttentionAlertManager`: fed by `AgentStatusNotificationBridge`'s session subscription, gated on the switch
  and on onboarding, plays the sound and publishes one bounded flash.

## 2. Drawing
- [x] 2.1 `AttentionAlertOverlay`: a two-sweep shimmer, or a static glow under Reduce Motion, in the awaiting-input
  colour.
- [x] 2.2 Draw it in the notch's body fill (`ContentView.notchBodyFill`) and on the lock-screen pill
  (`LockScreenLiveActivityOverlay`).

## 3. Setting
- [x] 3.1 `Defaults` keys `attentionAlertEnabled` (false) and `attentionAlertSound`.
- [x] 3.2 The Brain › Agents row with the sound picker and the preview button, its `settingsSearchIndex` entry, and
  every new string in all 17 languages.

## 4. Gates
- [x] 4.1 Rule tests: off by default; one alert per episode, several sessions at once included; Reduce Motion's static
  glow; nothing before the Terms or onboarding. [Mac]
- [x] 4.2 Full KannuTests and the Debug build, with compile tasks confirmed. [Mac]
- [x] 4.3 A snapshot board of the shimmer, the glow and the setting row, from a fixture, before and after. [Mac]
- [x] 4.4 `bash .githooks/pre-commit` with the CHANGELOG entry staged. [Mac]
- [x] 4.5 David's yes to commit, push and open the PR into `development`. [David]
- [ ] 4.6 A live check on the installed build: a real yellow, unlocked and locked. [Mac] [David]
