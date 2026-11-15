# Kannu Release Guide

Ship Kannu via **automated CI** (recommended) or **manual Xcode** export.

## Automated CI release (recommended)

Triggered only by pushing a `v*` tag. The workflow archives with Developer ID, notarizes the DMG, Sparkle-signs the appcast, publishes to GitHub Releases, and commits [`Updates/appcast.xml`](../Updates/appcast.xml).

### One-time: GitHub secrets

Add at **Settings → Secrets and variables → Actions** on `YANC-Kannu/kannu-macos`:

| Secret | Description |
|--------|-------------|
| `APPLE_CERTIFICATE` | Base64-encoded **Developer ID Application** `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the `.p12` export |
| `KEYCHAIN_PASSWORD` | Random string for the CI keychain (`openssl rand -base64 32`) |
| `APPLE_TEAM_ID` | 10-character team ID (Release: `S2WWHQQH2V`) |
| `APPLE_ID` | Apple ID email for notarization |
| `APPLE_NOTARIZATION_PASSWORD` | App-specific password from [appleid.apple.com](https://appleid.apple.com) |
| `SPARKLE_EDDSA_PRIVATE_KEY` | Ed25519 private seed matching `SUPublicEDKey` in `Kannu/Info.plist` |

Example (run locally after exporting your `.p12`):

```bash
gh secret set APPLE_CERTIFICATE --repo YANC-Kannu/kannu-macos < <(base64 -i ~/path/to/cert.p12)
gh secret set APPLE_CERTIFICATE_PASSWORD --repo YANC-Kannu/kannu-macos
gh secret set KEYCHAIN_PASSWORD --repo YANC-Kannu/kannu-macos
gh secret set APPLE_TEAM_ID --repo YANC-Kannu/kannu-macos --body "S2WWHQQH2V"
gh secret set APPLE_ID --repo YANC-Kannu/kannu-macos
gh secret set APPLE_NOTARIZATION_PASSWORD --repo YANC-Kannu/kannu-macos
gh secret set SPARKLE_EDDSA_PRIVATE_KEY --repo YANC-Kannu/kannu-macos < ~/path/to/eddsa_private.key
```

### Release day

1. Bump **Version** and **Build** in Xcode or `Kannu.xcodeproj/project.pbxproj`
2. Commit and push to `main`
3. Tag and push:

```bash
git tag v1.0.0
git push origin v1.0.0
```

4. Watch **Actions → Release**
5. Verify the GitHub Release contains `Kannu.<version>.dmg` and `Updates/appcast.xml` updated on `main`

### Beta (pre-release) tags

A tag with a hyphen — `v1.4.0-beta.1` — runs the same build, signing and notarization as a release,
publishes the DMG as a GitHub **pre-release** (never marked Latest), and skips the Sparkle export and
the appcast commit to `main`. Sparkle never offers it: only testers who download it from the Releases
page run it. The release notes come from `docs/release-notes/<version>.md` for the tag's version
(`1.4.0-beta.1.md`), or GitHub's generated list.

```bash
git tag v1.4.0-beta.1
git push origin v1.4.0-beta.1
```

Number the beta's build above the feed's newest and below the release's: with 1.3.4 at build 8,
the 1.4.0 beta is build 9 and 1.4.0 itself build 10, so Sparkle moves every beta tester to the
release when it ships. `ReleaseWorkflowRulesTests` pins the pre-release rules.

---

## Manual GitHub release (fallback)

Build and ship from Xcode when CI is unavailable.

### Quick start

1. **Bump version** in Xcode (target Kannu → General): increase **Version** and **Build**.
2. **Archive**: Product → Archive (Release scheme) → Distribute App → **Developer ID** → export `Kannu.app`.
3. **Run the release script** from repo root:

```bash
chmod +x scripts/manual-release.sh

./scripts/manual-release.sh \
  --app ~/Desktop/KannuRelease/Kannu.app \
  --version 1.0.0 \
  --tag v1.0.0 \
  --sparkle-key ~/path/to/eddsa_private.key \
  --publish \
  --push-appcast
