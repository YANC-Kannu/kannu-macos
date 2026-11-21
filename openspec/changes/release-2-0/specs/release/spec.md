## MODIFIED Requirements

### Requirement: The update feed
Installed apps SHALL read the Sparkle feed named by `SUFeedURL` in `Kannu/Info.plist`. From PR #3 on, that is this
repository's appcast: `raw.githubusercontent.com/YANC-Kannu/kannu-macos/main/Updates/appcast.xml`.

A final release's workflow run SHALL attach the signed appcast to the GitHub release, and SHALL NOT push to any
branch: the ruleset on `main` lets only an admin update it. An admin SHALL then commit the appcast to this
repository's `main` with `scripts/publish-appcast.sh`. The script SHALL refuse a pre-release tag, and an appcast that
is malformed, lacks a signed item for the tag's version, or drops a build the feed lists. Its `--dry-run` SHALL push
nothing. Run again after a push whose read-back failed, it SHALL push nothing, and SHALL still read the feed back
and print the item for the old repository's feed.

The new appcast SHALL be built from the feed on `main`, never from the tagged tree's `Updates/appcast.xml`, and
SHALL list every build that feed lists. `scripts/export-sparkle-update.sh` SHALL stop the run, before the release is
published, when the generated appcast drops one. `ReleaseWorkflowRulesTests` pins this.

#### Scenario: Checking for updates on 2.0
- **WHEN** a 2.0 install checks for updates
- **THEN** it reads `YANC-Kannu/kannu-macos`'s appcast

#### Scenario: Publishing a final release's appcast
- **WHEN** `v2.0.0`'s run has finished and an admin runs `./scripts/publish-appcast.sh v2.0.0`
- **THEN** `Updates/appcast.xml` on `main` lists 2.0.0, and the workflow itself pushed nothing

#### Scenario: A feed that already lists three builds
- **WHEN** the feed on `main` lists builds 8, 7 and 6 and `v2.0.0`'s run exports the appcast
- **THEN** the new appcast lists 2.0.0's build and builds 8, 7 and 6

#### Scenario: The release after 2.0.0
- **WHEN** a final tag is cut from a tree whose `Updates/appcast.xml` does not list 2.0.0, and `main`'s does
- **THEN** the new appcast lists that release and 2.0.0

#### Scenario: A read-back that failed
- **WHEN** the script pushed the appcast, its read-back failed, and an admin runs it again
- **THEN** it pushes nothing, reads the feed back, and prints the item for the old repository's feed

### Requirement: A hyphenated tag is a pre-release
A tag whose version has a hyphen (`v1.4.0-beta.1`) SHALL be built, signed and notarized like a release. It SHALL be
published as a GitHub pre-release that is never marked Latest. It SHALL publish no appcast: nothing is written to
`Updates/appcast.xml`, attached to the release or committed, so Sparkle never offers it. `ReleaseWorkflowRulesTests`
pins this.

#### Scenario: A beta tag
- **WHEN** `v1.4.0-beta.1` is pushed
- **THEN** a pre-release appears on GitHub, and `Updates/appcast.xml` is unchanged

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
3. `v2.0.0`, whose appcast an admin then publishes.

Each tag SHALL be pushed only on David's yes in the current chat turn.

#### Scenario: The beta tag
- **WHEN** `v2.0.0-beta.1` is pushed
- **THEN** a notarized pre-release appears on GitHub, and neither appcast changes

### Requirement: Sparkle is proven before the final tag
Every tag's run, a pre-release's too, SHALL check that the `SPARKLE_EDDSA_PRIVATE_KEY` secret pairs with
`SUPublicEDKey` in `Kannu/Info.plist`: it signs a probe file with the secret and verifies the signature against the
app's own public key (`scripts/check-sparkle-key.sh`). The check SHALL run before Apple's notary service is asked and
before anything is built, and SHALL never print the key.

A pre-release's run SHALL also rehearse the appcast export once the pre-release is published. The rehearsal SHALL
write to a scratch folder and upload its result as the `Kannu-sparkle-rehearsal` artifact, and SHALL NOT change
`Updates/appcast.xml` or the release. `ReleaseWorkflowRulesTests` pins this.

#### Scenario: A secret that does not pair with the app's key
- **WHEN** a tag is pushed while the secret holds a key other than the one `SUPublicEDKey` belongs to
- **THEN** the run stops before the build and says that every install would refuse the update

#### Scenario: A beta rehearses the export
- **WHEN** `v2.0.0-beta.3` is pushed and notarized
- **THEN** the pre-release is published, and the run uploads a rehearsed appcast that nothing reads

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
