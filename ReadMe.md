# കണ്ണ് (Kannu)

**The notch is the front door. Brain is the room behind it.**

Kannu is a free, open-source macOS app that lives in the MacBook notch. It began as a traffic light
for your AI coding agents. 2.0 makes it the home of your working day: your agents, tasks, timer,
notes, clipboard, usage and security live in **Brain**, a window that can fill the screen, and the
notch shows them at a glance. *Kannu* (കണ്ണ്) means eye in Malayalam.

This project is licensed under GPL v3. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for upstream
attribution.

Kannu is a fork of [Atoll](https://github.com/Ebullioscopic/Atoll), which itself builds on the
broader macOS notch lineage including [Boring.Notch](https://github.com/TheBoredTeam/boring.notch).

## What's inside

### Brain

- **Seven product pages:** Agents, Security, Usage, Tasks, Timer, Notes and Clipboard. Each opens
  on its live state, with its settings below, and every other setting sits behind one Settings row.
  Search finds any setting from any page.
- **Made to stay open.** Paper in light and ink in dark, set in Geist, with an appearance of its
  own. It goes full screen (⌃⌘F), has a menu bar of its own (Go ⌘1–⌘7, View, File › New Task ⌘N),
  and badges only what needs you: an agent waiting, high-severity findings, usage near a limit, a
  running timer.
- **Free when out of sight.** Closed, minimised, covered or in another Space, Brain stops every live
  view.

### Agents

- **Agent status traffic light:** green while an agent thinks or works, yellow while it waits for
  you (an approval card, say), red when it stops. Editor hooks and transcript polling feed one light
  in the notch, across every session, for Claude Code, Cursor, Codex, VS Code, Antigravity and more.
- **Make the light yours:** Classic (all three lights, the inactive ones dimmed) or Minimal (only the
  lit one), with a colour for each state from a curated palette. Two states can never share a
  colour, so the lights stay readable with red-green colour blindness.
- **Usage and quota:** Claude's rate limits in the notch, grouped as Session and Weekly with a
  per-model window, one reset countdown per group, and bar colour driven by the severity the server
  itself reports. Codex, Cursor and Antigravity have their own cards.
- **Security:** Kannu's own checks run inside the agent hook, on this Mac, with no model and no
  network: secrets in prompts and tool calls, sensitive files, hidden text, new MCP servers, and
  sessions with permission checks off. An agent policy can block matching tool calls in Claude Code
  and Cursor. Kannu reports what it finds and never remediates behind your back.
- **Jump to the session:** click a chat to bring up the app that owns it (terminal, IDE, or a
  resumable Claude session). Rows that cannot be located offer no affordance rather than a dead
  click.
- **Keep the Mac awake:** smart caffeinate holds sleep off while an agent runs and releases it when
  the agent stops, or you drive it by hand. One native power assertion, no `caffeinate` subprocess.
  Only system sleep is prevented: the display may still sleep, and closing the lid always sleeps
  the Mac.
- **Mobile notifications (optional):** push agent state changes to iPhone, Apple Watch or Android
  through ntfy, Pushover or a webhook of your own.

### Tasks and tags

- **Tasks from everywhere:** your own tasks beside the ones assigned to you in Jira Cloud, GitLab,
  GitHub (including GitHub Enterprise Server), Linear, Todoist and Apple Reminders, with estimates,
  tags, reminders and an archive. Sources are read, never changed, and their tokens stay in your
  Keychain.
- **Time it in the notch:** the timer times a task, and the time it records can go back to Jira or
  GitLab, only when you say so.
- **Tags you type:** `#launch` in a task's name becomes a tag and `@3pm` a reminder. Tags show as
  chips in their colours, `#tag` search finds the whole tag, and one Tag filter works in Brain and
  in the notch.

### The notch

- **Custom notch skins:** upload a background image clipped to the notch shape, with an optional
  dark scrim for readability, or pick the built-in Horns skin. **Copy AI prompt** gives ChatGPT or
  another image AI a prompt that asks what you want, then designs a skin sized for the notch
  ([docs/NOTCH-SKINS.md](docs/NOTCH-SKINS.md)).
- **Out of the way when you want:** hide the notch like closing an eye, and bring it back from the
  eye in the menu bar. It stays put when you switch Spaces.
- Media controls, live activities, lock screen widgets, stats, timers, notes, clipboard and shelf.
- **Keyboard shortcuts are off by default:** turn them on in **Brain › Settings › Shortcuts** when
  you want hotkeys.

Calendar, terminal and color picker features from the Atoll/Boring.Notch lineage are removed in
this fork.

## Requirements

- macOS 14.6 or later (optimised for macOS 15+).
- A MacBook with a notch, or a Mac without one, using the floating Dynamic Island pill mode.
- Apple silicon or Intel: the app builds universal.
- Xcode 16+ to build from source (the source needs Swift 6.1).
- Permissions as needed: Accessibility, Screen Recording, Music, Reminders, Notifications.

## Runtime permissions, by feature

The app is not sandboxed, so these are standard macOS privacy prompts (TCC). Kannu never raises one
on its own at launch: on a fresh install, onboarding's **Permissions** step lists only what your
choices use, says why, and asks for each one when you press **Allow**, one dialog at a time. The
welcome music plays after you finish. Press **Not now** and that feature stays off until you allow
it in **Brain › Settings › General › Permissions**; nothing asks for it later by surprise.

Asked on the Permissions step (when the feature is on):

- **Accessibility:** media keys and the volume and brightness HUD.
- **Bluetooth:** headphones and their battery when they connect.
- **Files & Folders (Downloads):** download progress in the notch.
- **Location (When In Use):** lock screen weather.
- **Automation (Apple Events)** and **Music (MusicKit):** playback controls, and Apple Music's
  animated artwork, when Spotify or Apple Music is your music source.
- **Automation (Apple Events) for Notes:** when you choose to sync notes with Apple Notes on the
  Notes step.
- **Data from other apps:** following agents running in Warp, when Warp is installed.
- **Login item:** "Open Kannu at login", a switch on the same step.

Asked only when you use the feature:

- **Screen Recording:** Screen Assistant screenshot capture. Screen-recording detection is separate
  and does not need it.
- **Microphone:** Screen Assistant's Record button, asked the first time you press it.
- **Local Network:** sending files from the Shelf to nearby devices with LocalSend.
- **Automation (Apple Events):** Apple Notes sync when you turn it on later in Brain › Notes, and
  opening an agent's terminal tab or a browser tab.
- **Full Disk Access:** custom Focus metadata and optional global Shelf behavior.
- **Files & Folders (Documents/Downloads):** Shelf, when Full Disk Access is not granted. Clipboard
  history keeps its files in Application Support, which needs no permission.
- **Audio Capture:** real-time waveform and audio-activity features.
- **Developer Tools:** optional, for the advanced Focus detection mode.
- **Reminders:** when you connect Apple Reminders as a task source (Brain › Tasks › Add a source).
- **Notifications:** the first time you schedule a task reminder.

For detailed prompts and one-click setup actions, open **Brain** in Kannu. Contributor docs are in
[CONTRIBUTING.md](CONTRIBUTING.md).

## Install (pre-built DMG)

1. Download the latest `Kannu.<version>.dmg` (for example `Kannu.2.0.0.dmg`) from the [Releases page](https://github.com/YANC-Kannu/kannu-macos/releases).
2. Open the DMG and drag **Kannu** into the **Applications** folder.
3. Launch Kannu from Applications.

Kannu updates itself through Sparkle. A beta, tagged like `v2.0.0-beta.1`, is a pre-release on the
same page: Kannu's updates never offer it, so you get one only by downloading it.

### "Kannu can't be opened" (Gatekeeper)

Releases on the Releases page are signed with a Developer ID and notarized by Apple. The first time
you open one, macOS asks you to confirm an app downloaded from the internet: click **Open**. That is
the ordinary prompt for any download, not a block, and nothing else is needed.

A real Gatekeeper block ("Apple could not verify Kannu is free of malware") only appears for a
build that did not come from the Releases page: a DMG made by `scripts/create-dmg.sh` without a
Developer ID identity, or one somebody passed you directly. If you trust where it came from:

- **Right-click (or Control-click)** `Kannu.app` **in Applications and choose "Open"**, then click
  **Open** in the dialog. On macOS 15 (Sequoia) and later, the option may only appear the *second*
  time you right-click › Open.
- If there is no Open button: go to **System Settings › Privacy & Security**, scroll down to the
  message about Kannu being blocked, and click **Open Anyway**.

An app you build and run from Xcode on your own Mac is never quarantined, so Gatekeeper does not
stop it.

## Build from source

1. Open `Kannu.xcodeproj` in Xcode.
2. Select the **Kannu** scheme and your Mac as the run destination.
3. Build and run (⌘R).

## Release manually (Xcode signing)

To ship a signed DMG and update Sparkle auto-update from your Mac, see
[scripts/RELEASE.md](scripts/RELEASE.md). After archiving in Xcode, run `scripts/manual-release.sh`
with your exported `Kannu.app` and Sparkle private key.

Application support data is stored under `~/Library/Application Support/Kannu/`. Agent status hooks
write to `~/.kannu/agent-status/`.

## Quick start

1. Launch Kannu, accept the Terms of Use, and finish onboarding.
2. Open **Brain** from the brain icon in the notch, or with ⌘,. On **Agents**, install the hook for
   the editors you use.
3. Run an AI agent: the closed notch shows its traffic light, and Brain › Agents shows the chat.
4. Optionally, turn on **Enable tasks** in **Brain › Tasks** and **Add a source**.
5. Optionally, pick or upload a notch skin under **Brain › Settings › Appearance › Notch skin** (see
   [docs/NOTCH-SKINS.md](docs/NOTCH-SKINS.md)).

## Mobile notifications setup

1. Open **Brain › Agents** and find **Mobile notifications** among its settings.
2. Turn on **Enable mobile notifications** and choose a provider:
   - **ntfy:** create a topic at [ntfy.sh](https://ntfy.sh) or self-host. Install the ntfy app on
     iPhone or Android and subscribe to your topic.
   - **Pushover:** use your user key and app token from [pushover.net](https://pushover.net).
   - **Webhook:** POST JSON `{ "state": "thinking", "title": "...", "body": "...", "timestamp": "..." }`
     to your URL.
3. Press **Send test notification** to check delivery.

Notifications are debounced (~2 seconds) and skip the inactive state unless you opt in. Apple Watch
mirrors iPhone alerts when mirroring is enabled in Watch settings.

**Privacy:** agent status stays on your Mac unless you enable outbound notifications. Public ntfy
topics can be read by anyone unless you self-host with authentication.

## Phase 2: Windows and Linux

See [docs/PHASE2.md](docs/PHASE2.md) for the planned shared `kannu-core` watcher and Tauri-based
shells for Windows 11 and Linux.

## License

GPL v3: see [LICENSE](LICENSE).

## Acknowledgments

Kannu is a fork of [Atoll](https://github.com/Ebullioscopic/Atoll) and inherits its architecture,
notch interaction patterns, and many features from that project. Atoll and Kannu both trace back to
[Boring.Notch](https://github.com/TheBoredTeam/boring.notch) and other open-source macOS notch
projects listed in upstream documentation.
