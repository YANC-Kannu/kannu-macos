# tags Specification

## Purpose
Tags group tasks across sources. They are typed inline, shown as chips, searched with `#` and used as a filter in the
notch and in Brain. The tag logic is pure and tested (`Kannu/managers/Tasks/TaskFacets.swift`, `TaskSearch.swift`,
`TaskQuickAdd.swift`). The behaviour is as built on `super/brain-6-around`.

## Requirements

### Requirement: Typed tags and reminders
A new local task's name SHALL turn these tokens into tags and a reminder, wherever it is typed: the notch's form, the
notch's popover and Brain's New task sheet (`TaskQuickAdd.parse`, `Kannu/managers/Tasks/TaskQuickAdd.swift:58`):
- `#` followed by a letter, then letters, digits, `-` or `_`, SHALL become a tag;
- `@` followed by a time word (`noon`, `morning`, `evening`, `tonight`), a day (`today`, `tomorrow`, a weekday) or a
  clock time (`5pm`, `17:30`) SHALL become the task's reminder.

Anything else SHALL stay in the title as typed, so `#123` and `a@b.com` are kept. The recognised tokens SHALL show as
chips at the field's end (`TaskQuickAddChips`), and the saved title SHALL leave them out.

#### Scenario: Chips while typing
- **WHEN** the user types "Review #docs @4pm"
- **THEN** both tokens show as chips at the field's end
- **AND** the task saves titled "Review", tagged "docs", with a reminder at the next 4 pm

#### Scenario: An issue number is not a tag
- **WHEN** the user types "Fix #4264"
- **THEN** the title keeps "#4264" and no tag is added

### Requirement: Labels count as tags
A task's displayed tags SHALL be its own tags plus its Jira or GitLab labels (`TaskFacets.displayTags(of:)`, `:244`).
`tags(in:)` (`:290`) SHALL return own tags only. The Tag filter's choices SHALL come from `filterTags(in:)` (`:295`).

#### Scenario: A GitLab label
- **WHEN** a GitLab issue carries the label "backend"
- **THEN** the task shows a "backend" chip and the Tag filter offers "backend"

### Requirement: Hash search matches tags, not substrings
In Find and in the notch rail's search, `#word` SHALL match a task whose tag or label is that whole word. Failing
that, it SHALL match the word with its `#` wherever a plain word would be found, so `#4264` still finds the key
"group/app#4264". Case and accents SHALL never matter. `#work` SHALL NOT find "Homework" or "workshop"
(`TaskSearch.matches`, `Kannu/managers/Tasks/TaskSearch.swift:36`; `TaskSearchTests`).

#### Scenario: Work is not Homework
- **WHEN** the user searches `#work`
- **THEN** a task tagged "work" is found, and a task titled "Homework" is not

#### Scenario: An issue key
- **WHEN** the user searches `#4264`
- **THEN** the GitLab issue keyed "group/app#4264" is found

### Requirement: Chips that never cut the caption
A task row SHALL show one tag chip when it fits, and "+N" for the rest, always. A tag the search found SHALL move first
(`TaskSearch.chipTags(of:query:)`, `:53`). In the notch rail the caption, which carries the time and any overtime,
SHALL win the space. A chip SHALL show only when room is left after the caption; otherwise only "+N" shows
(`Kannu/components/Notch/TaskTagChips.swift`). A row SHALL be tinted in its first tag's colour.

#### Scenario: A narrow notch rail
- **WHEN** a timed task's caption fills the rail's width
- **THEN** the caption shows whole, with only "+N" after it

### Requirement: One Tag filter in the notch and in Brain
The notch's Tag submenu (`Kannu/components/Notch/TaskSourceMenu.swift`) and Brain's Tag filter SHALL narrow the list
to one tag. The notch's choice SHALL be saved in `tasksNotchTagFilter` (`Kannu/models/Constants.swift:1664`). A saved
tag SHALL match its tasks ignoring case. In the notch, adding a task SHALL clear a Tag filter that would hide it
(`Kannu/components/Notch/TasksPopover.swift:399`).

#### Scenario: Adding under a filter
- **WHEN** the notch is filtered to "docs" and the user adds a task without that tag
- **THEN** the filter clears and the new task shows
