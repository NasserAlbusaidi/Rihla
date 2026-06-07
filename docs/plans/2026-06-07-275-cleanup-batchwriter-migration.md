# #275 — Migrate `cleanupAnonUidArtifacts.processGroup` off the 500-write transaction cliff to `deleteAccount`'s chunked `BatchWriter`

Follow-up explicitly deferred by **#217 §5** (`docs/plans/2026-06-05-217-activity-log-uid-migration.md:198-210`). #216 (PR #218, `a545509`) put the financial migration in the per-group transaction; #217 (PR #274, merged, issue CLOSED) added the highest-volume activity-log writes. Both ride the same cliff. #275 removes it for the whole cascade.

## 1. Problem (verified against code)

`cleanupAnonUidArtifacts.processGroup` (`functions/src/callables/cleanupAnonUidArtifacts.ts:263-489`) does **all** per-group migration inside **one `db.runTransaction`**. Firestore caps a transaction at **500 writes** (each `FieldValue.serverTimestamp()` counts as an extra write; reads are uncapped). The migrated writes are guarded (`tx.update` fires only for docs that reference `oldUid`), so the write count is bounded by the recovering user's **own footprint** in the group — but a dense, long-lived anon account (exactly the recovery-target population: tens-to-hundreds of expenses × activity-log-per-mutation) can plausibly exceed 500 writes in a single group.

**Failure mode (non-convergent):** the group's transaction exceeds 500 → throws → handler pushes the group to `cascadeFailed` (`:535`) → `oldUid` Auth user is preserved (`:595`) → client retries → **the same transaction throws again** → that group never converges. Data stays safe; cleanup never completes; the `oldUid` Auth user + `recoveryCleanupIntents/{oldUid}` doc + identity residue persist.

**Scope of the fix (precise — do not overclaim):** this PR removes the **500-write-cliff** sub-cause of non-convergence ONLY. A *separate*, pre-existing non-convergence vector remains and is **out of scope**: a malformed child doc (e.g. `participantIds` is a string, not an array) makes `getStringArray`/`getStringMap` (`:55-76`) throw on **every** pass, so that group is pushed to `cascadeFailed` every retry and never converges — identical in the current transaction code and in this rewrite (the current code throws on the same malformed doc in its read phase; `test:799-842` deliberately seeds this as the "bad" group). #275 neither fixes nor worsens that vector. (A follow-up could validate/quarantine malformed docs, but that is a different defect.)

## 2. Fix (the issue-directed approach)

Migrate the **entire** per-group cascade from `runTransaction` to the chunked **`BatchWriter`** pattern that `deleteAccount`/`deleteGroup` already use (`functions/src/callables/deleteGroup.ts:45-69`; `deleteAccount.ts:78-116`, "batched, may span auto-flushes"). The `BatchWriter` auto-flushes at `≤limit` (default **450**), removing the cliff for the whole cascade (events + expenses + settlements + activity child scrubs) plus a small bounded transaction for the member/group identity writes.

**Limit rationale (corrected — the naive "headroom for transforms" framing is wrong).** Firestore's cap is 500 writes per commit and a `FieldValue.serverTimestamp()` transform counts as an additional write against that cap (#217 §5, Firebase-docs-verified). So 450 is **not** simply "50 of headroom for transforms" — 450 transform-bearing writes would be 900 against the cap. 450 is safe here because **transforms are sparse**: in this cascade only **event** updates carry `updatedAt: serverTimestamp()` (current `:367`); expense/settlement/activity updates carry **none** (`:412/:435/:469`), and events-with-`oldUid`-per-group is small (tens, not hundreds). 450 also **matches deleteAccount (450) and deleteGroup (450)**, which have the identical sparse-transform write profile and are deployed. **Guard:** if a future change adds a `serverTimestamp` (or any transform) to a high-volume write (expense/activity), this limit MUST be halved (≤250). Documented as a comment at the seam.

