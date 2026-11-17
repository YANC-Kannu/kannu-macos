## 1. Reproduce
- [x] 1.1 `ClaudeUsageOrganizationTests.testAnEarlyResetReachesTheCardOnceTheRunLearnsClaudeCodesOrganization`: made-up
  `.claude.json` and `plan-usage-history.json` files in the measured shape, read through `ClaudeUsageSources.read`.
  Before the run is attributed, the card shows the desktop's pre-reset sample; after it, the cache's fresh week.

## 2. Fix
- [x] 2.1 `ClaudeCachedUsage.attributeRun`: the `movedOrganization` evidence.
- [x] 2.2 `ClaudeUsageSnapshot.selections`: newest live reading per window, ties to the earlier source, readings an
  exact reset has passed since dropped. `merged` built on it.
- [x] 2.3 `CursorAgentStatusMonitor`: one `notice` per card and window when its decision changes.

## 3. Tests
- [x] 3.1 Newer beats older across sources, in either source order.
- [x] 3.2 An early reset clears an older reading before its own reset, and a fresher reading replaces it.
- [x] 3.3 Equal times resolve to the earlier source, every time.
- [x] 3.4 A missing source is skipped, and the indices stay the list's.
- [x] 3.5 The log line carries sources, times and percentages only.
- [x] 3.6 A contradicted last known organization yields to the file's other organization, and only to one the cache
  does not contradict.

## 4. Gates
- [x] 4.1 Full KannuTests and the Debug build, with compile tasks confirmed.
- [x] 4.2 `bash .githooks/pre-commit` with the CHANGELOG entry staged.
- [x] 4.3 `openspec validate --all --strict --no-interactive`.
- [ ] 4.4 On the Mac, after an early reset: the Usage card shows the fresh weekly percentage within one refresh.
