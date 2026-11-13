# clipboard Specification

## Purpose
Kannu keeps a clipboard history and pinned items. They show in the notch, in a floating panel and in Brain › Clipboard.
This spec covers what is captured, what Brain's page leads with, live data, pinned images and the panel. The behaviour
is as built on `super/brain-6-around`; the image cleanup is already in `development` (#46).

## Requirements

### Requirement: Capture skips secrets
The history SHALL skip:
- copies marked concealed (`org.nspasteboard.ConcealedType`), Kannu's own included;
- copies marked transient (`org.nspasteboard.TransientType`);
- text that holds a token-shaped secret, found the way the agent hook finds one in a prompt.

`Kannu/managers/ClipboardCapturePolicy.swift:25-39` holds these rules.

#### Scenario: Copying an access token
- **WHEN** the user copies a fresh access token from GitLab's token page
- **THEN** it is not added to the history

### Requirement: Brain › Clipboard leads with pinned items
Brain › Clipboard (`Kannu/components/Settings/ClipboardOverview.swift`) SHALL show the pinned items and their count
first. History SHALL start folded (`:36-39`), because a copy can be anything. Rows SHALL offer Copy, Pin (or Unpin)
and Delete. The header SHALL offer Clear history, and Open history panel as the page's one primary verb
(`:150-161`). The page SHALL keep the live-data contract through `ClipboardPageData`
(`ClipboardPageLiveDataRulesTests`).

#### Scenario: Opening Clipboard
- **WHEN** the user opens Brain › Clipboard with pinned items and a long history
- **THEN** the pinned items show, and History stays folded until the user opens it

### Requirement: Pinned images keep their files
The launch cleanup SHALL keep the files of pinned images as well as History's (`ClipboardDataCleanup`). A Debug build
SHALL keep its images in a folder of its own, so it never deletes the installed app's images
(`ClipboardDataCleanupTests`).

#### Scenario: Relaunch with a pinned image
- **WHEN** Kannu relaunches with an image pinned
- **THEN** the pinned image still opens

### Requirement: The floating panel wears Brain's theme
The clipboard's floating panel (`Kannu/components/Clipboard/ClipboardPanel.swift`) SHALL draw in Geist and Brain's
tokens. History and Favorites SHALL be a segmented choice with counts. The panel's placement, focus, dismissal and
capture policy SHALL be unchanged. Its snapshot boards SHALL draw fixtures, never the Mac's own clipboard.

#### Scenario: Board rendering
- **WHEN** the snapshot run renders the panel's boards
- **THEN** they show fixture items, and `ClipboardManager` is never built
