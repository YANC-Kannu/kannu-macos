## ADDED Requirements

### Requirement: Screens are matched by display identity
Kannu SHALL select and look up the notch's screen by `CGDirectDisplayID`, never by `NSScreen.localizedName`. Each
notch view model SHALL hold the id of the display its window is on, and every per-screen decision for that view (its
closed size, whether it has a notch, its Dynamic Island style check, its fullscreen verdict, its HUD and sneak-peek
targets) SHALL read that display. `localizedName` SHALL NOT be used to select or look up a screen. It MAY be read
from a display already found by id: for text people read, and as the key of the per-display style and "Always show"
overrides (`displayStyleOverrides`, `alwaysShowOverrides`), which stay keyed by name and are outside this change.

#### Scenario: Two monitors with one name
- **WHEN** two connected monitors both report the name "DELL U2720Q" under ids 7 and 8
- **THEN** looking up id 8 returns the second monitor, not the first one with that name

#### Scenario: A display that is gone
- **WHEN** a view model's display id matches no connected display
- **THEN** the lookup finds no screen, and the view treats it as gone rather than as another display

### Requirement: The open notch's pointer check uses its own display
The open notch SHALL decide whether the pointer is on it from the frame of the display its view is on, using
`NotchInteractionGeometry.openNotchRect` unchanged, and SHALL count only the windows hanging off that display's notch
window.

#### Scenario: The second of two identical monitors
- **WHEN** the notch is open on the second of two same-named monitors and the pointer rests over its body
- **THEN** the pointer counts as on the notch, and the notch stays open

#### Scenario: The pointer over the other monitor's notch
- **WHEN** the pointer is over the first monitor's notch area
- **THEN** it does not count as on the second monitor's open notch

### Requirement: The chosen display is stored by UUID
"Display" in Brain › General SHALL list every connected display as its own choice, numbering the titles of displays that
share a name, and SHALL store the chosen display's UUID. In "A display I choose" mode Kannu SHALL use the display with that
UUID under whatever id it has now, and SHALL fall back to the main display while it is not connected, without changing
the stored choice.

#### Scenario: A reconnect under a new id
- **WHEN** the chosen monitor is unplugged and comes back with a different display id
- **THEN** the notch returns to that monitor

#### Scenario: The chosen monitor is unplugged
- **WHEN** the chosen monitor is not connected
- **THEN** the notch is on the main display, and the stored choice is unchanged

### Requirement: The old name preference carries over
While no UUID is stored, Kannu SHALL resolve a stored `preferred_screen_name` against the connected displays. A name that
matches SHALL pick the first display with it and store that display's UUID. A name that matches nothing SHALL use the
main display and SHALL leave the name in place for a later look.

#### Scenario: An existing user's choice is connected
- **WHEN** `preferred_screen_name` is "Studio Display", no UUID is stored, and a Studio Display is connected
- **THEN** the notch goes to it, and its UUID is stored

#### Scenario: An existing user's choice is not connected yet
- **WHEN** `preferred_screen_name` names a monitor that is not connected and no UUID is stored
- **THEN** the notch goes to the main display and nothing is stored

#### Scenario: A name-keyed override on a display found by id
- **WHEN** the view on display 8 reads its "Always show" override
- **THEN** it reads the override stored under display 8's name, taken from the display found by id, and never looks a
  screen up by that name
