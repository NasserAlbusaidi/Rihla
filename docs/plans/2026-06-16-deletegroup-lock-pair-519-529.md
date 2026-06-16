# deleteGroup Lock Pair (#519 + #529) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Spec:** Fixes #519 (stuck write-lock, no reaper) + #529 (concurrent caller clears a peer's live lock). One PR, one file (`deleteGroup.ts`) + one new scheduled fn.

**Goal:** A killed/abandoned `deleteGroup` can no longer permanently write-freeze a group, and a concurrent caller can no longer clear the lock out from under an in-progress finalize.

**Architecture:** Two changes that unify around lock lifecycle — *who may clear a lock, and how*:
1. **#529** — drop the `canClearObservedLock` branch. An invocation clears **only** a lock it created (`createdLock === true`). A concurrent observer never clears.
2. **#519** — add `deleteGroupLockReaper` (scheduled, system actor) that finds stale locks (`deletingInProgress==true`, `deleteLockedAt` older than a grace window > the 540s function timeout) and **resumes the idempotent finalize** via a shared core — completing the soft-delete if settled, or clearing the lock if unsettled. Stale-lock recovery moves from the in-band owner-retry (old test 22) to this out-of-band backstop.

**Money-safety hinge (do NOT break):** `recomputeNet` (`groupNetBalance.ts:518`) sets its resume horizon `includeSoftDeletedSinceMs = deletingInProgress===true ? timestampMillis(deleteLockedAt) : null`. A partially-flushed cascade (events soft-deleted under the lock) is correctly re-included **only while `deletingInProgress` stays true and `deleteLockedAt` is unchanged**. The reaper must therefore **never bump `deleteLockedAt`** before re-running finalize, and must never naively clear a lock that had a partial cascade (obs 28986 / balanceReconciler would then heal to an event-dropped balance). This is why the reaper *resumes finalize* rather than bare-clearing — and why a partial cascade is always settled (the balance gate passes before any mutation), so the reaper's finalize completes it instead of hitting the unsettled-clear branch.

**Tech Stack:** Firebase Cloud Functions v2 (Node 22, TS), `onSchedule`, Firestore Admin, Jest under the emulator (Java 21).

**Gate status:** Gate-category (`functions/**`, rules-adjacent lock governs `groupAllowsClientWrites`). Pre-implementation Gate REQUIRED on this spec; `/automerge` review+refute REQUIRED at merge. Deploy = human ceremony.

---

## Test harness notes (read before writing tests)

- Emulator test trap (CLAUDE.md): bare `npm test` HANGS. To scope to one file:
  ```bash
  RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand functions/test/callables/deleteGroup.test.ts" npm run test:emulator
  ```
  (run from `functions/`). For the reaper file, swap the path. A "scoped" RED can come from an unrelated suite — confirm the RED is in the file you expect.
- Existing concurrency seam: `process.env.DELETE_GROUP_PAUSE_AFTER_LOCK_MS` makes call #1 hold the lock while a second call observes it (see test 18/21). Reuse it for the #529 regression.
- Existing fixtures/helpers in `deleteGroup.test.ts`: `seedGroup(id, extra?)`, `seedMember`, `seedEvent`, `seedExpense`, `seedGroupSettlement`, `groupSnap`, `waitFor`, `wrapped`. The afterEach already deletes `DELETE_GROUP_PAUSE_AFTER_LOCK_MS` / `DELETE_GROUP_BATCH_LIMIT`.
- Reaper grace seam: add `DELETE_GROUP_LOCK_REAPER_GRACE_MS` (default > 540s) so tests can seed a "stale" lock without time travel.

---

## Task 1: Extract a shared, money-safe `finalizeGroupDeletion` core (no-op refactor)

**Why first:** the reaper (Task 3) must reuse the EXACT finalize the callable uses — no second copy to drift (mirrors the shared-`recomputeNet` oracle principle). This task changes no behavior; all existing deleteGroup tests stay green.

**Files:**
- Modify: `functions/src/callables/deleteGroup.ts` (extract lines ~254–306 into a function; rewire the callable)
- Test: `functions/test/callables/deleteGroup.test.ts` (existing tests are the regression net — no new test)

**Step 1: Add the shared core.** Insert above the callable (after `isHttpsErrorCode`):

