# Run log: where Kannu 2.0 stands

*As of 2026-11-13, 08:40 UTC, measured with `gh` and git. The redesign's full history stays in the local notes on
David's Mac. This file is the summary that anyone can continue from with only GitHub. Update it here from now on:
when a line moves, change it, and add the time and how you measured it.*

## The stack
The Brain redesign is three stacked supers. Each PR's diff is its own stage: on 12 Nov, Stage 4 merged `development`,
Stage 5 merged Stage 4, and Stage 6 merged Stage 5.

| PR | Branch → base | Head | State | Next |
|---|---|---|---|---|
| #42 | `super/brain-4-pages` → `development` | 75f08ecb | draft; CLEAN; both Build runners green; reviewed, every note answered | ready and merge, after David's Mac checks (tasks 1.3, 1.4) |
| #43 | `super/brain-5-tasks` → `super/brain-4-pages` | ccef6388 | draft; CLEAN; green; reviewed, every note answered | after #42: retarget to `development`, ready, merge |
| #52 | `super/brain-6-around` → `super/brain-5-tasks` | 764690d4 | draft; CLEAN; green; first review had 2 Minor notes, both fixed in #56 | after #56: re-review, answer, retarget, merge |
| #56 | `brain/6-6-audit-fixes` → `super/brain-6-around` | 5793076f | ready; CI running at 08:40 | merge once both runners pass |

- `development` is at 4168408b (#46 merged), and `main` at c63e3752.
- Each catch-up merge brought in only reviewed content, so none was reviewed again. David was told this.
- **Supers merge with merge commits, never squashes,** or the stack above loses its ancestry. If `gh pr merge`
  errors, use `gh api -X PUT repos/YANC-Kannu/kannu-macos/pulls/<n>/merge -f merge_method=merge`, on the same yes.
  Never use it to get around a refusal.
- **#52's replies** to its two CodeRabbit threads go up once #56 merges.

## Outside the stack
| PR | What | State |
|---|---|---|
| #55 | Kannu no longer holds up every Claude prompt | ready; CLEAN; into `development` |
| #3 | Points Kannu at `YANC-Kannu/kannu-macos`: the feed, CI and docs | ready; CONFLICTING with `development` |
| #14 | 1.4.0 gets the real Bluetooth HUD videos, not Git LFS pointers | ready; CLEAN; into `release/1.4.0` |
| #9 | SonarCloud CI and Dependabot | ready; CONFLICTING |
| #4 | Imports `main` from `libinmv/kannu` | ready; BLOCKED; into `main` |

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
1. **The Mac checks** of the installed build, F1 first (below).
2. **Merge #56** once its runners pass, then post #52's replies and request its re-review.
3. **Land the stack bottom-up:** #42, then #43, then #52, each as a merge commit.
4. **Catch #3 up** with `development`, and merge it.
5. **The decisions** in `tasks.md` section 9: the codename, What's New, the feed bridge, new features, AGENTS.md's
   overview, #55, `release/1.4.0`, and OpenSpec 2.x. (Decided 2026-11-13: the video's storyboard stays on David's Mac
   and is never committed.)

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
