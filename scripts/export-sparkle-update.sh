#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <path-to-dmg> <updates-directory> <download-url-prefix> [sparkle-bin-dir]" >&2
  exit 1
fi

DMG_PATH="$1"
UPDATES_DIR="$2"
DOWNLOAD_URL_PREFIX="$3"
SPARKLE_BIN_DIR="${4:-}"

if [ ! -f "$DMG_PATH" ]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 1
fi

mkdir -p "$UPDATES_DIR"

STAGING_DIR="$(mktemp -d)"
KEY_FILE=""
cleanup() {
  rm -rf "$STAGING_DIR"
  if [ -n "$KEY_FILE" ]; then
    rm -f "$KEY_FILE"
  fi
}
trap cleanup EXIT

DMG_NAME="$(basename "$DMG_PATH")"
cp "$DMG_PATH" "$STAGING_DIR/$DMG_NAME"

# Reuse existing feed entries by placing appcast.xml in the archives directory
# (generate_appcast merges into an appcast already present there).
if [ -f "$UPDATES_DIR/appcast.xml" ]; then
  cp "$UPDATES_DIR/appcast.xml" "$STAGING_DIR/appcast.xml"
fi

if [ -n "${SPARKLE_EDDSA_PRIVATE_KEY:-}" ]; then
  if [ -z "$SPARKLE_BIN_DIR" ]; then
    echo "Sparkle bin directory is required when SPARKLE_EDDSA_PRIVATE_KEY is set." >&2
    exit 1
  fi

  KEY_FILE="$(mktemp)"
  # Sparkle keys are typically a single line; avoid adding a trailing newline.
  printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" > "$KEY_FILE"

  "$SPARKLE_BIN_DIR/sign_update" "$STAGING_DIR/$DMG_NAME" --ed-key-file "$KEY_FILE"
fi

if [ -n "$SPARKLE_BIN_DIR" ] && [ -x "$SPARKLE_BIN_DIR/generate_appcast" ]; then
  GENERATE_ARGS=(
    "$SPARKLE_BIN_DIR/generate_appcast"
    --download-url-prefix "$DOWNLOAD_URL_PREFIX"
    --maximum-deltas 0
    # generate_appcast keeps three builds per branch unless told otherwise, and would drop the
    # oldest from a feed that already lists three. 0 keeps every build.
    --maximum-versions 0
  )

  if [ -n "$KEY_FILE" ]; then
    # CI has no Keychain EdDSA account; always pass the key file explicitly.
    GENERATE_ARGS+=(--ed-key-file "$KEY_FILE")
  fi

  GENERATE_ARGS+=("$STAGING_DIR")

  "${GENERATE_ARGS[@]}"

  # Every build the feed started with must still be listed, whatever generate_appcast decided.
  # This runs before the release is published. publish-appcast.sh checks the same against the
  # feed on main, but by then the release is public.
  if [[ -f "$UPDATES_DIR/appcast.xml" ]]; then
    LOST="$(comm -23 \
      <(grep -o '<sparkle:version>[^<]*</sparkle:version>' "$UPDATES_DIR/appcast.xml" | sort -u) \
      <(grep -o '<sparkle:version>[^<]*</sparkle:version>' "$STAGING_DIR/appcast.xml" | sort -u))"
    if [[ -n "$LOST" ]]; then
      echo "::error::The generated appcast drops builds the feed it started from lists:"
      echo "$LOST"
      exit 1
    fi
  fi

  cp "$STAGING_DIR/appcast.xml" "$UPDATES_DIR/appcast.xml"
else
  echo "Skipping appcast generation: Sparkle generate_appcast not available." >&2
fi

echo "Sparkle update assets written to $UPDATES_DIR/appcast.xml"
