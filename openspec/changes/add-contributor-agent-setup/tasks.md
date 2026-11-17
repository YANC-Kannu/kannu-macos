# Tasks: add-contributor-agent-setup

Section 1 shipped with 2.0, in the same PR as this proposal. Sections 2 to 7 wait until after 2.0. Every push, merge,
tag and release still needs a maintainer's yes (`openspec/project.md`, "The hold rule").

## 1. Quick wins, shipped with 2.0
- [x] 1.1 `.claude/settings.json`: drop `Bash(git push*)`; allow only read-only git, the KannuTests run, the pinned
  OpenSpec `list` and `validate`, and `bash .githooks/pre-commit`.
- [x] 1.2 `CLAUDE.md`: the `caveman` skill is optional; the ART contract stays first and the `AGENTS.md` import last.
- [x] 1.3 `openspec/project.md`: a maintainer's yes in the hold rule, the release owner's yes for tags and releases;
  specs describe `development`; the feed line after #3; the `development` and `super/**` rulesets.
- [x] 1.4 `AGENTS.md`: the pinned OpenSpec CLI, and never `openspec init` or `update`.
- [x] 1.5 `.claude/commands/openspec/*.md`: the pinned CLI, without the `openspec update` hint.
- [x] 1.6 CI: an ubuntu job running the pinned `openspec validate --all --strict --no-interactive` and the pre-commit
  hook.
- [x] 1.7 `.gitignore`: `marketing/`, `*.local.md`, `.claude/worktrees/`, `.claude/settings.local.json`.
- [x] 1.8 `CONTRIBUTING.md`: the Setup checklist, Xcode signing for contributors, and which file each agent tool
  reads.

## 2. As-built specs
Each is its own change with an ADDED delta, written from the code on `development` and citing the rule tests that
already pin it. One capability per change, archived as soon as it is reviewed.
- [ ] 2.1 `agent-status`: the traffic-light states and transitions, hook install and removal per provider, session
  discovery, click-through, and #55's behaviour (Claude hooks never hold up a prompt; the status line is left alone).
  Build it from `docs/REGRESSIONS.md`'s agent-status entries.
- [ ] 2.2 `agent-security`: findings, policy rules and acknowledgement.
- [ ] 2.3 `usage-limits`: providers, quota reads, alerts and refresh rules.
- [ ] 2.4 `timer`: the timer itself (Time to log is already in `tasks`).
- [ ] 2.5 `launch-gate`: the Terms of Use gate, onboarding, and when a permission may first be asked
  (`LaunchGateRulesTests`, `FirstLaunchRulesTests`).
- [ ] 2.6 `updates`: Sparkle, the feed and What's New, once `release-2-0`'s deltas are archived (section 7).
- [ ] 2.7 The notch surfaces: media, HUD, lock screen and shelf.
- [ ] 2.8 Drop the `super/brain-6-around` wording from the `brain-shell` and `product-pages` Purposes, and the
  "Today" version and feed lines from `release`, in the change that next touches each.

## 3. Setup tooling
- [ ] 3.1 `scripts/doctor.sh`: read-only PASS, WARN and FAIL lines for Xcode and Swift, the Metal toolchain on macOS
  26, `core.hooksPath`, the `Kannu Dev` identity, Node for OpenSpec, and Git LFS smudging. `install-git-hooks.sh`
  runs it at its end, and the Setup checklist links it.
- [ ] 3.2 A committed `CHANGELOG.md` conflict resolver that keeps both sides' entries, ordered by date.
- [ ] 3.3 A committed `Localizable.xcstrings` merge: key by key, then a check that no key was lost or changed.
- [ ] 3.4 `scripts/snapshot-boards.sh <app> <out> <tabs>`: fixtures only, refuses the shelf board.
- [ ] 3.5 `scripts/build-launch-app.sh`: `--identity` (default `Kannu Dev` when it exists, else ad-hoc) and
  `--install` (back up, quit, copy into `/Applications`, check the signature, relaunch).
- [ ] 3.6 `.gitignore`: let `.sh` and `.py` files under `.claude/`, `.agents/` and `.cursor/` be committed, since the
  skills in section 4 need helpers there.

## 4. Shared skills
- [ ] 4.1 `kannu-gates`, `kannu-boards` and `kannu-build-launch` under `.agents/skills/`, calling the scripts from
  section 3.
- [ ] 4.2 Move the Cursor build skills into `.agents/skills/`.
- [ ] 4.3 Symlinks from `.claude/skills/` and `.cursor/skills/` to each `.agents/skills/` folder, including
  `kannu-senior-contributor`. No copies.

## 5. OpenSpec for every tool
- [ ] 5.1 Run 0.23.0's `init` for Cursor and GitHub Copilot in a scratch checkout; commit only `.cursor/commands/`
  and `.github/prompts/`, with the pinned CLI and without the `openspec update` hint.
- [ ] 5.2 Note in the Setup checklist that Codex's OpenSpec prompts install per user, outside the repository.

## 6. Review and enforcement
- [ ] 6.1 `.github/pull_request_template.md`: a behaviour change carries an OpenSpec delta, or says why it is exempt.
- [ ] 6.2 `.github/CODEOWNERS` for `openspec/`, the instruction files, `.githooks/` and the danger zones.
- [ ] 6.3 `.githooks/pre-commit`: add `.claude/`, `.agents/`, `.cursor/` and `openspec/` to the source paths that
  need a CHANGELOG entry.
- [ ] 6.4 A PR-level CI check that a source change carries a CHANGELOG entry, since the checkout job cannot see one.
- [ ] 6.5 A cloud SessionStart setup (committed hook or setup script) that installs the git hooks and checks for
  `npx`.

## 7. Release-2-0's deltas
- [ ] 7.1 Split `release-2-0`'s deltas by capability (`release`, `whats-new`) from its release checklist and video,
  which are not spec deltas.
- [ ] 7.2 Archive each delta as its code lands, so the main specs stop contradicting the code (the feed since #3,
  What's New since #59).
