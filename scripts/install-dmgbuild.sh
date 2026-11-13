#!/usr/bin/env bash
set -euo pipefail

# Installs the pinned dmgbuild into a virtual environment for create-dmg.sh to find on PATH. Build-time
# only: every caller points this at a temporary directory, and nothing from it ships in the app.

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <venv-directory>" >&2
  exit 1
fi

VENV_DIR="$1"
REQUIREMENTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dmg-requirements.txt"

# dmgbuild needs Python 3.10 or newer, and the python3 Apple ships in /usr/bin is 3.9.
PYTHON=""
for candidate in python3 python3.14 python3.13 python3.12 python3.11 python3.10; do
  if command -v "$candidate" >/dev/null 2>&1 \
    && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
    PYTHON="$candidate"
    break
  fi
done

if [ -z "$PYTHON" ]; then
  echo "Python 3.10 or newer is required to build the DMG (dmgbuild). Try: brew install python" >&2
  exit 1
fi

"$PYTHON" -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install \
  --quiet \
  --disable-pip-version-check \
  --require-hashes \
  --only-binary :all: \
  -r "$REQUIREMENTS"
