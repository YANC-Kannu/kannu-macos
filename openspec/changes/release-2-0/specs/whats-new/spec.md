## ADDED Requirements

### Requirement: A welcome to 2.0, shown once after updating
Kannu SHALL show a What's New window once: the first time 2.0 runs on a Mac where an earlier version ran, after the
Terms of Use are accepted. A fresh install SHALL NOT show it, because onboarding introduces Kannu there. Closing the
window SHALL count as seen for 2.0.

#### Scenario: Updating from 1.3.4
- **WHEN** a 1.3.4 user updates to 2.0.0 and launches it
- **THEN** the What's New window opens once, after the Terms gate

#### Scenario: Shown once
- **WHEN** the user closes the window and relaunches Kannu
- **THEN** it does not open again

#### Scenario: A fresh install
- **WHEN** Kannu 2.0 is installed on a Mac where it never ran
- **THEN** onboarding runs, and the What's New window never opens

### Requirement: Three cards: Brain, Tasks and Tags
The window SHALL show one card per pillar, and one primary button that closes it:
- **Brain:** the product pages, full screen and the menu bar;
- **Tasks:** the sources, list-detail, the timer and Time to log;
- **Tags:** typing `#tag` and `@time`, chips, and the Tag filter.

#### Scenario: Reading the cards
- **WHEN** the window opens
- **THEN** it shows the Brain, Tasks and Tags cards, and one button that closes it

### Requirement: The window keeps the launch rules
The window SHALL never open before the Terms of Use are accepted, and never while onboarding runs. It SHALL never
raise a permission dialog.

#### Scenario: Terms not yet accepted
- **WHEN** an updated install launches and shows the Terms of Use
- **THEN** the What's New window waits until they are accepted

### Requirement: Brain's look, keyboard and VoiceOver
The window SHALL use Brain's theme in light and dark, with Geist. Return SHALL press its primary button, and Escape
SHALL close it. VoiceOver SHALL read each card's title and text. Under Reduce Motion nothing SHALL animate. Its
strings SHALL be in the catalog in all 17 languages. Its DEBUG snapshot board SHALL draw from a fixture.

#### Scenario: Keyboard only
- **WHEN** the window opens and the user presses Escape
- **THEN** it closes and counts as seen
