# Design: fix-display-identity

## Two identities, each for what it is good at
- **`CGDirectDisplayID` for everything live.** It is what `NSScreen.deviceDescription["NSScreenNumber"]` carries, what
  the window dictionaries in `AppDelegate` are already keyed on, and what `DisplayPlacementResolver` returns. It is
  unique among the displays connected at one moment, which is all a live lookup needs.
- **The display UUID for the stored choice.** Apple documents a display id as staying constant only while certain
  display parameters do not change. In practice it can differ after a reboot, after a monitor moves to another port
  or dock, and between two identical monitors that report no serial number. A stored id can therefore point at
  nothing, or at another display, after a reconnect. `CGDisplayCreateUUIDFromDisplayID` gives the identity ColorSync
  and the display arrangement preferences are stored under, built to survive those events. It is stored as its
  canonical string.

Storing the name as well would bring the bug back: a stored UUID that matches no connected display falls back to the
main display, never to a display that only shares the old name.

## Migration
`preferred_screen_name` is read raw, the way `migrateScreenCaptureVisibility` reads its retired key, because a declared
`Key` would register a default. The rule is pure (`DisplayPlacementResolver.chosenDisplayUUID`):
1. A stored UUID wins, whether or not that display is connected.
2. Otherwise a legacy name that matches a connected display picks the first such display, as the old lookup did, and
   that display's UUID is stored. From then on an identical second monitor cannot take it.
3. Otherwise nothing is stored, the main display is used, and the name stays for the next look. A dock that wakes
   after launch would otherwise turn an unresolved choice into "main display" for good.

The migration runs where the choice is read (`DisplayPlacementRuntime.activeDisplayIDs`), so it needs no launch hook
of its own. It writes only when a name resolves, and only once.

## Reconnects
- `screenConfigurationDidChange` compared the set of names. A display that came back under a new id with the same
  name and frame changed nothing, so the window stayed keyed on a dead id. It now compares ids.
- With one window per display, `adjustWindowPosition` already tears down windows whose id is gone and builds one per
  new id; each new view model gets its own id.
- With one window, every `adjustWindowPosition` resolves the screen again and writes `vm.screenID`. The choice follows
  the UUID, so the chosen monitor is found under its new id.

## Rejected
- **A new identity type** wrapping id and UUID. Every caller needs one or the other, never both, and the resolver
  already speaks `CGDirectDisplayID`.
- **Keeping names and disambiguating with the frame.** Frames change when a display is rearranged or rescaled.
