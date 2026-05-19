#!/usr/bin/env bash
#
# One-command release helper for Rihla.
#
#   ./tool/release.sh patch      # 1.2.0+11 -> 1.2.1+12
#   ./tool/release.sh minor      # 1.2.0+11 -> 1.3.0+12
#   ./tool/release.sh major      # 1.2.0+11 -> 2.0.0+12
#   ./tool/release.sh 1.4.2      # explicit semver, build auto-bumps
#
# What it does:
#   1. Verifies clean working tree on main, in sync with origin
#   2. Bumps version in pubspec.yaml (semver + build number)
#   3. Opens $EDITOR on a CHANGELOG stub for the new version
#   4. Commits as "chore(release): vX.Y.Z"
#   5. Runs the consolidated release-readiness audit on that exact commit
#   6. Tags as "vX.Y.Z" and pushes both branch and tag
#   7. Reports the GitHub Actions run URL — CI takes over and uploads
#      to the Play Store "first" closed-testing track
#
# Override the editor with EDITOR env var. Skip the changelog prompt
# with SKIP_CHANGELOG=1 (CI-friendly). Skip the post-commit approval prompt
# with SKIP_RELEASE_APPROVAL_PROMPT=1 only if RIHLA_RELEASE_APPROVED_SHA is
# already set to the release commit SHA.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PUBSPEC="pubspec.yaml"
CHANGELOG="CHANGELOG.md"
MAIN_BRANCH="main"
EDITOR_CMD="${EDITOR:-${VISUAL:-vi}}"

die() { echo "error: $*" >&2; exit 1; }

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

[ $# -eq 1 ] || usage
BUMP_ARG="$1"

# --- Preflight ----------------------------------------------------------------

command -v gh >/dev/null 2>&1 || die "gh CLI not installed"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$CURRENT_BRANCH" = "$MAIN_BRANCH" ] || \
  die "must be on $MAIN_BRANCH (currently on $CURRENT_BRANCH)"

if ! git diff --quiet || ! git diff --cached --quiet; then
  die "working tree is dirty — commit or stash first"
fi

git fetch origin "$MAIN_BRANCH" --quiet
LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git rev-parse "origin/$MAIN_BRANCH")"
[ "$LOCAL_SHA" = "$REMOTE_SHA" ] || \
  die "local $MAIN_BRANCH is out of sync with origin/$MAIN_BRANCH (pull or push first)"

# --- Parse current version ----------------------------------------------------

CURRENT_LINE="$(grep '^version:' "$PUBSPEC")"
CURRENT_VERSION="$(echo "$CURRENT_LINE" | sed -E 's/^version: *([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\1/')"
CURRENT_BUILD="$(echo "$CURRENT_LINE" | sed -E 's/^version: *([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\2/')"

[ -n "$CURRENT_VERSION" ] && [ -n "$CURRENT_BUILD" ] || \
  die "could not parse version from $PUBSPEC: $CURRENT_LINE"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

case "$BUMP_ARG" in
  major) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
  minor) NEW_VERSION="$MAJOR.$((MINOR + 1)).0" ;;
  patch) NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  [0-9]*.[0-9]*.[0-9]*) NEW_VERSION="$BUMP_ARG" ;;
  *) die "bump must be patch|minor|major or explicit X.Y.Z (got: $BUMP_ARG)" ;;
esac

NEW_BUILD="$((CURRENT_BUILD + 1))"
NEW_TAG="v$NEW_VERSION"

# --- Tag uniqueness check -----------------------------------------------------

if git rev-parse "$NEW_TAG" >/dev/null 2>&1; then
  die "tag $NEW_TAG already exists locally"
fi
if git ls-remote --tags origin "$NEW_TAG" | grep -q "$NEW_TAG"; then
  die "tag $NEW_TAG already exists on origin"
fi

echo "Releasing $CURRENT_VERSION+$CURRENT_BUILD -> $NEW_VERSION+$NEW_BUILD"

# --- Bump pubspec -------------------------------------------------------------

# macOS sed needs '' after -i; Linux GNU sed doesn't. Use a portable temp-file approach.
TMP="$(mktemp)"
awk -v new="version: $NEW_VERSION+$NEW_BUILD" \
  '/^version:/ { print new; next } { print }' "$PUBSPEC" > "$TMP"
mv "$TMP" "$PUBSPEC"

# --- Stub CHANGELOG entry -----------------------------------------------------

TODAY="$(date +%Y-%m-%d)"
STUB_HEADER="## [$NEW_VERSION] — $TODAY"

if grep -q "^## \[$NEW_VERSION\]" "$CHANGELOG"; then
  echo "CHANGELOG already has a $NEW_VERSION entry — skipping stub insert"
else
  STUB_FILE="$(mktemp)"
  cat <<STUB > "$STUB_FILE"
$STUB_HEADER

### Added
-

### Changed
-

### Fixed
-

STUB

  # Insert stub after the header block (line 6) and before the previous version.
  TMP="$(mktemp)"
  awk -v stub_file="$STUB_FILE" '
    BEGIN {
      while ((getline line < stub_file) > 0) stub = stub line "\n"
      close(stub_file)
      inserted = 0
    }
    /^## \[/ && !inserted {
      printf "%s", stub
      inserted = 1
    }
    { print }
  ' "$CHANGELOG" > "$TMP"
  mv "$TMP" "$CHANGELOG"
  rm -f "$STUB_FILE"

  if [ "${SKIP_CHANGELOG:-0}" = "0" ]; then
    echo "Opening $EDITOR_CMD on $CHANGELOG — fill in the bullets, save, quit."
    "$EDITOR_CMD" "$CHANGELOG"
  fi
fi

# --- Commit, tag, push --------------------------------------------------------

git add "$PUBSPEC" "$CHANGELOG"
git commit -m "chore(release): $NEW_TAG"
RELEASE_SHA="$(git rev-parse HEAD)"

echo
echo "Release commit created: $RELEASE_SHA"
echo "Before tagging, set GitHub repository variable RIHLA_RELEASE_APPROVED_SHA to this exact SHA after all release gates are approved:"
echo
echo "  gh variable set RIHLA_RELEASE_APPROVED_SHA --body \"$RELEASE_SHA\""
echo
echo "The release-readiness audit runs next and must pass before tag/push."
if [ "${SKIP_RELEASE_APPROVAL_PROMPT:-0}" = "0" ]; then
  printf "Press Enter after the release approval variable is set, or Ctrl+C to stop before tagging. "
  read -r _
fi

RIHLA_RELEASE_TARGET_SHA="$RELEASE_SHA" bash tool/check_release_readiness.sh

git tag -a "$NEW_TAG" -m "Release $NEW_TAG"

echo "Pushing $MAIN_BRANCH and $NEW_TAG to origin..."
git push origin "$MAIN_BRANCH"
git push origin "$NEW_TAG"

echo
echo "Release pushed. CI will build and upload to Play Store 'first' track."
REPO_SLUG="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
echo "  Workflow runs:  https://github.com/$REPO_SLUG/actions/workflows/release_android.yml"
echo "  Tag:            https://github.com/$REPO_SLUG/releases/tag/$NEW_TAG"
