#!/usr/bin/env bash
set -euo pipefail

# Asks Apple's notary service for the team's submission history before anything is built. It
# uploads nothing and answers in seconds, with the same credentials `notarize-dmg.sh` submits
# with. Both 2.0 betas built and signed for half an hour and were then refused at Notarize DMG:
# "HTTP status code: 403. A required agreement is missing or has expired." Apple had revised its
# Developer Program License Agreement, and only the team's Account Holder can accept it.

for var in APPLE_ID APPLE_NOTARIZATION_PASSWORD APPLE_TEAM_ID; do
  if [ -z "${!var:-}" ]; then
    echo "Required environment variable $var is not set." >&2
    exit 1
  fi
done

echo "Checking Apple notary access..."
if output="$(xcrun notarytool history \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_NOTARIZATION_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" 2>&1)"; then
  # The history itself is not printed: it lists earlier submissions and nobody needs it here.
  echo "Apple's notary service accepted the request."
  exit 0
fi

echo "$output" >&2
if grep -qi "agreement" <<<"$output"; then
  echo "::error::Apple refused the notary request: a required agreement is missing or has expired. The team's Account Holder must accept the updated agreement at developer.apple.com/account, then this job can be re-run."
else
  echo "::error::Apple's notary service refused the request or could not be reached. Check the APPLE_ID, APPLE_NOTARIZATION_PASSWORD and APPLE_TEAM_ID secrets, then re-run this job."
fi
exit 1
