# Change: Ship Kannu 2.0, a notch in front of a Brain of features

## Why
Kannu began as "watch your agents": a traffic light in the notch. The Brain redesign has since made it much more than
that. Brain gives agents, tasks with sources and tags, the timer, notes, the clipboard, usage and security one
full-screen home, and the notch shows them all at a glance. The redesign is built, gated and installed for review, in
three stacked PRs (#42, #43, #52). The next release presents it as what it is:

**The notch is the front door, and Brain is the room behind it.**

That is a bigger step than 1.4.0, whose betas never reached `development`. So the release is **2.0**, and it ships as a
**beta first**.

## What Changes
- **Version 2.0.0**, numbered so that Sparkle moves every user forward:
  - the betas' builds go above the 1.4.0 betas' (9 to 11);
  - 2.0.0's build goes above every beta's.
- **Beta first, then final:**
  - `v2.0.0-beta.1` is a notarized pre-release for testers, which Sparkle never offers;
  - then a fix window;
  - then `v2.0.0`, which updates the appcast.
- **Three pillars, as built** (specs: `brain-shell`, `product-pages`, `tasks`, `tags`, `notes`, `clipboard`):
  - **Brain:** product pages, the theme, Geist, full screen, the menu bar, sidebar badges and onboarding.
  - **Tasks:** Jira, GitLab, GitHub, Linear, Todoist and Reminders as sources; Brain › Tasks with list-detail; the
    notch's Tasks button; the timer and Time to log; the archive.
  - **Tags:** typing `#tag` and `@time`; chips and colours; `#tag` search; the Tag filter.
- **Codename: Horus, recommended.** He is next on the list in `scripts/RELEASE.md`. His eye matches the new one-eye
  logo and a notch that closes like an eye. He is still a watcher, and Brain still watches the agents. The codename is
  David's call. It lives only in `ReleaseInfo.codename` (`Kannu/models/Constants.swift`).
- **The feed moves to this repository, with a one-time bridge.** PR #3 points `SUFeedURL` at
  `YANC-Kannu/kannu-macos`. Every 1.x install still reads `libinmv/kannu`'s appcast, so 2.0.0 final's entry must
  also land there once. Betas skip the appcast, so they need no bridge.
- **ADDED: a What's New window for existing users.** It shows once after updating to 2.0, with three cards: Brain,
  Tasks and Tags. It uses the `showWhatsNew` and `whatsNewWindow` hooks, which are declared but unused today. This is
  recommended, and it is one small child PR.
- **Notes for the release:**
  - CHANGELOG's `[Unreleased]` becomes `[2.0.0]`, with a short user-facing summary on top;
  - `docs/release-notes/2.0.0-beta.1.md` and `docs/release-notes/2.0.0.md`;
  - `ReadMe.md` is rewritten for the pivot.
- **A launch video, "A day in the notch":** 45 s at 16:9, with a 15 s cut at 9:16. It lives outside the repo, and every
  generation needs David's yes.

## Impact
- **Affected specs:**
  - `release`: the feed is MODIFIED; 2.0 numbering, beta-then-final and the feed bridge are ADDED.
  - `whats-new`: new, ADDED.
  - The other six capabilities ship as built, with no delta.
- **Affected code and files:**
  - `Kannu.xcodeproj/project.pbxproj` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`);
  - `Kannu/models/Constants.swift` (`ReleaseInfo.codename`);
  - `Kannu/Info.plist` (`SUFeedURL`, through #3);
  - `Kannu/KannuApp.swift` and `Kannu/KannuViewCoordinator.swift` (What's New);
  - `Kannu/Localizable.xcstrings`;
  - `CHANGELOG.md`, `docs/release-notes/`, `ReadMe.md`;
  - `Updates/appcast.xml`, here and once in `libinmv/kannu`.
- **Order:** the release gates in `tasks.md` run in order. Every push, merge, retarget, tag and release needs David's
  yes in the current chat turn.
- **Where things stand:** `handoff.md` in this folder is the run log: the stack's state, the pending asks and the
  carry-overs. It replaces the local notes for anyone without the Mac.
