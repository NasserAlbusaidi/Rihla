---
name: deploy-ceremony
description: Deploy the Rihla Firebase backend (Cloud Functions + Firestore rules + indexes) to prod and keep the deploy state honest. Shows the merged-but-undeployed delta first (pending_deploy.sh), runs the commit-bound deploy + prod-state verify, advances the `backend-deployed` source-of-truth tag, then records the deploy in docs/DEPLOY-LEDGER.md and clears stale "⚠️ NOT deployed" flags. Use when asked to "deploy the backend", "run the deploy ceremony", "ship the functions", or after merging a Functions/rules PR.
---

# Deploy ceremony (backend)

The project's recurring failure mode is **ghost-debt**: Functions/rules merged to
`main` but never deployed, tracked only in scattered `⚠️ NOT deployed` memory notes.
This ceremony makes deploy state a single queryable fact (the `backend-deployed`
git tag) and a discoverable log (`docs/DEPLOY-LEDGER.md`), and refuses to let a
deploy finish without recording itself.

Scope: this is the **backend** deploy (Cloud Functions + `firestore.rules` +
`firestore.indexes.json` + hosting). It is **not** the client release ceremony
(`tool/release.sh`) and it does **not** satisfy the release-readiness gate — see
the warning in step 5.

## No-clients note

Per [[no-clients-deploy-freely]]: there are no real users on a shipped client yet,
so server-authoritative changes deploy **freely** — no client-compat gating, no
deploy-first-vs-client-first ordering. Ignore any `⚠️ old clients PERMISSION_DENIED`
warnings in older memory while this holds. Revisit once real users exist.

## Step 1 — show what's pending

```bash
bash tool/pending_deploy.sh rihla-safar
```

- Exit 0 (nothing pending) → stop; prod already matches `main`.
- Exit 1 → it prints the merged-but-undeployed backend commits + file delta. Read
  them. State out loud what is about to ship and why.

## Step 2 — get onto the exact commit being deployed

The deploy is commit-bound: it refuses unless the worktree is clean and
`RIHLA_FIREBASE_DEPLOY_APPROVED_SHA` equals `HEAD`.

```bash
git checkout main && git pull --ff-only
git status --porcelain   # must be empty
```

Deploy the tip of `main` (everything reviewed + merged). If you must deploy a
non-tip commit, check it out explicitly and know that anything merged after it
will still read as pending afterward.

## Step 3 — deploy (commit-bound + prerequisites confirmed)

Prereqs the script enforces: Blaze plan, Functions/Cloud Build/Artifact Registry
APIs, **App Check enrolled** before enforced callables. The `--force` makes repo
config authoritative (removes stale remote indexes/functions).

This needs your Firebase auth and is long-running — run it yourself in the session
with `!` so its output lands here:

```bash
! RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes RIHLA_FIREBASE_DEPLOY_APPROVED_SHA="$(git rev-parse HEAD)" bash tool/deploy_firebase_backend.sh rihla-safar
```

On success the script: deploys → runs `check_firebase_prod_state.sh` → **moves +
pushes the `backend-deployed` tag to the deployed SHA**. If the tag push warns of
failure, push it manually (`git push --force origin refs/tags/backend-deployed`)
or `pending_deploy.sh` will keep reporting the just-shipped change as pending.

## Step 4 — verify it landed

```bash
git rev-parse backend-deployed          # should equal the deployed SHA
bash tool/pending_deploy.sh rihla-safar # should now exit 0
```

A green `check_firebase_prod_state.sh` inside the deploy is the prod-match proof;
do not assert success without it (this repo's signature failure is fabricated
done-claims — see CLAUDE.md → Memory).

## Step 5 — record + clean up (the honesty step)

1. **Ledger** — append a row to `docs/DEPLOY-LEDGER.md` (newest at bottom): date,
   deployed SHA, the PRs/issues that shipped (from step 1's delta), and the
   prod-state result. Open a docs-only PR (main is protected; it's Gate-exempt →
   `/automerge` lands it on green `readiness`).
2. **Memory** — flip the `⚠️ NOT deployed` flags in the relevant `project_*.md`
   memory files (and MEMORY.md index lines) to deployed, with the SHA + date.
3. **PRODUCTION-READINESS** — clear the hand-written *pending-backend-deploy*
   informational block (the one PR #325 added). **Do NOT** touch the pinned
   `- [ ] Firebase production state is not aligned with this branch yet.` checkbox
   — `test/unit/release_workflow_gate_test.dart` keeps that OPEN until the full
   *release* ceremony (a recorded prod-state PASS vs the release SHA), which is a
   higher bar than a backend deploy. Flipping it turns CI red.

## Non-negotiables

- Show `pending_deploy.sh` BEFORE deploying — never deploy blind.
- The deploy is the only thing that may advance `backend-deployed`; never move the
  tag by hand to paper over a skipped deploy.
- A deploy that doesn't reach step 5 left ghost-debt — finish the record, or you've
  recreated the exact problem this ceremony exists to kill.
