## ADDED Requirements

### Requirement: A Claude Desktop turn that ends on a question is yellow
The hook SHALL mark a Claude Code turn `question_open`, without changing its state, when the turn asks its user a
question through Claude Desktop's next-step tool (`mcp__ccd_turn__wrap_up` with a non-empty `ask`), and the turn's
`Stop`, or a `StopFailure` that is not a rate limit, SHALL then write `awaiting_input` instead of `stopped`. The next prompt SHALL
clear the mark. The tool's name SHALL be one documented constant on each side; when it no longer matches, the light
SHALL fall back to red, as before.

#### Scenario: A turn ends on a question
- **WHEN** a Code-tab turn calls the question tool with an `ask` and then stops
- **THEN** the chat's light is yellow within a second

#### Scenario: The user answers
- **WHEN** the user sends the next prompt in that chat
- **THEN** the question mark is cleared, and the next turn ends red unless it asks again

#### Scenario: A recap with no question
- **WHEN** the question tool is called with an empty `ask`
- **THEN** the turn's `Stop` is red, as before

### Requirement: An unanswered question outlives its process for up to 12 hours
A question yellow SHALL stay yellow while the chat's transcript shows the question newer than the newest real user
prompt, whether or not the Claude process is still alive, for at most 12 hours from the `Stop` that wrote it. `SessionEnd`
SHALL keep such a status file, marked `process_ended`. Past 12 hours, or once the transcript shows an answer, the card
SHALL fall back to the usual ladder and its file to the usual stale cap.

#### Scenario: The desktop ends the CLI
- **WHEN** the desktop app ends the CLI process of a chat whose question is unanswered
- **THEN** the card stays yellow

#### Scenario: Twelve hours pass
- **WHEN** a question has been unanswered for more than 12 hours
- **THEN** the card is no longer yellow and its status file is deleted

### Requirement: Claude's own record is evidence, never the origin of yellow
While a Claude process is alive, Kannu SHALL keep an `executing` or `thinking` hook session green past the 360 s hook
window when the process's session record says `busy`. A record that says `waiting` SHALL hold a yellow the hooks wrote,
and SHALL NOT make any chat yellow on its own. `idle`, `shell` and `waiting` SHALL NOT hold green.

#### Scenario: A long single tool
- **WHEN** a Claude tool or thinking stretch runs for 30 minutes with no hook event and the record says `busy`
- **THEN** the chat stays green

#### Scenario: Waiting without a hook yellow
- **WHEN** the record says `waiting` and no hook wrote `awaiting_input`
- **THEN** the chat is not yellow

### Requirement: Every colour change is logged with its evidence
Kannu SHALL log one line per real colour change of a card (green, yellow, red, dim, hidden) to subsystem
`com.kannu.app`, category `AgentState`, naming the provider, a short session id, both colours, the raw state, the hook
event, the transcript tail verdict, Claude's record status and whether a question hold applied. It SHALL NOT log a
switch between two greens, a scan with no change, or any chat name, path or prompt text.

#### Scenario: A chat turns yellow
- **WHEN** a Claude chat's card turns from green to yellow
- **THEN** one `AgentState` line records the change with the hook event `Stop` and the tail verdict
