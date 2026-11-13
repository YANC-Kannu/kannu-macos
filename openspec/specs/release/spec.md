# release Specification

## Purpose
How Kannu is versioned, built, published and offered as an update. `scripts/RELEASE.md` owns the procedure, and this
spec states its rules. The release files are the same on `development` and on the Brain stack.

## Requirements

### Requirement: A tag builds and publishes the release
Pushing a `v*` tag SHALL run `.github/workflows/release.yml`. The workflow archives with Developer ID, builds the DMG,
notarizes it and publishes a GitHub Release with `Kannu.<version>.dmg`. The manual path (`scripts/manual-release.sh`)
SHALL remain a fallback, and it does not notarize. A tag or release SHALL be made only on David's yes.

#### Scenario: A release tag
- **WHEN** `v1.3.4` is pushed
- **THEN** CI publishes a notarized `Kannu.1.3.4.dmg` on GitHub Releases

### Requirement: A hyphenated tag is a pre-release
A tag whose version has a hyphen (`v1.4.0-beta.1`) SHALL be built, signed and notarized like a release. It SHALL be
published as a GitHub pre-release that is never marked Latest. It SHALL skip the Sparkle export and the appcast commit,
so Sparkle never offers it. `ReleaseWorkflowRulesTests` pins this.

#### Scenario: A beta tag
- **WHEN** `v1.4.0-beta.1` is pushed
- **THEN** a pre-release appears on GitHub, and `Updates/appcast.xml` is unchanged

### Requirement: Curated release notes
The release's notes SHALL come from `docs/release-notes/<version>.md` for the tag's version. If that file is missing,
GitHub's generated list SHALL be used.

#### Scenario: Notes file present
- **WHEN** `v1.3.4` is tagged and `docs/release-notes/1.3.4.md` exists
- **THEN** the GitHub Release body is that file

### Requirement: Build numbers only go up
`CURRENT_PROJECT_VERSION` SHALL rise with every build that ships. A beta's build SHALL sit above the feed's newest
build and below its release's build, so Sparkle moves every beta tester to the release (`scripts/RELEASE.md`, "Beta
(pre-release) tags"). Today the project is 1.3.4, build 8. The 1.4.0 betas, which are not in `development`, used builds
9, 10 and 11.

#### Scenario: Numbering a beta
- **WHEN** a beta follows a feed whose newest build is 8
- **THEN** the beta's build is above 8, and the release that follows is above every beta's

### Requirement: The codename lives in one place
The release codename SHALL live only in `ReleaseInfo.codename` (`Kannu/models/Constants.swift`). The GitHub release
title SHALL be "Kannu <version> — <codename>", read from that line. The current codename is "Heimdall".

#### Scenario: Release title
- **WHEN** a release is tagged with codename "Heimdall"
- **THEN** its title reads "Kannu <version> — Heimdall"

### Requirement: The update feed
Installed apps SHALL read the Sparkle feed named by `SUFeedURL` in `Kannu/Info.plist`. Today that is
`libinmv/kannu`'s `main` branch `Updates/appcast.xml`. A final release SHALL commit the new appcast to `main` of the
repository that runs the workflow.

#### Scenario: Checking for updates on 1.3.4
- **WHEN** a 1.3.4 install checks for updates
- **THEN** it reads `libinmv/kannu`'s appcast
