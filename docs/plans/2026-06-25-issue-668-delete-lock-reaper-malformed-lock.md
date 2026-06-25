# Issue 668 Malformed Delete Lock Reaper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every server-side delete-lock recovery path handle `deletingInProgress:true` with missing or malformed `deleteLockedAt` without finalizing from an unsafe resume horizon.

**Architecture:** Preserve the existing valid-lock path: stale locks with a valid old `deleteLockedAt` still resume `finalizeGroupDeletion`, and fresh locks still stay untouched. Add a separate malformed-lock path for `timestampMillis(deleteLockedAt) == null`: clear the malformed lock transactionally without finalizing the group, because a missing/malformed lock timestamp is not a safe delete-resume horizon for money recomputation. Apply that rule to both server entry points that can observe an existing delete lock: the scheduled reaper and the `deleteGroup` callable owner-retry path.

**Tech Stack:** Firebase Cloud Functions v2 scheduled function, TypeScript, Firebase Admin SDK, Firestore/Auth emulator tests, Jest.

---

## Live Code Verification

Commands run while writing this spec:

- `gh issue view 668 --json number,title,state,labels,milestone,body,url,comments`
- `rg -n "deleteGroupLockReaper|deleteLockedAt|deletingInProgress|timestampMillis|clearOwnedDeleteGroupLock" functions/src functions/test security/firestore.rules docs`
- `nl -ba functions/src/scheduled/deleteGroupLockReaper.ts | sed -n '1,180p'`
- `nl -ba functions/test/scheduled/deleteGroupLockReaper.test.ts | sed -n '1,280p'`
- `nl -ba functions/src/callables/groupNetBalance.ts | sed -n '280,315p;560,590p'`
- `nl -ba security/firestore.rules | sed -n '128,144p'`
- `nl -ba functions/src/callables/deleteGroup.ts | sed -n '120,285p'`
- `nl -ba functions/test/callables/deleteGroup.test.ts | sed -n '1090,1260p'`
- `RIHLA_AUTH_EMULATOR_PORT=19192 RIHLA_FIRESTORE_EMULATOR_PORT=18182 RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/scheduled/deleteGroupLockReaper.test.ts" bash tool/run_firebase_emulator_tests.sh`
- `rg -n "finalizeGroupDeletion\\(|acquireDeleteGroupLock|clearDeleteGroupLockForFailure|timestampMillis\\(" functions/src functions/test`

Findings:

- `functions/src/scheduled/deleteGroupLockReaper.ts:68-69` maps `deleteLockedAt` with `timestampMillis(data.deleteLockedAt)` and skips the group when the result is `null`.
- `functions/src/callables/groupNetBalance.ts:290-303` returns `null` for missing, string, number, or other malformed timestamp values.
- `security/firestore.rules:134-139` blocks client writes whenever `deletingInProgress == true`, so a malformed lock skipped forever freezes the group forever.
- `functions/src/callables/deleteGroup.ts:159-165` is the shipped writer of `deletingInProgress:true`; it writes `deleteLockedAt: Timestamp.now()` in the same transaction, so #668 is a defensive future/out-of-band repair path.
- `functions/src/callables/deleteGroup.ts:223-225` and `docs/plans/2026-06-16-deletegroup-lock-pair-519-529.md:13` make `deleteLockedAt` the money-safety resume horizon. Without a valid timestamp, calling `finalizeGroupDeletion` cannot safely distinguish a partial delete cascade from older intentionally soft-deleted events.
- `functions/src/callables/deleteGroup.ts:148-156` also observes existing locks during creator retry. If that existing lock has malformed `deleteLockedAt`, the callable currently returns `lockedAtMs:null` and still reaches `finalizeGroupDeletion` at `functions/src/callables/deleteGroup.ts:299-316`.
- `functions/src/callables/groupNetBalance.ts:578-581` uses `timestampMillis(groupData.deleteLockedAt)` as the delete-resume horizon, so the callable malformed-lock path has the same money-safety hazard as the reaper malformed-lock path.
- Existing baseline is clean: `deleteGroupLockReaper.test.ts` passed 5 tests before this change.

