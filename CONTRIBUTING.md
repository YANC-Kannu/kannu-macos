# Contributing to Kannu (കണ്ണ്)

Thank you for your interest in contributing to Kannu! We welcome contributions from everyone—developers, designers, testers, and documentation writers. Please read the following guidelines to help us maintain a collaborative and high-quality project.

## Setup checklist

Do these in order on a fresh clone. Each step names the check that proves it worked.

1. **Clone, then switch to `development`.** The default branch, `main`, is the release branch and lags behind
   the agent setup and the specs. Skipping the LFS smudge keeps older refs' LFS pointers from failing the clone
   (see [Development Setup](#development-setup)):

   ```bash
   GIT_LFS_SKIP_SMUDGE=1 git clone <your-fork-url> kannu
   cd kannu
   git checkout development
   ```

2. **Install the git hooks** with `./scripts/install-git-hooks.sh`, then check that `git config core.hooksPath`
   prints `.githooks`. CI runs the hook only on the committed tree, so only your local hook checks that each
   commit carries its CHANGELOG entry.
3. **Create the `Kannu Dev` code-signing identity** once, as
   [AGENTS.md, "Build, test, and run"](AGENTS.md#build-test-and-run) describes, and check that
   `security find-identity -v -p codesigning` lists it. A stable identity keeps macOS privacy grants
   (Accessibility and others) across rebuilds; ad-hoc signing loses them on every build.
4. **Run the unit tests**, in a derived-data folder of their own:
   `xcodebuild test -project Kannu.xcodeproj -scheme KannuTests -destination "platform=macOS" -derivedDataPath .build-tests`
5. **Build the app** (Debug, unsigned, to check that it compiles):
   `xcodebuild -project Kannu.xcodeproj -scheme Kannu -configuration Debug CODE_SIGNING_ALLOWED=NO build`.
   AGENTS.md gives the signed variant that you can launch.
6. **Check OpenSpec** (needs Node.js 20.19 or later):
   `OPENSPEC_TELEMETRY=0 npx -y @fission-ai/openspec@0.23.0 list`. Always use this pinned form, and never run
   `openspec init` or `openspec update`; [AGENTS.md](AGENTS.md) says why.

**Building in Xcode instead of the command line:** the project file names the maintainers' Apple teams, so
Automatic signing fails for anyone else. Under the Kannu target's Signing & Capabilities, set Team to your own
(or to None, with `Kannu Dev` as the certificate), and don't commit that change to `Kannu.xcodeproj`.

**Which file each agent tool reads:**
- **Claude Code:** `CLAUDE.md`, which imports `AGENTS.md`, plus `.claude/settings.json` (shared permissions),
  `.claude/commands/openspec/` and `.claude/skills/`. Personal settings go in `.claude/settings.local.json` and
  personal notes in `CLAUDE.local.md`; both are git-ignored.
- **Codex:** `AGENTS.md` and `.agents/skills/`.
- **Cursor:** `AGENTS.md`, `.cursor/rules/` and `.cursor/skills/`.
- **GitHub Copilot, Aider and Windsurf:** `AGENTS.md`.

## Table of Contents
- [Setup checklist](#setup-checklist)
- [How to Contribute](#how-to-contribute)
- [Code of Conduct](#code-of-conduct)
- [Development Setup](#development-setup)
- [Git Hook Setup](#git-hook-setup)
- [Working with AI Agents](#working-with-ai-agents)
- [Pull Request Process](#pull-request-process)
- [Before Changing Agent Status Code](#before-changing-agent-status-code)
- [Commit Checklist](#commit-checklist)
- [Coding Guidelines](#coding-guidelines)
- [Design Contributions](#design-contributions)
- [Documentation](#documentation)
- [Code Review process](#code-review-process)
- [Community & Support](#community--support)


---

## How to Contribute

1. **Fork the repository** and clone your fork locally.
2. **Create a feature branch** for your changes: `git switch -c feature/your-feature-name`
3. **Make your changes** following the guidelines below.
4. **Test your changes** to ensure they work as expected and do not break existing functionality.
5. **Commit** with clear, descriptive messages after completing the [Commit Checklist](#commit-checklist).
6. **Push** to your fork and submit a **pull request** (PR) to the `development` branch.
7. **Participate in code review** and address any feedback.

## Code of Conduct

We are committed to fostering a welcoming and inclusive environment. Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

## Development Setup

- **Requirements:**
	- macOS Sonoma 14.0 or later
	- Xcode 16.4 or later, with a Swift 6.1+ toolchain — `KannuApp.swift` uses `extension CGRect: @retroactive Hashable`, which needs Swift 6.0, and CI builds on `macos-15`/`macos-26` for Swift 6.1+
	- MacBook with a notch (for full feature testing)
- **Clone the repo:**
	```bash
	git clone <your-fork-url>
	cd kannu
	open Kannu.xcodeproj
	```
- **This repo does not use Git LFS.** Everything the app bundles must be an ordinary git blob, so do not add an LFS rule: `xcodebuild` copies a pointer into the app without complaint, and the user gets an empty icon. `BundledVideoTests` and `scripts/check-no-lfs-pointers.sh` catch that. Older refs still hold pointers, `main` and `release/1.4.0` included until this change reaches them, and their objects are not on this repo's LFS store. So do not set `lfs: true` on a checkout of one, and if you have git-lfs installed, clone or check one out with `GIT_LFS_SKIP_SMUDGE=1`. A plain `git clone` lands on `main`.
- **Build & Run:**
	- Select your Mac as the run destination in Xcode.
	- Choose the **Kannu** scheme.
	- Press ⌘R to build and run.

## Git Hook Setup

Run this once after cloning:

```bash
./scripts/install-git-hooks.sh
```

This enables the repo-managed `pre-commit` hook from `.githooks/`.

## Working with AI Agents

Agents do a meaningful share of the work here — the Commit Checklist below asks for an agent feature
label precisely because of that. If you are pointing one at this repository, or you are one:

- **`AGENTS.md` at the repository root is the canonical instruction file.** It holds the engineering
  standards: the architecture principles, the build/test/run commands, the house conventions and the
  traps this project has already paid for. Codex, Cursor, Copilot, Aider and Windsurf read it
  automatically.
- **`CLAUDE.md` is Claude Code's entry point**, because Claude Code reads that filename and not
  `AGENTS.md`. It holds only Claude-specific machinery and imports the shared file with `@AGENTS.md`.
- **Do not copy rules between them.** One rule in two files is how this repo shipped a documented
  CHANGELOG shape that the commit hook rejected — twice, in two different files.
  `KannuTests/ChangelogRuleDocsTests.swift` now fails CI if the copies disagree with the hook.

## Pull Request Process

1. Ensure your PR has a clear title and description, and target `development` unless a maintainer asks for a different base branch.
2. Link any related issues.
3. Keep PRs focused—one feature or fix per PR when possible.
4. Update documentation if your change affects user-facing behavior.
5. Wait for review and address feedback promptly.

Work too large for one review ships as stacked super PRs; `AGENTS.md` has the rules.

## Before Changing Agent Status Code

The agent-status subsystem (`Kannu/managers/AgentStatus/`) has repeatedly re-broken the same
invariants. [docs/REGRESSIONS.md](docs/REGRESSIONS.md) records each one with the commits that
prove it, why it recurs, and the guard that now catches it. Please read it before working in
that area, and add an entry when you find a bug recurring.

## Commit Checklist

Before each commit:

1. Define the **developer feature label** (what you are building).
2. Define the **agent feature label** if an agent did any of the work. The line itself is required
   either way — write `none — human-authored` when it did not.
3. Add one new entry at the **top** of `## [Unreleased]` in `CHANGELOG.md`, in exactly this shape.
   `.githooks/pre-commit` parses it literally and rejects anything else, so the bold keys and the
   trailing colons matter:

   ```markdown
   ### YYYY-MM-DD - <a short title for the change>
   - **Developer label:** <the developer feature label, or the request in the requester's own words>
   - **Agent label:** <agent feature label, or "none — human-authored">
   - **Changes:**
     - <one concrete change per bullet>
   ```

   The heading and the `Developer label` are not the same string: the heading titles the change,
   while the label names the feature or quotes the request that prompted it. Every entry in
   `CHANGELOG.md` follows that split — read the last few before writing yours.
4. Stage `CHANGELOG.md` together with the code changes.
5. Use a commit subject that reflects the developer feature label (avoid vague messages like `Fixes`).

## Coding Guidelines

- Follow existing Swift and SwiftUI conventions in the project.
- Match surrounding code style, naming, and structure.
- Keep changes scoped to the task at hand.
- Prefer extending existing abstractions over duplicating logic.

## Design Contributions

UI and UX improvements are welcome. Include screenshots or screen recordings in your PR when changing visual behavior.

## Documentation

Update `ReadMe.md`, localized strings, and inline help text when you change user-visible features or settings.

## Code Review process

Maintainers will review PRs for correctness, style, and scope. Be responsive to feedback and iterate as needed.

## Community & Support

Open an issue for bugs, feature requests, or questions. Be respectful and provide reproduction steps for bug reports.

Thank you for helping make Kannu better!
