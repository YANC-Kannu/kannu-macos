## ADDED Requirements

### Requirement: The agent light sits beside the notch
On a display with a physical notch, Kannu SHALL draw the closed agent light as a sideways pill at the closed notch's
height, with nothing below the housing: the one lit dot in a left wing, the housing in the middle and the primary
session's app icon in a right wing. Both wings SHALL be the same width, `max(left content, icon) + 12` points, and the
icon SHALL be `closed height − 16` points square: 16 points on a 32-point notch, so each wing is 28 points. A pending
high finding SHALL show the shield glyph beside the dot in the left wing. This SHALL be the only layout on a notched
MacBook, for every install, updaters included: there is no band below the notch and no setting for one. Displays
without a notch, the Dynamic Island among them, SHALL keep their centred light. Under Reduce Motion the wings SHALL fade in
and out instead of sliding. VoiceOver SHALL read one label naming the state and the app, e.g. "Agent status: working,
Claude Code".

#### Scenario: An agent starts working on a notched MacBook
- **WHEN** an agent's state switches to working on a MacBook with a notch
- **THEN** the closed notch shows the dot left of the housing and the agent's app icon right of it, at the closed
  height, with no band below

#### Scenario: A display without a notch
- **WHEN** an agent's state switches on an external display without a notch
- **THEN** the closed notch shows the centred light, as before

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

### Requirement: The agent light is one lit dot
Every display SHALL draw the agent light as one dot, the colour of the current state, and nothing while no state is
lit. There SHALL be no choice of style: the Classic three-dot look, its setting and its onboarding choice are removed,
and the stored `agentTrafficLightStyle` and `agentPillLayout` values SHALL be removed on launch.

#### Scenario: An updater who had chosen Classic
- **WHEN** someone who had chosen Classic, or Below the notch, updates to 2.0 and an agent's state switches
- **THEN** the notch shows the one lit dot beside the notch, and Brain › Agents offers no style or position to choose

### Requirement: Onboarding shows the light instead of asking about it
Onboarding's light step SHALL show the real sideways pill at a real notch's 32 points, with a real housing's ratio, in
its three states (working, needs you, finished), each with a symbol stand-in for an app icon and a one-line label,
followed by a short explanation and Continue. Nothing on the step SHALL animate, and it SHALL write no setting.

#### Scenario: A first run reaches the light step
- **WHEN** a new user reaches the light step
- **THEN** one card shows the pill in green, yellow and red, still, and Continue moves on with nothing to choose
