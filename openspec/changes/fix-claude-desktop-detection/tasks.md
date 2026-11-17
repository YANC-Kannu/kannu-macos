# Tasks: fix-claude-desktop-detection

## 1. Implementation
- [x] 1.1 Hook v50: the blocking question group, `question_open`, a yellow `Stop`, cleared by the next prompt, kept by
  `SessionEnd`; the embedded copy regenerated from the mirror. The cloud relay leaves the group out.
- [x] 1.2 The `.questionOpen` tail verdict, widening the read window once to find the question.
- [x] 1.3 The question hold (12 h, live process or not) in `holdsAwaitingInput` and `awaitingInputOutlivesStaleCap`;
  the reconciler keeps a held question; `waiting` corroborates a hook yellow.
- [x] 1.4 `claudeBusy` keeps an aged `executing` or `thinking` hook session green, in the ladder and the reconciler.
- [x] 1.5 The `AgentState` log: one line per real colour change, with the evidence.

## 2. Tests
- [x] 2.1 `HookScriptTests`: a question then `Stop` is yellow and the next prompt clears it; the group changes no state;
  an empty `ask` or another tool is no question; `SessionEnd` keeps a question file; a quota stop stays a quota stop.
- [x] 2.2 `AgentSessionLogParserTests`: the verdict, its answer, a widened window, and the cases that are not a
  question.
- [x] 2.3 `RegressionGuardTests` and `ClaudeReconcilerTests`: held at 1 h with no process, expired at 12 h; `busy`
  green at 30 min and `idle` not; `waiting` never makes a yellow; the log names only real changes.
- [x] 2.4 `AgentHookLayoutTests`: the group's row and blocking, the one tool name in the layout and the script.

## 3. Gates
- [x] 3.1 Full KannuTests and the Debug build. [Mac]
- [x] 3.2 `bash .githooks/pre-commit` with the CHANGELOG entry staged. [Mac]
- [x] 3.3 `openspec validate --all --strict --no-interactive`.
- [ ] 3.4 A maintainer's check on the beta 2 install: a Code-tab chat ending with a question is yellow within a second,
  still yellow after the CLI exits, and cleared by the reply; a long single tool or thinking stretch (over 10 min) stays
  green; AskUserQuestion and ExitPlanMode are yellow as before; `/usr/bin/log show --predicate 'category ==
  "AgentState"'` shows each change with its evidence. [Mac] [Maintainer]
