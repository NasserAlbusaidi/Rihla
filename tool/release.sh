#!/usr/bin/env bash
#
# One-command release helper for Rihla.
#
#   ./tool/release.sh patch      # 1.2.0+11 -> 1.2.1+12
#   ./tool/release.sh minor      # 1.2.0+11 -> 1.3.0+12
#   ./tool/release.sh major      # 1.2.0+11 -> 2.0.0+12
#   ./tool/release.sh 1.4.2      # explicit semver, build auto-bumps
#   RIHLA_SKIP_IOS_QA=yes ./tool/release.sh patch
#                                # Android-only release while iOS is deferred
#
# What it does:
#   1. Verifies clean working tree on main, in sync with origin
#   2. Bumps version in pubspec.yaml (semver + build number)
#   3. Opens $EDITOR on a CHANGELOG stub for the new version
#   4. Commits as "chore(release): vX.Y.Z"
#   5. Runs the consolidated release-readiness audit on that exact commit
#   6. Pushes the commit on a release/vX.Y.Z branch and opens a PR with
#      native auto-merge (squash) enabled — main's branch protection requires
#      the "readiness" status check, so a direct push to main is rejected
#      (#985); a PR is the only way for that check to run before merge
#   7. Waits for the PR to merge, tags the resulting SQUASH-MERGE commit as
#      "vX.Y.Z", and pushes only the tag (tag pushes aren't blocked)
#   8. Reports the GitHub Actions run URL — CI takes over and uploads
#      to the Play Store "first" closed-testing track
#
# Override the editor with EDITOR env var. Skip the changelog prompt
# with SKIP_CHANGELOG=1 (CI-friendly). Skip both approval prompts (before the
# readiness audit, and before tagging the merged commit) with
# SKIP_RELEASE_APPROVAL_PROMPT=1 only if RIHLA_RELEASE_APPROVED_SHA is already
# set correctly at each point — the script prints the exact SHA to set before
# each prompt. For the current Android-only launch, run with
# RIHLA_SKIP_IOS_QA=yes so the consolidated audit uses the documented
# Android-only real-device QA gate. Omit it when iOS ships.

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

require_clean_worktree() {
  local untracked_files

  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "working tree is dirty - commit or stash first so the release can be tied to an exact commit"
  fi

  untracked_files="$(git ls-files --others --exclude-standard)"
  if [ -n "$untracked_files" ]; then
    echo "Untracked files:" >&2
    printf '%s\n' "$untracked_files" >&2
    die "remove, commit, or stash untracked files first so the release can be tied to an exact commit"
  fi
}

[ $# -eq 1 ] || usage
BUMP_ARG="$1"

# --- Preflight ----------------------------------------------------------------

command -v gh >/dev/null 2>&1 || die "gh CLI not installed"
command -v jq >/dev/null 2>&1 || die "jq CLI not installed"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$CURRENT_BRANCH" = "$MAIN_BRANCH" ] || \
  die "must be on $MAIN_BRANCH (currently on $CURRENT_BRANCH)"

restore_branch_on_exit() {
  local exit_code=$?
  local now_branch
  now_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -n "$now_branch" ] && [ "$now_branch" != "$CURRENT_BRANCH" ]; then
    echo "Restoring checkout to $CURRENT_BRANCH..." >&2
    git checkout "$CURRENT_BRANCH" >/dev/null 2>&1 || true
  fi
  exit "$exit_code"
}
trap restore_branch_on_exit EXIT

require_clean_worktree

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

# --- Commit ---------------------------------------------------------------

git add "$PUBSPEC" "$CHANGELOG"
git commit -m "chore(release): $NEW_TAG"
require_clean_worktree
RELEASE_SHA="$(git rev-parse HEAD)"

