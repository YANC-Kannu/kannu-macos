# tasks Specification

## Purpose
Tasks come from the user's own list and from read-only sources. They are timed in the notch, and listed and edited
in Brain › Tasks. This spec covers the sources, the page, list-detail, new tasks, the timer and Time to log, and the
archive. Tags have their own spec (`tags`). The behaviour is as built on `super/brain-6-around`; the sources are
documented in `docs/TASK-SOURCES.md`.

## Requirements

### Requirement: Sources are read-only and sync only when asked
Tasks SHALL come from Local tasks, Jira Cloud, GitLab, GitHub (github.com or Enterprise Server), Linear, Todoist and
Apple Reminders (`TaskSource`, `Kannu/managers/Tasks/TaskModels.swift`). Every source but Local SHALL be read-only:
Kannu never writes back. A source SHALL sync only when asked: when its page appears, on Refresh, or on Connect, never
on a timer (`Kannu/managers/Tasks/SourceSync.swift`). A source's token SHALL live in the Keychain, one item per
source.

#### Scenario: Editing a Jira task in Kannu
- **WHEN** the user renames or completes a Jira task in Kannu
- **THEN** nothing is sent to Jira

### Requirement: Time to log sends time only on a click
Time to log SHALL send time only to Jira and GitLab, and only when the user clicks to send it
(`Kannu/managers/Tasks/WorklogDrafts.swift`; `WorklogConsentRulesTests`).

#### Scenario: A timed Jira task stops
- **WHEN** a timer on a Jira task stops
- **THEN** a draft waits in Time to log, and nothing is sent until the user clicks to log it

### Requirement: Brain › Tasks lists, finds and filters
Brain › Tasks (`Kannu/components/Settings/TasksOverview.swift`, `TasksSettings.swift`) SHALL show:
- a header with the title and New task;
- Active, Done and Archived tabs;
- a Find field that takes `#tag`, and a Tag filter.

The page's only filters SHALL be Find and Tag. It SHALL keep the live-data contract through `TasksPageData`.

#### Scenario: Finding by tag
- **WHEN** the user types `#docs` in Find
- **THEN** the list shows tasks tagged or labelled "docs", plus any whose text holds the literal `#docs`

### Requirement: List-detail at wide windows
The selected task SHALL show beside the list once the panel fits both: the inset, the 360-pt list, the inset again,
a task's 720-pt page and a last inset, about 1,224 pt (`ListDetailLayout.showsPageBeside`,
`Kannu/helpers/ListDetailLayout.swift:34`). Narrower, the task's page SHALL take the list's place, with a back row.
One width function SHALL decide the switch, with no `minWidth:`, no `ViewThatFits` and no `.inspector`.

#### Scenario: Widening with a task open
- **WHEN** a task is open in the list's place and the window grows past the width that fits both
- **THEN** the list returns beside the task's page, scrolled to that task's row

### Requirement: New task, with tags and a reminder typed inline
New task SHALL open `NewTaskSheet` (`Kannu/components/Settings/NewTaskSheet.swift`), from the header or from
File › New Task (⌘N). The notch has its own form. In a new local task's name, `#tag` SHALL become a tag and `@time` a
reminder (`TaskQuickAdd`, see `tags`).

#### Scenario: Typing a tagged task with a reminder
- **WHEN** the user types "Ship notes #launch @3pm" and adds it
- **THEN** the task is titled "Ship notes" and tagged "launch"
- **AND** its reminder is the next 3 pm

### Requirement: The timed task stays listed, and closed tasks archive themselves
The notch's list SHALL always show the task being timed, whatever source or Tag filter is set
(`TaskOrdering.viewFilter`, `Kannu/managers/Tasks/TaskOrdering.swift:55`), so it can always be stopped. A closed task
SHALL move to the archive after 3 days. An archived Jira or GitLab task SHALL be cleared 7 days later
(`Kannu/managers/Tasks/TaskArchive.swift`). Clearing SHALL never take:
- time not yet logged;
- a ticket the server still lists as open;
- a local task;
- the task being timed.

The archive SHALL run after a load or a sync, never on a timer.

#### Scenario: A filter would hide the timed task
- **WHEN** the notch is filtered to a tag the timed task does not have
- **THEN** the timed task is still listed

#### Scenario: Unlogged time keeps a task
- **WHEN** an archived Jira task still has time waiting in Time to log
- **THEN** it is not cleared until that time is logged or kept on this Mac
