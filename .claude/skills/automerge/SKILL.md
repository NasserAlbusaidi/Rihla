---
name: automerge
description: Review-gated auto-merge for Rihla PRs. Classifies a PR's diff; Gate-exempt PRs (docs, token sweeps, one-sentence diffs) get GitHub native auto-merge enabled immediately so they merge on green `readiness`. Gate-category PRs (money math / firestore.rules / Cloud Functions auth / routing / schema-field-name) get a fresh-context Opus diff review, then an independent refuter, and auto-merge is enabled ONLY if both clear. Use when asked to "auto-merge this PR", "/automerge <N>", or under /loop to sweep open PRs.
---

# Auto-merge (review-gated)

The fresh-context review is the thing that flips auto-merge on — nothing reaches `main` on green CI alone for the dangerous categories. This is the Gate (`run-the-gate`) applied to a **PR diff at merge time** instead of a spec before code, plus the `verified-sweep` refute guard, wired to `gh pr merge --auto`.

GitHub does the actual merge: enabling auto-merge holds the PR until the required `readiness` check is green and the branch is up-to-date, then merges and deletes the branch. "Enabled" ≠ "merged now."

**Auto-merge NEVER updates a BEHIND branch.** `allow_update_branch` only *permits* the update — nothing calls it (verified 2026-07-03: #859 sat BEHIND indefinitely; the old claim here that BEHIND PRs "self-update" was false). Every squash-merge re-BEHINDs whatever is queued behind it, so a merge train stalls after the first car. After enabling auto-merge, check `mergeStateStatus` and update BEHIND branches yourself (Step 3a); the `pr-babysitter` skill re-does this on every pass for the whole board.

## The one property this lives or dies on

**Classification fails TOWARD review.** A false positive costs one wasted Opus review. A false negative auto-merges an unreviewed money/rules/routing/schema change on green CI — the disaster this whole system exists to prevent. When a changed path is unfamiliar or you can't confidently say it's harmless, treat it as GATE. Never drift toward "just merge it."

## Pipeline

```
/automerge <N>
  └─ preconditions: PR open, not draft, auto-merge not already enabled
  └─ classify  (gh pr diff <N> --name-only  vs the denylist below)
       ├─ EXEMPT → enable auto-merge → done
       └─ GATE   → fresh Opus diff review (zero history)
                    ├─ P1s > 0 → post P1s as PR comment, STOP (you fix; re-run = NEW round)
                    └─ clean   → fresh REFUTER (tries to find a missed P1)
                                  ├─ refuted/unverified → post reason, STOP
                                  └─ cleared            → enable auto-merge → done
```

## Step 1 — preconditions

```bash
gh pr view <N> --json isDraft,state,autoMergeRequest,mergeStateStatus
```
- `state != OPEN` or `isDraft == true` → stop, report why.
- `autoMergeRequest != null` → already enabled, nothing to do.

## Step 2 — classify the diff

```bash
gh pr diff <N> --name-only
```
GATE if **any** changed path matches the denylist (verified to exist 2026-06-06):

| Category | Paths |
|---|---|
| Money math | `lib/features/ledger/providers/expense_provider.dart` (BalanceCalculator), `lib/core/services/money_serializer.dart` |
| Rules / Functions auth | `security/firestore.rules`, `functions/**` |
| Routing / deep links | `lib/core/router/**`, `lib/core/config/app_links.dart` |
| Schema / field-name | `**/models/**.dart` (e.g. `lib/core/models/**`, `lib/features/*/models/**`) |

Plus the catch-all: **any changed path you don't recognize as plainly safe → GATE.** Docs (`*.md`), `docs/**`, golden/test-only changes, design-token sweeps under `lib/core/theme/tokens/` + widget styling, `fastlane/**`, asset files → EXEMPT.

## Step 3a — EXEMPT → enable auto-merge

Resolve the repo default method at runtime (do not pin):
```bash
m=$(gh repo view --json viewerDefaultMergeMethod -q .viewerDefaultMergeMethod)
case "$m" in SQUASH) f=--squash;; REBASE) f=--rebase;; *) f=--merge;; esac
gh pr merge <N> --auto $f
```

Then clear the BEHIND stall (auto-merge will never do this itself):
```bash
s=$(gh pr view <N> --json mergeStateStatus -q .mergeStateStatus)
[ "$s" = "BEHIND" ] && gh pr update-branch <N>
```

Report: classified EXEMPT (which check let it through), auto-merge enabled, branch updated if it was BEHIND, will merge on green `readiness`.

## Step 3b — GATE → review → refute → enable

**Review.** Spawn a fresh reviewer — `Agent`, `subagent_type: general-purpose`, `model: opus`, zero history. Prompt = the full contents of `diff-reviewer-prompt.md` (this skill's dir) + the PR number. The agent runs `gh pr diff <N>` itself and verifies against live code. Do NOT paste this session's reasoning in. Beyond the code rubric, the reviewer also checks **spec conformance** (if the PR body has a `Spec:` link, the diff must not drift from the Gate-approved spec — un-gated scope creep or an unbuilt acceptance box is a [P1]) and **RED evidence** (a bug-fix must ship a regression test + pasted failing-before-fix output).

- Verdict has P1s → post them as a PR comment (`gh pr comment <N> --body ...`), STOP. Auto-merge stays OFF. You fix + push; **re-running `/automerge <N>` is a NEW round with a NEW fresh agent** (never `SendMessage` to continue the old one — continuation re-imports the context the freshness exists to escape).
- Verdict clean (0 P1s) → go to Refute. A clean review alone does NOT enable auto-merge.

**Refute** (the `verified-sweep` guard — a PASS is a done-claim, and fabricated/sycophantic done-claims are this repo's signature failure; `delete_branch_on_merge` makes the merge effectively irreversible). Spawn a SECOND fresh `Agent` (opus, zero history). Give it the diff + the reviewer's clean verdict; its job is to REFUTE — find one P1 the reviewer missed, default to `refuted: true` on any uncertainty. Model the prompt on `.claude/workflows/verified-sweep.js`'s refute prompt.

- `refuted: true` (or refuter returns nothing) → post the reason as a PR comment, STOP. Treat unverified as refuted.
- `refuted: false` with concrete evidence it actively confirmed clean → enable auto-merge (Step 3a commands, including the BEHIND update).

## The merge tail — hand it to pr-babysitter

Enabling auto-merge is not the finish line: branches go BEHIND after every squash-merge (and never self-update), CI goes red, reviewers leave P1s, merged worktrees linger. The **`pr-babysitter`** skill (this repo) owns that tail — per pass it updates BEHIND PRs, runs THIS pipeline on any open PR still missing auto-merge, and surfaces P1/red-CI/conflict PRs for the human. Under `/loop` it runs until the board is clear. Use it instead of hand-polling `gh pr view`.

## Non-negotiables

- Classification fails toward GATE. Unknown path = GATE.
- One reviewer / one refuter = one fresh `Agent` call each, zero history. Round 2 must not know round 1 existed.
- A clean review never enables auto-merge on its own — the refuter must also clear.
- A green test suite is NOT the review (worked example #185: rules suite green while the client write violated the rule).
- Never bypass to direct merge. The skill only ever enables native auto-merge; GitHub + `readiness` do the merge.
- Repo-default merge method, resolved at runtime — don't hardcode `--squash`.
