## MODIFIED Requirements

### Requirement: The update feed
Installed apps SHALL read the Sparkle feed named by `SUFeedURL` in `Kannu/Info.plist`. From PR #3 on, that is this
repository's appcast: `raw.githubusercontent.com/YANC-Kannu/kannu-macos/main/Updates/appcast.xml`. A final release
SHALL commit the new appcast to this repository's `main`.

#### Scenario: Checking for updates on 2.0
- **WHEN** a 2.0 install checks for updates
- **THEN** it reads `YANC-Kannu/kannu-macos`'s appcast

## ADDED Requirements

### Requirement: 2.0 version numbering
2.0 SHALL be `MARKETING_VERSION` 2.0.0. Its build numbers SHALL be set so that Sparkle moves 1.3.4 users (build 8)
and every beta tester forward to 2.0.0:
- each 2.0 beta's `CURRENT_PROJECT_VERSION` above 11, the last 1.4.0 beta's, and rising with each beta;
- 2.0.0's above every 2.0 beta's.

#### Scenario: Two betas, then the release
- **WHEN** 2.0.0-beta.1 ships as build 12 and beta.2 as build 13
- **THEN** 2.0.0 ships as build 14 or higher

### Requirement: Beta first, then final
2.0 SHALL ship in three steps:
1. `v2.0.0-beta.1`, a notarized GitHub pre-release that Sparkle never offers;
2. a fix window, with more betas if needed;
3. `v2.0.0`, which updates the appcast.

Each tag SHALL be pushed only on David's yes in the current chat turn.

#### Scenario: The beta tag
- **WHEN** `v2.0.0-beta.1` is pushed
- **THEN** a notarized pre-release appears on GitHub, and neither appcast changes

### Requirement: A one-time feed bridge for 1.x installs
Copies installed before PR #3 read `libinmv/kannu`'s appcast. So 2.0.0 final's appcast entry SHALL also be added to
`libinmv/kannu`'s `Updates/appcast.xml`, once. Betas SHALL NOT be added to either feed. Releases after 2.0.0 SHALL NOT
need the bridge, because 2.0.0 itself reads this repository's feed.

#### Scenario: A 1.3.4 user after 2.0.0 ships
- **WHEN** a 1.3.4 install checks for updates after 2.0.0 is released
- **THEN** `libinmv/kannu`'s appcast lists 2.0.0, and Sparkle offers it

#### Scenario: A 2.0.0 user at the next release
- **WHEN** a 2.0.0 install checks for updates after 2.0.1 is released
- **THEN** it finds 2.0.1 in this repository's appcast, with no bridge
