# Draft: the summary on top of CHANGELOG's `[2.0.0]`

Task 4.1. The text between the two rules below goes under `## [2.0.0] - <date> - <codename>`, above
the first entry, when 2.0.0's version lands (task 4.6). Until then it stays here, so the top of
`## [Unreleased]` keeps only entries, as the pre-commit hook reads it. It has no `###` line, so the
hook can never mistake it for an entry.

**Cut 1.3.1 to 1.3.4 first.** `## [Unreleased]` was last cut at 1.3.0. Its 23 oldest entries, from
"Ship 1.3.4" down to just above `## [1.3.0]`, shipped in 1.3.1 to 1.3.4. Renaming the whole section
would file them under 2.0.0, so they need a section of their own before the rename.

---

Kannu 2.0 makes the notch the front door and **Brain** the room behind it. The notes for people
who use Kannu are in `docs/release-notes/2.0.0.md`; the entries below are the changes as they were
made.

- **Brain:** Settings becomes seven product pages (Agents, Security, Usage, Tasks, Timer, Notes and
  Clipboard) that open on their live state, with the settings behind one Settings row. Paper and
  ink, Geist, full screen, a menu bar of its own and sidebar badges for what needs you.
- **Tasks:** Jira Cloud, GitLab, GitHub, Linear, Todoist and Apple Reminders beside your own tasks,
  all read-only; Active, Done and Archived with Find and a Tag filter; list-detail on a wide window;
  the timer and Time to log; and an archive that tidies itself.
- **Tags:** `#tag` and `@time` typed in a task's name, chips and colours, a `#tag` search that finds
  the whole tag, and one Tag filter in Brain and in the notch.
- **Also:** a first launch that asks for each permission on its own step; a notch that hides like
  an eye and stays put across Spaces; steadier agent monitoring and usage; a hook that never writes
  a prompt to disk; and a new eye icon.
- **On updating from 1.x:** Settings is now Brain, the minimal UI mode is gone, and a short welcome
  shows once.

---