```typescript
// Money-safe, idempotent finalize core. Reused by the callable AND the reaper
// (#519) so there is no second copy to drift. NO rate-limit, NO pause seam —
// those are callable-entry concerns. Throws FAILED_PRECONDITION (pre-mutation)
// when any per-currency bucket is unsettled; otherwise soft-deletes the live
// events + group doc and clears the lock via the finalize batch.
//
// `onMutateStart` fires immediately before the FIRST mutation (the aggregate
// delete) so the caller can mark `finalizeStarted` and preserve the
// partial-cascade money guard: a catchable error AFTER this point must leave
// the lock in place for an idempotent resume (reaper / owner retry), never
// clear it (obs: balanceReconciler would otherwise heal to an event-dropped
// balance).
async function finalizeGroupDeletion(
  db: Firestore,
  groupRef: DocumentReference,
  onMutateStart?: () => void,
): Promise<{ eventsSoftDeleted: number }> {
  const { net, liveEventRefs } = await recomputeNet(db, groupRef);
  const hasOutstanding = [...net.values()].some(
    (bucket) => [...bucket.values()].some((value) => !value.isZero()),
  );
  if (hasOutstanding) {
    throw new HttpsError(
      'failed-precondition',
      'Group has unsettled balances and cannot be deleted.',
    );
  }

  // #366: drop the balance-aggregate display cache BEFORE the group doc flips
  // isDeleted (see original inline comment — unchanged semantics).
  onMutateStart?.();
  await groupRef.collection('aggregates').doc('balance').delete();

  const now = Timestamp.now();
  const writer = new BatchWriter(db);
  for (const eventRef of liveEventRefs) {
    await writer.update(eventRef, { isDeleted: true, deletedAt: now, updatedAt: now });
  }
  await writer.update(groupRef, {
    isDeleted: true,
    deletedAt: now,
    updatedAt: now,
    deletingInProgress: false,
    deleteFinalizedAt: now,
  });
  await writer.flush();

  return { eventsSoftDeleted: liveEventRefs.length };
}
```

**Step 2: Rewire the callable body** (replace the inline recompute→gate→finalize block, current lines ~254–306) with:

```typescript
    let finalizeStarted = false;
    try {
      await enforceDeleteGroupRateLimit(db, uid);
      await pauseAfterLockIfRequested();
      const { eventsSoftDeleted } = await finalizeGroupDeletion(
        db,
        groupRef,
        () => { finalizeStarted = true; },
      );
      logger.info('deleteGroup soft-deleted group', { uid, groupId, eventsSoftDeleted });
      return { groupId, mode: 'softDelete', eventsSoftDeleted, alreadyDeleted: false };
    } catch (error) {
      if (!finalizeStarted) {
        await clearDeleteGroupLockForFailure(groupRef, lock);
      }
      throw error;
    }
```

