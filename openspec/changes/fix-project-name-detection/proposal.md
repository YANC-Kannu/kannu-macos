# Change: Name every chat's project after the folder the user knows

## Why
A chat's card shows the project it runs in. Two cases got it wrong, and nothing recorded how a name was chosen, so a
wrong label could not be told from a right one without reading code:
- **Claude Desktop worktrees.** Desktop runs a chat in `<repo>/.claude/worktrees/<random>`. The card showed the random
  folder name, not the repository.
- **Cursor project slugs.** Without a hook file, a Cursor chat is named from its transcript folder,
  `~/.cursor/projects/<slug>`, where the slug is the project's path with every character that is not a letter or digit
  written as `-`. The decoder kept only the slug's last word, so `acme-api` became `api`. It also encoded only the
  home folder's slashes, so on a home with a dot or underscore in it (`/Users/alice.smith`) the home never matched and
  the card showed the whole slug.

## What Changes
- **One rule, in Swift.** `ProjectNameRules.projectName(forWorkingDirectory:)` (Foundation-only, in the logic test
  target) names the project: the folder name, except anywhere under `<repo>/.claude/worktrees/<name>`, which is
  `<repo>`. Every other `.claude` folder is an ordinary folder.
- **Every resolution point goes through it:** the hook file reader (the hook script's workdir, its first workspace root
  or `cwd`), Claude's passive session record, and the transcript fallback for Claude and Codex. The hook script does not
  change, so `KANNU_HOOK_SCRIPT_VERSION` stays where it is.
- **Cursor slugs decode against the folders that exist,** longest match first with backtracking, and at most 48 folder
  listings. Kannu never lists a home folder whose first read raises a macOS privacy prompt (Desktop, Documents,
  Downloads, Library, Movies, Music, Pictures) or anything under `/Volumes`; a slug there falls back to the old guess,
  with the home folder encoded the way Cursor encodes it.
- **A `ProjectName` log** (subsystem `com.kannu.app`): one line each time a session's name or its inputs change, with
  the agent, the source, the session id, the chosen name and the rule that chose it public, and the working directory
  and workspace roots private.

## Impact
- Affected specs: `agent-status` (ADDED requirements, scoped to project naming).
- Affected code: `Kannu/managers/AgentStatus/ProjectNameRules.swift` (new), `CursorAgentStatusMonitor.swift`,
  `AgentSessionLogParser.swift`, `CursorTranscriptParser.swift`; `KannuTests/ProjectNameRulesTests.swift` (new).
- No hook-script change, no new setting, no new permission.