This is the **correct scope** (the financial contribution from #216 also rides the cliff) — deliberately **not** bolted onto #217. The migration semantics (WHICH docs/fields change) are **unchanged byte-for-byte**; only the execution mechanism (one transaction → chunked batch + a small bounded transaction) changes.

## 3. Why this is safe — the convergence contract (the load-bearing argument the Gate must scrutinise)

A `runTransaction` gives per-group **atomicity**. `BatchWriter` is **non-atomic across flushes** (each `batch.commit()` is atomic up to the limit, but a torn cascade can leave some flushes committed and a later one failed). This is acceptable **only if** the cascade is **idempotent + convergent-on-retry** — the exact contract `deleteAccount` (#46) already relies on. `cleanupAnonUidArtifacts` already satisfies it; this rewrite preserves it.

### 3a. Every migration op is idempotent (no-op on a second run after a partial migration)

Re-derived from the code (`cleanupAnonUidArtifacts.ts`), per op:

| Op | Mechanism | Idempotent because |
|---|---|---|
| group `memberIds` | `replaceUid` (`:78`) | 2nd run: `oldUid` already gone → maps to itself → no change |
| group/event/expense/settlement `createdBy` | `=== oldUid → newUid` | 2nd run: field is `newUid`, not `oldUid` → skip |
| member copy | guarded `!newMemberExists && oldMemberDocs.length>0` | 2nd run: `newMember` exists → skip |
| member delete | iterates `oldMemberDocs` (userId===oldUid) | 2nd run: those docs deleted → empty → skip |
| event `participantIds` | `replaceUid` | as group `memberIds` |
| event `participantNames` | rename guarded by `hasOwnProperty(oldUid)` | 2nd run: `oldUid` key gone → skip |
| expense `payerParticipantId` / `customSplitParticipants` | `=== oldUid` / `replaceUid` | as above |
| **expense `splitDistribution`** | `mergeUidMapKey` (`:103`) — **sums on collision** | **load-bearing:** sums ONLY when `oldUid` key is still present (`:112`); after the first write removes it, the retry sees no `oldUid` key → `changed:false` → no write → **no double-sum** |
| event/group settlement | `settlementMigrationUpdate` (`:133`) | 2nd run: no `oldUid` ref → returns null → skip |
| event/group activity | `activityMigrationUpdate` (`:186`) → `migrateMetadataValue` (pure substitution, `:161`) | 2nd run: no `oldUid` → returns null → skip |

The only summing op (`splitDistribution`) is the one most at risk under non-atomic retry, and it is provably idempotent because the sum is gated on the source key's continued presence. A single `batch.update(ref, {splitDistribution: …})` replaces the **whole field** (not a dotted-path merge), so the read-modify-write of `splitDistribution` is whole-field-atomic per commit — there is no sub-field tearing. **This is the single fact a non-atomic retry could have broken; it does not.**

**Cross-collection consistency is NOT required (the hole a reviewer could drive through, closed):** under the rewrite, Phase B's reads are separate non-transactional `.get()`s, so they are no longer a single consistent snapshot like the old transaction. This is safe because **each per-doc migration depends only on that doc's own current `oldUid` presence — never on cross-collection or cross-doc consistency.** No op reads doc A to decide how to write doc B. Therefore a torn cross-collection read view cannot corrupt; at worst it under-migrates a doc this pass, which the next retry (or the same pass, since each doc is read immediately before its own write) handles idempotently.

### 3b. The retry query must keep finding the group until convergence

The handler's retry driver is `groups where memberIds array-contains oldUid` (`:515-518`). Convergence depends on the group staying **query-visible** until every child-doc migration is durable. Therefore the write that removes `oldUid` from `memberIds` (group update) **must not commit before all child scrubs are durable.**

`deleteAccount` enforces this with a strict **Phase B (child scrubs, batched) → flush → Phase C (identity retirement, transactional)** ordering (`:464-553` then `:556-609`); none of the three identity-visibility writes land before Phase B is durable. **#275 mirrors this exactly.** The current cleanup code writes the group `memberIds` update *first* (`:322`), which is only safe because the whole thing is one atomic transaction — under chunked batching that ordering would be a convergence bug, so the rewrite **reorders**: child scrubs first, identity (member + `memberIds`) last.

### 3c. Torn-cascade walk (each leaves a convergent state)

- **Phase B flush N fails (transient/cliff cause):** `processGroup` throws → group → `cascadeFailed` → Auth preserved → retry → Phase A re-reads (`memberIds` still has `oldUid`, group still visible) → Phase B re-runs (committed migrations are idempotent no-ops, remaining ones apply, and chunking means no single flush ever exceeds the limit) → … → Phase C → converged. (Does **not** cover the malformed-doc cause from §2 — a `getStringArray` throw recurs every pass and never converges, pre-existing and out of scope.)
- **Phase B all durable, Phase C transaction throws:** group → `cascadeFailed` → retry → Phase B no-ops → Phase C re-runs (re-reads `memberIds`, still has `oldUid`) → converged.
- **Phase C commits:** done. `memberIds` no longer has `oldUid` → group leaves the retry query.
- **uid raced out of `memberIds` between Phase A and Phase C** (double-invocation): Phase C re-read finds `oldUid` absent → no-op skip; the already-applied Phase B migrations were idempotent. No corruption.

### 3d. Accepted residual — concurrent-write orphan (money-adjacent in recovery; the atomicity trade-off the issue explicitly sanctions)

Non-transactional reads can be stale: if a concurrent write adds a new `oldUid`-referencing child doc *after* Phase B's read but *before* Phase C removes `oldUid` from `memberIds`, that doc is not migrated this invocation, and once Phase C removes `oldUid` the group leaves the retry query → the ref is orphaned under the about-to-be-auth-deleted `oldUid`.

**Honest severity (corrected from an earlier "same as deleteAccount" hand-wave).** The old transaction's serializable isolation *would* have caught this: a concurrent insert into a collection the transaction queried forces an abort+retry, re-reading and migrating the new doc. The batch rewrite loses that. And unlike `deleteAccount` (where the orphan is pure identity-residue for a departing user), in **recovery** the orphan can be **money-adjacent**: another group member, whose client still shows the stale `oldUid`, adds an expense/settlement listing `oldUid` as payer/participant/split during the seconds-long cleanup window → that money ref strands under the deleted UID, understating the recovered person's balance until corrected.

**Why it is nonetheless accepted:**
1. The issue text **explicitly sanctions this trade-off**: "The transaction gives per-group atomicity. `deleteAccount`'s BatchWriter is non-atomic but relies on the cascade being idempotent + convergent-on-retry — which `cleanupAnonUidArtifacts` already is." Removing atomicity is the named cost of removing the cliff.
2. The only fully-atomic alternative is exactly the single transaction we are removing to fix the cliff — there is no cheap middle ground (re-scanning all child collections inside Phase C *is* the cliff again).
3. Window is seconds (one recovery invocation); `oldUid` itself is abandoned (the recovered client writes as `newUid`); the racing writer is another member with a stale roster, a narrow timing coincidence.
4. **Recoverable, not silent corruption:** the stranded ref is a real document, discoverable; it does not double-count or destroy money. If observed, a re-run of recovery (within the 15-min intent window) or a manual data fix repoints it.

Net: a genuine, narrow, money-adjacent residual — the explicit price of escaping the cliff — not a silent corruption. Flagged here so it is a known accepted risk, not a discovered surprise.

## 4. Exact implementation

### 4a. Inline a per-callable `BatchWriter` (follow the established project precedent — do NOT extract a shared module)

**Decision reversal after the Gate.** An earlier draft proposed extracting `BatchWriter` to `functions/src/util/batch_writer.ts` and rewiring `deleteAccount`. The Gate surfaced that the project has a **deliberate, documented precedent against this**: `deleteGroup.ts:35-36` keeps its **own** inlined `BatchWriter` + `DELETE_GROUP_BATCH_LIMIT` seam *specifically* "so the deleteAccount cascade stays untouched." There are already **two** intentional copies (deleteAccount + deleteGroup), each with its own seam. The locally-idiomatic, lowest-blast-radius choice is therefore to **add a third inline copy** in `cleanupAnonUidArtifacts.ts` with its own `CLEANUP_BATCH_LIMIT` seam — NOT to extract.

Benefits: `deleteAccount.ts` and `deleteGroup.ts` are **100% untouched** (zero regression risk, no Gate/PR surface bleed into two other money/recovery callables), one-PR-one-thing holds, and it matches the pattern a maintainer already expects.

Cleanup's Phase B only needs `update` + `flush` (Phase B never `set`/`delete`s — the member copy/delete is in Phase C's transaction), so the closest template is `deleteGroup.ts:45-69`'s **update-only** writer, copied verbatim with the seam renamed:

```ts
import { DocumentData, DocumentReference, Firestore, WriteBatch } from 'firebase-admin/firestore';

// Batch writer (≤450-op auto-flush). Local to this callable with its OWN test
// seam (CLEANUP_BATCH_LIMIT) so the deleteAccount / deleteGroup cascades stay
// untouched — mirrors deleteGroup.ts's deliberate per-callable copy.
// LIMIT GUARD: only event updates here carry a serverTimestamp transform (which
// counts as +1 against Firestore's 500-write commit cap); expense/settlement/
// activity updates carry none, so 450 is safe. If a transform is ever added to a
// high-volume write, halve this to ≤250.
const DEFAULT_BATCH_LIMIT = 450;

function resolveBatchLimit(): number {
  return Number(process.env.CLEANUP_BATCH_LIMIT) || DEFAULT_BATCH_LIMIT;
}

class BatchWriter {
  private batch: WriteBatch;
  private writes = 0;
  private readonly limit: number;

  constructor(private readonly db: Firestore) {
    this.batch = db.batch();
    this.limit = resolveBatchLimit();
  }

  async update(ref: DocumentReference, data: DocumentData): Promise<void> {
    this.batch.update(ref, data);
    this.writes += 1;
    if (this.writes >= this.limit) {
      await this.flush();
    }
  }

  async flush(): Promise<void> {
    if (this.writes === 0) return;
    await this.batch.commit();
    this.batch = this.db.batch();
    this.writes = 0;
  }
}
```

Add `Firestore`, `WriteBatch` to the existing `firebase-admin/firestore` import in `cleanupAnonUidArtifacts.ts` (currently imports `DocumentData, DocumentReference, FieldValue, Timestamp, getFirestore`). `deleteAccount.ts` and `deleteGroup.ts` are **not modified.**

### 4b. Rewrite `cleanupAnonUidArtifacts.processGroup` (the substance)

The `CLEANUP_BATCH_LIMIT` seam lives inside the inline `BatchWriter` block (§4a), resolved at construction like `deleteGroup`'s.

`processGroup(groupRef, oldUid, newUid): Promise<string[]>` becomes three phases. **All helper functions (`replaceUid`, `getStringArray`, `getStringMap`, `mergeUidMapKey`, `settlementMigrationUpdate`, `activityMigrationUpdate`, `toFiniteNumber`, `migrateMetadataValue`) are unchanged.** Migration predicates are preserved exactly (active-events-only for expenses/settlements/activity; ALL events for participant migration; `createdBy` only for non-deleted events; soft-deleted expenses skipped).

**TWO MANDATORY IMPLEMENTATION RULES (Gate R2 P2 — these are correctness traps, not style):**

- **R-A: `for...of`, never `.forEach`, around any `writer.update`.** The current code uses `activeEventSnaps.forEach((snap, i) => { … tx.update(…) })` (`:380/:427/:460`) — that is only safe because `tx.update` is **synchronous**. `writer.update` is **async** (it `await`s the auto-flush at the limit). A `forEach` callback swallows the returned promise → the `await` is not honored → the auto-flush is not awaited → writes race and the 450 gate silently no-ops. **Every Phase B loop that calls `writer.update` must be `for (const … of …)`** (mirror `deleteAccount.ts:470-529`, which uses `for...of` for exactly this reason). Do NOT copy the cleanup `forEach` idiom.
- **R-B: keep the parallel `Promise.all` read pre-fetch (do not regress to serial reads).** The current code pre-fetches expenses/settlements/activity with `Promise.all` (`:295-311`). Reads do NOT need to be in the writer's flush cadence — only writes do. Pre-fetch all collection reads in parallel via plain `.get()` (non-transactional), THEN iterate with `for...of` staging `writer.update`s. Serial per-event reads would multiply latency by event-count against the 540s budget for exactly the dense-account population this PR targets. Pre-fetched read arrays are correlated to `activeEventSnaps` by index, as today.

- **Phase A — reads + guard (non-transactional):**
  - `const db = getFirestore(); const newMemberRef = groupRef.collection('members').doc(newUid);`
  - `const groupSnap = await groupRef.get();` → if `!exists` return `[]`.
  - `getStringArray(groupData, 'memberIds', …)`; if `!memberIds.includes(oldUid)` return `[]`.
  - `const eventsSnap = await groupRef.collection('events').get();`
  - `const activeEventSnaps = eventsSnap.docs.filter(e => e.data().isDeleted !== true);`
- **Phase B — pre-fetch reads (parallel) then child scrubs (batched, `for...of`):** delete the now-obsolete all-reads-before-writes comments (`:298-300`, `:305-307`) — that transaction invariant no longer applies once reads are non-transactional; leaving them would assert a false contract in money-handling code. Pre-fetch in parallel (plain `.get()`, per R-B): `const [expenseSnaps, eventSettlementSnaps, eventActivitySnaps] = await Promise.all([Promise.all(activeEventSnaps.map(e => e.ref.collection('expenses').get())), Promise.all(activeEventSnaps.map(e => e.ref.collection('settlements').get())), Promise.all(activeEventSnaps.map(e => e.ref.collection('activity_logs').get()))]); const groupSettlementsSnap = await groupRef.collection('settlements').get(); const groupActivitySnap = await groupRef.collection('activity').get();` Then `const writer = new BatchWriter(db);` `const actions: string[] = [];` and stage writes with `for...of` (per R-A):
  - **Events (ALL `eventsSnap.docs`):** `for (const eventSnap of eventsSnap.docs)` — build `eventUpdate` exactly as today (`participantIds`/`participantNames`/`createdBy`-if-`isDeleted!==true` + `updatedAt`); `await writer.update(eventSnap.ref, eventUpdate)`; push `events.${id}`.
  - **Expenses (active events):** `for (let i=0; i<activeEventSnaps.length; i++) for (const expenseSnap of expenseSnaps[i].docs)` — skip `isDeleted===true`; build `expenseUpdate` exactly as today (`createdBy`/`payerParticipantId`/`customSplitParticipants`/`splitDistribution` via `mergeUidMapKey`); `await writer.update(...)`; push `expenses.${eid}.${xid}`.
  - **Event settlements (active events):** iterate `eventSettlementSnaps[i].docs`; `settlementMigrationUpdate`; `await writer.update(...)`; push `settlements.${eid}.${sid}`.
  - **Group settlements:** iterate `groupSettlementsSnap.docs`; same; push `settlements.group.${sid}`.
  - **Event activity_logs (active events):** iterate `eventActivitySnaps[i].docs`; `activityMigrationUpdate(..., true)`; `await writer.update(...)`; push `activity_logs.${eid}.${aid}`.
  - **Group activity:** iterate `groupActivitySnap.docs`; `activityMigrationUpdate(..., false)`; `await writer.update(...)`; push `activity.${aid}`.
  - `await writer.flush();`
- **Phase C — transactional identity retirement (bounded, runs after B is durable):**
  ```ts
  const retired = await db.runTransaction(async (tx) => {
    const gSnap = await tx.get(groupRef);
    if (!gSnap.exists) return { applied: false, createdByMigrated: false, copied: false, deleted: 0, removed: false };
    const gData = gSnap.data() ?? {};
    const currentMemberIds = getStringArray(gData, 'memberIds', `groups/${groupRef.id}`);
    if (!currentMemberIds.includes(oldUid)) {
      return { applied: false, createdByMigrated: false, copied: false, deleted: 0, removed: false };
    }
    const membersSnap = await tx.get(groupRef.collection('members'));
    const oldMemberDocs = membersSnap.docs.filter((d) => d.data().userId === oldUid);
    const newMemberExists = membersSnap.docs.some((d) => d.data().userId === newUid);

    const nextMemberIds = replaceUid(currentMemberIds, oldUid, newUid);
    const groupUpdate: Record<string, unknown> = { memberIds: nextMemberIds, updatedAt: FieldValue.serverTimestamp() };
    const createdByMigrated = gData.createdBy === oldUid;
    if (createdByMigrated) groupUpdate.createdBy = newUid;

    let copied = false;
    if (!newMemberExists && oldMemberDocs.length > 0) {
      tx.set(newMemberRef, { ...(oldMemberDocs[0].data() ?? {}), id: newUid, userId: newUid });
      copied = true;
    }
    for (const d of oldMemberDocs) tx.delete(d.ref);
    tx.update(groupRef, groupUpdate);
    return {
      applied: true, createdByMigrated, copied, deleted: oldMemberDocs.length,
      removed: currentMemberIds.includes(newUid),
    };
  });
  ```
  After the transaction, append observability-equivalent action strings (`group.createdBy`, `group.memberIds.removeOldUid`/`replaceOldUid`, `members.copyOldToNew`, `members.deleteOld`×N) so the handler's existing `logger.info('… group write', { actions })` keeps its content. Return `actions`. (Gate R2 P3: the action-string **set** is preserved; **order** changes — child actions now precede identity actions, since Phase C runs last. No consumer reads `actions` order — the handler only `logger.info`s it, and tests mock the logger — so this is harmless.)

The **handler** (`:491-618`) is **unchanged** — `processGroup` still returns `string[]`, still throws on failure → `cascadeFailed`, `groupsProcessed` still increments on non-throw.

### 4c. Note re Phase C re-validation

Phase C re-reads `memberIds` transactionally before the identity writes (the deleteAccount Phase C pattern). This both (a) handles the raced-out-of-membership case as a clean skip and (b) keeps the identity retirement atomic. Phase C's write count is bounded (1 group update + ≤1 member copy + N member deletes; realistically ≤3), so it cannot itself hit the cliff.

## 5. Test plan (RED → GREEN; Jest + emulator) — `functions/test/callables/cleanupAnonUidArtifacts.test.ts`

The existing 25 tests are the behaviour-preservation guard — they must stay green unchanged **except** the one whose mechanism the rewrite invalidates (5c).

**MANDATORY test-isolation fix first (Gate P1-2).** The cleanup test file's `beforeEach` (`:117-124`) does NOT reset batch-limit env vars (unlike `deleteAccount.test.ts:108-109` which does `delete process.env.DELETE_ACCOUNT_BATCH_LIMIT`). The new `CLEANUP_BATCH_LIMIT` seam introduces global-mutable state; a leak would silently force chunking onto the money-conservation tests (`:370`, `:676`) and could change their commit topology. So: **add `delete process.env.CLEANUP_BATCH_LIMIT;` to the existing `beforeEach`**, and wrap every per-test `process.env.CLEANUP_BATCH_LIMIT = …` in `try { … } finally { delete process.env.CLEANUP_BATCH_LIMIT; }` (mirrors `deleteAccount.test.ts:624/658`). Without this the suite is order-dependent.

1. **NEW — chunk-spanning convergence (the regression that proves the cliff is gone).** Set `process.env.CLEANUP_BATCH_LIMIT = '3'` (in `try/finally`). Seed one group with `oldUid` member + enough `oldUid`-referencing child docs that the cascade exceeds the limit across **multiple flushes** (e.g. 5+ active expenses each touching `oldUid`). Assert: `cascadeFailed: []`, `authUserDeleted: true`, **every** seeded `oldUid` ref migrated to `newUid` (group `memberIds`, member doc, each expense `payerParticipantId`/`splitDistribution`), and the `oldUid` Auth user is gone. This test would **FAIL on the current single-transaction code only if** the doc count exceeded 500 — too large to seed; instead it asserts correctness *with chunking forced on*, proving multi-flush spanning produces the identical end state. It is a GREEN-only correctness surrogate (honest framing: it does **not** RED on the un-seedable 500-cliff; the structural RED is 5a). This mirrors exactly how `deleteAccount.test.ts:622` (`DELETE_ACCOUNT_BATCH_LIMIT='2'`) proves its torn-multi-batch convergence.
2. **NEW — idempotent re-run after a torn Phase C (no double-sum: the load-bearing §3a guarantee under torn-batch retry).** Seed the both-members `splitDistribution` collision (`old=1000,new=500 → 1500`). First `cleanupCall()` with a spy on `Transaction.prototype.update` that rejects when `ref.path === 'groups/g1'` (fires only in Phase C — Phase B uses `WriteBatch`, so Phase B commits, Phase C throws) → assert `cascadeFailed: ['g1']`, expense `splitDistribution['new-uid'] === 1500` (Phase B summed once), `memberIds` still contains `old-anon-uid` (Phase C did not commit), Auth + intent preserved. Restore the spy, second `cleanupCall()` → assert convergence: `memberIds` migrated, `splitDistribution['new-uid']` **still 1500** (NOT 2000 — proves no double-sum on retry: `mergeUidMapKey` saw no `oldUid` key the 2nd pass), `authUserDeleted: true`.
3. **NEW — ordering: a Phase B write failure leaves the group query-visible (`oldUid` still in `memberIds`).** Seed a group with an `oldUid`-referencing child doc; spy `WriteBatch.prototype.commit` to reject (the Phase B flush) → assert group `memberIds` still contains `oldUid` (the Phase C group update never ran), `cascadeFailed: ['g1']`, Auth preserved, intent preserved. Proves the §3b reorder (child scrubs before identity).
4. **Preserved (unchanged):** all #216/#217 migration tests (expense payer/split/customSplit, settlements, activity, soft-deleted skips, both-members collision dup-vs-sum, participant migration, **`createdBy` across surfaces — incl. the assertion that a *deleted* event's `createdBy` stays `old-anon-uid` while its participantIds still migrate, `test:269/305`**, #294 uuid-keyed creator doc, member copy/delete, both-UIDs survivor, missing-intent rejection, anon/equal-uid rejection, fcm/joinAttempts gates, auth-not-found, **the "per-group failure preserves auth user" test `:799` whose malformed-`participantIds` event must still throw in Phase B before any flush so `bad` stays untouched**). They must pass byte-for-byte against the rewritten internals (same migration semantics).
5. **MECHANISM-UPDATED (not assertion-patched):**
   - **5c.** `#217 activity write failure gates auth delete + preserves intent` (`:729`) currently spies `Transaction.prototype.update` to reject on `activity_logs` refs. After the rewrite, activity writes go through `WriteBatch` (Phase B), not a transaction → the existing spy never fires. **Retarget the spy to `WriteBatch.prototype.commit`** (the mechanism the suite already proves works — `deleteAccount.test.ts:644` spies `WriteBatch.prototype.commit`; there is *no* existing precedent for spying `WriteBatch.prototype.update`, which may be a bound/instance method that the prototype spy never intercepts → a false GREEN). The test's seeded group has **only** an activity-log doc (no expenses/settlements), so the single Phase B flush *is* the activity write → rejecting that `commit` is precisely an activity-write failure. **Assertions unchanged** (`cascadeFailed:['g1']`, `authUserDeleted:false`, Auth + intent preserved). During TDD, confirm the spy actually fires (forced failure observed → `cascadeFailed:['g1']`) so the RED is for the right reason, not a no-op. This is a mechanism change forced by the implementation change, not a weakening — it still proves an activity-write failure enters the gate.
   - **5a (genuine architecture-distinguishing RED).** Test #2 is the real RED, not a surrogate: write it against the **current** single-transaction code first. Forcing a mid-cascade throw on the current code rolls back the **entire** transaction (atomic) → the expense `splitDistribution` stays `{old:1000,new:500}` and `splitDistribution['new-uid']` is `500`/undefined, so test #2's first-pass assertion `splitDistribution['new-uid'] === 1500` **FAILS RED** (current code never partially commits the Phase-B sum). After the rewrite, Phase B commits the sum before Phase C throws → `1500` → GREEN, and the second pass proves no double-sum. This test **only passes under the batched architecture** and would have to be deleted to make the current code green — exactly the RED→GREEN signal. Capture both RED (current) and GREEN (rewritten) output in the PR.

Plus: `npm run build` (tsc) clean, `eslint src` clean, full functions emulator suite green (current count + new tests).

## 6. Out of scope / not touched

- `security/firestore.rules`, `firestore.indexes.json` — unchanged (no new collection, no new field, no new callable). The Admin SDK still writes THROUGH the append-only settlement/activity rules exactly as #216/#217 documented.
- `functions/src/index.ts` — unchanged (no function added/removed; pure internal rewrite of an existing callable).
- The migration **semantics** (#216 financial + #217 activity) — unchanged byte-for-byte.
- Client (`lib/`) — untouched. This is server-only.
- `docs/CLOUD-FUNCTIONS.md` — add a one-line note that the recovery cascade is now chunked (BatchWriter) rather than a single transaction.

## 7. Verification principles (run while writing)

1. **Callsite classification:** all migrated fields are repointed in-place; the only *reader* that gates behaviour is the handler's `memberIds array-contains oldUid` retry query (OUTBOUND for convergence) — §3b traces it. ✓
2. **Concrete claims vs code:** every cited line (cleanup `:263-489/:515-518/:535/:595`, deleteAccount `:78-116/:465/:478-481/:556-609`, 500-cap from #217 §5 Firebase-docs fetch) re-read this session. ✓
3. **Read-path per write-path:** the one write whose timing matters (group `memberIds`) has a named reader (retry query); §3b/§3c trace it. ✓
4. **Fields from the type:** migration field set is inherited unchanged from #216/#217 (already enumerated from models there); not re-deriving — only the mechanism changes. ✓
5. **Data contracts:** exact `BatchWriter` signature, exact `resolveCleanupBatchLimit` env key, exact Phase C transaction shape + action strings spelled out (§4). ✓
6. **Arithmetic decomposition:** the only summing op is `splitDistribution`/`mergeUidMapKey`; §3a proves its idempotency-under-retry is gated on the source key's presence (no double-sum) — this is the money-conservation invariant under the new non-atomic execution. ✓
7. **Adversarial orthogonal axis:** the fix is on the *execution-mechanism* axis (transaction→batch); the worked tests exercise the **retry/identity axis** (torn Phase C → re-run → no double-sum, test #2) and the **ordering axis** (Phase B fail → group stays visible, test #3) — not just "does it still migrate." ✓
