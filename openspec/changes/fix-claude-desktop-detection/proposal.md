# Change: Claude's yellow and green in Claude Desktop Code-tab chats

## Why
Claude Code now runs mostly inside Claude Desktop's Code tab. Kannu's colour logic is unchanged since 24 October, but
that host exposed three gaps, measured on a maintainer's Mac:
- **A question showed red.** A Code-tab turn ends with the desktop's own next-step question (an internal MCP tool,
  `mcp__ccd_turn__wrap_up`, with an `ask`). `Notification` and `PermissionRequest` never fire there, so the turn's
  `Stop` wrote `stopped`: a chat waiting on its user was red.
- **The card vanished while waiting.** The desktop app ends the CLI process minutes after the turn; `SessionEnd`
  deleted the status file.
- **Green faded on long silent stretches.** Past the 360 s hook window, green rested on the passive tail alone (600 s
  from the last record), while Claude's own session record said `busy`, a status Kannu read but used only for
  background agents.

## What Changes
- **Hook v50.** A blocking Claude `PreToolUse` group for the question tool marks the turn `question_open` when its `ask`
  is not empty. `Stop` or `StopFailure` (not a rate limit) on such a turn writes `awaiting_input`; the next prompt
  clears it; `SessionEnd` keeps the file, marked `process_ended`. The tool's name is one documented constant on each
  side. The cloud relay leaves the group out.
- **A `.questionOpen` tail verdict.** The newest question in the transcript is newer than the newest real prompt. It
  holds a question yellow, live process or not, for at most 12 h from the `Stop`, and exempts its file from the stale
  cap. The reconciler does not demote a held question. The passive side reads it as a finished turn.
- **Claude's record as evidence.** `busy`, with a live process, keeps an `executing` or `thinking` hook session green
  past 360 s. `waiting`, with a live process, holds a hook yellow; it never creates one.
- **An `AgentState` log** (subsystem `com.kannu.app`): one line per real colour change of a card, with its evidence.

## Impact
- Affected specs: `agent-status` (ADDED requirements, scoped to Claude Desktop detection).
- Affected code: `AgentHookInstaller.swift` and `scripts/kannu-agent-status.sh` (v50), `AgentHookLayout.swift`,
  `ClaudeCloudRelaySetup.swift`, `AgentSessionLogParser.swift`, `AgentTrafficLightState.swift`,
  `AgentSubagentFold.swift`, `CursorAgentStatusMonitor.swift`; tests in `HookScriptTests`, `AgentHookLayoutTests`,
  `AgentSessionLogParserTests`, `RegressionGuardTests`, `ClaudeReconcilerTests`.
- Docs: `docs/AGENT-HOOKS.md` (new), REGRESSIONS entries 2 and 12 addenda, `docs/CLOUD-SESSIONS.md`, beta 2 notes.
- The installer's version migration reinstalls the Claude hook on upgrade. No new setting, no new permission.
