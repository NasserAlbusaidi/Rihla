# #441 PR5 — Delete the merge engine + ops tail Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Delete the now-unreachable cross-UID merge engine (server callable + rules block + TTL override + client wrapper) and rewrite the recovery docs, then run the deploy ceremony that removes it from prod and sweeps residual intent docs.

**Architecture:** After PR4 (merged), no client code writes `recoveryCleanupIntents` or invokes `cleanupAnonUidArtifacts` — the engine is dead weight with an attack surface (an anonymously-writable collection + a 691-LOC callable holding a bearer-secret protocol). PR5 removes the server half, its rules, its TTL fieldOverride, and the client wrapper, and aligns the docs. Pure deletion; no behavior change for any reachable path.

**Parent:** `docs/plans/2026-06-11-durable-credential-recovery-rearchitecture.md` (PR5 row). Epic #441 — this PR closes it.

---

## Preconditions (both verified 2026-06-11)

1. **PR4 merged.** PR #449 (no-merge `restoreWithEmailLink`) removed the last production caller of the merge engine. PR5 branches from the post-#449 main; building it earlier fails to compile (`auth_recovery_service.dart` on pre-PR4 main still constructs the default `cleanupAnonUidArtifacts` wiring).
2. **Mechanical prod check (mitigation 7) — RUN, result recorded honestly:** enumerated all 36 prod groups + 29 unique member UIDs via Admin API (2026-06-11). 28 UIDs are anonymous-provider-only, across ~35 groups; 1 UID is credentialed (`HIvgHwjoCAdCyiay33vankSLuIF2`, the project owner's email-linked account). **This is NOT the zero-hit pass the epic demanded** — but every hit is identifiable developer QA data (`QA 2026-06-05`, `QA 0351b`, `QA 0529/0531`, `Dtest`×2, `Test Group`, `Test`, `UAT`, `PushTest`, `OMR Trip`/`USD Trip`/`Collision` (#383 currency QA), `Frontech`, `Big D`×3, etc.), all created before the PR2 gate went live (2026-06-11, `20689860`). The standing "no real users yet" decision holds: these anon sessions belong to the decision owner's own test devices, and an anon-only UID has NO recovery path even WITH the merge engine (the merge only fires during a recover/restore into a previously-linked account — anon-only users by definition have none). Deleting the engine strands no capability these UIDs ever had. Decision: PROCEED. Residual `recoveryCleanupIntents` docs found: 4 (all QA; 2 already TTL-expired) — swept in Task 6.
3. **PR3 device-QA ordering note:** the epic ordered PR5 after PR3 device-QA, which has NOT happened. Proceeding anyway on explicit owner instruction (2026-06-11 "continue with PR4 and 5") + no-real-users + full git recoverability (`firebase deploy` re-creates the callable from history in minutes if device-QA later fails). Flagged, not hidden.

## Deletion inventory (every line verified against post-PR4 code)

| Surface | Path | Action |
|---|---|---|
| Server callable | `functions/src/callables/cleanupAnonUidArtifacts.ts` (691) | delete file |
| Server test | `functions/test/callables/cleanupAnonUidArtifacts.test.ts` (1125) | delete file |
| Export | `functions/src/index.ts:7` | remove line (auto-updates `tool/list_expected_functions.sh`'s derived set — awk reads `export {} from` lines) |
| Client wrapper | `lib/core/services/firebase_functions_service.dart:12-46` (`CleanupOutcome` + `cleanupAnonUidArtifacts`, ~35/88 lines) | remove; keep `deleteAccount`/`deleteGroup`/`leaveGroup`/`removeMember` |
| Client wrapper tests | `test/unit/firebase_functions_service_cleanup_outcome_test.dart` (114) delete; `test/unit/firebase_functions_service_test.dart:14-30` remove the full cleanup `test(...)` block | edit |
| Rules block | `security/firestore.rules:238-264` (`match /recoveryCleanupIntents/{oldUid}` + `validCleanupIntent` + the explanatory comment above it) | remove; with no match block the collection falls to the default deny-all |
| Rules comment | `security/firestore.rules:15-16` — `isDurableSignIn` doc says "recoveryCleanupIntents is intentionally anonymous-written and must NOT use this" | drop that clause (keep the money-data sentence) |
| Rules test | `functions/test/firestore-rules-publish-readiness.test.ts:454-520` — the `recoveryCleanupIntents` `test(...)` block (`validIntent`/`intent` fixtures + 11 asserts; helpers are block-local) | remove the whole test block |
| TTL override | `firestore.indexes.json:67-76` (`recoveryCleanupIntents`/`expiresAt`, `"ttl": true`) | remove entry (deploy updates prod TTL config) |
| Docs | `docs/ACCOUNT-RECOVERY.md` (483) | rewrite as the durable-credential architecture doc: anon-first + gate (PR2), Google link/restore (PR1/PR3), slim email fallback (PR4), merge engine deleted (PR5), pointers to the epic plan. Keep a short History section naming the deleted design + #213/#216/#414/#427 |
| Docs | `docs/CLOUD-FUNCTIONS.md`, `docs/SECURITY-RULES.md`, `docs/ARCHITECTURE.md` | remove/replace `cleanupAnonUidArtifacts` + `recoveryCleanupIntents` entries; fix callable counts where stated |
| CLAUDE.md | Quick Nav functions-count line (`CLAUDE.md:21` says "4 callables + 3 triggers + 1 scheduled reaper" — ALREADY stale; actual post-deletion set = **5 callables + 10 triggers + 2 scheduled, 17 total** per `tool/list_expected_functions.sh` minus the deleted one — verify the exact split at implementation) + any now-false `cleanupAnonUidArtifacts` mentions (e.g. #294 bullet's "broken creator recovery" context note) | update minimally — history references stay, present-tense claims change |
| Test fixture | `functions/test/fixtures.ts:46` — emulator cleanup helper iterates `['joinAttempts', 'recoveryCleanupIntents']` | drop `'recoveryCleanupIntents'` from the list (Admin SDK sweep of a dead collection) [Gate R1 P2] |
| Doc comments | `lib/features/auth/services/auth_recovery_service.dart:48,280` — two `///` references to the deleted symbol | reword to past tense ("the deleted merge engine") so the guard grep can reach zero [Gate R1 P2] |
| AGENTS.md | `AGENTS.md:9` present-tense "new `cleanupAnonUidArtifacts` callable scrubs…" | reword to past tense [Gate R1 P3] |
| KEEP (history, no edits) | `docs/DEPLOY-LEDGER.md`, `docs/PRODUCTION-READINESS.md` records, `docs/plans/*` (except parent-plan correction below), `docs/RUNBOOK.md`/`POST-LAUNCH-ROADMAP.md`/`PRODUCT.md`/`REAL-DEVICE-QA.md` mentions reviewed — edit only actively-false present-tense lines | — |
| Parent plan correction | `docs/plans/2026-06-11-durable-credential-recovery-rearchitecture.md` deletion-inventory line listing `recover_screen.dart`/`recover_pending_screen.dart`/their tests as deletable | annotate: KEPT as the slim email-fallback UI (PR4 decision); merge-dialog deleted in PR4 |

**NOT deleted (shared / live):** cache-isolation stack (all 7 pieces), `deletionReaper.ts`, email LINK path, `recover_screen.dart` + `recover_pending_screen.dart` + `/recover` routes + their tests (the PR4-kept fallback UI), `signOutCurrentDevice`, `firebase_auth_test.dart` (#213 contract).

## Verification principles run

1. **Callsites:** `cleanupAnonUidArtifacts` post-PR4 grep — `lib/`: only `firebase_functions_service.dart` (the wrapper itself, zero callers) + 2 doc-comments in `auth_recovery_service.dart`. `functions/src/`: only the callable file + `index.ts:7`. `recoveryCleanupIntents` writer: NONE in `lib/` (PR4 deleted it); reader: only the callable being deleted. No orphaned consumer.
2. **Concrete claims:** all paths/line-numbers in the table re-grepped 2026-06-11 in the post-PR4 tree.
3. **Read-path per write-path:** the deleted collection's only reader is the deleted callable; rules fall to deny-all (no `match` = no access). The TTL override's only job was reaping the now-unwritable collection; the 4 residual docs are swept manually in Task 6 BEFORE the TTL override is dropped, so nothing is left behind unreapable.
4. **Fields from the type:** `FirebaseFunctionsService` remaining methods enumerated: `deleteAccount`, `deleteGroup`, `leaveGroup`, `removeMember` — none reference `CleanupOutcome`.
5. **Data contracts:** no shapes change; pure removal. `tool/list_expected_functions.sh` derives the expected-functions set from `index.ts` re-exports, so the drift check self-aligns (and `release_workflow_gate_test.dart:588-623` re-derives it with its own regex — stays green). **[Gate R1 P2 correction]** `check_firebase_prod_state.sh:208-227` only verifies expected ⊆ deployed — it will NOT flag a lingering deployed callable. The thing that actually purges prod is `tool/deploy_firebase_backend.sh:82-85` running `firebase deploy --force` (removes stale remote functions). Task 6 must confirm post-deploy via `firebase functions:list` (or the deploy output's delete line) that `cleanupAnonUidArtifacts` is gone — do not rely on the prod-state check for this direction.
6. **Arithmetic:** N/A — no money math. The balance oracle (`groupNetBalance.ts` `recomputeNet`) is NOT touched; `cleanupAnonUidArtifacts.ts` has its own private copies of nothing shared (verified: it imports `mergeUidMapKey`-style helpers locally — confirm at implementation that no OTHER module imports from it: `grep -rn "from './cleanupAnonUidArtifacts'" functions/src/` must return only `index.ts`).
7. **Orthogonal axis (security):** post-deletion, an attacker can no longer write anonymously to `recoveryCleanupIntents` (deny-all) — strict attack-surface reduction. No new permission grant anywhere in the diff.

## Tasks

### Task 1: Delete the server half
Delete `cleanupAnonUidArtifacts.ts` + its jest test; remove `index.ts:7`. Verify `grep -rn "cleanupAnonUid" functions/src/ functions/test/` → zero. Run `cd functions && npm test` → green (rules suite still passes — its intents block goes in Task 2; jest test count drops by the deleted file only). NOTE: if the rules-readiness suite imports nothing from the callable, Tasks 1–2 are independently green; run the suite after EACH to keep the tree green per commit.

### Task 2: Delete the rules block + rules test + TTL override
Remove `firestore.rules:238-264` block + the `:15-16` comment clause; remove the rules-readiness `it` block; remove the `firestore.indexes.json` entry. Run the rules suite (Java 21 emulator): green. Commit.

### Task 3: Delete the client wrapper
Remove `CleanupOutcome` + `cleanupAnonUidArtifacts` from `firebase_functions_service.dart`; delete `firebase_functions_service_cleanup_outcome_test.dart`; remove the cleanup case from `firebase_functions_service_test.dart`. `flutter analyze` clean; `flutter test test/unit/firebase_functions_service_test.dart` + full suite green. Commit.

### Task 4: Docs tail
Rewrite `ACCOUNT-RECOVERY.md`; sweep `CLOUD-FUNCTIONS.md` / `SECURITY-RULES.md` / `ARCHITECTURE.md` / CLAUDE.md per inventory; annotate the parent plan's deletion-inventory correction. Commit.

### Task 5: Ship
Branch verification (analyze + full flutter suite + functions jest + guard greps `cleanupAnonUid\|recoveryCleanupIntents\|CleanupOutcome` zero live hits outside history docs) → push → PR with `Closes #441` + `Spec:` line → `/automerge` (Gate-category: rules + functions).

### Task 6: Deploy ceremony (AFTER merge — deploy-ceremony skill)
1. `tool/pending_deploy.sh` — show the delta.
2. Sweep the 4 residual `recoveryCleanupIntents` docs (Admin SDK/console delete; rules deny client deletes): `FxtaZTzmtUTp5xsdh8wVDD0zKgd2`, `lgb7GQojVCP0sJ20MLS9VMWw6yp2`, `nFf1H1LGVjaZ2HrqsDcuscfiNz42`, `zh0JfFxHfYPVoGM55koeLLl1XQE2`.
3. `tool/deploy_firebase_backend.sh` from the merge SHA — rules + indexes + functions; its `--force` removes the stale remote callable (`deploy_firebase_backend.sh:82-85`).
4. **Confirm the deletion direction yourself** (`firebase functions:list` must NOT show `cleanupAnonUidArtifacts`) — the prod-state check only verifies expected ⊆ deployed and cannot flag a lingering callable [Gate R1 P2]. Then prod-state verify PASS, advance `backend-deployed`, record in `DEPLOY-LEDGER.md` (include the mitigation-7 result verbatim), close #441.

## Considered and rejected
- **Purging the 35 anon QA groups to force a literal zero-hit pass:** destructive sweep of the owner's active test data for a checkbox; the check's intent (no REAL user stranded) is satisfied by inspection. Offered as optional cleanup, not done unilaterally.
- **Keeping the callable "just in case" until device-QA:** a deployed 691-LOC bearer-secret endpoint with an anonymously-writable intents collection is attack surface, not insurance; git restores it in minutes.