(`clearDeleteGroupLockForFailure` loses its `error` param in Task 2; until then keep passing `error`. To keep this task a pure no-op, do Step 2 + Task 2's signature change together, OR temporarily keep the 3-arg signature. Prefer: do Task 1 Step 2 with the OLD 3-arg call, then Task 2 changes the signature + the call. Keeping tasks atomic and green.)

**Step 3: Run the full deleteGroup suite — expect ALL green (no behavior change).**
```bash
cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/deleteGroup.test.ts" npm run test:emulator
```
Expected: 22/22 pass.

**Step 4: `npm run build` (tsc) clean. Commit.**
```bash
git commit -am "refactor(functions): extract shared finalizeGroupDeletion core for deleteGroup (no-op)"
```

---

## Task 2: #529 — an invocation clears only the lock it created

**Files:**
- Modify: `functions/src/callables/deleteGroup.ts` (`clearDeleteGroupLockForFailure`, drop `canClearObservedLock`)
- Test: `functions/test/callables/deleteGroup.test.ts` (NEW regression + retarget test 22)

**Step 1: Write the failing #529 regression test.** Add after test 21. This models the true #529 harm — a fresh (live) observed lock cleared via the failed-precondition gate, breaking the write-quiesce:

```typescript
  test('23. #529 a concurrent caller does NOT clear the first invocation live lock on failed-precondition', async () => {
    // Unsettled group: BOTH overlapping owner calls will hit the balance gate.
    process.env.DELETE_GROUP_PAUSE_AFTER_LOCK_MS = '3000';
    await seedGroup('g');
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 12000,
      splitMode: 'exact',
      scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitDistribution: { [OWNER]: 6000, [MEMBER]: 6000 },
    });

    const firstDelete = wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any);
    await waitFor(
      async () => (await groupSnap('g')).data()?.deletingInProgress === true,
      'first deleteGroup quiesce lock',
    );
    const lockedAt = (await groupSnap('g')).data()?.deleteLockedAt;

    // Concurrent call #2 observes the FRESH lock, hits the unsettled gate, and
    // must NOT clear call #1's lock (pre-fix: canClearObservedLock cleared it).
    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    const during = (await groupSnap('g')).data();
    expect(during?.deletingInProgress).toBe(true);
    expect(during?.deleteLockedBy).toBe(OWNER);
    expect(during?.deleteLockedAt).toEqual(lockedAt); // untouched

    // Call #1 then also fails the gate and clears ITS OWN lock.
    await expect(firstDelete).rejects.toMatchObject({ code: 'failed-precondition' });
    const after = (await groupSnap('g')).data();
    expect(after?.deletingInProgress).toBe(false);
  });
```

**Step 2: Run it — expect FAIL** (pre-fix, call #2 clears the live lock so `during.deletingInProgress` is false).
```bash
cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand -t '#529' test/callables/deleteGroup.test.ts" npm run test:emulator
```
Expected: FAIL — `during.deletingInProgress` is `false` (call #2 cleared it).

**Step 3: Implement.** Replace `clearDeleteGroupLockForFailure` (drop the `error` param + `canClearObservedLock`):

```typescript
async function clearDeleteGroupLockForFailure(
  groupRef: DocumentReference,
  lock: { createdLock: boolean; lockedAtMs: number | null; lockedBy: string | null },
): Promise<void> {
  // #529: only the invocation that CREATED the lock may clear it on failure. A
  // concurrent observer (createdLock:false) never clears — clearing a peer's
  // live lock re-opens client writes against a group mid-finalize (quiesce
  // violation). Stale locks from a dead/abandoned invocation are reclaimed by
  // deleteGroupLockReaper (#519), not by an in-band observer.
  if (!lock.createdLock || lock.lockedAtMs == null || lock.lockedBy == null) {
    return;
  }
  const lockedAtMs = lock.lockedAtMs;
  const lockedBy = lock.lockedBy;
  await groupRef.firestore.runTransaction(async (tx) => {
    const groupData = (await tx.get(groupRef)).data() ?? {};
    if (
      groupData.deletingInProgress !== true
      || groupData.deleteLockedBy !== lockedBy
      || timestampMillis(groupData.deleteLockedAt) !== lockedAtMs
    ) {
      return;
    }
    tx.update(groupRef, {
      deletingInProgress: false,
      deleteLockedAt: FieldValue.delete(),
      deleteLockedBy: FieldValue.delete(),
    });
  });
}
```

Update the callable's catch call to the 2-arg form: `await clearDeleteGroupLockForFailure(groupRef, lock);`. Delete the now-unused `isHttpsErrorCode` helper IF nothing else references it (grep first).

**Step 4: Retarget test 22.** Its old contract (owner in-band retry clears an observed stale lock) is deliberately removed — stale-lock recovery is now the reaper's job. Rewrite it to assert the observer does NOT clear and the lock survives for the reaper:

```typescript
  test('22. #205/#529 owner retry no longer clears an observed lock in-band (reaper owns stale recovery)', async () => {
    const deleteLockedAt = new Date('2026-02-01T00:00:00.000Z');
    await seedGroup('g', { deletingInProgress: true, deleteLockedAt, deleteLockedBy: OWNER });
    await seedMember('g', OWNER);
    await seedMember('g', MEMBER);
    await seedEvent('g', 'e1');
    await seedExpense('groups/g/events/e1/expenses/x1', {
      amountFils: 12000, splitMode: 'exact', scope: 'custom',
      customSplitParticipants: [OWNER, MEMBER],
      splitDistribution: { [OWNER]: 6000, [MEMBER]: 6000 },
    });

    await expect(
      wrapped({ data: { groupId: 'g' }, auth: { uid: OWNER } } as any),
    ).rejects.toMatchObject({ code: 'failed-precondition' });

    // Observer no longer clears: the stale lock survives for deleteGroupLockReaper.
    const group = (await groupSnap('g')).data();
    expect(group?.deletingInProgress).toBe(true);
    expect(group?.deleteLockedBy).toBe(OWNER);
  });
```

> NOTE for the Gate: test 20 (`owner retry resumes a quiesced partial finalize`) is UNAFFECTED — it depends on the observer *proceeding to finalize* (settled → completes), not on observed-clear. Confirm 20 stays green.

**Step 5: Run the full suite — expect all green** (tests 1–23, with 22 retargeted).

**Step 6: `npm run build`. Commit.**
```bash
git commit -am "fix(functions): deleteGroup clears only its own lock; reaper owns stale recovery (Refs #529)"
```

---

## Task 3: #519 — `deleteGroupLockReaper` scheduled backstop

**Files:**
- Create: `functions/src/scheduled/deleteGroupLockReaper.ts`
- Create: `functions/test/scheduled/deleteGroupLockReaper.test.ts`
- Export `finalizeGroupDeletion` from `deleteGroup.ts` (add `export` keyword) so the reaper imports the shared core.

**Design:**
- Query `groups where deletingInProgress == true` (single-field equality → auto-indexed; the set is tiny and short-lived). `.limit(batch)`. Filter `deleteLockedAt < now - graceMs` in memory. Log `scanned`/`stale`/`resumed`/`cleared`, **and emit a `logger.warn` when `scanned === batch`** (cap hit → stale locks may remain for the next pass — no silent truncation). **Convergence, not immediacy:** unlike `deletionReaper` (whose server-side `where(... '<', cutoff).limit()` only ever returns reapable docs), this query has no age predicate or `orderBy`, so a cap-hit pass could return all-fresh docs and skip a stale one. Each resumed/cleared group clears `deletingInProgress`, freeing a slot, so successive hourly passes converge — a stuck group self-heals within a bounded number of passes, not necessarily the first. Acceptable given no real users + the rare trigger; the composite-index `(deletingInProgress, deleteLockedAt)` alternative (Open Question #2) is the fix if the `deletingInProgress==true` set ever grows past `batch` at steady state.
- Grace default **3600000 ms (1h)** — comfortably > the 540s function timeout, so the reaper never races a live invocation. Seam: `DELETE_GROUP_LOCK_REAPER_GRACE_MS`.
- Per stale group: call `finalizeGroupDeletion(db, groupRef)` (NO `onMutateStart` — the reaper has no `finalizeStarted` guard to maintain).
  - **Resolves** → group soft-deleted, lock cleared. `resumed++`.
  - **Throws `failed-precondition`** (unsettled) → the original op died pre-mutation (a partial cascade is always settled, so this branch implies no partial cascade). Transactionally clear the stale lock (compare-and-clear on the `deleteLockedBy`/`deleteLockedAt` we read) so the group becomes usable. `cleared++`.
  - **Throws anything else** → log + leave the lock (next pass retries). Do NOT clear.

**Step 1: Write the failing reaper tests.** Create `functions/test/scheduled/deleteGroupLockReaper.test.ts` (model boot/seed helpers on `deleteGroup.test.ts`). Cases:
1. **stale + settled → resumes & completes**: seed group `{deletingInProgress:true, deleteLockedAt: <2h ago>, deleteLockedBy: OWNER}`, a balanced expense+settlement, a not-yet-soft-deleted event. Run reaper. Assert group `isDeleted:true`, `deletingInProgress:false`, event `isDeleted:true`.
2. **stale + settled + PARTIAL cascade → resumes idempotently**: as above but the event is already `isDeleted:true` with `deletedAt` AFTER `deleteLockedAt` (simulating a flushed partial batch). Assert balance still computed correctly (group completes, no throw) — guards the resume-horizon money-safety.
3. **stale + unsettled → clears lock, group NOT deleted**: seed `{deletingInProgress:true, deleteLockedAt:<2h ago>}` + an unbalanced expense. Run reaper. Assert `deletingInProgress:false`, `deleteLockedAt` cleared, `isDeleted` still false/absent.
4. **fresh lock → untouched**: seed `{deletingInProgress:true, deleteLockedAt: now}`. Run reaper. Assert `deletingInProgress` still true, `deleteLockedAt` unchanged.
5. **no lock → no-op**: seed a normal live group. Run reaper. Assert unchanged + `scanned:0`.

Invoke the reaper handler directly (it takes no event payload): `await reaperWrapped({} as any)` via `firebase-functions-test` `wrap`, matching how `deletionReaper` is tested (check `functions/test/scheduled/` for the existing pattern — reuse it).

**Step 2: Run — expect FAIL** (module does not exist).
```bash
cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/scheduled/deleteGroupLockReaper.test.ts" npm run test:emulator
```

**Step 3: Implement `deleteGroupLockReaper.ts`:**

```typescript
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import '../admin';
import { finalizeGroupDeletion } from '../callables/deleteGroup';
import { timestampMillis } from '../callables/groupNetBalance';

// #519: backstop for the "deleteGroup killed mid-finalize / creator never
// retries" tail. A hard kill (540s timeout, OOM, infra) after the lock is
// acquired leaves `deletingInProgress:true`, which freezes ALL client writes
// via groupAllowsClientWrites (firestore.rules) — permanently, with no in-band
// recovery once the creator is gone. This job reclaims stale locks: it resumes
// the SHARED idempotent finalize (settled → completes the soft-delete; unsettled
// → clears the lock so the group is usable). Money-safe: it never bumps
// deleteLockedAt, so recomputeNet's resume horizon still re-includes a partially
// flushed cascade.
const DEFAULT_GRACE_MS = 60 * 60 * 1000; // > 540s function timeout: never race a live invocation
const DEFAULT_BATCH = 50;

const resolveGraceMs = (): number =>
  Number(process.env.DELETE_GROUP_LOCK_REAPER_GRACE_MS) || DEFAULT_GRACE_MS;
const resolveBatch = (): number =>
  Number(process.env.DELETE_GROUP_LOCK_REAPER_BATCH) || DEFAULT_BATCH;

export const deleteGroupLockReaper = onSchedule(
  { schedule: 'every 1 hours', timeoutSeconds: 540, memory: '1GiB' },
  async () => {
    const db = getFirestore();
    const cutoffMs = Date.now() - resolveGraceMs();
    // deletingInProgress==true is rare + short-lived → tiny set; age-filter in
    // memory to avoid a composite index. Batch-capped; log if truncated.
    const locked = await db
      .collection('groups')
      .where('deletingInProgress', '==', true)
      .limit(resolveBatch())
      .get();

    let resumed = 0;
    let cleared = 0;
    let stale = 0;
    for (const doc of locked.docs) {
      const data = doc.data();
      const lockedAtMs = timestampMillis(data.deleteLockedAt);
      if (lockedAtMs == null || lockedAtMs >= cutoffMs) continue; // fresh — skip
      stale += 1;
      const lockedBy = typeof data.deleteLockedBy === 'string' ? data.deleteLockedBy : null;
      try {
        await finalizeGroupDeletion(db, doc.ref);
        resumed += 1;
      } catch (error) {
        if (error != null && typeof error === 'object'
          && (error as { code?: unknown }).code === 'failed-precondition') {
          // Pre-mutation gate → no partial cascade → safe to clear the stale
          // lock (compare-and-clear so we never clobber a refreshed lock).
          await db.runTransaction(async (tx) => {
            const cur = (await tx.get(doc.ref)).data() ?? {};
            if (cur.deletingInProgress !== true
              || cur.deleteLockedBy !== lockedBy
              || timestampMillis(cur.deleteLockedAt) !== lockedAtMs) {
              return;
            }
            tx.update(doc.ref, {
              deletingInProgress: false,
              deleteLockedAt: FieldValue.delete(),
              deleteLockedBy: FieldValue.delete(),
            });
          });
          cleared += 1;
        } else {
          logger.error('deleteGroupLockReaper finalize error', {
            groupId: doc.id,
            error: error instanceof Error ? error.message : String(error),
          });
        }
      }
    }

    if (locked.size === resolveBatch()) {
      // Cap hit with no age-predicate/orderBy on the query → some stale locks
      // may be unscanned this pass. They self-heal on a later pass as slots free
      // up (each cleared group drops deletingInProgress). Never silent.
      logger.warn('deleteGroupLockReaper batch cap hit — stale locks may remain for next pass', {
        batch: resolveBatch(),
      });
    }
    logger.info('deleteGroupLockReaper run', {
      scanned: locked.size, stale, resumed, cleared,
    });
  },
);
```

**Step 4: Run reaper tests — expect all green.** Re-run the deleteGroup suite too (the `export` on `finalizeGroupDeletion` is the only delta there — stays green).

**Step 5: `npm run build`. Commit.**
```bash
git commit -am "feat(functions): deleteGroupLockReaper resumes stale deleteGroup locks (Refs #519)"
```

---

## Task 4: Wire the export + deploy-set lock

**Files:**
- Modify: `functions/src/index.ts` (add re-export)
- Verify: `tool/list_expected_functions.sh` picks it up; `test/unit/release_workflow_gate_test.dart` stays green.

**Step 1:** Add after the `balanceReconciler` line in `index.ts`:
```typescript
export { deleteGroupLockReaper } from './scheduled/deleteGroupLockReaper';
```

**Step 2: Verify the extractor sees it (deploy drift-check source of truth):**
```bash
bash tool/list_expected_functions.sh | grep deleteGroupLockReaper   # must print the name
```

**Step 3: Run the release-workflow gate test (Dart):**
```bash
flutter test test/unit/release_workflow_gate_test.dart
```
Expected: green (the new fn is a proper `export { } from` re-export).

**Step 4: Commit.**
```bash
git commit -am "feat(functions): register deleteGroupLockReaper in index.ts (Refs #519)"
```

---

## Task 5: Whole-suite verification + ship

**Step 1:** Full Functions suite under the emulator (no `-t` filter):
```bash
cd functions && npm run test:emulator
```
Expected: all green, incl. new reaper file + retargeted deleteGroup suite.

**Step 2:** `flutter analyze` clean (Dart side untouched, but the gate test ran). `cd functions && npm run build` clean.

**Step 3:** Open PR. Body carries:
- `Refs #519` and `Refs #529` (PARTIAL by definition — a backend fix isn't "done" until deployed + the human deploy ceremony runs; per the merge-hygiene rule, partial → `Refs`, and put `Refs #519` / `Refs #529` in the **commit message** too, since squash-merge auto-closes from the squashed commit body). Issues stay OPEN re-scoped to "deploy".
- `Spec:` line pointing at this plan.
- RED evidence: pasted failing-before-fix output for test 23 (#529) and the reaper RED.
- **Semantic-change note (so the refuter doesn't read it as an accidental delta):** `onMutateStart` fires immediately BEFORE the `aggregates/balance` delete, whereas live code set `finalizeStarted` AFTER it. Deliberate: the aggregate delete is a mutation, so a throw there must now leave the lock for idempotent resume (was: cleared). No existing test asserts lock-clearing on aggregate-delete failure, so nothing breaks; `balanceReconciler` heals a stranded aggregate.

**Step 4:** `/automerge <PR>` — Gate-category (`functions/**`) → fresh-context Opus review + refuter before auto-merge enables.

**Step 5 (separate, human ceremony):** After merge → `deploy-ceremony` skill. `deleteGroupLockReaper` is a NEW Cloud Scheduler surface (2nd scheduled fn family). Verify it appears in `check_firebase_prod_state.sh` expected set and is CREATED in prod. Advance the `backend-deployed` tag. Record in `docs/DEPLOY-LEDGER.md`. Then comment `Closes #519` / `Closes #529` (or close manually) once prod-verified.

---

## Open questions for the Gate

1. **Grace window (1h).** Long enough to never race a 540s invocation; short enough that a stuck group self-heals within ~2h. Reasonable, or tie it to a named constant shared with the timeout?
2. **Reaper query without composite index.** Relies on `deletingInProgress==true` being a tiny, short-lived set (age-filtered in memory, batch-capped + logged). If that assumption is wrong at scale, a composite index on `(deletingInProgress, deleteLockedAt)` is the alternative (adds a `firestore.indexes.json` deploy surface + index-build timing). Acceptable as-is given no real users + rare trigger?
3. **Dropping in-band stale recovery (test 22 retarget).** Owner fast-recovery now waits for the reaper instead of an immediate retry-clear. Acceptable given the reaper backstop + rare trigger, or should `acquireDeleteGroupLock` also reclaim a stale lock on owner retry (careful: must NOT bump `deleteLockedAt` or it breaks the resume horizon)?
