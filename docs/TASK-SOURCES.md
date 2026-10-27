# Task sources

Kannu lists tasks from several places: the user's own (Local tasks), Jira Cloud, GitLab, GitHub
(github.com or GitHub Enterprise Server), Linear, Todoist and Apple Reminders. Every source but Local
is read-only: Kannu fetches the user's open items, lists and times them, and never writes back. The
one exception is Time to log, which sends time to Jira and GitLab, and only on the user's click
(`WorklogConsentRulesTests`).

This page is the map for adding a source. Every source follows the same shape, so a new one is a new
case and a few files, not a hunt through the views.

## The pieces

| Piece | Where | What it holds |
|---|---|---|
| `TaskSource` | `managers/Tasks/TaskModels.swift` | The case. Its raw value is stored in `tasks.json` and never changes. |
| Facts | `managers/Tasks/TaskSourceFacts.swift` (logic target) | Name, title, whether its time can be logged, whether it uses a token, how its keys read (`keyStyle`, which also gives its project), what its items are called, its "Open in …" label. |
| Settings | `managers/Tasks/TaskSourceSettings.swift`, keys in `models/Constants.swift` | Sync switch, the display copy of what it is connected to (`scopeKey`), account name, colour, Show in notch. |
| Engine | `managers/Tasks/SourceSync.swift` (logic target) | One source's sync: state, generation, kept refresh, Connect and Disconnect guards. Shared by every source; never copied. |
| Credential | `managers/Tasks/CredentialStore.swift`, `TaskCredentials.swift`, `helpers/SecureSecretsStore.swift` | The token and where it may be sent, one Keychain item per source, read off the main thread. |
| API | `managers/Tasks/<Source>API.swift` (logic target) | The credential type, host rules, request builders, decoding, the mapping to `RemoteIssue`, failure wording, and a `<Source>Reader` with an injected `URLSession`. Foundation only. |
| Client and provider | `managers/Tasks/<Source>Client.swift` (app) | A logging wrapper (counts and outcomes only) and the `TaskSourceProvider`: where a credential may be sent, and one fetch. |
| Manager | `managers/Tasks/TasksManager.swift` | The source's `lazy var` engine, its place in `syncs`, its Connect function, and its `browseURL` case. |
| Brain | `components/Settings/TaskSourcePages.swift`, `TaskConnectSheets.swift`, `TasksSettings.swift`, `SettingsView.swift` | Its status words, its own options, its connect sheet text, its row's deep link and search entry. |

## Adding a source

1. **The case and its facts.** Add the case to `TaskSource`, in the order Brain lists sources, then
   answer each switch in `TaskSourceFacts` and `TaskSourceSettings`. The compiler finds the rest:
   every switch over sources is exhaustive on purpose.
2. **Settings keys.** In `Constants.swift`: `<source>Enabled`, the scope display copy (empty when not
   connected), the account name, `<source>TaskColor`, `tasksPopoverShow<Source>`. Display copies
   only: the token lives in the Keychain with the one site, server or account it may be sent to.
3. **The API file** (add it to the KannuTests target's Sources phase in the project file):
   - A credential struct that never prints its token (`description`, `debugDescription`, `Mirror`),
     with `encoded()`/`decoded(_:)` and `StoredCredential`.
   - Request builders that set the source's own auth header. Only that file may set it
     (`IntegrationSecretRulesTests.authorizationHeaderOwners`).
   - Fetch at most two pages and say when there was more (`RemoteFetch.complete`); never follow a URL
     from an answer — build the next page's request yourself.
   - Map each item to a `RemoteIssue` whose `key` follows the source's `keyStyle`. Keep a web link
     only when it is on the connected site (`webURL`), and check it again before opening it.
   - Map failures to `SourceSyncState` with words the user can act on: a refused token is
     `.authFailed`, a rate limit `.rateLimited(until:)` from the source's own headers.
4. **Client and provider.** Logs carry status codes and counts, never a token, host, user name or
   title (`IntegrationSecretRulesTests` scans the log lines).
5. **Credential store.** A `SecureSecretKey` case and a `TaskCredentials` store.
6. **Manager.** The engine (`connection`, `options`, `forget`), its place in `syncs`, a Connect that
   checks the credential with the source inside `engine.connect { … }` and writes the display copies
   in its commit, and the `browseURL` case.
7. **Brain.** `TaskSourceStatus` (status, detail, pitch), `SourceOptionRows` if it has options, the
   connect sheet's explanation, a `SettingsDeepLink` id in `taskSourceRows` and in
   `TaskSourcesSection.highlighted`, and a search entry. Re-pin `SettingsHighlightInventoryTests`.
8. **Tests.** `<Source>APITests` (requests, decoding, mapping, errors, a two-page run through a stubbed
   `URLProtocol`, redaction). `SourceSyncTests` already covers the engine for every source.

## Rules every source keeps

- **When it syncs:** a page appearing (only a stale source, never with the Keychain dialog, never
  after a refused token), the user's Refresh, an option that changes what is fetched, the source
  saying it changed (Apple Reminders), and right after Connect. No timer, no polling, nothing at
  launch.
- **Where a token goes:** only to the scope saved with it in the Keychain. A display copy that
  disagrees means "reconnect", never a request elsewhere.
- **What a permission costs:** macOS's questions (Keychain, Reminders) come only from a click.
- **Older builds:** a build from before a source existed drops that source's tasks when it reads
  `tasks.json` (`TaskItem.UnknownSource`), keeps every other task, and writes the file without
  them on its next save — their recorded time goes with them; the build that knows the source
  lists them again. Any other fault in the file still moves it aside (kept, not lost). Testers do
  not go back.
