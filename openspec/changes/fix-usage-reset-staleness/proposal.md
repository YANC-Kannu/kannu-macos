# Change: Show the fresh Claude limit after an early reset

## Why
On 2026-11-16 the Claude weekly limit reset early. Claude Code's cache had the fresh week within the hour, but Kannu's
Claude card kept Claude Desktop's sample from before the reset, at its old percentage.

Two faults, measured read-only on David's Mac:
- **The run never learned whose cache it fetched.** Claude Code had moved from Team to Max. Kannu still recorded Team,
  and had never remembered Max's weekly anchor. The run fetches no profile, so `ClaudeCachedUsage.attributeRun` found
  that the cache contradicted Team's week and named nobody (`contradicted`). Every run since ended the same way. On
  each read the cache's owner was then `unknown`, so the fresh cache went on no card. The card followed Claude
  Desktop's organization, and showed Claude Desktop's sample alone.
- **An older reading survives a reset it never saw.** `ClaudeUsageSnapshot.merged` drops a copy only when its own reset
  has passed. The desktop history infers its resets, so a sample from before an early reset stays live until a reset
  that no longer applies.

## What Changes
- `attributeRun`: when the cache the run wrote contradicts the last known organization's week, and the file names
  another organization whose week the cache does not contradict, the run goes to that organization
  (`movedOrganization`) and remembers its resets. The file naming no other organization, or one the cache also
  contradicts, stays `contradicted`, as before.
- `ClaudeUsageSnapshot.selections`: per window, the newest live reading wins, whatever its source. Equal times go to the
  source earlier in the list. A reading taken before an exact reset that any source has seen pass is dropped
  (`resetSince`), even while its own reset is still ahead. `merged` takes each window from that decision and never
  borrows a reset from a dropped copy.
- One `notice` log line per card and window when the decision changes: which source won, why, and each copy's
  observation time and percentage. Subsystem `com.kannu.app`, category `ClaudeUsage`. No organization, account,
  email or token.
- No new file read, spawn or timer. The decision runs on what the existing read already holds.

## Impact
- Affected specs: `usage` (new capability).
- Affected code: `Kannu/managers/AgentStatus/ClaudeCachedUsage.swift`, `ClaudeUsageSnapshot.swift`,
  `CursorAgentStatusMonitor.swift`. All three are in the usage-limits danger zone (`docs/REGRESSIONS.md`, entry 8).
- Reverses one pinned decision: `testAContradictedLastKnownOrganizationIsNeitherKeptNorTaught` held that a profile from
  outside the run never names the cache's organization. It now does when the cache has ruled out the last known
  organization and does not contradict the named one. Entry 8 gets a dated addendum.
