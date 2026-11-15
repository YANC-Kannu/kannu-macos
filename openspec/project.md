# Project Context

Read this before you write a spec, a change or a task here. `AGENTS.md` is canonical for the engineering standards.
This file adds only what OpenSpec work needs on top of it. Each rule below names the file that owns it; when the two
disagree, that file wins.

## Purpose
Kannu began as a notch that watches your coding agents: a traffic light for Cursor, Codex, Claude Code and others.
**2.0 pivots it: the notch is the front door, and Brain is the room behind it.** Agents, tasks with their sources and
tags, the timer, notes, the clipboard, usage and security live in one place. The notch shows them at a glance, and Brain
opens them full screen.

Three pillars:
- **Brain:** product pages, the paper-and-ink theme, Geist, full screen, the menu bar, sidebar badges and onboarding.
- **Tasks:** Jira, GitLab, GitHub, Linear, Todoist and Apple Reminders as sources; Brain › Tasks with list-detail; the
  notch's Tasks button; the timer and Time to log; the archive.
- **Tags:** typing `#tag` and `@time`; chips and colours; `#tag` search; the Tag filter.

2.0 ships as a beta first. The plan, its gates and the open asks are in `openspec/changes/release-2-0/`.

## Tech Stack
- Swift, SwiftUI and AppKit, with native frameworks only (AGENTS.md, "Architecture principles"). The app targets
  macOS 14.6. Updates come through Sparkle.
- Xcode 27.2 on the Mac. CI picks `latest-stable` on macos-15 and macos-26 (`.github/workflows/ci.yml`).
- `KannuTests` is the pure-logic test target. Its rule tests read the source and pin house rules against planted
  offenders. Headless run, in a derived-data folder of its own (every `.build-*` folder is git-ignored):
  `xcodebuild test -project Kannu.xcodeproj -scheme KannuTests -destination "platform=macOS" -derivedDataPath .build-tests`
- GitHub `YANC-Kannu/kannu-macos`, which is **public**. The default branch is `main`, and day-to-day work goes to
  `development`. CI builds and tests every push to `main` and `development`, and every PR into them or into
  `super/**`. A `v*` tag runs `.github/workflows/release.yml`.
- The OpenSpec CLI is pinned at **0.23.0**. Run it through npx, with telemetry off:
  `OPENSPEC_TELEMETRY=0 npx -y @fission-ai/openspec@0.23.0 <command>`, for example `list` or
  `validate --strict --no-interactive`. 0.23.0 is the last release with this layout: this file, `openspec/AGENTS.md`
  and the managed block in AGENTS.md. From 1.0 on, OpenSpec keeps project context in `openspec/config.yaml` and
  reports this file as legacy. Moving to 2.x is an open decision in the release change.

## Project Conventions

### The hold rule
Nothing is committed, pushed, merged, retargeted, marked ready, tagged or released without David's yes in the current
chat turn. One yes covers one shipment. A plan, a document or an earlier yes is not that yes. Finished work waits,
staged and uncommitted.

### Branches and PRs
- PRs target `development`; `main` is the release branch.
- Work too large for one review ships as stacked supers (AGENTS.md, "Stacked super PRs"):
  - Each stage is a `super/<name>` branch, with a PR onto the super below it. The bottom super targets `development`.
  - Small child PRs merge into their super with a merge commit once CI is green.
  - CodeRabbit reviews supers only: bottom-up, one review an hour. It skips a PR with more than about 150 files.
  - A super merges into `development` only after its review, with a merge commit, never a squash. Then the next super
    is retargeted.
  - A fix on a lower super is merged up the stack.
- A commit that touches source, as `.githooks/pre-commit` defines it (AGENTS.md and CLAUDE.md included), needs a new
  entry at the top of `CHANGELOG.md`'s `## [Unreleased]`, in the shape AGENTS.md gives. Never restate that shape in a
  file under `openspec/`: `ChangelogRuleDocsTests` fails on any copy it does not pin.
- Run the branch's own hook before committing: `bash .githooks/pre-commit`. Never `git commit --amend`.

### The lean rules
- Build from the existing specs. No new spec, research or critique workflows.
- One implementation agent, or the main thread, per child PR. Each child runs:
  - the full KannuTests;
  - the Debug app build, confirming its changed files compiled;
  - the snapshot boards for the pages it touches.
- One build at a time. Never two writers on the same files.
- One independent reviewer, only for high-risk work: live data and CPU, keyboard and VoiceOver on custom controls, and
  danger-zone files.
- For CodeRabbit's notes:
  - fix what the PR broke, plus any one-line fix;
  - answer the rest in one PR comment and record them as follow-ups;
  - merge once the latest commit is reviewed and every note is answered.
- Don't wait on a review or CI before starting the next piece. Each PR-state change still needs David's yes.

### Where agent sessions start
The hook script names each agent session's project after the folder the agent runs in: its first workspace root, or
Claude Code's `cwd`. An agent also loads that folder's instructions, hooks and settings. So:
- A coordinating chat runs in this repository's own checkout, never in another project's folder.
- Each lane gets its own git worktree first (`git worktree add --no-track -b <branch> <path> <base>`), and its session
  then starts with that worktree as its folder.
  - A lane never works in the main checkout, which may hold another change's branch: its commits would land there.
