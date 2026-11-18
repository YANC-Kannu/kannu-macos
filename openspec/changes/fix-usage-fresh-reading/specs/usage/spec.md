## ADDED Requirements

### Requirement: The card shows the freshest reading of its organization
Claude Code's cache SHALL be read as Claude Desktop's organization's reading when `~/.claude.json` names that
organization with a profile fetched no later than the cache and nothing contradicts the cache's week, whether or not Kannu has recorded Claude Code's
organization. Each window SHALL then take the newest reading of that organization. Claude Code's statusline SHALL
stay off Desktop's card until Kannu has recorded Claude Code's organization. A reading of one organization SHALL
NOT join another organization's card.

#### Scenario: First run, same organization
- **WHEN** Kannu has recorded no organization, `~/.claude.json` and Desktop's newest sample name the same one,
  Desktop's sample is 13 hours old at 48 %, and the cache is half an hour old at 73 %
- **THEN** the card's weekly bar shows 73 %

#### Scenario: A profile written back after the cache
- **WHEN** the file names Desktop's organization with a profile fetched after the cache, and the cache is another
  organization's
- **THEN** the cache stays off Desktop's card

#### Scenario: Different organizations
- **WHEN** the file names a Team organization and Desktop's newest sample names a Max one
- **THEN** Max's card shows Desktop's reading only, and Team's reading appears only on its own card once Kannu has
  recorded Team

### Requirement: The cache's owner follows the file when the recorded organization is ruled out
A read SHALL attribute the cache to the organization `~/.claude.json` names when the cache's weekly reset
contradicts the recorded organization's anchor, matches no remembered one, and does not contradict the named
organization's anchor (`ClaudeCachedUsage.cacheOwner`). Otherwise such a cache SHALL stay unattributed and go on no
card.

#### Scenario: A stale recorded organization
- **WHEN** Team is recorded with a Tuesday 05:00Z week, the cache resets Wednesday 00:00Z, and the file names Max
  with no remembered week
- **THEN** the cache is Max's and goes on Max's card before any of Kannu's runs

#### Scenario: The named organization is contradicted too
- **WHEN** the cache's week contradicts both the recorded organization's and the named organization's anchors
- **THEN** the cache goes on no card

### Requirement: Desktop samples carry no age limit of their own
A Claude Desktop sample SHALL stay on its card until its window ends, a fresher reading of the same organization
replaces it, or its `notAfter` bound passes. Kannu SHALL NOT drop it for age alone, and the card SHALL label its age.

#### Scenario: A desktop-only user
- **WHEN** Desktop's only sample of the week is 20 hours old and no other source has a reading
- **THEN** the card shows that sample with its age
