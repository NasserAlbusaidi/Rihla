# PR #714 claimShadow per-shadow lock — Gate-review fix spec (2026-06-27)

Fixes the 4 P1 merge blockers from `/tmp/pr714-review.md` (fresh-context Gate review of #710),
plus one P2 (stale display aggregate) and two coverage gaps. All P1 claims were re-verified
first-hand against the PR branch (`82384a95`) before this spec — findings below cite live lines.

## Why these are P1 (and emulator-masked)

Both freeze flags gate `groupAllowsClientWrites` (`security/firestore.rules:140-143`), referenced
by 8 write rules → a leaked freeze is a **group-wide write outage** for all members. The emulator
ignores indexes and never opens the post-crash reaper window, so all 560 tests pass while prod breaks.

---

## Change 1 (P1 #1a) — COLLECTION_GROUP indexes

`deleteAccount.ts:667-668` and `:690-691` run two collection-group equality queries
(`collectionGroup('claimRequests').where('requesterUid','==',uid)` and
`collectionGroup('claimShadowLocks').where('claimerUid','==',uid)`). Firestore auto-creates only
COLLECTION-scope single-field indexes; collection-group equality needs an explicit COLLECTION_GROUP
single-field index. `firestore.indexes.json` has **0** COLLECTION_GROUP entries → prod throws
`FAILED_PRECONDITION: requires an index` at query-plan time, regardless of result count.

**Index-scope subtlety (verified):** `requesterUid` is ALSO queried at COLLECTION scope by the
pre-existing `listMyClaimRequests.ts:57-58` (`.collection('groups/{gid}/claimRequests').where('requesterUid','==',uid)`).
Declaring a `fieldOverride` REPLACES the field's automatic single-field indexes — so the override
MUST keep the COLLECTION-scope index or `listMyClaimRequests` breaks. `claimerUid` has no
COLLECTION-scope query (only the collection-group + a `.doc(shadowMemberId)` ref), but I include
COLLECTION scope on it too for symmetry / future-proofing.

Add to `firestore.indexes.json` `fieldOverrides`:
```json
{
  "collectionGroup": "claimRequests",
  "fieldPath": "requesterUid",
  "indexes": [
    { "order": "ASCENDING", "queryScope": "COLLECTION" },
    { "order": "DESCENDING", "queryScope": "COLLECTION" },
    { "order": "ASCENDING", "queryScope": "COLLECTION_GROUP" }
  ]
},
{
  "collectionGroup": "claimShadowLocks",
  "fieldPath": "claimerUid",
  "indexes": [
    { "order": "ASCENDING", "queryScope": "COLLECTION" },
    { "order": "DESCENDING", "queryScope": "COLLECTION" },
    { "order": "ASCENDING", "queryScope": "COLLECTION_GROUP" }
  ]
}
```
Deploy (`tool/deploy_firebase_backend.sh` runs `--only firestore:rules,firestore:indexes,functions,hosting`,
so the override deploys WITH the functions). No-real-users → no client-compat ordering concern.

## Change 2 (P1 #1b) — scrub failure must degrade, not abort

`scrubClaimStateForDeletingUid` is `await`ed bare at `deleteAccount.ts:788`, with NO try/catch
(unlike the `fcm_tokens`/`joinAttempts` deletes immediately after) and BEFORE the Auth-delete gate
(`:814`). So a scrub throw aborts the entire `runAccountDeletionCascade` (and never reaches the
gate) for EVERY user. Wrap the await in try/catch that folds failure into `cascadeFailed`
(→ `partialCascade` → auth user preserved → retryable), exactly like the two deletes that follow it.

```ts
try {
  await scrubClaimStateForDeletingUid(db, uid, cascadeFailed);
} catch (error) {
  if (!cascadeFailed.includes('claimState')) cascadeFailed.push('claimState');
  logger.error('deleteAccount claim-state scrub failed', { uid, error: ... });
}
```
(The index — Change 1 — is the actual fix; this is defense so a transient/indexless failure degrades
gracefully instead of leaving the GDPR cascade in limbo.)

## Change 3 (P1 #2) — engine signals "this lock completed the claim"

`completedByThisLock` is `false` at all three return sites (`claimShadow.ts:573,746,753`); the engine
never reads `options.resumeExistingLock` (declared `:79`, dead). The reaper at
`claimShadowLockReaper.ts:189` returns `'left'` whenever `result.alreadyClaimed && !result.completedByThisLock`.
Crash-after-Phase-C (shadow retired + balance correct, instance dies before finalize): the reaper
resumes, the engine finds the shadow gone + de-referenced → idempotent clean → `alreadyClaimed:true,
completedByThisLock:false` → `'left'` **every pass** → `claimingInProgress` freeze never clears.

Fix: the two idempotent-clean return sites return `completedByThisLock: options.resumeExistingLock === true`.

**Soundness:** the lock doc is keyed by `shadowMemberId` and CAS-guarded (`decideClaimRequest.ts:239-243`
throws `aborted` if it exists) → at most one live lock per shadow. The reaper sets
`resumeExistingLock:true` ONLY (`:187`) after verifying a mutation marker + a matching `claiming`
request (`:160-180`). So a clean idempotent-gone under resume ⟹ THIS lock's claim committed →
`completedByThisLock:true` is correct. Non-resume callers (decideClaimRequest) keep `false` (unchanged).

## Change 4 (P1 #3) — atomic finalize (reaper AND decideClaimRequest)

`claimShadowLockReaper.ts:196-201` writes `status:'claimed'` THEN `releaseReservation` — a crash
between leaves `status:'claimed'` + live lock + freeze; the next pass needs `status==='claiming'`
(`:169`) → now false → `'left'` → permafreeze. **Orthogonal finding (re-verified):
`decideClaimRequest.ts:358-363` has the IDENTICAL two-step** and runs on every claim (not just
stale-lock recovery) — the more likely trigger. The reviewer flagged only the reaper.

Fix: one atomic transaction (status + lock-delete + freeze-clear). Add to `claimShadow.ts`:
```ts
export async function finalizeClaimAndRelease(
  db: Firestore, groupRef: DocumentReference, requestRef: DocumentReference,
  token: ClaimShadowLockToken, decidedBy: string,
): Promise<void> {
  const lockRef = db.doc(token.refPath);
  await db.runTransaction(async (tx) => {
    const groupSnap = await tx.get(groupRef);    // reads before writes
    const lockSnap = await tx.get(lockRef);
    const requestSnap = await tx.get(requestRef);
    // P1-A (Gate round 1): the guard-read (reaper :169-180) and this finalize are
    // SEPARATE txns. Only relabel a STILL-`claiming` request → never resurrect a
    // legitimately declined/re-decided one to 'claimed'. Lock-delete + freeze-clear
    // stay unconditional (token-matched) so they converge regardless of status.
    if (requestSnap.exists && requestSnap.data()?.status === 'claiming') {
      tx.update(requestRef, { status: 'claimed', decidedBy,
        decidedAt: FieldValue.serverTimestamp() });
    }
    if (lockSnap.exists && claimLockMatches(lockSnap.data(), token)) tx.delete(lockRef);
    const groupData = groupSnap.data() ?? {};
    if (groupSnap.exists && groupData.claimingInProgress === true
        && timestampMillis(groupData.claimLockedAt) === token.lockedAtMs) {
      tx.update(groupRef, { claimingInProgress: FieldValue.delete(),
        claimLockedAt: FieldValue.delete(), claimMutationStartedAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp() });
    }
  });
}
```
- Reaper: replace `:196-201` with `await finalizeClaimAndRelease(groupRef.firestore, groupRef, requestRef, token, token.lockedBy)`.
- decideClaimRequest success path: replace `:358-363` with `await finalizeClaimAndRelease(db, groupRef, requestRef, decision.token, uid)`.
- The `alreadyClaimed`→decline block (`:339-356`, NOT the user-decline CAS at `:244-251`/`:286-288`) is
  left as-is: on `alreadyClaimed:true` the engine returns at `claimShadow.ts:573` BEFORE
  `markClaimMutationStarted` (`:624`), so its lock is NOT mutation-marked → the reaper's
  `resetPreMutationReservation` clears its lock+freeze regardless of request status → already convergent.
  (P2-2/Gate: the `!retired` mutation-marked variant at `claimShadow.ts:746` would NOT be covered by the
  reset path, but is UNREACHABLE while the lock holds — every shadow-retiring callable gates on
  `claimingInProgress`. Add a one-line comment at `:339` noting that dependency.)

Because BOTH two-steps become atomic, the only live-lock state has `status==='claiming'`; the reaper's
existing guard stays correct, and no resume-guard change is needed. Convergence cases:
- crash before finalize tx (shadow gone): reaper resume → completedByThisLock:true → atomic finalize. ✓
- crash mid-Phase-B (shadow present): reaper resume re-runs B+C fresh → alreadyClaimed:false → finalize. ✓
- finalize tx committed: lock gone → reaper never sees it. ✓

## Change 5 (P1 #4) — release the accountDeletion freeze on group failure

`accountDeletionInProgress` is set in `acquireAccountDeletionGroupMarker` (`deleteAccount.ts:404`)
before Phase B, cleared ONLY in Phase C (`:573`). A Phase B throw (the torn-batch test forces one)
is swallowed by the per-group catch (`:778`) → marker leaks → group-wide write freeze for innocent
co-members until the same uid's `deletionReaper` converges. Also: the two `skippedGroup()`
early-returns (`:431,:434`) leak it.

Fix: add `releaseAccountDeletionGroupMarker(db, groupRef, uid)` (tx: clear the three accountDeletion*
fields iff `accountDeletionInProgress===true && accountDeletionUid===uid`). In `processGroup`, after
`acquireAccountDeletionGroupMarker` succeeds, wrap Phase A+B+C in try/catch: catch releases (best-effort,
log on failure) then rethrows; the two `skippedGroup()` returns release first. Happy path is unchanged
(Phase C clears the marker and returns inside the try; catch not entered → no extra transaction).

## Change 6 (P2-1) — refresh the display aggregate after a claim

Every claim-time write hits `balanceAggregator`'s freeze early-return (`balanceAggregator.ts:79-83`),
and the release write to `groups/{gid}` changes no balance key → the aggregate doc (home-hero display
cache) stays pre-claim up to 24h (until `balanceReconciler` / next money write). After release
(freeze cleared), call `refreshGroupBalanceAggregate(db, groupId, Date.now())` best-effort in
decideClaimRequest (success) and the reaper (resumed). It re-checks the freeze (now clear) and the
`sourceTimeMs` staleness guard accepts `Date.now()`. Display-only; best-effort (claim already
succeeded; a refresh failure self-heals via the reconciler).

## Tests (RED-first)

1. **Reaper crash-after-Phase-C** (`claimShadowLockReaper.test.ts`): seed POST-Phase-C state
   (memberIds=[OWNER,CLAIMER], shadow member doc deleted, event re-keyed, NO shadow refs) +
   live lock + freeze + `status:'claiming'` mutation-marked request. Run reaper → expect
   `status:'claimed'`, lock gone, `claimingInProgress` undefined. RED on current (returns `'left'`).
2. **Torn-batch freeze cleared** (`deleteAccount.test.ts` torn-batch test ~:790): add
   `expect((await db.doc('groups/big').get()).data()?.accountDeletionInProgress).toBeUndefined();`
   after the Phase B failure. RED on current (marker leaks).
3. **Scrub degradation** (`deleteAccount.test.ts`): mock `db.collectionGroup` to throw → expect
   `partialCascade` (auth user preserved, marker `cascadeFailed` contains 'claimState'), not an
   unclassified callable abort.
4. **D9 pre-mutation reset coverage** (`claimRequest.test.ts:472`, P1-B/Gate re-scope): the lock-gone +
   freeze-cleared assertions already exist in D8 (`:468-469`). The UNCOVERED property is that after the
   D9 `failed-precondition` throw (pre-scan reject, before any mutation marker), `resetPreMutationClaimReservation`
   cleaned up the CAS-created lock + freeze. Add AFTER the D9 `rejects` (`:485-487`):
   `expect(lockExists).toBe(false)` + `expect((await groupDoc('g')).claimingInProgress).toBeUndefined()`.
   GREEN-on-current (coverage of existing behavior the original review flagged unasserted), not RED.

## Out of scope (noted, not fixed)
- P2-2 stuck-`claiming` copy in `requestClaimShadow.ts:121` — self-resolves once P1s land; copy only.
- P2-3 terminal-`left` lock blocking the claimer's own deletion — mitigated by P1 #2/#3.
