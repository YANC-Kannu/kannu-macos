# Change: The Claude card shows the freshest reading of its organization

## Why
The first-run review on 2026-11-18 (finding F1) caught the Claude card showing a Claude Desktop sample 13 hours old,
logged as `desktop won (only live reading)`. Claude Code's cache of the same organization was half an hour old.

On a fresh install Kannu has recorded no organization for Claude Code. `ClaudeUsageSnapshot.cardSources` then kept
the cache off the card unless the cache's own week named Desktop's organization. That needs a remembered weekly
anchor, which a first run cannot have. `~/.claude.json` and Desktop's newest sample named the same organization,
but nothing used that.

The same symptom came from a stale recorded organization on 2026-11-16 (`fix-usage-reset-staleness`). That change
fixed it for Kannu's own runs. The read side still waited for a run.

## What Changes
- `ClaudeCachedUsage.organizationNamingCache`: the file names the cache's organization only when its profile was
  fetched no later than the cache, with 2 s of slack. A profile written after the cache may be another process's
  write-back. On 2026-10-28 one put Team's zeros on the Max card, and
  `testAnUnrecordedClaudeCodeOrganizationKeepsItsSourcesOff` still pins that case.
- `ClaudeCachedUsage.cacheOwner` takes the organization the file names. A cache that rules out the recorded
  organization goes to the named one when the cache does not contradict that one's week, on every read.
- `cardSources`, with Claude Code's organization unrecorded: the cache joins Desktop's card when the file names
  Desktop's organization and the cache's owner is not unknown. The statusline stays off until Kannu records the
  organization.
- No age limit on Desktop samples. Desktop writes them only while its usage panel is in use, so gaps of days are
  normal. A fresher reading of the same organization beats an old sample (`selections`), the card labels the age,
  and the week's end bounds it.
- `CardSources.cachePlacement`: one `notice` line in category `ClaudeUsage` each time the placement changes. It
  says where the cache went, who owns it, and how the organizations compare. It contains no ids.
- Kept: the first card follows Desktop's organization, and two organizations get two cards.

## Impact
- Affected specs: `usage` (adds to `fix-usage-reset-staleness`, which is not archived yet).
- Affected code: `Kannu/managers/AgentStatus/ClaudeCachedUsage.swift`, `ClaudeUsageSnapshot.swift` and
  `CursorAgentStatusMonitor.swift`. All three are danger-zone files (`docs/REGRESSIONS.md` entries 8 and 24).
