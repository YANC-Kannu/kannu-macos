## ADDED Requirements

### Requirement: The agent light sits beside the notch by default
On a display with a physical notch, Kannu SHALL draw the closed agent light as a sideways pill at the closed notch's
height, with nothing below the housing: the light (Classic's three dots or Minimal's one) in a left wing, the housing
in the middle and the primary session's app icon in a right wing. Both wings SHALL be the same width,
`max(left content, icon) + 12` points, and the icon SHALL be `closed height − 12` points square. A pending high
finding SHALL show the shield glyph beside the light in the left wing. This layout
(`Defaults[.agentPillLayout] == .sideways`) SHALL be the default for every install, updaters included. Displays without
a notch, the Dynamic Island among them, SHALL keep their centred lights. Under Reduce Motion the wings SHALL fade in
and out instead of sliding. VoiceOver SHALL read one label naming the state and the app, e.g. "Agent status: working,
Claude Code".

#### Scenario: An agent starts working on a notched MacBook
- **WHEN** an agent's state switches to working on a MacBook with a notch
- **THEN** the closed notch shows the dot left of the housing and the agent's app icon right of it, at the closed
  height, with no band below

#### Scenario: A display without a notch
- **WHEN** an agent's state switches on an external display without a notch
- **THEN** the closed notch shows the centred dots, as before

#### Scenario: The locked Mac
- **WHEN** the Mac is locked, the lock-screen pill is on screen, and an agent's state switches
- **THEN** the pill shows the lit dot where the lock icon was and the app icon in its other wing for the reveal, then
  the lock icon again, and its window keeps its size

### Requirement: The agent light goes ahead of persistent activities without stacking
In the sideways layout the agent light SHALL show only after a switch of the published light, for the reveal window
(`notchRevealHoldSeconds`, 7 seconds). While that window is live it SHALL take the closed notch ahead of the music pill
and a running timer. When it ends, the music or the timer SHALL return with no agent light in its centre, and neither
SHALL keep the light lit. The fullscreen hide (`vm.hideOnClosed`) SHALL still hide it.

#### Scenario: Music is playing
- **WHEN** music is playing and an agent's state switches
- **THEN** the sideways agent pill replaces the music pill for the reveal, then the music pill returns with no light in
  its centre

#### Scenario: A timer is running
- **WHEN** a timer is running and an agent's state switches
- **THEN** the sideways agent pill replaces the timer for the reveal, then the timer returns with no light in its
  centre

### Requirement: The app icon beside the light stays still
The app icon in the sideways pill and on the lock-screen pill SHALL never scale, pulse or animate: the breathing dot
SHALL carry all the motion. Snapshot boards, onboarding and Brain's preview SHALL draw a symbol stand-in, never another
company's logo.

#### Scenario: A working agent breathes
- **WHEN** an agent works and its dot breathes
- **THEN** the app icon beside it stays at its size, without moving

### Requirement: The band below the notch remains an option
Brain › Agents › Traffic light SHALL offer, inside an Advanced disclosure, "Agent light position" with Beside the notch
and Below the notch. Below the notch (`AgentPillLayout.belowNotch`) SHALL keep the earlier behaviour unchanged: the band
below the housing, the shield-and-title pill, the light in the music and timer centres and its persistence there, and
the lock-screen pill without the light. Settings search SHALL land on the disclosure.

#### Scenario: Choosing Below the notch
- **WHEN** the user chooses Below the notch and an agent's state switches while music plays
- **THEN** the music pill shows the light in its centre, with the band below the housing, as before
