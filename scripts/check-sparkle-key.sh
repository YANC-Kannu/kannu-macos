#!/usr/bin/env bash
set -euo pipefail

# Proves that the Sparkle signing key in SPARKLE_EDDSA_PRIVATE_KEY pairs with the public key the app
# ships with (SUPublicEDKey in Info.plist), before anything is built. It signs a small probe file
# the way a release is signed, then checks that signature against the app's own public key. Asking
# sign_update to check its own signature would prove nothing: it would hold the key against itself.
#
# The release workflow only ever saw that the secret was not empty. A key that does not pair would
# first show on a final release, as every installed Kannu refusing the update.

if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 <sparkle-bin-dir> [path-to-Info.plist]" >&2
  exit 1
fi

SPARKLE_BIN_DIR="$1"
INFO_PLIST="${2:-Kannu/Info.plist}"

if [[ -z "${SPARKLE_EDDSA_PRIVATE_KEY:-}" ]]; then
  echo "Required environment variable SPARKLE_EDDSA_PRIVATE_KEY is not set." >&2
  exit 1
fi
if [[ ! -x "$SPARKLE_BIN_DIR/sign_update" ]]; then
  echo "Sparkle's sign_update was not found in $SPARKLE_BIN_DIR." >&2
  exit 1
fi

PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST" 2>/dev/null || true)"
if [[ -z "$PUBLIC_KEY" ]]; then
  echo "::error::$INFO_PLIST has no SUPublicEDKey, so no install could verify an update."
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
printf 'Kannu Sparkle key probe\n' > "$WORK_DIR/probe"

echo "Checking the Sparkle signing key..."
# The key reaches sign_update on standard input: never on a command line, never in a file. What
# sign_update says when it fails is not printed, in case it quotes what it was given.
if ! SIGNATURE="$(printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" | "$SPARKLE_BIN_DIR/sign_update" --ed-key-file - -p "$WORK_DIR/probe" 2>/dev/null)"; then
  echo "::error::Sparkle's sign_update could not sign with the SPARKLE_EDDSA_PRIVATE_KEY secret. It must hold the private key exactly as Sparkle's generate_keys exports it."
  exit 1
fi

cat > "$WORK_DIR/verify.swift" <<'SWIFT'
import CryptoKit
import Foundation

// Exit 0: the signature is valid for the public key. 1: it is not. 2: an input could not be read.
let arguments = CommandLine.arguments
guard arguments.count == 4,
      let publicKey = Data(base64Encoded: arguments[1]),
      let signature = Data(base64Encoded: arguments[2].trimmingCharacters(in: .whitespacesAndNewlines)),
      let data = FileManager.default.contents(atPath: arguments[3]),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
    exit(2)
}
exit(key.isValidSignature(signature, for: data) ? 0 : 1)
SWIFT

set +e
xcrun swift "$WORK_DIR/verify.swift" "$PUBLIC_KEY" "$SIGNATURE" "$WORK_DIR/probe"
status=$?
set -e

case "$status" in
  0)
    echo "The Sparkle signing key pairs with SUPublicEDKey in $INFO_PLIST."
    ;;
  1)
    echo "::error::The SPARKLE_EDDSA_PRIVATE_KEY secret does not pair with SUPublicEDKey in $INFO_PLIST. Every installed Kannu would refuse an update signed with it. Set the secret to the private key that belongs to that public key, then re-run this job."
    exit 1
    ;;
  *)
    echo "::error::The Sparkle key check could not run: SUPublicEDKey in $INFO_PLIST or the signature could not be read (exit $status)."
    exit 1
    ;;
esac