## Gate Classification

This touches a Cloud Functions scheduled write path and server-side validation of `deletingInProgress` lock state. Run `rihla-run-the-gate` before implementation. Stop until a fresh-context reviewer returns no [P1] findings.

## Callsite Classification

- OUTBOUND: `functions/src/scheduled/deleteGroupLockReaper.ts` reads `groups/*` where `deletingInProgress == true`, writes group lock fields, and may call `finalizeGroupDeletion`.
- OUTBOUND: `functions/src/callables/deleteGroup.ts` creates valid delete locks, observes existing delete locks on owner retry, writes group lock fields when clearing a malformed observed lock, and owns normal deletion/finalization.
- BOTH but unchanged: `functions/src/callables/groupNetBalance.ts` provides `timestampMillis` and computes delete-resume balance scope from `deleteLockedAt`.
- INBOUND: `security/firestore.rules` `groupAllowsClientWrites` reads `deletingInProgress`, and client group/event readers observe `isDeleted` / `deletedAt` soft-delete state. Clearing a malformed lock restores normal client writes; valid stale locks still finalize or clear exactly as before.

## Data Contracts

Malformed delete lock definition:

```ts
data.deletingInProgress === true && timestampMillis(data.deleteLockedAt) == null
```

Malformed lock behavior:

- Do not call `finalizeGroupDeletion` for malformed locks in either server path.
- Do clear the lock transactionally if the group still has `deletingInProgress === true`, the same parsed `deleteLockedBy`, and `timestampMillis(cur.deleteLockedAt) == null`.
- Write exactly:

```ts
{
  deletingInProgress: false,
  deleteLockedAt: FieldValue.delete(),
  deleteLockedBy: FieldValue.delete(),
}
```

Valid lock behavior remains unchanged:

- `lockedAtMs >= cutoffMs`: skip as fresh.
- `lockedAtMs < cutoffMs`: call `finalizeGroupDeletion`.
- `failed-precondition` from valid stale finalize: compare-and-clear by `deleteLockedBy` and exact `lockedAtMs`.
- Callable-created lock with valid `lockedAtMs`: existing normal path still calls `finalizeGroupDeletion`.
- Callable-observed lock with valid `lockedAtMs`: existing retry/resume behavior remains unchanged. If the balance gate fails, the observed lock stays intact; the reaper owns stale recovery.
- Callable-observed malformed lock (`createdLock:false && lockedAtMs == null`): clear the malformed lock transactionally, log one warning, then throw `failed-precondition` from this invocation. Do not immediately create a fresh lock or finalize in the same invocation, because this invocation observed an invalid resume horizon.

Logging/counters:

- Add `malformed` to the run summary so malformed repairs are visible.
- Log one warning when clearing a malformed lock:

```ts
logger.warn('deleteGroupLockReaper malformed lock cleared', { groupId: doc.id });
```

- Log one warning when the callable clears a malformed observed lock:

```ts
logger.warn('deleteGroup malformed lock cleared', { uid, groupId });
```

Reason for clearing rather than finalizing malformed locks:

- `finalizeGroupDeletion` depends on `recomputeNet`, whose delete-resume horizon is `timestampMillis(groupData.deleteLockedAt)`.
- With a malformed timestamp the horizon is `null`, so already-soft-deleted partial-cascade events are excluded. Finalizing from that state can misclassify a settled partial cascade as unsettled or re-include the wrong historical soft-deleted events if a synthetic timestamp is invented.
- Because no shipped path creates this state, the safe defensive action is to unfreeze the group and surface a warning, not to infer a delete intent without a valid horizon. For the callable, the owner can retry after the lock is cleared; the retry creates a fresh valid lock with a real timestamp.

## Files

- Already modified in this PR: `functions/test/scheduled/deleteGroupLockReaper.test.ts`
  - Contains RED regressions for missing and malformed `deleteLockedAt`.