echo
echo "Release commit created: $RELEASE_SHA"
echo "Before the readiness audit, set GitHub repository variable RIHLA_RELEASE_APPROVED_SHA to this exact SHA:"
echo
echo "  gh variable set RIHLA_RELEASE_APPROVED_SHA --body \"$RELEASE_SHA\""
echo
echo "This SHA is superseded once the release PR merges (main's branch protection"
echo "squash-merges it onto a new commit) — you will be asked to re-point the"
echo "variable at the merged SHA before tagging."
echo
echo "The release-readiness audit runs next and must pass before the release PR opens."
if [ "${RIHLA_SKIP_IOS_QA:-}" = "yes" ]; then
  echo "Android-only QA mode is enabled: RIHLA_SKIP_IOS_QA=yes"
else
  echo "Full iOS + Android QA mode is enabled. Set RIHLA_SKIP_IOS_QA=yes only for the Android-only launch."
fi
if [ "${SKIP_RELEASE_APPROVAL_PROMPT:-0}" = "0" ]; then
  printf "Press Enter after the release approval variable is set, or Ctrl+C to stop before the audit. "
  read -r _
fi

RIHLA_RELEASE_TARGET_SHA="$RELEASE_SHA" bash tool/check_release_readiness.sh

# --- Open a release PR (main's branch protection requires the "readiness" ----
# --- status check, so it rejects a direct push — see #985) ------------------

RELEASE_BRANCH="release/$NEW_TAG"

if git show-ref --verify --quiet "refs/heads/$RELEASE_BRANCH"; then
  die "local branch $RELEASE_BRANCH already exists — leftover from a previous release attempt? Delete it (git branch -D $RELEASE_BRANCH) after confirming it isn't an in-flight release, then retry."
fi
if git ls-remote --exit-code --heads origin "$RELEASE_BRANCH" >/dev/null 2>&1; then
  die "origin already has a $RELEASE_BRANCH branch — leftover from a previous release attempt? Delete it (git push origin --delete $RELEASE_BRANCH) after confirming it isn't an in-flight release, then retry."
fi

git branch "$RELEASE_BRANCH" "$RELEASE_SHA"
echo
echo "Pushing $RELEASE_BRANCH to origin..."
if ! git push origin "$RELEASE_BRANCH"; then
  die "failed to push $RELEASE_BRANCH to origin — fix the error above, then retry (the local release commit is still on $RELEASE_BRANCH: $RELEASE_SHA)"
fi

echo "Resetting local $MAIN_BRANCH to origin/$MAIN_BRANCH (the release commit now lives on $RELEASE_BRANCH)..."
git reset --hard "origin/$MAIN_BRANCH"

PR_BODY="Release $NEW_TAG.

