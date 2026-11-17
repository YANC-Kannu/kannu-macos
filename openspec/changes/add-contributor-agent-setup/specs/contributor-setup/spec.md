## ADDED Requirements

### Requirement: One ordered setup path
`CONTRIBUTING.md` SHALL open with one ordered setup checklist that takes a fresh clone to a working setup: switching
to `development`, installing and checking the git hooks, the `Kannu Dev` signing identity, the KannuTests run, the
Debug build and the pinned OpenSpec CLI. Each step SHALL name the check that proves it worked. A read-only
`scripts/doctor.sh` SHALL report the same checks in one run.

#### Scenario: A fresh clone
- **WHEN** a contributor clones the repository and follows the checklist in order
- **THEN** `git config core.hooksPath` prints `.githooks`, KannuTests pass, and the pinned `openspec list` runs

#### Scenario: A broken setup
- **WHEN** the hooks are not installed, or Node is missing
- **THEN** `scripts/doctor.sh` reports a FAIL or WARN line that names the step to repeat

### Requirement: Shared agent settings never pre-approve publishing
The committed `.claude/settings.json` SHALL allow only read-only and gate commands. It SHALL NOT allow `git push`, a
merge, a tag or a release without a prompt. Personal permissions SHALL live in the git-ignored
`.claude/settings.local.json`.

#### Scenario: An agent tries to push
- **WHEN** a contributor's Claude Code session runs `git push` in this repository
- **THEN** it asks first, because no committed rule allows it

### Requirement: The OpenSpec CLI is pinned and enforced
Every committed instruction and command that runs OpenSpec SHALL use
`OPENSPEC_TELEMETRY=0 npx -y @fission-ai/openspec@0.23.0`. CI SHALL run
`validate --all --strict --no-interactive` with that CLI on every push and PR that runs the Build jobs.

#### Scenario: A malformed delta
- **WHEN** a PR adds a requirement without a scenario
- **THEN** the OpenSpec CI job fails

### Requirement: Every agent tool sees the same skills and commands
Shared skills SHALL live once, under `.agents/skills/`, and SHALL reach Claude Code and Cursor through symlinks, not
copies. OpenSpec commands SHALL exist for Claude Code, Cursor and GitHub Copilot.

#### Scenario: A skill changes
- **WHEN** a contributor edits `.agents/skills/kannu-gates/SKILL.md`
- **THEN** Claude Code, Cursor and Codex all read the edited text, with no second file to update

### Requirement: Recurring merges have committed tools
The repository SHALL ship resolvers for its two recurring conflicts: `CHANGELOG.md`, which keeps both sides' entries
in date order, and `Kannu/Localizable.xcstrings`, which merges key by key and reports any lost or changed key.

#### Scenario: Two branches both add a CHANGELOG entry
- **WHEN** a merge conflicts at the top of `## [Unreleased]`
- **THEN** the resolver keeps both entries, newest first, and the pre-commit hook accepts the result
