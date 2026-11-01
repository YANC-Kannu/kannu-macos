#!/usr/bin/env bash
# Fails when a path holds a Git LFS pointer instead of the file the pointer stands for.
#
# xcodebuild copies a pointer into the app as readily as the real file, and nothing complains until
# someone looks at an empty icon: every Kannu release through 1.4.0-beta.3 shipped 131-byte pointers
# for the Bluetooth HUD clips. create-dmg.sh runs this, so a DMG cannot be made from such a bundle.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <path>" >&2
  exit 2
fi

# grep exits 0 on a match, 1 on none and 2 on an error. Only "none" passes, so a path that cannot be
# read is not reported as clean. -I skips binaries, and a real movie is one.
status=0
pointers="$(grep -rlI '^version https://git-lfs.github.com/spec/v1$' "$1")" || status=$?

case "$status" in
  1)
    exit 0
    ;;
  0)
    echo "Git LFS pointers found where real files belong:" >&2
    echo "$pointers" >&2
    echo "Anything the app bundles must be an ordinary git blob. See \"Known traps\" in AGENTS.md." >&2
    exit 1
    ;;
  *)
    echo "Could not scan $1 for Git LFS pointers." >&2
    exit 2
    ;;
esac
