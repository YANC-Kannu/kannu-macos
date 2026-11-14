# Run log: where Kannu 2.0 stands

*As of 2026-11-13, 22:05 UTC, measured with `gh` and git. The redesign's full history stays in the local notes on
David's Mac. This file is the summary that anyone can continue from with only GitHub. Update it here from now on:
when a line moves, change it, and add the time and how you measured it.*

## The stack
The Brain redesign was three stacked supers. **All three landed in `development` on 13 Nov at 10:30 UTC.** They
went in bottom-up, each a merge commit pinned to its reviewed head, with both Build runners green and every review
note answered.

| PR | Branch → base | Reviewed head | Merged as |
|---|---|---|---|
| #56 | `brain/6-6-audit-fixes` → `super/brain-6-around` | 5793076f | 16263d8b (08:47 UTC) |
| #42 | `super/brain-4-pages` → `development` | 75f08ecb | 70ab4242 |
| #43 | `super/brain-5-tasks` → `development` (retargeted) | ccef6388 | a711fece |
| #52 | `super/brain-6-around` → `development` (retargeted) | 418dee32 | d7d839d3 |

- The landing left `development` at d7d839d3, whose tree is Stage 6's reviewed head tree. `main` is at c63e3752.
- **#57 (OpenSpec, with this change) merged at 13:18 UTC** as 385070c8, after it caught up (3a1c1236, both Build
  runners green).
- **#3 (the repoint to `YANC-Kannu/kannu-macos`) merged at 14:02 UTC** as e69311ea.
- **#58 (where agent sessions start, in `openspec/project.md`) merged at 14:47 UTC** as 1145e7b5, which is
  `development` now (14:48 UTC, `git fetch`).
- #52's reviews:
  - the first review's two notes were fixed in #56;
  - the second review's one note (a failed note-image load stayed cached) was fixed in 418dee32 on the super;
  - the third review was clean.
- Each catch-up merge brought in only reviewed content, so none was reviewed again. David was told this.
- **Supers merge with merge commits, never squashes,** or the stack above loses its ancestry. If `gh pr merge`
  errors, use `gh api -X PUT repos/YANC-Kannu/kannu-macos/pulls/<n>/merge -f merge_method=merge`, on the same yes.
  Never use it to get around a refusal.
## Outside the stack
The states are what `gh` reported at 14:00 UTC. Where a PR conflicts, the files named are a `git merge-tree` forecast
against d7d839d3.

| PR | What | State |
|---|---|---|
| #57 | OpenSpec, with this change | merged as 385070c8 (13:18 UTC) |
| #55 | Kannu no longer holds up every Claude prompt | ready; CONFLICTING, in CHANGELOG, `SettingsView.swift` and `SettingsHighlightInventoryTests.swift`; waits until after 2.0 (9.7) |
| #3 | Points Kannu at `YANC-Kannu/kannu-macos`: the feed, CI and docs | merged as e69311ea (14:02 UTC) |
| #58 | Says where agent sessions start, in `openspec/project.md` | merged as 1145e7b5 (14:47 UTC) |
| #14 | 1.4.0 gets the real Bluetooth HUD videos, not Git LFS pointers | ready; CLEAN; into `release/1.4.0` |
| #9 | SonarCloud CI and Dependabot | ready; GitHub still computing (CONFLICTING before) |
| #4 | Imports `main` from `libinmv/kannu` | ready; BLOCKED; into `main` |

## The release copy
The [Cloud] writing tasks are on `docs/release-2-0-copy`. It was cut from `development` at 385070c8 and moved up to
1145e7b5 as #3 and #58 merged, so the work sits on both. On David's yes it went up as one commit, in a PR into
`development` (2026-11-13, 22:05 UTC):
- `docs/release-notes/2.0.0-beta.1.md` and `docs/release-notes/2.0.0.md` (4.2, 4.3);
- `changelog-summary.md` in this folder, the draft for the top of `[2.0.0]` (4.1). The rename waits for 4.6, which
  first gives 1.3.1 to 1.3.4 their own section;
