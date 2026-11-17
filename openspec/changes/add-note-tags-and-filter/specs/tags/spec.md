## ADDED Requirements

### Requirement: One set of tags across tasks and notes
Kannu's tags SHALL be one set. Notes' tags SHALL be cleaned by the rule tasks keep (`TaskItem.cleanedTags`):
- at most 10 tags;
- at most 24 characters each;
- no leading "#";
- one spelling of each, compared ignoring case.

Every tag field SHALL suggest the tags in use on tasks and on notes (`Kannu/managers/SharedTags.swift`), read as the
field gains focus or a sheet appears, never on each redraw. A tag SHALL have one colour wherever it shows. The colours
SHALL stay in tasks.json (`TasksFile.tagColors`), so with Tasks off, tags draw uncoloured. Labels SHALL stay tasks'
alone: never suggested, never on a note. Tasks' Tag filters SHALL keep listing only the tags on the tasks they list.

#### Scenario: A note's tag offered on a task
- **WHEN** a note carries "acme" and the user types "ac" in a task's tag field
- **THEN** "acme" is suggested, with its colour dot if it has one

## MODIFIED Requirements

### Requirement: One Tag filter in the notch and in Brain
The notch's Tag submenu (`Kannu/components/Notch/TaskSourceMenu.swift`) and Brain's Tag filter SHALL narrow the list
to one tag. The notch's choice SHALL be saved in `tasksNotchTagFilter` (`Kannu/models/Constants.swift`). A saved tag
SHALL match its tasks ignoring case. In the notch, adding a task SHALL clear a Tag filter that would hide it
(`Kannu/components/Notch/TasksPopover.swift`).

#### Scenario: Adding under a filter
- **WHEN** the notch is filtered to "docs" and the user adds a task without that tag
- **THEN** the filter clears and the new task shows
