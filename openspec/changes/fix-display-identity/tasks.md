# Tasks: fix-display-identity

## 1. Implementation
- [x] 1.1 `ScreenFacts` carries the display UUID; `DisplayPlacementResolver` resolves `chooseDisplay` by UUID, with the
  legacy name only while no UUID is stored; add `chosenDisplayUUID`, `screen(withID:in:)` and `pickerTitles`.
- [x] 1.2 `NSScreen.displayID`, `NSScreen.displayUUID` and `NSScreen.withDisplayID(_:)` in `DisplayPlacementRuntime.swift`;
  the runtime reads `preferredScreenUUID`, migrates `preferred_screen_name`, and stores the UUID once.
- [x] 1.3 `vm.screen` becomes `vm.screenID`; launch and `adjustWindowPosition` seed it from the resolved screen.
- [x] 1.4 The sizing helpers, `ContentView`'s screen lookups (`isPointerOnOpenNotch` and `attachedWindowFrames` included),
  the HUD and sneak-peek targets, the fullscreen detector and `ClosedNotchVisibility`, and the control windows match ids.
- [x] 1.5 Brain › General › Display lists every display by UUID, with numbered titles for shared names.
- [x] 1.6 `screenConfigurationDidChange` compares display ids.

## 2. Tests
- [x] 2.1 `DisplayIdentityTests`: two same-named displays resolve to two screens; the pointer check's rectangle comes
  from each display's own frame; the migration (resolved, unresolved, stored UUID wins); a reconnect under a new id.
- [x] 2.2 `DisplayIdentityRulesTests`: no screen is looked up by `localizedName` in the app's sources, against planted
  offenders.
- [x] 2.3 Update the source pins that quoted the old launch seed and fullscreen filter.
- [x] 2.4 PR #80 review: id-to-frame layout changes, control-window refresh by display, the battery HUD target
  following the notch; a fixture test and a source pin for each.
- [x] 2.5 The per-display overrides keyed by UUID, carried over once per display from the name-keyed ones; three
  fixture tests and a source rule.

## 3. Docs and gates
- [x] 3.1 REGRESSIONS: entry 17 and entry 23 addenda; one CHANGELOG entry.
- [ ] 3.2 Full KannuTests, the Debug build with compile activity, and `bash .githooks/pre-commit`. [Mac]
- [ ] 3.3 `OPENSPEC_TELEMETRY=0 npx -y @fission-ai/openspec@0.23.0 validate --all --strict --no-interactive`.
- [ ] 3.4 Two identical monitors, checked by eye: each notch stays open under the pointer, the picker lists both, the
  choice survives unplugging and replugging, and Brain › General shows one override group for each. [Mac] [David]
