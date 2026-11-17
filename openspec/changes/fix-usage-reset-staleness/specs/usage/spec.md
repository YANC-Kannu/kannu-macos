## ADDED Requirements

### Requirement: The newest reading of each Claude window wins
For each Claude rate-limit window (the five-hour window, the weekly window and any per-model window), the card SHALL
show the newest live reading among the sources it may combine (the statusline file, Claude Code's cache and Claude
Desktop's history), whatever the source (`ClaudeUsageSnapshot.selections`). Two readings observed at the same moment
SHALL resolve to the source earlier in the list, the same way on every read. A missing source SHALL be skipped.

#### Scenario: A newer desktop sample beats an older cache
- **WHEN** the cache read the weekly window at 62 % ten hours ago and Claude Desktop sampled it at 7 % ten minutes ago
- **THEN** the card shows 7 %

#### Scenario: Equal times
- **WHEN** two sources read the weekly window at the same moment with different percentages
- **THEN** the card shows the earlier source's percentage on every read

#### Scenario: A source is missing
- **WHEN** the statusline file and the desktop history are absent and the cache holds a live weekly reading
- **THEN** the card shows the cache's reading

### Requirement: A reset clears readings taken before it
A reading taken before an exact reset of the same window that any source has seen pass SHALL NOT be shown, even while
its own reset, reported or inferred, is still ahead. An inferred reset SHALL clear nothing. A reset that passed before
a reading was taken SHALL NOT clear that reading.

#### Scenario: The weekly limit resets early
- **WHEN** Claude Desktop sampled the weekly window at 72 % two hours ago, with an inferred reset three days ahead,
  and Claude Code's cache reports that the window reset thirty minutes ago
- **THEN** the card does not show 72 %

#### Scenario: A fresher reading of the new window
- **WHEN** an older reading of the five-hour window says 64 % with its reset an hour ahead, and a fresher reading from
  another source says 2 % with a later reset
- **THEN** the card shows 2 % and the later reset

### Requirement: A run learns that Claude Code moved organization
A run SHALL go to the organization `~/.claude.json` names when the cache that one of Kannu's `/usage` runs wrote
contradicts the last known organization's weekly anchor and matches no remembered one, provided the named organization
is another one and the cache does not contradict its anchor (`ClaudeCachedUsage.attributeRun`, evidence
`movedOrganization`). The run SHALL then remember that organization's resets. When the file names no such organization, the run SHALL name nobody and
remember nothing.

#### Scenario: Claude Code moved from Team to Max
- **WHEN** Kannu last recorded Team, remembers only Team's week, and its run writes a cache on Max's Wednesday anchor
  while the file's profile, fetched days earlier, names Max
- **THEN** Claude Code is recorded on Max, Max's week is remembered, and the cache's fresh reading reaches the card
  within that refresh

#### Scenario: The file names the contradicted organization
- **WHEN** the run's cache contradicts Team's week and the file names Team
- **THEN** the run names nobody and remembers nothing

### Requirement: The source decision is logged without identities
Each time a card's decision for a window changes, Kannu SHALL log one `notice` line (subsystem `com.kannu.app`,
category `ClaudeUsage`) that names the winning source, why it won, and each copy's observation time and percentage.
The line SHALL NOT contain an organization, account, email or token. A read that only moves a percentage SHALL NOT
log again.

#### Scenario: Reading the decision on a Mac
- **WHEN** `/usr/bin/log stream --predicate 'subsystem == "com.kannu.app" AND category == "ClaudeUsage"'` runs while
  the card's weekly window changes source
- **THEN** a line starting `Usage source first card, seven_day:` names the winner and the times and percentages it
  weighed