- `ReadMe.md`, rewritten for the pivot, with #3's Releases link (4.4);
- `whats-new-copy.md` in this folder, the window's English copy (5.1);
- the codename (3.2): `ReleaseInfo.codename` is Horus, and `scripts/RELEASE.md`'s Codenames table gives 2.0.0 its
  row, with Vigil next and then Sentinel;
- task 2.3 ticked: all seven release secrets exist, by name.

David's decisions of 13 Nov match what the copy assumed: Horus (9.1), the welcome window (9.2), and #55 after 2.0
(9.7).

## The installed checkpoint
- **Installed on David's Mac** on 2026-11-12 at 23:44 UTC: a local combined build of all three supers on
  `development`, never pushed. Its gates:
  - KannuTests 2,521 passed, 0 failed;
  - the Debug build green;
  - the hook passing;
  - no catalog key lost.
- **The scoped final audit** found nothing High:
  - F1 is Medium: New note's text may not take Return as a new line. It needs a Mac check.
  - F2 to F10 are Low. #56 fixes F3, F5, F6, F8 and F9.
  - F11 is two Mac checks.

## Pending asks for David
1. **The Mac checks**, F1 first (below). The stack landed first, on David's yes, so they now run on the final install
   from `development` (section 6).
2. **The decisions** left in `tasks.md` section 9: the feed bridge, new features, AGENTS.md's overview,
   `release/1.4.0`, and OpenSpec 2.x. Decided 2026-11-13: the codename is Horus, 2.0 adds What's New, #55 waits until
   after 2.0, and the video's storyboard stays on David's Mac and is never committed.