- Already modified in this PR: `functions/src/scheduled/deleteGroupLockReaper.ts`
  - Contains malformed-lock transaction clear path before the fresh/stale valid timestamp branch.
- Remaining modify: `functions/test/callables/deleteGroup.test.ts`
  - Add RED regressions for owner retry observing missing and string malformed locks.
- Remaining modify: `functions/src/callables/deleteGroup.ts`
  - Add callable malformed-lock clear/refuse path before rate limit, pause, or finalization.

No Firestore rules, indexes, callable exports, or client code change.

## Already Implemented In This PR: Reaper Malformed Lock Recovery

The current PR branch already contains the scheduled reaper implementation and RED/GREEN evidence for this portion:

- `functions/test/scheduled/deleteGroupLockReaper.test.ts` already has tests `4b` and `4c` for missing and string `deleteLockedAt`.
- `functions/src/scheduled/deleteGroupLockReaper.ts` already has `clearMalformedLock`, the `lockedAtMs == null` branch, `malformed` summary counting, and `deleteGroupLockReaper malformed lock cleared` logging.

Do not duplicate this work. The remaining implementation work starts below.

## Task 1: RED/GREEN Callable Malformed Lock Recovery

**Files:**
- Modify: `functions/test/callables/deleteGroup.test.ts`
- Modify: `functions/src/callables/deleteGroup.ts`

- [ ] **Step 1: Add the callable RED regression**

Add this test after the existing `20. #205 owner retry resumes a quiesced partial finalize idempotently` test:

```ts
  test('20b. #668 owner retry clears missing-timestamp observed lock and does NOT finalize', async () => {
    await seedGroup('g', {
      deletingInProgress: true,
      deleteLockedBy: OWNER,
    });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      scope: 'personal',
      payerParticipantId: OWNER,
      amountFils: 1000,
    });

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const group = (await groupSnap('g')).data();
    expect(group?.isDeleted).toBe(false);
    expect(group?.deletingInProgress).toBe(false);
    expect(group?.deleteLockedAt).toBeUndefined();
    expect(group?.deleteLockedBy).toBeUndefined();
    expect(logger.warn).toHaveBeenCalledWith(
      'deleteGroup malformed lock cleared',
      { uid: OWNER, groupId: 'g' },
    );
  });

  test('20c. #668 owner retry clears string-timestamp observed lock and does NOT finalize', async () => {
    await seedGroup('g', {
      deletingInProgress: true,
      deleteLockedAt: 'not-a-timestamp',
      deleteLockedBy: OWNER,
    });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      scope: 'personal',
      payerParticipantId: OWNER,
      amountFils: 1000,
    });

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const group = (await groupSnap('g')).data();
    expect(group?.isDeleted).toBe(false);
    expect(group?.deletingInProgress).toBe(false);
    expect(group?.deleteLockedAt).toBeUndefined();
    expect(group?.deleteLockedBy).toBeUndefined();
    expect(logger.warn).toHaveBeenCalledWith(
      'deleteGroup malformed lock cleared',
      { uid: OWNER, groupId: 'g' },
    );
  });
```

- [ ] **Step 2: Run callable RED**

Run:

```bash
RIHLA_AUTH_EMULATOR_PORT=19192 RIHLA_FIRESTORE_EMULATOR_PORT=18182 RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/deleteGroup.test.ts -t \"20b|20c\"" bash tool/run_firebase_emulator_tests.sh
```

Expected: FAIL. Current code observes `lockedAtMs:null` for both missing and string timestamps and still calls `finalizeGroupDeletion`, so the group is soft-deleted instead of rejected and unlocked.

- [ ] **Step 3: Add callable malformed-lock clear/refuse helper**

Add this helper after `clearDeleteGroupLockForFailure`:

