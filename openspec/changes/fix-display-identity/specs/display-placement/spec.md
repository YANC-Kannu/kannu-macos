## ADDED Requirements

### Requirement: Screens are matched by display identity
Kannu SHALL select and look up the notch's screen by `CGDirectDisplayID`, never by `NSScreen.localizedName`. Each
notch view model SHALL hold the id of the display its window is on, and every per-screen decision for that view (its
closed size, whether it has a notch, its Dynamic Island style check, its fullscreen verdict, its HUD and sneak-peek
targets) SHALL read that display. `localizedName` SHALL NOT be used to select, look up or key a screen; it is for
text people read.

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

### Requirement: Per-display overrides are stored by UUID
The per-display style and "Always show" overrides SHALL be stored under the display's UUID, and Brain › General SHALL
list one override group for each display without a notch, numbering the titles of displays that share a name. Kannu
SHALL carry each connected display's name-keyed override over to its UUID once, at launch or when the display first
appears, SHALL NOT overwrite an override already stored by UUID, and SHALL NOT write the name-keyed overrides again.

#### Scenario: Two monitors shared one override
- **WHEN** the name-keyed "Always show" override for "DELL U2720Q" is off and two monitors with that name are connected
- **THEN** each monitor's UUID gets "off", and turning one on leaves the other off

#### Scenario: A Reset after the carry-over
- **WHEN** a display's overrides were carried over and the user resets them
- **THEN** the display follows the defaults, and its name-keyed override does not come back

#### Scenario: A monitor plugged in later
- **WHEN** a monitor with a name-keyed override was not connected at launch and is plugged in
- **THEN** its UUID gets that override