3. **The version PR** (2.0.0, build 12, task 3.1): a yes to merge it.
   - Then the final install from `development` (6.1).
   - Then the Mac checks (6.2), with What's New on an updated install and on a fresh account.
   - The release copy (#60) and What's New (#59) have merged.

## David's Mac checks
**On the installed build:**
1. The audit's checks first:
   - F1: New note, type, press Return.
   - F3: ⌃⌘F twice fast; ⌘W in full screen, then ⌃⌘F.
   - F2: `top` with Brain left on Devices, Appearance's idle animations or Downloads, then minimised, covered or
     parked.
   - F11: VoiceOver on a badged sidebar row; only one Enter Full Screen under View.
2. The overall feel, in light and dark and in full screen: enter it, leave it, close Brain in it, and watch the notch
   meanwhile.
3. The controls:
   - Selects under Full Keyboard Access, including Escape in Policy rules › Edit.
   - VoiceOver adjusting the "Scrim opacity" slider.
   - Set End Time: Space, then Escape.
4. Agents:
   - CPU with an agent busy: Brain closed after visiting Agents, open on Agents, and parked full screen.
   - The metrics stop on minimise, ⌘H and a Space switch.
   - The hero and rows at 1,100 × 760 and in full screen.
   - A click opens the chat, and Install installs the hook once.
5. Consistency:
   - The choice ring, and VoiceOver saying "selected".
   - Devices' AirPods movie.
   - Search's list: never taller than 344 pt, with its fade.
   - The 12-pt cut under the title.
   - The swatch ring in dark, and badge text at 10 pt.
6. Usage:
   - Refresh with Claude signed in and signed out.
   - Brain follows the notch's Usage tab at most twice a second.
   - CPU open, closed and parked.
   - "Agent Status is off" shows when it is off.
   - VoiceOver on a window row and a model row.
7. Security:
   - CPU with permission checks off.
   - Scan now dims and then updates, and both buttons start only one scan.
   - Connect ADR's ring, and the deep links.
   - Minimise during a scan.
   - VoiceOver reads the counts.
   - The "Connect ADR" moment at first launch.
8. Timer:
   - Brain's time against the notch's.
   - Pause, Resume and Stop from Brain.
   - CPU while a timer runs.
   - Return in the preset sheet saves once.
9. Tags in the notch:
   - The rail at 640 pt.
   - Hover on a clipped caption.
   - A `#tag` search that shows only "+N".
   - The Colour menu on a pill.
   - VO-Shift-M on a pill.
10. Notes and Tasks list-detail:
    - Cross about 1,440 pt with a note open.
    - VoiceOver announces ›, the menu and the selected row.
    - Pin, Copy and Delete beside the list.
    - The bare back row.
    - CPU closed and parked.
11. The menu bar:
    - Only one Enter Full Screen.
    - ⌘1–⌘7, ⌃⌘S and ⌘N from any page, with a field focused, and with a sheet up.
    - Hide Sidebar in full screen.
    - A cold ⌘N.
12. Sidebar badges:
    - The agents' dot on paper.
    - VoiceOver reads "Security, High: 2".
    - CPU while an agent works.
13. Geist in the notch: the running timer's name, the tag chip, monospaced readouts and the music title.
14. Onboarding, on a fresh install:
    - light and dark;
    - the choice cards under Full Keyboard Access and VoiceOver;
    - Allow raises one dialog, and Not now raises none;
    - General › Permissions shows Allow and Not now side by side.
15. The floating panels: the clipboard panel and the LocalSend picker, on the new theme.

**#56's own checks:**
- ⌃⌘F twice fast, then ⌘W in full screen and ⌃⌘F at once: Brain ends windowed or closed, never stuck.
- Notes with an image open while the same note is typed in the notch: no flicker. A replaced image shows within about
  half a second.
- Search with more than seven matches: the fade at the list's foot behaves.
- VoiceOver on Shelf's two permission callouts.

## Review follow-ups left for later
Each was answered on its PR. None is a 2.0 gate unless David makes it one.
- **#42, first review:**
  - "Open chat" shows on a session with no target (`AgentsOverview.swift:216`). Hiding it needs a per-session check
    cached outside `body`.
  - The Timer Presets search result targets a row that isn't built while Timer is off (`SettingsView.swift:974`).
    This predates the PR. Fix: a Timer branch in `landingOnABuiltRow`.
  - Usage's card says "No reading yet" after a failed read. Whether the page shows provider errors and their
    recovery action is David's call.
  - "Models this week" can show last week's snapshot. "As of" or hide is David's call.
  - Tool detection misses VS Code, Gemini CLI, Qwen Code and opencode, and `.gemini` alone reports Antigravity. Both
    are in the danger zone (`Kannu/managers/AgentStatus/`).
  - Off-state boards for Agents, Security and Clipboard, like Usage's `usageOff`.
- **#42, second review:**
  - The notch's Notes rows still ask by scope before deleting (`NotchNotesView.swift:821`, `:1013`).
  - Three wording fixes, for the strings pass.
  - Editors & hooks counts hookless editors but never names them.
- **#43, first review:**
  - `TaskListRulesTests.filteredRowProblems` never pins `shown`.
  - `TaskColorRulesTests` accepts an empty Colour picker.
- **#52, first review:** after a failed task-list load, New Task's retry needs a reload API that Tasks lacks.
- **#56:** the notch's note rows re-read their thumbnail on each save (`NotchNotesView.swift:908`).
- **Copy:** Brain's Tasks and Notes pages keep older wording ("Turn On", "Tag colours"). 49 of onboarding's 77
  strings have no catalog entry.

## How to continue
- **Read first:** `openspec/project.md`, `openspec list`, then this change's `proposal.md`, `tasks.md` and this file.
- **A local session** builds and tests in its own worktree, one build at a time, and stops at "verified" for David's
  yes.
- **A cloud session** does the [Cloud] tasks only. It never builds, tags or releases, and it never stages
  `marketing/`. Its changes go on a branch for David to review. The video's storyboard is not one of its tasks: it
  lives only on David's Mac.
- **When a gate moves:**
  - tick it in `tasks.md`;
  - update the tables here, with the time and the instrument;
  - keep `openspec validate --strict --no-interactive` passing.
