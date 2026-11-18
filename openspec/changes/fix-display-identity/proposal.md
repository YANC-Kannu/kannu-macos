# Change: Pick the notch's display by identity, not by name

## Why
Kannu picked, stored and matched the notch's screen by `NSScreen.localizedName` (issue #24, deferred from PR #11's
review). Two identical monitors share that name, so every name lookup found the first of the pair:
- **The chosen display.** "Display" in Brain › General stored a name in `preferred_screen_name`. With two identical
  monitors the picker listed them as one choice, and the notch always went to whichever macOS listed first.
- **The view model's screen.** `vm.screen` held a name. With one window per display, the notch on the second of two
  identical monitors resolved its screen to the first one: its closed size, its notch-or-not check, its Dynamic Island
  check and its fullscreen verdict all read the wrong display.
- **The open notch's pointer check.** `isPointerOnOpenNotch` built the open body's rectangle from the first monitor's
  frame. On the second monitor the pointer was never "on the notch", so the notch closed under a pointer that was
  still over it, and the windows hanging off it (`attachedWindowFrames`) were read from the wrong window.

## What Changes
- **Live lookups use `CGDirectDisplayID`,** the identity `DisplayPlacementRuntime` and `DisplayPlacementResolver`
  already use. `vm.screen` (a name) becomes `vm.screenID`. The sizing helpers in `matters.swift`, `ContentView`'s screen
  lookups (the pointer check and its attached windows included), the HUD and sneak-peek targets, the fullscreen
  detector, the music and timer control windows and the Do Not Disturb activity all take or match an id.
  `localizedName` stays for what people read: the picker's titles and log lines.
- **The stored choice is the display's UUID** (`CGDisplayCreateUUIDFromDisplayID`), in a new `preferredScreenUUID`
  key. A `CGDirectDisplayID` is not promised to survive a reconnect or a reboot; the UUID is the identity macOS itself
  stores display arrangements under (design.md).
- **The old preference carries over.** While no UUID is stored, a `preferred_screen_name` that matches a connected
  display picks it and its UUID is stored; one that matches nothing falls back to the main display and is kept, so a
  monitor that wakes after launch is still honoured. Picking a display stores its UUID and, for a downgrade, its name.
- **The picker lists every display.** Two displays with one name are two choices, titled `Name (1)` and `Name (2)` in
  the order macOS lists them.
- **Reconnects.** The screen-change check compares display ids, not names, so a display that comes back under a new id
  rebuilds its window; the choice follows the UUID to the new id.

## Impact
- Affected specs: `display-placement` (new capability, ADDED requirements).
- Affected code: `DisplayPlacementResolver.swift`, `DisplayPlacementRuntime.swift`, `ClosedNotchVisibility.swift`,
  `KannuApp.swift` (`continueLaunch`, `adjustWindowPosition`, `screenConfigurationDidChange`), `KannuViewModel.swift`,
  `KannuViewCoordinator.swift`, `ContentView.swift`, `sizing/matters.swift`, `Constants.swift`,
  `GeneralSettings.swift`, `BatteryStatusViewModel.swift`, `FullscreenMediaDetection.swift`, the music and timer
  control window managers, `TimerLiveActivity.swift`, `DoNotDisturbLiveActivity.swift` and the lock-screen live
  activity window manager.
- Out of scope: the per-display style and "Always show" overrides stay keyed by name, as GeneralSettings already
  records; keying them by UUID is a follow-up with its own migration.
- No new permission and no new dependency.
