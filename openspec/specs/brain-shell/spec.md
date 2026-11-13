# brain-shell Specification

## Purpose
Brain is Kannu's main window: a sidebar of product pages and Settings in one theme, opened from the notch and the
menu bar, at any size up to full screen. This spec covers the window, the sidebar, the theme, the menu bar and the
badges. It does not cover what each page shows (see `product-pages`). The behaviour is as built on
`super/brain-6-around`, which reaches `development` through #42, #43 and #52.

## Requirements

### Requirement: One sidebar order
Brain's sidebar SHALL list the product pages first, in this order: Agents, Security, Usage, Tasks, Timer, Notes and
Clipboard. The Settings pages and About SHALL follow. The order lives once, in `SettingsTab.sidebarOrder`
(`Kannu/components/Settings/SettingsView.swift:73`), and search and the Go menu follow it. Clicking Settings SHALL swap
the sidebar to the settings list, with a Back row. Every page SHALL keep its `SettingsTab` id, so that deep links and
the search index keep working.

#### Scenario: Settings swaps the sidebar
- **WHEN** the user clicks Settings in Brain's sidebar
- **THEN** the sidebar lists General through Extensions, with a Back row to the product list
- **AND** each row opens the page its id names, as a deep link does

#### Scenario: Search ranks by sidebar order
- **WHEN** a search matches rows on two pages
- **THEN** the first match in the sidebar's order is the one search jumps to

### Requirement: One theme for Brain's window only
Brain SHALL draw everything from `SettingsTheme`
(`Kannu/components/Settings/DesignSystem/SettingsTheme.swift`):
- paper in light, ink in dark, and the logo's eye blue as the one accent;
- the Geist and Geist Mono fonts, bundled in `Kannu/Fonts` and registered through `ATSApplicationFontsPath`
  (`Kannu/Info.plist`), with no work at launch.

The `brainAppearance` key (System, Light or Dark; `Kannu/models/Constants.swift:945`) SHALL apply to Brain's window
only.

#### Scenario: Dark appearance stays in Brain
- **WHEN** the user sets Brain's appearance to Dark while macOS is light
- **THEN** Brain draws ink
- **AND** the notch and every other window keep the system's appearance

### Requirement: Full screen that closes cleanly
Brain's window SHALL be able to go full screen (`.fullScreenPrimary`,
`Kannu/components/Settings/SettingsWindowController.swift:87`, `:147`). Closing Brain in full screen SHALL first wait
for the exit from full screen (`deferCloseUntilWindowed`, `:279`), so the window is never ordered out inside a
full-screen Space. Brain's root SHALL keep an unbounded frame, because the size bridge clamps a full-screen window to
its root (`docs/REGRESSIONS.md` entry 17).

#### Scenario: Close while in full screen
- **WHEN** the user presses ⌘W with Brain in full screen
- **THEN** Brain leaves full screen first and then closes
- **AND** no empty full-screen Space is left behind

### Requirement: Brain knows when it is on screen
`BrainVisibility.isOnScreen` (`Kannu/components/Settings/BrainVisibility.swift:31`) SHALL be false while Brain is
closed, minimised, hidden with the app, fully covered or in another Space. It SHALL start false. Every live
subscription in Brain SHALL run only while it is true (see `product-pages`).

#### Scenario: Parked in another Space
- **WHEN** a full-screen Brain sits in a Space the user has left
- **THEN** `isOnScreen` is false and no page or badge subscription runs

### Requirement: The menu bar is built around Brain
The app's menus (`Kannu/KannuApp.swift:50-88`) SHALL offer:
- **Go:** the product pages in sidebar order, on ⌘1–⌘7;
- **View:** Hide or Show Sidebar (⌃⌘S), Appearance, and Enter or Exit Full Screen (⌃⌘F), titled from
  `BrainVisibility.isFullScreen`;
- **File › New Task:** ⌘N.

Every item that opens Brain SHALL go through `openBrain`, which checks the Terms of Use first. AppKit's own Enter
Full Screen item SHALL be turned off, so View shows one.

#### Scenario: New task from the menu
- **WHEN** the user chooses File › New Task (⌘N) while Brain shows any page
- **THEN** Brain shows Tasks with the New task sheet

#### Scenario: Before the Terms are accepted
- **WHEN** the Terms of Use have not been accepted
- **THEN** no Go, View or File item opens Brain

### Requirement: Sidebar badges for states that need you
The sidebar SHALL badge only these states (`Kannu/components/Settings/SidebarBadges.swift:41-44`):
- Agents: a dot while an agent waits for input;
- Security: the count of high findings to review;
- Usage: a dot while a reading is near its limit;
- Timer: a static ▶ while a timer runs.

There SHALL be no open-task count and no setup checklist. Nothing in the sidebar SHALL tick. Each badge SHALL say
itself to VoiceOver.

#### Scenario: An agent waits
- **WHEN** an agent session awaits the user's input
- **THEN** Agents' row shows the light's yellow dot
- **AND** VoiceOver reads the badge with the row

### Requirement: Onboarding wears Brain's theme
The onboarding window (`Kannu/components/Onboarding/OnboardingView.swift`) SHALL use Brain's root and theme. On
permission rows, Allow SHALL be the primary button and Not now the quiet one. The Terms gate and the timing of every
permission prompt SHALL stay as `FirstLaunchRulesTests` and `LaunchGateRulesTests` pin them.

#### Scenario: Not now raises nothing
- **WHEN** the user presses Not now on a permission card
- **THEN** no macOS permission dialog appears
