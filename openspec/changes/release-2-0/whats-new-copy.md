# What's New: the English copy

Task 5.1. The window that 5.2 builds (`specs/whats-new`, `design.md`) takes these strings as its English
source, through `String(localized:)`. Task 5.3 adds them to `Kannu/Localizable.xcstrings` in all 17
languages. They follow Brain's copy rules (`docs/SETTINGS.md`): sentence case, with a capital only for the
first word and for names, and American spelling.

## The window

| Part | English | Catalog today |
|---|---|---|
| Window title (Window menu, VoiceOver) | What's New | exists, in all 17 languages |
| Title | Welcome to Kannu 2.0 | new |
| Line under the title | The notch is the front door. Brain is the room behind it. | new |
| Primary button (Return; Escape also closes) | Continue | exists, in all 17 languages |

## The cards

One card per pillar, each a title over its text. VoiceOver reads the two together.

| Card | Title | Text |
|---|---|---|
| Brain | Brain | Settings is now Brain: pages for your agents, tasks, notes and more, full screen, with a menu bar of its own. |
| Tasks | Tasks | Jira, GitLab, GitHub, Linear, Todoist and Reminders, beside your own. Open a task beside the list, time it, and log the time. |
| Tags | Tags | Type #launch or @3pm in a task's name for a tag or a reminder, shown as chips. Filter any list by tag. |

Each text covers what `specs/whats-new` asks of its card:
- **Brain:** the product pages, full screen and the menu bar.
- **Tasks:** the sources, list-detail, the timer and Time to log ("log the time").
- **Tags:** typing `#tag` and `@time`, chips, and the Tag filter.

## For 5.2 and 5.3
- **Card titles are page names.** Brain is a name, never translated. Tasks should use the same key as the sidebar's
  Tasks page (`SettingsTab.title`), so a card never names a page differently from the sidebar. Neither "Brain",
  "Tasks" nor "Tags" has a catalog entry today.
- **The sources are product names,** never translated. They are spelled as the app writes them in running text
  (`TaskSource.name`).
- **`#launch` and `@3pm` are what the user types,** so a translation keeps them as tokens the parser reads
  (`TaskQuickAdd`). `#launch` stays as it is. `@3pm` may become `@15:00` where clocks are 24-hour, never a
  translated word.
- **Room to grow.** Each text is one or two lines in English. A card grows with its text and never cuts it short,
  since some languages run about a third longer.