```

Without `--publish` / `--push-appcast`, the script only builds `build/Kannu.<version>.dmg` and updates `Updates/appcast.xml`, then prints the commands to run manually.

### What the manual script does

1. Verifies the exported app is code-signed
2. Creates `build/Kannu.<version>.dmg` via [`create-dmg.sh`](create-dmg.sh), with a temporary `dmgbuild` venv (needs Python 3.10+)
3. Sparkle-signs the DMG and merges [`Updates/appcast.xml`](../Updates/appcast.xml) via [`export-sparkle-update.sh`](export-sparkle-update.sh)
4. Optionally runs `gh release create` and pushes the appcast to `main`

Manual releases do **not** notarize automatically; use CI for notarized builds.

---

## Codenames

Each feature release carries a watcher's name — Kannu watches your agents — shown in Settings › About
and in the GitHub release title (`Kannu 1.3.0 — Heimdall`). The list, in order:

| Version | Codename |
|---|---|
| 1.2.0 | Argus |
| 1.3.0 | Heimdall |
| 2.0.0 | Horus |
| next | Vigil |
| then | Sentinel |

Pick the next name for what the release actually does, not just for its turn in the list — the list
is the shortlist, not a queue. Argus, all eyes, suited a release that only watched; Heimdall, who
keeps watch at Bifröst and refuses passage, suited the one that added the agent policy; Horus, one
eye, suited 2.0's one-eye logo and a notch that closes like an eye. If a release does not fit the
next name on the list, take one further down or add a watcher to it.

The name lives in one place: `ReleaseInfo.codename` in `Kannu/models/Constants.swift`. Both release
paths grep that line for the title, so bump it there and nowhere else. 1.0.0 shipped as "Fiji", the
last of the island names inherited from Atoll (Maldives → Bora Bora → Seychelles → Fiji); that chain
is not continued.

## The install window

Opening the DMG shows a paper-coloured window with the app icon, an arrow and the Applications folder.
[`create-dmg.sh`](create-dmg.sh) builds it with [`dmgbuild`](https://dmgbuild.readthedocs.io), using the
layout in [`dmg-settings.py`](dmg-settings.py). `dmgbuild` writes that layout straight into the volume's
`.DS_Store`, so there is no Finder scripting, no window on the build machine and no Automation prompt,
which is what lets it run the same on CI.

`dmgbuild` is a build-time tool and nothing of it ships in the app. [`dmg-requirements.txt`](dmg-requirements.txt)
pins it and its two dependencies by hash, and [`install-dmgbuild.sh`](install-dmgbuild.sh) installs those
wheels into a temporary venv. It needs Python 3.10 or newer, which `/usr/bin/python3` is not: the release
workflow sets up its own, and a local build needs one on `PATH` (`brew install python`).
`build-dmg.sh`, `manual-release.sh` and the release workflow all set up the venv themselves; calling
`create-dmg.sh` directly needs `dmgbuild` on `PATH` first, and says how if it is not.

The app icon, the `logo2` image, `.github/assets/kannu-logo.png`, the volume icon and the window's
background are all drawn by one script, and the outputs are committed:

```bash
swift scripts/brand/generate-brand-assets.swift
```

If you move the icons, change `InstallWindow` in that script and `icon_locations` and `window_rect` in
`dmg-settings.py` together: the script draws the heading and arrow around those positions. Instrument
Serif is under the SIL Open Font License ([`brand/OFL.txt`](brand/OFL.txt)), and only the generator reads it.

To read a built DMG's layout without opening a window, attach it with `hdiutil attach -nobrowse` and read
the volume's `.DS_Store` with the `ds_store` package from that venv.

## Verify signing

```bash
codesign -dv --verbose=4 /path/to/Kannu.app
spctl -a -vv /path/to/Kannu.app
```

## Verify auto-update

1. Install an older build to `/Applications`
2. Launch Kannu → **Check for Updates…**
3. Optional logs: `/usr/bin/log stream --predicate 'process CONTAINS "Kannu" OR subsystem CONTAINS "sparkle"' --level debug` — spell out the path. `log` is a zsh builtin and a builtin always wins over `PATH`, so bare `log stream …` never reaches Apple's tool; it answers `zsh:log:1: too many arguments`, which reads like a mistake in your predicate rather than the wrong program.

## Workflow reference

CI pipeline: [`.github/workflows/release.yml`](../.github/workflows/release.yml)

Scripts:

- [`create-dmg.sh`](create-dmg.sh) — styled DMG via `dmgbuild` and [`dmg-settings.py`](dmg-settings.py), then signs it
- [`install-dmgbuild.sh`](install-dmgbuild.sh) — pinned `dmgbuild` into a temporary venv
- [`notarize-dmg.sh`](notarize-dmg.sh) — `notarytool submit` + staple
- [`export-sparkle-update.sh`](export-sparkle-update.sh) — Sparkle-sign DMG + appcast
- [`manual-release.sh`](manual-release.sh) — local release helper
