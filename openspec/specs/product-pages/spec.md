# product-pages Specification

## Purpose
Brain's seven product pages (Agents, Security, Usage, Tasks, Timer, Notes and Clipboard) open on their live state.
Their settings follow below. This spec covers what every product page shares: the frame, the order of regions, the
empty states and the live-data contract. Each page's code is its `<Page>Overview.swift` beside its `<Page>Settings.swift`
in `Kannu/components/Settings/`. The behaviour is as built on `super/brain-6-around`.

## Requirements

### Requirement: Product first, settings below
Each product page SHALL open on its product: a hero, a list or an empty state. Its settings SHALL follow under a
full-width "<Page> settings" rule, which a gear in the header jumps to. Settings SHALL stay on their page, so every
row's id, the search index and the notch's deep links keep working (`docs/SETTINGS.md`, "Product pages").

#### Scenario: The gear jumps to the settings
- **WHEN** the user clicks the gear in a product page's header
- **THEN** the page scrolls to its "<Page> settings" rule

### Requirement: One frame at every width
Every page SHALL start its content `pageInset` from the panel's leading edge: 32 pt, or 48 when the panel is at least
1,000 pt wide (`Kannu/components/Settings/DesignSystem/SettingsTheme.swift:106-108`). Nothing SHALL be centred.
Each page SHALL have one header row: a 24-pt title on the left, and its actions on the right, with the page's one
primary verb last. The widths SHALL be capped:
- settings at 720 pt (`pageMaxWidth`);
- product content at 1,200 pt (`productMaxWidth`);
- prose at 380 pt (`proseMaxWidth`);
- row captions at 440 pt (`descriptionMaxWidth`).

A wider window SHALL show the same items in the same order. Only Tasks and Notes switch layout, to list-detail.

#### Scenario: A full-screen 14-inch Mac
- **WHEN** Brain is full screen on a 1,512-pt-wide display
- **THEN** content starts 48 pt in, product content stops at 1,200 pt, and settings stop at 720 pt

### Requirement: Empty states teach and offer one action
An empty product SHALL say what its state is, teach in one line of at most 380 pt, and offer at most one action:
- Usage: "Turn on a provider";
- Security: Connect ADR or Scan now;
- Timer: its preset tiles;
- Notes: New note;
- Clipboard: nothing to press, because History fills itself.

#### Scenario: No agents running
- **WHEN** Agents has no sessions
- **THEN** its hero is a card at least 200 pt tall that says no agents are running
- **AND** it offers to install a hook only for a detected tool that lacks one

### Requirement: Live data is throttled, scoped and off when unseen
A page that shows live data SHALL copy what it shows into one value from one subscription, throttled to 500 ms and
assigned only on a change. Its subscriptions SHALL be `.task(id: visibility.isOnScreen)`, which run only while Brain is
on screen. No page SHALL observe a store whole. A page SHALL read its sources once as it appears and again when Brain
comes back. Its live views SHALL give way to a static copy with no clock while Brain is off screen. A click SHALL
resolve its target in its action, never in `body`. `AgentsPageLiveDataRulesTests`,
`SecurityPageLiveDataRulesTests`, `UsagePageLiveDataRulesTests`, `TimerPageLiveDataRulesTests`,
`TasksPageLiveDataRulesTests`, `NotesPageLiveDataRulesTests` and `ClipboardPageLiveDataRulesTests` pin it
(`docs/SETTINGS.md`, "Live data").

#### Scenario: Brain is closed while an agent works
- **WHEN** Brain is closed after showing Agents and an agent's hook writes 20 times a second
- **THEN** no Agents subscription runs and the page's `body` does no work for those writes

### Requirement: Usage never reads usage on its own
Brain › Usage SHALL show the readings the agent monitor and the notch already took, each marked with when it was
taken. Its Refresh button SHALL be the only way it starts a read (`docs/REGRESSIONS.md` entry 8;
`UsagePageLiveDataRulesTests`).

#### Scenario: Opening Usage
- **WHEN** the user opens Brain › Usage
- **THEN** no usage command is spawned, and each card shows "as of" the time of its reading
