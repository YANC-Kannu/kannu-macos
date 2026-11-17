---
name: OpenSpec: Apply
description: Implement an approved OpenSpec change and keep tasks in sync.
category: OpenSpec
tags: [openspec, apply]
---
<!-- OPENSPEC:START -->
**Guardrails**
- Favor straightforward, minimal implementations first and add complexity only when it is requested or clearly required.
- Keep changes tightly scoped to the requested outcome.
- Refer to `openspec/AGENTS.md` (located inside the `openspec/` directory—run `ls openspec` if you don't see it) if you need additional OpenSpec conventions or clarifications.
- Run the OpenSpec CLI only in the pinned form these steps use (`openspec/project.md`, Tech Stack). Never run `openspec update` or `openspec init`: 0.23.0 writes its block into `CLAUDE.md`; if it happens, restore it with `git checkout -- CLAUDE.md`.

**Steps**
Track these steps as TODOs and complete them one by one.
1. Read `changes/<id>/proposal.md`, `design.md` (if present), and `tasks.md` to confirm scope and acceptance criteria.
2. Work through tasks sequentially, keeping edits minimal and focused on the requested change.
3. Confirm completion before updating statuses—make sure every item in `tasks.md` is finished.
4. Update the checklist after all work is done so each task is marked `- [x]` and reflects reality.
5. Reference `OPENSPEC_TELEMETRY=0 npx -y @fission-ai/openspec@0.23.0 list` or `OPENSPEC_TELEMETRY=0 npx -y @fission-ai/openspec@0.23.0 show <item>` when additional context is required.

**Reference**
- Use `OPENSPEC_TELEMETRY=0 npx -y @fission-ai/openspec@0.23.0 show <id> --json --deltas-only` if you need additional context from the proposal while implementing.
<!-- OPENSPEC:END -->
