# Tasks: fix-project-name-detection

## 1. Implementation
- [x] 1.1 Add `ProjectNameRules` (Foundation-only) with `projectName(forWorkingDirectory:)` and the Cursor slug
  decoder, and add it to the logic test target's Sources phase.
- [x] 1.2 Route the hook file reader, the passive Claude session record and the Claude/Codex transcript fallback
  through it.
- [x] 1.3 Decode Cursor slugs against existing folders, never listing a prompting home folder or `/Volumes`; cache each
  slug's result for the app's life.
- [x] 1.4 Log each resolution to `com.kannu.app` / `ProjectName`, once per change, with paths private.

## 2. Tests
- [x] 2.1 `ProjectNameRulesTests`: a plain repository, a Desktop worktree, a path inside one, a trailing slash, the
  root, and the `.claude` folders that are not worktrees.
- [x] 2.2 `ProjectNameRulesTests`: a hyphenated Cursor project, dots and underscores, backtracking, the fallback, a
  dotted home, scratch slugs, and the listing bound.

## 3. Gates
- [x] 3.1 Full KannuTests and the Debug build. [Mac]
- [x] 3.2 `bash .githooks/pre-commit` with the CHANGELOG entry staged. [Mac]
- [x] 3.3 `openspec validate --all --strict --no-interactive`.
- [ ] 3.4 David's check on his Mac: `/usr/bin/log stream --predicate 'subsystem == "com.kannu.app" AND category ==
  "ProjectName"'` while chats run, a Claude Desktop worktree chat among them; each card's label matches its folder.
  [Mac] [David]
