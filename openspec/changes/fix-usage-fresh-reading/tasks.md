## 1. Tests (made-up organizations)
- [x] 1.1 First run: no recorded organization, the file and Desktop name the same one, and a 13-hour-old Desktop sample sits next to a fresh cache.
- [x] 1.2 Stale recorded organization: the cache rules it out, and the file names Desktop's.
- [x] 1.3 Different organizations: they stay on separate cards, recorded or not.
- [x] 1.4 `cacheOwner` refusals: the file names the ruled-out organization, names none, or names one whose week the cache also contradicts.

## 2. Fix
- [x] 2.1 `cacheOwner(weeklyReset:claudeCode:named:resets:)`.
- [x] 2.2 `cardSources`: the same-organization cache joins Desktop's card while Claude Code's organization is unrecorded.
- [x] 2.3 `cachePlacement` logged in `ClaudeUsage`.

## 3. Gates
- [x] 3.1 Full KannuTests, and the Debug build with compile activity confirmed.
- [x] 3.2 `bash .githooks/pre-commit` with a CHANGELOG entry staged.
- [x] 3.3 `openspec validate --all --strict --no-interactive`.
- [ ] 3.4 On the Mac, after the hold lifts, check a first run. Preconditions:
  - `oauthAccount.organizationUuid` in `~/.claude.json` names the same organization as Desktop's newest sample;
  - `profileFetchedAt` is no later than `cachedUsageUtilization.fetchedAtMs`;
  - the cache's weekly window is live and at or above Desktop's sample from that week.

  Then the card's weekly bar matches `cachedUsageUtilization` within one read, and the log shows
  `cache placement: cache first card`. If a precondition fails, the card shows Desktop's reading until
  Kannu's first fetch records the organization, as designed.
