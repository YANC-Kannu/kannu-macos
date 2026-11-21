#!/usr/bin/env bash
set -euo pipefail

# Publishes a final release's appcast: commits the signed Updates/appcast.xml that the release
# workflow attached to the GitHub release onto the feed branch, which every installed Kannu reads.
#
# An admin runs this by hand, once per final release. The workflow cannot do it: the ruleset on
# `main` lets only an admin update that branch, and no bot is given that right. It works in a fresh
# clone in a scratch folder, so no checkout or worktree of yours changes branch.
#
#   ./scripts/publish-appcast.sh v2.0.0 --dry-run    # check everything, show the change, push nothing
#   ./scripts/publish-appcast.sh v2.0.0
#
# To rehearse it without touching GitHub, give it both an appcast file and a repository to push to
# (a local bare one). The file is never taken without the repository, so a local file can never
# reach the real feed:
#
#   KANNU_APPCAST_FILE=/path/to/appcast.xml KANNU_FEED_REMOTE=/path/to/scratch.git \
#     ./scripts/publish-appcast.sh v2.0.0

usage() {
  echo "Usage: $0 <tag> [--dry-run]" >&2
  exit 1
}

TAG=""
DRY_RUN=false
for argument in "$@"; do
  case "$argument" in
    --dry-run) DRY_RUN=true ;;
    -*) usage ;;
    *)
      if [ -n "$TAG" ]; then usage; fi
      TAG="$argument"
      ;;
  esac
done
if [ -z "$TAG" ]; then usage; fi

REPO="YANC-Kannu/kannu-macos"
BRANCH="main"
FEED_PATH="Updates/appcast.xml"
VERSION="${TAG#v}"

# A tag with a hyphen is a pre-release. Sparkle never offers one: only testers who download it run it.
if [[ "$VERSION" == *-* ]]; then
  echo "$TAG is a pre-release, and a pre-release never reaches the feed." >&2
  exit 1
fi

REHEARSAL=false
if [ -n "${KANNU_APPCAST_FILE:-}" ] || [ -n "${KANNU_FEED_REMOTE:-}" ]; then
  if [ -z "${KANNU_APPCAST_FILE:-}" ] || [ -z "${KANNU_FEED_REMOTE:-}" ]; then
    echo "A rehearsal needs both KANNU_APPCAST_FILE and KANNU_FEED_REMOTE." >&2
    exit 1
  fi
  REHEARSAL=true
fi
REMOTE_URL="${KANNU_FEED_REMOTE:-https://github.com/${REPO}.git}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
NEW_APPCAST="$WORK_DIR/appcast.xml"

if [ "$REHEARSAL" = true ]; then
  echo "Rehearsal: taking the appcast from a file, and pushing to $REMOTE_URL."
  cp "$KANNU_APPCAST_FILE" "$NEW_APPCAST"
else
  echo "Downloading appcast.xml from the $TAG release..."
  if ! gh release download "$TAG" --repo "$REPO" --pattern appcast.xml --dir "$WORK_DIR"; then
    echo "The $TAG release has no appcast.xml. The release workflow attaches it once a final release is notarized." >&2
    exit 1
  fi
fi

# Nothing is pushed until the appcast has passed every check below.
if ! xmllint --noout "$NEW_APPCAST" 2>/dev/null; then
  echo "The appcast is not well-formed XML." >&2
  exit 1
fi

# The <item> for this version, from its opening tag to its closing one.
ITEM="$(awk -v marker="<sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>" '
  /<item>/ { item = ""; inside = 1 }
  inside { item = item $0 "\n" }
  /<\/item>/ { if (inside && index(item, marker)) { printf "%s", item; exit } inside = 0 }
' "$NEW_APPCAST")"
if [ -z "$ITEM" ]; then
  echo "The appcast lists no item for ${VERSION}." >&2
  exit 1
fi
if ! grep -q 'sparkle:edSignature=' <<<"$ITEM"; then
  echo "The appcast's item for ${VERSION} carries no EdDSA signature, so every install would refuse it." >&2
  exit 1
fi

ENCLOSURE_URL="$(sed -n 's/.*<enclosure[^>]* url="\([^"]*\)".*/\1/p' <<<"$ITEM" | head -1)"
if [ "$REHEARSAL" != true ]; then
  DOWNLOAD_PREFIX="https://github.com/${REPO}/releases/download/${TAG}/"
  if [[ "$ENCLOSURE_URL" != "$DOWNLOAD_PREFIX"* ]]; then
    echo "The item's download is not on the $TAG release: ${ENCLOSURE_URL:-none}" >&2
    exit 1
  fi
  if ! curl -sfIL -o /dev/null "$ENCLOSURE_URL"; then
    echo "The item's download does not answer: $ENCLOSURE_URL" >&2
    exit 1
  fi
fi

echo "Cloning $BRANCH into a scratch folder..."
git clone --quiet --depth 1 --branch "$BRANCH" "$REMOTE_URL" "$WORK_DIR/feed"

# Every build the feed already lists must still be listed: the new file replaces the old one whole.
if [ -f "$WORK_DIR/feed/$FEED_PATH" ]; then
  LOST="$(comm -23 \
    <(grep -o '<sparkle:version>[^<]*</sparkle:version>' "$WORK_DIR/feed/$FEED_PATH" | sort -u) \
    <(grep -o '<sparkle:version>[^<]*</sparkle:version>' "$NEW_APPCAST" | sort -u))"
  if [ -n "$LOST" ]; then
    echo "The new appcast drops builds the feed lists today:" >&2
    echo "$LOST" >&2
    exit 1
  fi
fi

mkdir -p "$(dirname "$WORK_DIR/feed/$FEED_PATH")"
cp "$NEW_APPCAST" "$WORK_DIR/feed/$FEED_PATH"
git -C "$WORK_DIR/feed" add "$FEED_PATH"
if git -C "$WORK_DIR/feed" diff --staged --quiet; then
  echo "$FEED_PATH on $BRANCH already lists ${VERSION}: nothing to publish."
  exit 0
fi
git -C "$WORK_DIR/feed" --no-pager diff --staged --stat

if [ "$DRY_RUN" = true ]; then
  echo "Dry run: every check passed, and nothing was pushed."
  exit 0
fi

# The commit is public, so it carries a GitHub no-reply address, never whatever this Mac's git is set to.
if [ "$REHEARSAL" = true ]; then
  AUTHOR_NAME="Dana Example"
  AUTHOR_EMAIL="dana@example.com"
else
  AUTHOR_NAME="$(gh api user --jq .login)"
  AUTHOR_EMAIL="$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"
fi
git -C "$WORK_DIR/feed" -c user.name="$AUTHOR_NAME" -c user.email="$AUTHOR_EMAIL" \
  commit --quiet -m "Update appcast for ${TAG}"
git -C "$WORK_DIR/feed" push origin "HEAD:${BRANCH}"
echo "Published: $FEED_PATH on $BRANCH now lists ${VERSION}."

if [ "$REHEARSAL" != true ]; then
  # Read through the API, which is not cached. The raw URL installs read can lag by a few minutes.
  if gh api "repos/${REPO}/contents/${FEED_PATH}?ref=${BRANCH}" -H "Accept: application/vnd.github.raw" \
    | grep -q "<sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>"; then
    echo "Read back from GitHub: the feed lists ${VERSION}."
  else
    echo "The push went through, but the feed read back from GitHub does not list ${VERSION}." >&2
    exit 1
  fi
fi

echo
echo "For installs that still read the old repository's feed, add this item to its ${FEED_PATH}:"
echo
printf '%s' "$ITEM"