```ts
async function clearMalformedObservedDeleteGroupLock(
  groupRef: DocumentReference,
  lockedBy: string | null,
): Promise<boolean> {
  return groupRef.firestore.runTransaction(async (tx) => {
    const groupSnap = await tx.get(groupRef);
    const groupData = groupSnap.data() ?? {};
    const curLockedBy = typeof groupData.deleteLockedBy === 'string'
      ? groupData.deleteLockedBy
      : null;
    if (
      groupData.deletingInProgress !== true
      || curLockedBy !== lockedBy
      || timestampMillis(groupData.deleteLockedAt) != null
    ) {
      return false;
    }
    tx.update(groupRef, {
      deletingInProgress: false,
      deleteLockedAt: FieldValue.delete(),
      deleteLockedBy: FieldValue.delete(),
    });
    return true;
  });
}
```

Then add this branch immediately after the `alreadyDeleted` return and before rate limiting:

```ts
    if (!lock.createdLock && lock.lockedAtMs == null) {
      if (await clearMalformedObservedDeleteGroupLock(groupRef, lock.lockedBy)) {
        logger.warn('deleteGroup malformed lock cleared', { uid, groupId });
      }
      throw new HttpsError(
        'failed-precondition',
        'Malformed delete lock was cleared. Retry group deletion.',
      );
    }
```

- [ ] **Step 4: Run callable GREEN**

Run the Step 2 command again.

Expected: PASS.

## Task 2: Verification And Handoff

**Files:**
- No additional edits.

- [ ] **Step 1: Run focused reaper suite**

Run:

```bash
RIHLA_AUTH_EMULATOR_PORT=19192 RIHLA_FIRESTORE_EMULATOR_PORT=18182 RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/scheduled/deleteGroupLockReaper.test.ts" bash tool/run_firebase_emulator_tests.sh
```

Expected: PASS.

- [ ] **Step 2: Run related deleteGroup suite**

Run:

```bash
RIHLA_AUTH_EMULATOR_PORT=19192 RIHLA_FIRESTORE_EMULATOR_PORT=18182 RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/deleteGroup.test.ts" bash tool/run_firebase_emulator_tests.sh
```

Expected: PASS.

- [ ] **Step 3: Run build/lint/diff checks**

Run:

```bash
npm --prefix functions run build
npm --prefix functions run lint
git diff --check
git status --short
```

Expected: build and lint exit 0, diff check has no output, status shows only this plan/test/source change.

- [ ] **Step 4: Commit**

Run:

```bash
git add docs/plans/2026-06-25-issue-668-delete-lock-reaper-malformed-lock.md functions/src/scheduled/deleteGroupLockReaper.ts functions/test/scheduled/deleteGroupLockReaper.test.ts functions/src/callables/deleteGroup.ts functions/test/callables/deleteGroup.test.ts
git commit -m "fix(functions): clear malformed deleteGroup locks" -m "Closes #668"
```

## Verification Principles Self-Check

1. **Callsites classified:** see "Callsite Classification." Changed paths are the scheduled reaper OUTBOUND write and the callable owner-retry OUTBOUND write.
2. **Concrete claims verified against code:** line references in "Live Code Verification" were read from live files.
3. **Read path traced:** `security/firestore.rules` `groupAllowsClientWrites` blocks client writes using `deletingInProgress`; client group/event readers observe `isDeleted` / `deletedAt` soft-delete state.
4. **Fields enumerated from code:** changed lock fields are exactly `deletingInProgress`, `deleteLockedAt`, `deleteLockedBy`; valid finalize continues to write existing `isDeleted`, `deletedAt`, `updatedAt`, `deleteFinalizedAt` through unchanged `finalizeGroupDeletion`.
5. **Data contracts spelled out:** malformed lock definition and exact update map are specified.
6. **Arithmetic decomposition checked:** no arithmetic decomposition is changed. The plan explicitly avoids finalizing malformed locks because the balance oracle's resume horizon depends on valid `deleteLockedAt`.
7. **Orthogonal axis checked:** the existing partial-cascade money-safety test remains in the focused suites and must stay green; Task 2 also reruns `deleteGroup.test.ts` for owner retry/live-lock behavior.
