---
name: pr-babysitter
description: Owns the merge tail for Rihla PRs — the stretch between "auto-merge enabled" and "actually merged" that GitHub never finishes on its own. Each pass updates BEHIND branches (auto-merge never self-updates them), runs /automerge on open PRs that lack it, surfaces P1-commented / red-CI / conflicted PRs, checks for pending backend deploys after merges, and GCs worktrees whose PR merged. Use when asked to "babysit the PRs", "watch the merge queue", "/pr-babysitter", or under /loop to run until the board is clear.
---

# PR babysitter

GitHub auto-merge holds a PR until `readiness` is green AND the branch is
up-to-date — but it **never updates a BEHIND branch itself** (`allow_update_branch`
only permits the update; nothing calls it). Every squash-merge re-BEHINDs the PRs
queued behind it, so a merge train stalls after the first car unless someone keeps
nudging. That someone is this skill. It is the tail of `/automerge`, not a
replacement — it never merges anything itself.

## One pass

### 1. Snapshot the board

```bash
gh pr list --state open --json number,title,isDraft,mergeStateStatus,autoMergeRequest,statusCheckRollup
```

### 2. Per open non-draft PR, in this order

- **CONFLICTING** → surface it for the human. Never resolve or force anything.
- **BEHIND** → `gh pr update-branch <N>`. If the update errors (usually a
  conflict with the new base) → surface as CONFLICT.
- **No auto-merge enabled** (`autoMergeRequest == null`) → check whether a prior
  `/automerge` round left P1 comments with no push since
  (`gh pr view <N> --json comments,commits`):
  - P1s still standing → surface, skip. The human fixes; a new push makes it
    eligible again.
  - Otherwise → run the full **`automerge`** skill pipeline on it (classify →
    exempt-enable or gate-review→refute). This may spawn Opus reviewer/refuter
    agents — that's the point; classification still fails toward GATE.
- **Checks failing** (any `statusCheckRollup` conclusion FAILURE) → surface with
  the failing check's name. Don't auto-fix, don't re-run blindly.

### 3. Post-merge housekeeping

For PRs that merged since the previous pass (first pass: since session start —
`gh pr list --state merged --limit 10 --json number,mergedAt,files`):

- **Backend delta** — if a merged PR touched `functions/**`, `security/**`, or
  `firestore.indexes.json`, run `bash tool/pending_deploy.sh rihla-safar`. If it
  reports pending, say so and point at the **`deploy-ceremony`** skill. NEVER
  deploy from here — the ceremony needs the user's Firebase auth and their eyes
  on the delta.
- **Worktree GC** — `git worktree list`. A non-main worktree is removable ONLY
  when ALL of:
  1. its branch's PR is merged: `gh pr list --head <branch> --state merged --json number,headRefOid` is non-empty;
  2. the worktree HEAD equals that PR's `headRefOid` (squash-merge means branch
     commits are never ancestors of main — comparing SHAs is the only safe test;
     a differing HEAD = commits made after the merge → surface, don't remove);
  3. `git -C <worktree> status --porcelain` is empty.
  Then `git worktree remove <path>` and delete the local branch. Anything dirty,
  unmerged, or ambiguous: leave it and report. Never `--force`.

### 4. Report the board

One line per PR: number, title, state, action taken this pass, what it's waiting
on. Plus any pending-deploy reminder and worktrees GC'd/skipped.

## /loop pacing

- Any tracked PR has CI running or was just updated → wake in ~270s (stay inside
  the prompt-cache window).
- Everything waiting on the human (P1s, conflicts, red CI) or nothing in flight →
  1200s+.
- No open PRs, no pending deploy → end the loop and say the board is clear.

## Non-negotiables

- **Never `gh pr merge` without `--auto`.** Only the `automerge` pipeline enables
  merging; this skill never bypasses it — not for "obviously safe" PRs either.
- **Never override a P1 stop.** A new push = a NEW `/automerge` round with fresh
  agents (never continue the old reviewer).
- Conflicts, red CI, and deploys belong to the human — surface, don't fix.
- Worktree removal requires merged PR + HEAD==merged SHA + clean tree. When in
  doubt, report instead of removing.