Version bump ($PUBSPEC) + CHANGELOG entry only, generated by \`tool/release.sh\`. This is the recurring release ritual — not tied to a feature issue, nothing to link with Closes/Refs.

Auto-merge is enabled — this merges on its own once the required \`readiness\` status check is green. \`tool/release.sh\` is waiting on this PR and will tag the squash-merge commit as $NEW_TAG once it merges."

echo "Opening release PR..."
PR_URL="$(gh pr create \
  --base "$MAIN_BRANCH" \
  --head "$RELEASE_BRANCH" \
  --title "chore(release): $NEW_TAG" \
  --body "$PR_BODY")"
echo "  $PR_URL"

echo "Enabling auto-merge (squash)..."
if ! gh pr merge "$PR_URL" --auto --squash; then
  die "could not enable auto-merge on $PR_URL — confirm auto-merge is allowed for this repo (Settings > General > Pull Requests) and that $RELEASE_BRANCH has no conflicts with $MAIN_BRANCH, then run: gh pr merge $PR_URL --auto --squash"
fi

# --- Wait for the release PR to merge ----------------------------------------

POLL_INTERVAL="${RIHLA_RELEASE_PR_POLL_INTERVAL_SECS:-30}"
POLL_TIMEOUT="${RIHLA_RELEASE_PR_POLL_TIMEOUT_SECS:-1200}"
ELAPSED=0
SQUASH_SHA=""

echo
echo "Waiting for $PR_URL to merge (readiness CI takes a few minutes; polling every ${POLL_INTERVAL}s, timeout ${POLL_TIMEOUT}s)..."

while [ "$ELAPSED" -lt "$POLL_TIMEOUT" ]; do
  PR_JSON="$(gh pr view "$PR_URL" --json state,mergeCommit,mergeStateStatus)"
  PR_STATE="$(echo "$PR_JSON" | jq -r '.state')"

  if [ "$PR_STATE" = "MERGED" ]; then
    SQUASH_SHA="$(echo "$PR_JSON" | jq -r '.mergeCommit.oid')"
    break
  fi
  if [ "$PR_STATE" = "CLOSED" ]; then
    die "$PR_URL was closed without merging — resolve whatever blocked it, then either reopen and re-enable auto-merge (gh pr reopen $PR_URL && gh pr merge $PR_URL --auto --squash) or merge manually and tag the squash commit yourself: git tag -a $NEW_TAG -m \"Release $NEW_TAG\" <squash-sha> && git push origin $NEW_TAG"
  fi

  echo "  ... still $PR_STATE (mergeStateStatus=$(echo "$PR_JSON" | jq -r '.mergeStateStatus')), elapsed ${ELAPSED}s/${POLL_TIMEOUT}s"
  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ -z "$SQUASH_SHA" ]; then
  die "timed out after ${POLL_TIMEOUT}s waiting for $PR_URL to merge — check CI status at the PR URL. Once it merges, tag the squash commit yourself: git tag -a $NEW_TAG -m \"Release $NEW_TAG\" <squash-sha> && git push origin $NEW_TAG"
fi

echo "Merged. Squash commit: $SQUASH_SHA"

# --- Tag the squash-merge commit, not the pre-merge release commit ----------

git fetch origin "$MAIN_BRANCH" --quiet
if ! git merge-base --is-ancestor "$SQUASH_SHA" "origin/$MAIN_BRANCH"; then
  die "merge commit $SQUASH_SHA is not an ancestor of origin/$MAIN_BRANCH — refusing to tag. Investigate before retrying (do not tag a commit that isn't on $MAIN_BRANCH)."
fi
git reset --hard "origin/$MAIN_BRANCH"

if git rev-parse "$NEW_TAG" >/dev/null 2>&1; then
  die "tag $NEW_TAG already exists locally — did another release run concurrently? Investigate before retrying."
fi
if git ls-remote --tags origin "$NEW_TAG" | grep -q "$NEW_TAG"; then
  die "tag $NEW_TAG already exists on origin — did another release run concurrently? Investigate before retrying."
fi

echo
echo "Before tagging, re-point GitHub repository variable RIHLA_RELEASE_APPROVED_SHA at the SQUASH-MERGE commit (not $RELEASE_SHA):"
echo
echo "  gh variable set RIHLA_RELEASE_APPROVED_SHA --body \"$SQUASH_SHA\""
echo
if [ "${SKIP_RELEASE_APPROVAL_PROMPT:-0}" = "0" ]; then
  printf "Press Enter after RIHLA_RELEASE_APPROVED_SHA is re-pointed at %s, or Ctrl+C to stop before tagging. " "$SQUASH_SHA"
  read -r _
fi

RIHLA_RELEASE_TARGET_SHA="$SQUASH_SHA" bash tool/check_github_release_governance.sh || \
  die "GitHub release governance check failed for $SQUASH_SHA (see FAIL lines above) — fix it and re-run before tagging"

git tag -a "$NEW_TAG" -m "Release $NEW_TAG" "$SQUASH_SHA"

echo "Pushing $NEW_TAG to origin (tag pushes bypass the branch-protection status-check requirement)..."
git push origin "$NEW_TAG"

git branch -D "$RELEASE_BRANCH" >/dev/null 2>&1 || true

echo
echo "Release pushed. CI will build and upload to Play Store 'first' track."
REPO_SLUG="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
echo "  Workflow runs:  https://github.com/$REPO_SLUG/actions/workflows/release_android.yml"
echo "  Tag:            https://github.com/$REPO_SLUG/releases/tag/$NEW_TAG"
