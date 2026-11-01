#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <path-to-Kannu.app> <output-dmg-path>" >&2
  exit 1
fi

APP_PATH="$1"
DMG_PATH="$2"

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if ! command -v dmgbuild >/dev/null 2>&1; then
  cat >&2 <<EOF
dmgbuild not found on PATH. build-dmg.sh and manual-release.sh set it up themselves; to call this
script directly, install it into a temporary venv first:

  scripts/install-dmgbuild.sh /tmp/kannu-dmgbuild
  PATH="/tmp/kannu-dmgbuild/bin:\$PATH" $0 <path-to-Kannu.app> <output-dmg-path>
EOF
  exit 1
fi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$(dirname "$DMG_PATH")"
rm -f "$DMG_PATH"

# The layout lives in dmg-settings.py. dmgbuild writes it into the volume's .DS_Store and copies the
# app with ditto, which keeps its signature intact; nothing here scripts Finder or opens a window.
dmgbuild \
  -s "$SCRIPTS_DIR/dmg-settings.py" \
  -D app="$APP_PATH" \
  -D brand_dir="$SCRIPTS_DIR/brand" \
  "Kannu" \
  "$DMG_PATH"

# Sign the disk image itself. The app inside is already Developer ID signed and the DMG gets a
# stapled notarization ticket from notarize-dmg.sh, but an unsigned DMG still has nothing for a
# signature check to evaluate: `spctl -a -t open` reports "no usable signature" on a released
# build. Signing must happen here, before notarization — stapling a signed DMG afterwards leaves
# the signature intact.
#
# Optional by design: releases run with a Developer ID cert in the keychain (CI installs one into
# a temporary keychain), while a local `build-dmg.sh` run usually has none. Skip rather than fail
# so an unsigned DMG is still produced for local testing.
SIGN_IDENTITY="${DMG_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Developer ID Application/{print $2; exit}')}"

# An explicit DMG_SIGN_IDENTITY is deliberately NOT filtered. The release workflow never sets it —
# it resolves its own Developer ID identity and calls this script bare — so the override exists for
# local runs, where the documented signing identity is the self-signed "Kannu Dev" cert. Refusing
# anything but Developer ID would break exactly that. Warn instead: only a Developer ID Application
# signature survives notarization, and saying so here beats a rejection from notarytool later.
# Matched against the whole find-identity line, so a certificate hash is accepted as readily as a name.
if [ -n "${DMG_SIGN_IDENTITY:-}" ] \
  && ! security find-identity -v -p codesigning 2>/dev/null \
     | grep 'Developer ID Application' | grep -qF "$DMG_SIGN_IDENTITY"; then
  echo "Warning: DMG_SIGN_IDENTITY does not name a Developer ID Application certificate; this DMG will not pass notarization. Signing anyway." >&2
fi

if [ -n "$SIGN_IDENTITY" ]; then
  echo "Signing $DMG_PATH as $SIGN_IDENTITY"
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
else
  echo "No Developer ID Application identity found; leaving $DMG_PATH unsigned." >&2
fi

echo "Created $DMG_PATH"
