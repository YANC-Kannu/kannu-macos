## Context
Most of the release machinery already exists:
- a `v*` tag builds, notarizes and publishes;
- a tag with a hyphen is a pre-release that never reaches the appcast;
- notes come from `docs/release-notes/<version>.md`.

Three facts shape 2.0 (measured 2026-11-13):
- **Numbering:** the project is 1.3.4, build 8. The 1.4.0 betas (`v1.4.0-beta.1` to `.3`, on `release/1.4.0`, never
  merged into `development`) used builds 9, 10 and 11.
- **The feed:** `SUFeedURL` still names `libinmv/kannu`'s appcast. PR #3 repoints it, along with CI and the docs, to
  this repository. It has been open since 2026-10-27 and conflicts with `development` today.
- **What's New:** `showWhatsNew` (`@AppStorage`, `Kannu/KannuViewCoordinator.swift:138`) and `whatsNewWindow`
  (`Kannu/KannuApp.swift:183`) are declared and never used. `continueLaunch()` already knows whether a launch is an
  upgrade: `isUpgrade = !coordinator.firstLaunch` (`Kannu/KannuApp.swift:1105`). Onboarding's version is still 1, so an
  updated 1.x install does not rerun onboarding.

## Goals / Non-Goals
- **Goals:**
  - Ship 2.0 as a beta, then final.
  - Every 1.x install is offered 2.0.0.
  - People who update meet the pivot once.
- **Non-Goals:**
  - New features: they lead the 2.x roadmap unless David adds them.
  - Changing the release workflow.
  - Automating the feed bridge, which is needed once.

## Decisions
- **Numbering.** beta.1 is build 12, and each later beta is one more. 2.0.0 is the last beta's build plus one. With
  one beta, 2.0.0 is build 13.
- **Beta path.** Use the existing pre-release path unchanged: `v2.0.0-beta.1`, a fix window, then `v2.0.0`. Testers
  install the beta from the Releases page. Sparkle moves them to 2.0.0 because its build is higher.
- **The feed bridge.** After the `v2.0.0` run updates this repository's `Updates/appcast.xml`:
  1. Copy its 2.0.0 `<item>` (already Sparkle-signed, with the enclosure on this repository's release) into
     `libinmv/kannu`'s `main` `Updates/appcast.xml`, as one commit.
  2. Verify by reading that file's raw URL: it lists `sparkle:version` for 2.0.0.

  **Rejected: keeping `SUFeedURL` on `libinmv/kannu` for 2.0.** Every later release would then need the bridge.
- **What's New.**
  - It shows from the end of `continueLaunch()` when `isUpgrade` holds and 2.0's welcome has not been seen.
  - Whether a launch has seen it is stored in a `Defaults` key in `Kannu/models/Constants.swift`, because AGENTS.md
    keeps every key there. The child PR either retires the stray `showWhatsNew` `@AppStorage` or reuses it there, and
    says which.
  - `whatsNewWindow` holds the window.
  - Its content view takes a fixture for its snapshot board.

## Risks / Trade-offs
- **The bridge is forgotten, and 1.x users never see 2.0.** Mitigation: the ship step's checklist reads the old feed's
  raw XML after release (tasks 7.3 and 7.4).
- **A build number is too low, and Sparkle offers nothing.** Mitigation: the version step checks the numbers against
  the table above, and the beta's notarized pre-release proves the build before final (`ReleaseWorkflowRulesTests`
  holds the pre-release rules).
- **What's New shows on a fresh install.** Mitigation: a rule test on the `isUpgrade` gate, and a Mac check on a fresh
  user account.

## Migration Plan
The gates in `tasks.md` run in order.
- **A bad beta** is only a pre-release: supersede it with `beta.2`.
- **A bad final** is followed by 2.0.1 with a higher build. If 2.0.0 is pulled, the bridge entry comes out of
  `libinmv/kannu`'s appcast with it.

## Open Questions
`tasks.md`, section 9, lists each one with its recommendation.