- A chat that started in the wrong folder moves into the right one once it exists. The move takes effect when the chat's
  turn ends, so the chat uses absolute paths until then.

### Live data (`docs/SETTINGS.md`, "Live data")
Brain's content is built once and kept for the app's life. The agent monitor publishes up to about 20 times a second.
So a page that shows live data keeps three rules, each pinned by its page's `…LiveDataRulesTests`:
1. **Throttled and scoped.** Copy what the page shows into one value, from one subscription throttled to 500 ms, and
   assign it only when it changes. Nothing observes a store whole.
2. **Stopped while Brain is off screen.** The subscription is a `.task(id: visibility.isOnScreen)` on
   `BrainVisibility`. It ends when Brain is closed, minimised, covered or in another Space. The page reads once as it
   appears.
3. **No work while nothing is on screen.** Live views give way to a static copy, with no clock of their own.

A click resolves where it goes in its action, never in `body`.

### The string catalog
- `Kannu/Localizable.xcstrings`, with English as the source. Every user-facing string goes through
  `String(localized:)` and gets all 17 languages: ar, cs, de, en-GB, es, fr, hu, it, ko, nl, pl, pt-BR, ru, th, tr,
  uk and zh-Hans.
- Insert a new key as text in Xcode's own layout, before the first letter-initial key that sorts after it, ignoring
  case. The catalog lists punctuation-first keys first. Inserted this way, nothing else in the file moves.
- Never resolve a catalog conflict by hand:
  - merge it key by key;
  - check that no key went wrong and that no retired key is still used;
  - retire a key only when the compiler no longer extracts it.

### Snapshot boards
- DEBUG builds render Brain's pages to PNG:
  `open -n -W <Debug app> --args --kannu-snapshots <dir> --kannu-snapshot-tabs a,b`
  (`Kannu/helpers/DebugSnapshot.swift`).
- **Boards draw fixtures only,** never the Mac's own sessions, tasks, notes or clipboard. **The shelf board is never
  rendered.**
- Render the touched pages before and after a change. Add `shell` and `designSystem` when a theme value changes.

### Danger zones (`docs/REGRESSIONS.md`, "Danger zones")
- Before you edit a file in the ledger's Danger zones table, read its entries. Today the table covers:
  - everything under `Kannu/components/Settings/` (Brain);
  - the agent monitor, the traffic-light states and the hook installer;
  - the usage spawn and the usage limits;
  - `HostedContent.swift`;
  - the notch's Spaces and window creation;
  - `ModalPresenter.swift` and `BluetoothAudioManager.swift`;
  - AGENTS.md and CLAUDE.md;
  - the media controllers;
  - the notch's close and its swipe-to-close;
  - the launch permissions and onboarding;
  - the session-log parser.
- When a rule there breaks again, its dated addendum goes in the same commit as the fix.

### Release
`scripts/RELEASE.md` owns the process, and `openspec/specs/release/spec.md` states it as requirements. In short:
- A `v*` tag builds, signs, notarizes and publishes.
- A tag with a hyphen is a pre-release and never reaches the appcast.
- The notes come from `docs/release-notes/<version>.md`.
- The codename lives only in `ReleaseInfo.codename`.
- Build numbers only go up.

## Domain Context
- **Specs describe the redesign as built.** `openspec/specs/` describes the behaviour on the Brain redesign stack:
  - `super/brain-6-around` holds Stages 4 to 6 on top of `development`.
  - It reaches `development` through PRs #42, #43 and #52.
  - Until they merge, some files the specs cite exist only on the supers.
- **Brain is the main window,** opened from the notch and the menu bar. Its code lives under
  `Kannu/components/Settings/`, for historical reasons; `docs/SETTINGS.md` explains the naming rules.

## Important Constraints
- Nothing runs before the Terms of Use are accepted. No permission dialog appears before onboarding's Permissions
  step (AGENTS.md, "Known traps").
- No `v*` tag and no release without David's yes. Never stage `marketing/`. Never type or commit a secret.
- `CLAUDE.md` keeps the ART framework first and `@AGENTS.md` as its last line (`ChangelogRuleDocsTests`). Never run
  `/init`.
- **0.23.0's `openspec update` and `openspec init` also write their block into `CLAUDE.md`.** After running either,
  restore it with `git checkout -- CLAUDE.md`. Keep only the block in AGENTS.md.
- A cloud session cannot build, test, install or notarize the app. Those run on a Mac or in CI.

## External Dependencies
- GitHub Actions for CI and releases, CodeRabbit for PR review, Apple notarization, and Sparkle with its appcast.
- **The update feed:** installed copies read `libinmv/kannu`'s `Updates/appcast.xml` until PR #3 repoints
  `SUFeedURL`. The release change covers the bridge.
- The task sources' APIs: Jira Cloud, GitLab, GitHub, Linear and Todoist, plus EventKit for Apple Reminders
  (`docs/TASK-SOURCES.md`).
