## ADDED Requirements

### Requirement: A chat's project is named after its folder
Kannu SHALL name a chat's project after the last component of the folder the chat runs in, from whichever source
supplies that folder: the hook file's workdir (the first workspace root, else `cwd`), Claude's session record, or the
transcript. Every source SHALL use the one rule, `ProjectNameRules.projectName(forWorkingDirectory:)`. A trailing slash
or a `file://` prefix SHALL NOT change the name, and the root folder SHALL have none.

#### Scenario: A chat in a repository
- **WHEN** a chat runs in `/Users/alice/code/acme-api`
- **THEN** its card's project is `acme-api`

#### Scenario: The root folder
- **WHEN** a chat's folder is `/`
- **THEN** that source gives no project name

### Requirement: A Claude Desktop worktree is named after its repository
A chat whose folder is `<repo>/.claude/worktrees/<name>`, or any folder below it, SHALL be named `<repo>`. Every other
`.claude` folder, `.claude/worktrees` itself included, SHALL be named like any other folder.

#### Scenario: A Desktop worktree chat
- **WHEN** a chat runs in `/Users/alice/code/acme-api/.claude/worktrees/brave-otter-7f3a`
- **THEN** its card's project is `acme-api`

#### Scenario: A folder under `.claude` that is not a worktree
- **WHEN** a chat runs in `/Users/alice/code/acme-api/.claude/skills/review`
- **THEN** its card's project is `review`

### Requirement: A Cursor project slug decodes to the real folder
When a Cursor chat is named from its `~/.cursor/projects/<slug>` folder, Kannu SHALL decode the slug against the
folders that exist, so that a project whose name holds a `-`, `.` or `_` keeps its whole name. Decoding SHALL list at
most 48 folders and SHALL never list a home folder whose first read raises a macOS privacy prompt, or anything under
`/Volumes`. Decoding SHALL match only real folders: never a file, and never a symbolic link, whose target a path check
cannot see. When decoding fails, Kannu SHALL fall back to the slug's last word after the home folder, encoding the home
folder the way Cursor does.

#### Scenario: A hyphenated project
- **WHEN** a Cursor chat's slug is `Users-alice-code-acme-api` and `/Users/alice/code/acme-api` exists
- **THEN** its card's project is `acme-api`, not `api`

#### Scenario: A home folder with a dot
- **WHEN** the home folder is `/Users/alice.smith`, the slug is `Users-alice-smith-acme`, and decoding fails
- **THEN** its card's project is `acme`, not the whole slug

#### Scenario: A file that shares the project's slug
- **WHEN** a Cursor chat's slug is `Users-alice-code-acme-api`, `/Users/alice/code/acme-api` is a file and
  `/Users/alice/code/acme/api` is a folder
- **THEN** its card's project is `api`

### Requirement: Project naming is observable
Kannu SHALL log each project-name resolution to subsystem `com.kannu.app`, category `ProjectName`, once each time a
session's chosen name or its inputs change. Each line SHALL carry the agent, the source, the session id, the chosen
name and the rule that chose it as public fields, and the working directory and workspace roots as private fields. A
name that is a whole undecoded Cursor slug (`rule=cursor-slug-unresolved`) spells out a folder path, so it SHALL be
private too.

#### Scenario: Watching a worktree chat get its name
- **WHEN** a user runs `/usr/bin/log stream --predicate 'subsystem == "com.kannu.app" AND category == "ProjectName"'`
  and starts a Claude Desktop chat in a worktree
- **THEN** a line shows that chat's session id with `rule=claude-desktop-worktree` and the repository's name
