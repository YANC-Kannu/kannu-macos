# Connecting ADR to Kannu

Kannu can show security findings from [ADR](https://github.com/uber/ADR) — Uber's open-source
Agentic Detection and Response toolkit (Apache-2.0). ADR is a **separate install** that you own;
Kannu connects to it. Kannu never installs ADR, never edits your MCP configurations, and never
sends a finding anywhere unless you turn on push notifications.

## 1. Install ADR Discovery (once)

Discovery inventories the AI tools on this Mac and raises findings such as an MCP server that
resolves an unpinned package at launch, or one reached over plain HTTP. It needs Python 3.11 or
newer; `uv` brings its own interpreter, so nothing else is required.

```bash
uv tool install "adr-discovery @ git+https://github.com/uber/ADR@6b33dffecd719708c435f772c9e93f1210944e31#subdirectory=Discovery"
```

pipx works the same way:

```bash
pipx install "git+https://github.com/uber/ADR@6b33dffecd719708c435f772c9e93f1210944e31#subdirectory=Discovery"
```

Both lines pin `main` at `6b33dff` (2026-10-16), the commit this page and Kannu were last checked
against. An unpinned install runs whatever reached `main` last — the same supply-chain shape Kannu
reports when an MCP server does it. The package calls itself 0.2.0 at that commit and before it, so
the version number cannot tell an old install from a new one. To move an existing install to the
pinned commit, run the line above again with `--reinstall` after `uv tool install` (pipx:
`pipx install --force …`).

Then open Kannu → Settings → Agents → **ADR Discovery** and press **Check again**. Kannu looks
in `~/.local/bin`, uv's tool directory, `/opt/homebrew/bin` and `/usr/local/bin`; a different
location can be set in the **ADR tools folder** row (choose the folder that holds `adr-discovery`,
`adr-sensor` or `uv`; leave it empty for the standard places). Avoid a folder inside Documents,
Desktop, Downloads or iCloud Drive: macOS asks for permission every time Kannu looks there.

## 2. Produce a snapshot

Kannu reads the newest `snapshot-*.json` in its snapshot folder (default
`~/.kannu/adr/discovery`, changeable in Settings). Run a scan into it:

```bash
adr-discovery --json --output-dir ~/.kannu/adr/discovery > /dev/null
```

Findings appear in Settings within a second of the file landing. Exit code `2` means the scan
could not read everything (a denied directory, an unavailable probe); Kannu shows that as
*partial coverage* rather than claiming the machine is clean.

To see exactly what Discovery collects before you run it:

```bash
adr-discovery --dry-run --explain
```

It reports paths, metadata and allowlisted config keys — never file contents; environment variable
*names* only; credential-bearing flag values replaced; URLs stripped of user info and query strings;
and no access at all under personal folders such as `~/.ssh`, `Documents`, `Mail` and `Messages`.

## 3. Let Kannu run it (default once connected)

With Discovery connected, Settings → Agents → ADR Discovery → **Let Kannu run scans** makes
Kannu invoke `adr-discovery --json --output-dir <snapshot folder>` itself. Kannu checks once a
minute whether a scan is due, and runs one:

- when Kannu has never run one;
- 24 hours after Kannu's last scan;
- when the MCP servers declared in an AI tool's global settings change — `~/.claude.json`,
  `~/.claude/mcp.json`, Claude Code's managed `/Library/Application Support/ClaudeCode/managed-mcp.json`,
  Claude Desktop's `claude_desktop_config.json`, `~/.cursor/mcp.json`, VS Code's `mcp.json`, Cline's
  `cline_mcp_settings.json` (in VS Code's `globalStorage/saoudrizwan.claude-dev/settings`),
  `~/.codex/config.toml`, `~/.gemini/settings.json`, `~/.qwen/settings.json` and
  `~/.config/opencode/opencode.json` — at most once every five minutes (the server names are
  compared, not the files' dates, so an unrelated rewrite of `~/.claude.json` does not count);
- after a scan that wrote no snapshot (it timed out, failed to start, exited with an error, or
  left an unreadable file): again after 1, 2, 4, 8 and 16 hours, never later than the daily scan.
  While scans keep failing, a settings change waits for that retry too;
- whenever you press **Scan now**.

Settings shows when the next automatic scan is due under "Last run by Kannu". The exact command is
fixed in code and pinned by tests; Kannu never adds flags to it. Turn the toggle off if something
else already schedules Discovery — Kannu then only reads, and labels those snapshots as watched.

## 4. How a high-severity finding gets your attention

- **In the closed notch:** a monochrome shield pill beside the traffic light — never a fourth
  light colour — that stays until you acknowledge the finding (default). Settings offers
  *For 5 seconds, then glyph*, *Glyph only* and *Off*. While a Focus mode is on, only the small
  glyph shows; the pill appears when Focus ends. Clicking the pill opens the panel.
- **In the panel:** the finding is pinned above the primary session with Details, Acknowledge and
  Copy for agent; medium findings appear as a count beside "Recent chats".
- **On your phone:** with mobile notifications on, each new high finding is pushed once
  (priority 5, the same as "needs input"); medium ones only if you enable that.
- **Kannu's own findings:** a session started with permission checks bypassed
  (`claude --dangerously-skip-permissions`, Codex `approval_policy = never`) is reported by Kannu
  from the hook payload — Discovery cannot see process arguments on macOS.
- **Hidden text (Kannu's own, on by default, local):** the hook looks at what agents read and write
  — prompts, tool results, tool input — for characters a person cannot see but a model reads:
  Unicode tag characters ("ASCII smuggling"), bytes hidden in variation selectors, right-to-left
  overrides on a line with no right-to-left letters (Trojan Source), long zero-width runs. No model,
  nothing sent. A sighting is high when it decodes to readable text; the decoded text is only ever
  shown inside Kannu, never pushed and never copied for an agent. "Tell the agent when hidden text
  is found" (off by default) adds one factual sentence to the agent's context — never the hidden
  text.
- **Secrets (Kannu's own, on by default, local):** API keys and private keys in a prompt or in what
  an agent hands a tool (AWS, GitHub, GitLab, Slack, Stripe live, Anthropic, OpenAI, Google, npm,
  Hugging Face, PEM/OpenSSH/PGP private keys). Tool results are never scanned. The hook keeps only
  the kind, the vendor prefix, the length and the first 12 hex digits of the SHA-256 — never the
  key. High when the agent used a key in a command or any non-file tool; medium for a file edit or
  your own prompt.
- **Sensitive files (Kannu's own, on by default, local):** after a tool ran, the paths it read or
  changed — SSH and GPG keys, cloud and Git credentials, AI tools' sign-in files, password stores,
  the keychain (including `security find-generic-password`), browser profiles, `.env` files, shell
  history — and changes to files that run code on their own (LaunchAgents, `crontab`, Git hooks,
  `authorized_keys`), shell startup files and agent settings (`.claude/settings.json`, `.mcp.json`,
  Codex `config.toml`, Kannu's own `~/.kannu`). Reading a startup file or an agent's settings is
  ordinary and not reported. Paths come from file tools and from parsing shell commands; code that
  opens a file from inside `python -c` is not seen.
- **New MCP servers (Kannu's own, on by default, local):** once a minute Kannu reads the MCP
  servers declared in Claude Code (`~/.claude.json`, user and local scopes, and an administrator's
  `managed-mcp.json`), Claude Desktop, Cursor, VS Code (and Cline in VS Code — not Cline in Cursor
  or another editor), Codex, Gemini CLI, Qwen Code and opencode settings, plus the project files
  (`.mcp.json`, `.cursor/mcp.json`, `.vscode/mcp.json`…) of the folders your sessions run in,
  skipping Desktop, Documents, Downloads and cloud folders so macOS never prompts. The first look
  only learns what is there; a server that appears later is a medium finding ("New MCP server:
  github"), with what it runs (`npx @modelcontextprotocol/server-github`, or a URL cut to its host)
  kept in Kannu. Env values, headers and URL paths are never read into a finding. Kannu-run
  Discovery scans use the same reads: a scan runs when the declared servers change, not whenever a
  settings file is touched.

## 5. Run it on your own schedule (optional)

Kannu does not install launch agents. If you want a daily scan, save this as
`~/Library/LaunchAgents/dev.kannu.adr-discovery.plist` and load it with
`launchctl load ~/Library/LaunchAgents/dev.kannu.adr-discovery.plist`. Adjust the path to
`adr-discovery` (`which adr-discovery`).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>dev.kannu.adr-discovery</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/YOU/.local/bin/adr-discovery</string>
    <string>--json</string>
    <string>--output-dir</string>
    <string>/Users/YOU/.kannu/adr/discovery</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>/dev/null</string>
  <key>StandardErrorPath</key><string>/Users/YOU/.kannu/adr/discovery/launchd.log</string>
</dict>
</plist>
```

Fleet deployments that already run Discovery from their own scheduler only need to point Kannu's
snapshot folder at wherever those snapshots land.

## 6. Tenant policy (optional)

Discovery accepts `--policy policy.json`: a JSON object with up to five arrays — `tenant_domains`,
`approved` and `forbidden` of non-empty strings, `approved_indicators` and `forbidden_indicators` of
indicator objects. Any other key is ignored; a file ADR cannot read fails every scan ("cannot read
policy"), and that includes an indicator with an unknown `kind` or a field its kind does not take.
This is from upstream's source at the pinned commit (`judge/sanction.py`, `judge/findings.py`, and
the Discovery README's "Policy file"):

- **`tenant_domains`** — a server declared with a `url` whose host is not one of these domains, or a
  subdomain of one, raises the *third-party destination* finding (Kannu: "MCP server reaches outside
  your domains"). No wildcards; servers that run as a local command have no destination and are
  never checked.
- **`forbidden`** (ADR *catalog ids* of AI tools: `claude-code`, `cursor`, …) and
  **`forbidden_indicators`** (anything without a catalog id) mark an asset forbidden, and a forbidden
  asset raises a high *forbidden asset* finding (Kannu: "Forbidden by your ADR policy"). Indicators:
  `{"kind": "mcp_endpoint", "url": "https://…"}` — an MCP server declaring that URL (scheme and host
  case, user info, query, fragment and trailing slash ignored, so leave those — and any key in
  them — out of the file; a server whose path carries a key is better named with a `name`
  indicator); `{"kind": "package", "ecosystem": "npm"|"pypi", "name": "…",
  "versions": ["1.2.3"]}` or `"all_versions": true` instead of `versions` — a server launched with
  `npx`, `bunx`, `pnpm dlx`, `uvx` or `pipx` for that package (a launch that pins no version matches
  only `all_versions`); `{"kind": "name", "asset_kind": "mcp_server", "name": "…"}`; `{"kind":
  "skill_sha256", "sha256": "…"}` — a skill's folder hash (schema 1.2 redefined it, so one written
  for 1.1 no longer matches); and `{"kind": "file_sha256", "sha256": "…"}`.
- **`approved`** and **`approved_indicators`** are the opposite and raise no finding; forbidden beats
  approved. Assets a non-empty approved list could have named but does not — catalogued tools for
  `approved`, assets of an indicator's kind for `approved_indicators` — are marked *unsanctioned* in
  the snapshot, which is not a finding either.

A Discovery installed from `main` before 2026-10-12 ignores both indicator lists and never raises
*forbidden asset*.

Point Kannu at the file with Settings → Agent Security → ADR scans → Advanced → **ADR scan policy**;
Kannu passes it to every scan it runs, and never parses it itself. **Copy a prompt that drafts a
policy** on the same row has your agent read your MCP configs, ask which domains are yours, and
write `~/.kannu/adr/policy.json`; it describes the forbidden lists but leaves them out unless you
ask. This is ADR's policy, about the tools and MCP servers on the machine; it cannot name a command.
The policy that can — and that Kannu can enforce — is the *agent policy* in §9.

## 7. ADR Sensor (optional, not used yet)

`adr-sensor` exports normalised session records for Claude Code, Cursor, Codex, Warp, Claude
Desktop, Cline and opencode. **Kannu does not use it**: it reads those sources itself, and no
finding depends on the Sensor. It is listed because a security team may want those sessions in a
SIEM. Settings shows whether it is installed and offers **Copy install command**
(`uv tool install adr-sensor`) — Kannu never installs anything itself.

## 8. Session analysis with ADR Detection (opt-in, off by default)

Detection (`ADR/Detection`) judges a *finished* chat's transcript: a local hidden-Unicode check,
an optional gpt-4o triage pass (OpenAI), then a Claude reasoning agent that runs as an unattended
`claude -p` session on your Mac with three local MCP context servers. It is Uber's research tool
(Apache-2.0, "not for production"); Kannu only runs it when you ask, and never ships it.

Setup, all yours:

```bash
git clone https://github.com/uber/ADR && cd ADR && git checkout 6b33dffecd719708c435f772c9e93f1210944e31 && cd Detection && uv sync   # Python 3.10–3.12
npm install -g @anthropic-ai/claude-code && claude auth login           # if not already
```

The checkout is pinned to the same commit as Discovery. A checkout older than 2026-09-22 cannot read
Claude Code 2.1's JSON output (upstream fix `1c8ecd6`), so every analysis would fail; Settings says
so on the **Detection checkout** row and gives the update line — in the `Detection` folder,
`git fetch && git checkout 6b33dffecd719708c435f772c9e93f1210944e31 && uv sync`.

Then Settings → Agents → Session analysis → **Analyze chats with ADR Detection** (a consent
alert names what leaves the Mac), choose the `Detection` folder, and optionally store keys:
an OpenAI key if you turn **Triage with OpenAI first** on (off = Claude only), an Anthropic API
key if you would rather spend API credits than your subscription's 5-hour/weekly quota.
Model names, the three context servers, the reasoning timeout, the message cap (newest N
messages) and the transcript budget are all editable. Long tool results are trimmed keeping
head **and** tail — an injected payload hides at the end of fetched content at least as often
as at the start — and past the budget the oldest tool results are stubbed. Only tool results are
stubbed: user and assistant text never is, so a prose-heavy chat can still overrun the budget.

Run one: right-click a finished Claude Code chat in the notch → **Analyze with ADR Detection…**.
By default a confirmation names the transcript and the providers every time. The verdict shows
under the chat ("ADR: clean · 0.08" or "ADR: malicious · 0.91"); a malicious verdict becomes a
finding — high when confidence ≥ 0.8, medium otherwise — and rides the same shield/pill/card/push
path as every other finding. ADR's verdict names no tactic at the pinned commit (the only tactic it
records is what triage suspected beforehand), so the finding is titled "Malicious activity in this
chat" and the explanation says what happened. Reports are kept under `~/.kannu/adr/detection/`
(reveal from the chat's menu or Settings).

What leaves the Mac, exactly: the chosen transcript text, to Anthropic (your login or your key)
and, only with triage on, to OpenAI. Nothing else, nothing automatic, nothing without your click.
The adapter Kannu runs is its own GPL script (`scripts/adr-analyze-session.py`, written to
`~/.kannu/adr/detection/` at run time); it imports ADR from your checkout and copies nothing. Its
environment is a whitelist, with `.env` loading switched off (`PYTHON_DOTENV_DISABLED`): upstream
imports a detector that would otherwise load the first `.env` found in or above the checkout
into the run.

What stays on the Mac but outside `~/.kannu`: upstream writes its own working files **inside the
checkout**, in `Detection/ads_reasoning_workspace/` — a `.mcp.json` for its context servers and, in
`debug_logs*/`, `conversation_claude_output.json` (the Claude run's raw output, its explanation and
the triage reasoning; when the hidden-Unicode check fires, the decoded hidden text too) or, when
triage clears the chat, `conversation_triage_only.json`. Every run overwrites the same names. The
Claude CLI also keeps the reasoning session, prompt included, under `~/.claude/projects/` like any
other session; upstream reads it back to count context-server calls. Delete either when you no
longer need it.

## 9. Agent policy (opt-in; blocking on Claude Code, Cursor and Antigravity)

A JSON file you write, `~/.kannu/agent-policy.json`, naming commands and tools an agent may not use:

```json
{
  "version": 1,
  "block": [
    { "command": "ssh",     "reason": "Servers are off limits to agents on this Mac." },
    { "command": "scp" },
    { "command": "rm -rf /" },
    { "tool": "WebFetch",   "reason": "No web fetches from agents in this repo." }
  ]
}
```

- A `command` rule matches a shell command whose first word — after `sudo`, `env`, `nohup` and
  the like, and reduced to its basename, so `/usr/bin/ssh` is `ssh` — is that word, in any segment
  joined by `;`, `&&`, `||` or `|`, and inside a `sh -c "…"` string. A multi-word rule matches a
  segment that starts with those words. `sshd` and `sshpass` do not match `ssh`; `echo ssh` does
  not either. There is no regex: a pattern from a file is a denial-of-service risk in a hook that
  must answer in milliseconds.
- A `tool` rule matches a tool by its exact name, on every agent.
- `reason` is optional and is what the agent is told.
- Caps: 64 KB, 200 rules, 200 characters per string. Anything else — missing, not JSON, over a cap,
  `version` not 1, a rule with neither key — means **no policy**; the hook never fails closed on
  its own configuration, and Settings → Agents → **Agent policy** says why.

Kannu writes this file in two places, both at your click and both only after checking the bytes
with the same rules as above, so neither can replace a working policy with a bad one. **Import…**
copies a JSON file you chose, byte for byte. **Edit rules** is an editor on the Policy rules row: a
row per rule, no JSON; Save writes the rules and keeps any other keys the file already had, and if
the file changed on disk while the editor was open it asks before replacing it. A file Kannu cannot
read is never opened in the editor (Open in Editor hands it to your own editor instead).
**Copy a prompt that drafts a policy** puts a prompt on the clipboard for your own agent — the
format, the rules above, and "ask me which commands and tools" — the same way Copy install command
and Copy for agent work. Both sit on the **Get a policy** row, next to the status of the file.

Every match is recorded as a finding (`policy_command` / `policy_tool`) with the rule, the tool,
and whether the call was refused or ran. **Block matching tool calls** (off by default) is what
turns a report into a refusal: on Claude Code (`PreToolUse`, through `permissionDecision: deny`,
whose reason reaches the model and the transcript), on Cursor (`beforeShellExecution`,
`beforeMCPExecution`, `preToolUse`, through `permission: deny`) and on Antigravity (`PreToolUse`,
through `decision: deny` with a `reason`), the hook refuses the call and tells
the agent `Kannu policy: "ssh" is blocked on this Mac by the user's agent policy. <reason> Ask the
user before trying another way.` A refused call is a medium finding — the policy working; a call
that ran is high. Antigravity's deny (hook v46) follows antigravity.google/docs/hooks and has not
been tested on a real install; the Settings row says so. Codex, VS Code, Gemini CLI, Qwen Code,
Copilot CLI and opencode get the finding only: their hook contracts either have no verified deny or
no pre-tool event at all, and Kannu does not guess at a host's protocol.

Real enforcement for an agent Kannu cannot refuse lives in that agent's own permission system —
for Claude Code, `"permissions": {"deny": ["Bash(ssh *)"]}` in `settings.json`, which Kannu neither
reads nor writes.

## What Kannu does with findings

- Lists them in Settings → Agents → Security findings, highest severity first. Each row is
  compact — title, severity and a two-line summary — with its actions on the bottom row: **Details**
  on the left, and on the right a "…" menu, **Acknowledge** and **Copy for agent**. Details opens
  the evidence and, in plain words, what the finding means and what to do, as one block of text
  that can be selected and copied in one drag. The "…" menu holds Snooze 24h, **Reveal File in
  Finder** (the file the finding is about: the sensitive file itself, the settings file a server was
  added to, ADR's report or the path Discovery names), **Reveal Project Folder** (for findings about
  a chat), **Open Chat** (only where the chat already is — its Claude Desktop chat, terminal tab,
  tmux pane or running app; never a resume, never a cold launch) and **Copy Details**.
  Acknowledgements are per finding: if a finding disappears and later returns with different
  evidence, it is shown again.
- **Copy Details** copies the finding for a person: title, severity, source, the evidence and the
  two plain-language paragraphs — with the same care as Copy for agent (no chat name, no decoded
  hidden text, no session id; untrusted text flattened to one line).
- **Copy for agent** puts a plain-text request on the clipboard, ready to paste into Claude Code,
  Codex or any agent: what the finding means, what to do, and the details, marked as data rather
  than instructions. It never includes a key, the decoded hidden text, a chat name or a session
  id, and text that came from files or tools is flattened to one line with invisible characters
  removed. Nothing is sent until you paste it.
- Never changes the traffic light. Green, yellow and red keep meaning working, needs input, and
  finished; a security finding is shown with a shield instead.
- Never terminates a process, edits a configuration file, or installs software. It refuses a tool
  call only under your own agent policy (§9), only with blocking switched on, and only on a host
  whose hook can say no.

## Licence

ADR is licensed under the Apache License 2.0 and is not distributed with Kannu. Kannu (GPL-3.0-or-later)
runs the separately installed programs and reads the files they write; no ADR code is included in
Kannu. "ADR" and "Uber" are their owners' marks; Kannu references them only to identify the tool.
