# Tasks: update-sideways-agent-pill

Tags: **[Mac]** needs a Mac to build, test or render; **[David]** his decision or his yes.
Nothing is committed, pushed or opened as a PR without David's yes in the current chat turn.

## 1. Layout and setting
- [x] 1.1 `ClosedAgentPillLayout` (pure, in the test target): equal wings, the icon at `closed height − 12`, the shield.
- [x] 1.2 `AgentPillLayout` (`sideways`, `belowNotch`) and the `agentPillLayout` key, default `.sideways`.

## 2. Drawing
- [x] 2.1 `AgentTrafficLightIndicator` draws every placement (centred, beside, lock pill), so it stays the one observer.
- [x] 2.2 `ContentView`: the sideways branch ahead of music and the timer while the reveal is live; no light in their
  centres; no band; Reduce Motion fades.
- [x] 2.3 The lock-screen pill: the dot and the icon during a reveal while locked, and on the attention flash.

## 3. Brain and onboarding
- [x] 3.1 Brain › Agents › Traffic light › Advanced › Agent light position, its search entry on the disclosure, and a
  still preview of the chosen layout.
- [x] 3.2 Onboarding step 4's cards preview the sideways pill.
- [x] 3.3 Every new string in all 17 languages.

## 4. Gates
- [x] 4.1 `ClosedAgentPillLayoutTests` and `ClosedAgentPillRulesTests`; the timer, music, observation and inventory
  tests still pass. [Mac]
- [x] 4.2 Full KannuTests and the Debug build, with compile tasks confirmed. [Mac]
- [x] 4.3 The `closedAgentPill` board and the touched pages, before and after. [Mac]
- [x] 4.4 `bash .githooks/pre-commit` and `openspec validate --all --strict`. [Mac]
- [ ] 4.5 David's yes to commit, push and open the PR into `development`. [David]
- [ ] 4.6 David's checks on the beta.2 install: switches, music, a timer, locked with the live activity on and off,
  Below the notch, Reduce Motion, VoiceOver, fullscreen, a display without a notch. [Mac] [David]
