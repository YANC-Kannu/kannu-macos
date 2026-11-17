# Agent hooks: Claude Code

How Kannu's hook tells the notch what a Claude Code chat is doing, and how to check it on a Mac. The
script itself is the authority: `AgentHookInstaller.swift` embeds it, `scripts/kannu-agent-status.sh`
mirrors it (REGRESSIONS entry 1), and `AgentHookLayout.claudeHookEntries` is the table of groups it
installs into `~/.claude/settings.json`. Read `docs/REGRESSIONS.md` entries 1, 2, 7, 12 and 15 before
changing any of it.

## The groups

One Kannu group per row of `claudeHookEntries`. Most run async (hook v49); a group blocks only where
Kannu may have to answer, or where its write must land before the next event
(`AgentHookLayout.claudeHookIsAsync`):

- **Always blocking:** `Stop`, `StopFailure`, `SubagentStop`, `SessionEnd`; every group that turns
  the light yellow (`PermissionRequest`, the gated `PreToolUse`, `Notification/needs_input`); and the
  question group (v50, below).
- **Blocking on a setting:** `PreToolUse` while "Block matching tool calls" is on, and the note events
  while "Tell the agent when hidden text is found" is on.

Each group writes `~/.kannu/agent-status/claude-<session id>.json`. The colour comes from its `state`:

| `state` | Light | Written by |
|---|---|---|
| `thinking`, `executing` | green | prompts, tool calls, tool results |
| `awaiting_input` | yellow | `PermissionRequest`, AskUserQuestion and ExitPlanMode, `Notification` prompts, a Stop on a question turn (v50) |
| `stopped`, `quota_exceeded` | red | `Stop`, `StopFailure` |
| `idle` | dim | `SessionStart` |

## Claude Desktop's Code tab (hook v50)

A Code-tab chat runs the same CLI, but it asks its end-of-turn question through the desktop's own
next-step tool, `mcp__ccd_turn__wrap_up` (`AgentHookLayout.claudeQuestionTool`; the script's
`QUESTION_TOOL`). `Notification` and `PermissionRequest` never fire there, and the desktop app ends
the CLI process minutes after the turn. So:

1. **The question group** (`PreToolUse`, matcher `mcp__ccd_turn__wrap_up`, key `question`, blocking).
   A non-empty `tool_input.ask` sets `question_open` (and `question_ms`) on the file. State, clock and
   event order are unchanged; the generic `PreToolUse` group does the rest.
2. **The turn's Stop** (or a `StopFailure` other than a rate limit) on a `question_open` turn writes
   `awaiting_input` with `hook_event: "Stop"` instead of `stopped`.
3. **The next prompt** (`UserPromptSubmit`, `UserPromptExpansion`) clears `question_open`.
4. **`SessionEnd`** keeps a question file, marked `process_ended`, instead of deleting it.

In the app, the yellow is held while the transcript still shows the question unanswered (the
`.questionOpen` tail verdict), with or without a live process, for up to 12 hours from the Stop
(`AgentTrafficLightMapper.questionHoldMs`). After that the card dims and the file is deleted. The tool
is internal to the desktop app: if it is renamed, the question group matches nothing and a waiting chat
shows red again, as it did before v50.

Two signals from Claude's own record, `~/.claude/sessions/<pid>.json`, read only while its process is
alive:

- **`busy`** keeps an `executing` or `thinking` file green past the 360 s window
  (`AgentTrafficLightMapper.holdsActiveRun`). `waiting`, `shell` and `idle` do not.
- **`waiting`** holds a yellow the hooks wrote. It never makes a chat yellow on its own.

## Checking it on a Mac

Each real colour change of a card is one log line: subsystem `com.kannu.app`, category `AgentState`.
It names the provider, the first eight characters of the session id, the colours before and after
(green, yellow, red, dim, hidden), and the evidence: the raw state, the hook event behind the file,
the transcript tail verdict, Claude's record status and whether a question hold applied. No chat
names, paths or prompt text.

```bash
/usr/bin/log show --last 1h --predicate 'subsystem == "com.kannu.app" AND category == "AgentState"'
```

Spell out `/usr/bin/log`: in zsh, `log` is a builtin. The status files themselves are in
`~/.kannu/agent-status/`.
