# Spec — #216: recovery ledger migration in `cleanupAnonUidArtifacts`

**Date:** 2026-06-02
**Issue:** #216 (P1, data-integrity) — account recovery leaves historical ledger keyed to the dead `oldUid` → split balances / "settle with your former self".
**Surface:** Cloud Functions (`functions/src/callables/cleanupAnonUidArtifacts.ts`) + money math + schema, read+write paths.
**Gate:** MANDATORY before implementation (money + Functions + schema). This doc is the input to that Gate.

---

## 1. Problem (verified against code)

`AuthRecoveryService.completeRecovery` (`lib/features/auth/services/auth_recovery_service.dart`) takes the device's current **anonymous** `oldUid`, signs in via email link to `newUid`, and on `oldUid != newUid` calls `cleanupAnonUidArtifacts(oldUid)`. That callable's `processGroup` migrates:

- `group.memberIds`, `group.createdBy`, member doc copy old→new (`:177-204`)
- `event.participantIds`, `event.participantNames`, `event.createdBy` for **active** events (`:206-231`)
- expense **`createdBy` only**, for **active** expenses in **active** events (`:233-241`)

Then, on full success, it **deletes the `oldUid` Auth user** (`:351-353`).

It does **NOT** migrate the financial attribution fields. After recovery, these still point at the now-deleted `oldUid`:

| Doc | Field | Holds | Migrated today? |
|---|---|---|---|
| expense | `payerParticipantId` | UID | ❌ |
| expense | `splitDistribution` (map **keys**) | UID → int subunit | ❌ |
| expense | `customSplitParticipants` | UID[] | ❌ |
| event settlement | `payerParticipantId` / `recipientParticipantId` | UID | ❌ (settlements never read) |
| event settlement | `createdBy` | UID | ❌ |
| group settlement | `payerParticipantId` / `recipientParticipantId` / `createdBy` | UID | ❌ |

### Impact mechanism (verified)

`group_balance_provider.dart:225-234`:
```
eventFinancialUids = { every expense.payerParticipantId } ∪ { settlement payer/recipient ids }
eventLocalFormerActors = eventFinancialUids.difference(liveMemberIds)   // :234
```
Post-recovery: `oldUid ∈ eventFinancialUids` (carries all the paid/owed) but `∉ liveMemberIds` (removed from members) → it becomes a **former financial actor** with its own balance row. `newUid ∈ liveMemberIds` but appears in no financial attribution → **zero**. The recovered user is split into two: a live self with no money and a ghost holding all of it. `crossGroupBalanceProvider` then reports their group net as 0.

### Proof the fields are UID-keyed

`functions/src/callables/deleteAccount.ts` already scrubs exactly this surface (`=== uid` comparisons are direct evidence): `expenseUpdates` (`:281-321`: `payerParticipantId`, `customSplitParticipants`, `splitDistribution` keys, `createdBy`), `settlementUpdates` (`:323-349`: payer/recipient ids+names, `createdBy`) at both event-level (`:494`) and group-level (`:517`). Recovery is the *inverse* operation (migrate, not erase) on the same fields.

---

## 2. Scope of THIS change

**In scope — migrate `oldUid → newUid` on the balance-feeding financial surface:**

1. **Active expenses in active events** — extend the existing `activeEventSnaps`/`expenseSnaps` loop (`:233-241`):
   - `payerParticipantId === oldUid` → `newUid`
   - `customSplitParticipants` contains `oldUid` → `replaceUid` (existing helper; **dedupes** — correct, see §4)
   - `splitDistribution` has key `oldUid` → **rename key, summing values on collision** (new helper, see §3)
   - (`createdBy` already migrated — keep)
2. **Event settlements** — read `eventSnap.ref.collection('settlements')` for each active event:
   - `payerParticipantId === oldUid` → `newUid`
   - `recipientParticipantId === oldUid` → `newUid`
   - `createdBy === oldUid` → `newUid`
3. **Group settlements** — read `groupRef.collection('settlements')`:
   - same three fields as event settlements.

**Explicitly OUT of scope (and why):**

- **`payerName` / `recipientName` on settlements** — these are denormalized display strings. Recovery copies the member doc old→new with the **same `displayName`**, so the name is unchanged; touching it would be wrong. (Contrast `deleteAccount`, which sets them to "Deleted member" *because* the person is gone — the opposite case.) **This is the migrate-vs-scrub distinction: repoint UID references only; never null/rename user content.**
- **`note` / `description` / `receiptUrl`** — the recovered user keeps their own data. Do NOT null them (again, opposite of `deleteAccount`).
- **Activity logs** — deferred to a follow-up issue. The live event-activity writers (`activity_service.dart:60`, `expense_service.dart:205`) and `deleteAccount.ts:501` all use the **same** `activity_logs` subcollection (`actorId` / `metadata` carry UID refs) — there is **no** schema discrepancy. The reason to defer is solely scope: activity does **not** feed the balance engine (`group_balance_provider.dart` never reads `activity_logs`), so a stale `oldUid` in `actorId`/`metadata` is an **inert orphan** — the feed still renders via the denormalized `actorName`, so it is not a visible ghost. It is the same defect class (incomplete `oldUid` migration) but non-balance-affecting; tracked as a separate issue to keep this PR on the money-critical path.
- **Soft-deleted expenses / soft-deleted events** — the balance engine reads only `isDeleted=false` events (`groupEventsProvider`), `isDeleted=false` expenses (`expense_service watchExpenses`), and `isDeleted=false` settlements (`settlement_service`). Soft-deleted docs never feed balances. Keeping the existing **active-only** expense gate (matching today's `createdBy` policy) leaves inert `oldUid` refs on soft-deleted expenses — an **accepted residual**, identical in class to the existing `createdBy` active-only behavior pinned by the current test. Settlements are append-only and read whole-collection (see §5).

---

## 3. `splitDistribution` merge-on-collision (the money landmine)

`deleteAccount`'s `renameMapKey` (`:245-261`) renames `uid → freshTombstoneId`, which **never collides** (the tombstone id is freshly generated). Recovery renames `oldUid → newUid`, and **`newUid` may already be a key** in the same expense's `splitDistribution` (the "both UIDs are members" case — an existing tested scenario). `renameMapKey` would **overwrite** `newUid`'s value with `oldUid`'s → silently drop `newUid`'s share → **money bug**.

**Contract:** new helper `mergeUidMapKey(map, oldUid, newUid)`:
- not a plain object / `oldUid` not a key → `{changed: false}`.
- `oldUid` key present, `newUid` absent → move value (plain rename).
- both present → `value[newUid] = num(old) + num(new)`, delete `oldUid`. `num(x) = (typeof x === 'number' && isFinite(x)) ? x : 0`.
- returns a **new** object (immutable).

The `num()` coercion fires **only** in the both-keys-present (collision) branch and only on a non-numeric value — which legitimate data never produces (`expense_model.dart:329-339` always persists JS `number`). It is an intentional lossy-toward-zero guard against a forged/corrupt entry (zeroing a garbage share is safer than NaN-propagating or throwing). The plain-rename branch moves the value **verbatim**, uncoerced. One benign side effect: dropping the `oldUid` key changes the sorted key set, so `_allocateWeighted`/`_allocateExact` may pick a different alphabetically-last recipient to absorb the ≤1-subunit rounding remainder — conservation (`sum==amount`) and the merged person's combined total are unaffected; at most a co-participant's allocation shifts by one subunit. The collision test (§6.3) should not over-assert other participants' sub-fil values.

### Conservation proof (why summing is correct)

The persisted `splitDistribution` value is a **per-uid integer in mode-specific units** (`expense_model.dart:329-339`):
- `exact` → money subunits; `percent` → percent×1000; `shares` → share count; `equally` → **not consumed** by the calculator.

The calculator (`expense_provider.dart:166-176`) **excludes `equally`** from `splitDistribution` entirely and consumes the map only for `exact` / `shares` / `percent`. All three are **additive weights**, and the from-persisted reconstruction is **linear** (`fromSubunits`, `/1000`, `Decimal.fromInt`), so `f(a) + f(b) = f(a+b)`. Merging two keys of the *same physical person* into one:

- **The denominator total is unchanged** — `totalShares` / `totalPercent` / exact-`total` are sums over all values; collapsing `{old:a, new:b}` into `{new:a+b}` leaves the sum identical. So every validity guard still holds (`totalShares>0`, `|totalPercent−100|≤tol`, `|exactTotal−amount|≤tol`).
- **The merged person's allocation = their combined pre-merge allocation.** `_allocateWeighted` gives `amount·(a+b)/denominator`; conservation (`sum(allocations)==amount`) is preserved because the last recipient absorbs the remainder exactly as before.

∴ summing the **persisted ints** on collision is conservation-safe for every mode the engine reads. (Server writes go through the Admin SDK, which **bypasses** `firestore.rules`, so the #192 non-negative/sum validators do not reject these writes — and summing cannot produce a negative or change the total anyway.)

---

## 4. `customSplitParticipants` — dedupe (not sum)

`customSplitParticipants` is a `List<String>` of UIDs; for `custom` scope the calculator does an **equal split over the set** (head count). If the recovered person appears as both `oldUid` and `newUid` in the list, they must collapse to **one head** (summing would double-charge). The existing `replaceUid` helper (`cleanupAnonUidArtifacts.ts:78-87`) already maps then dedupes via `next.includes(...)` — **correct as-is**, reuse it.

`payerParticipantId` is single-valued per doc → no collision → plain `=== oldUid ? newUid : value`.

---

## 5. Mechanics & `isDeleted` policy

- **Transaction:** keep the existing single per-group `db.runTransaction` (atomic; consistent with current code). Add the new reads to the read phase *before* any write (Firestore requirement): per active event, `tx.get(eventSnap.ref.collection('settlements'))`; once, `tx.get(groupRef.collection('settlements'))`. Expense financial migration extends the existing `activeEventSnaps`/`expenseSnaps` write loop.
- **Expenses:** active-only (existing gate `expenseData.isDeleted !== true`), active events only — matches the balance surface and the existing `createdBy` policy.
- **Settlements:** read the **whole** collection and migrate every doc whose payer/recipient/createdBy matches `oldUid`, regardless of `isDeleted`. Justification: settlements are **append-only** (the `isDeleted` field exists but corrections are offsetting rows, so soft-deleted settlements are effectively absent in practice), `deleteAccount` likewise reads the whole settlement collection, and migrating all of them guarantees **zero** surviving `oldUid` reference in a live financial record. **Rules note:** `firestore.rules` denies client settlement updates (`allow update: if false` at `:730` event / `:897` group, B3 append-only). The migration's `tx.update` deliberately writes **through** that denial via the **Admin SDK** (which bypasses `firestore.rules`) — the same bypass class as the #192 value-validators in §3. The append-only contract is intentionally server-overridden for identity migration; clients still cannot mutate settlements.
- **Auth-delete gate UNCHANGED:** the new migration runs inside `processGroup`, whose throw is caught into `cascadeFailed`. The existing gate (`cascadeFailed.length === 0` before `getAuth().deleteUser(oldUid)` and intent consumption, `:351-364`) means a **partial ledger migration preserves the `oldUid` Auth user** for retry within the 15-min intent window. No change to that logic — but the new code paths must surface failures as throws (transaction throws propagate naturally) so the gate sees them.
- **Scale residual:** a group with a very large active ledger inflates the single transaction's read/write count — the same ceiling the current all-expenses-in-one-transaction design already has. Recovery targets an anon user's own (typically small) groups; broader batching is out of scope (would mirror `deleteAccount`'s `BatchWriter` — separate change if ever needed).

---

## 6. Test matrix (TDD)

RED first. The current test `createdBy is rewritten on group, active event, and active expense only` (`cleanupAnonUidArtifacts.test.ts:225-265`) **pins the bug** at `:264` (`settlement.createdBy === 'old-anon-uid'`). That assertion **flips** to `'new-uid'` — built-in RED.

New / updated cases:
1. **expense `payerParticipantId`** `oldUid` → `newUid` (active expense).
2. **expense `splitDistribution` rename, no collision** — `{old: 1500}` → `{new: 1500}`.
3. **expense `splitDistribution` collision-merge (money proof)** — `{old: 1000, new: 500, owner: 1500}`, amount 3000 subunits exact → `{new: 1500, owner: 1500}`; assert `old` key gone, `new` = 1500, sum preserved = 3000.
4. **expense `customSplitParticipants` dedupe** — `[old, new, owner]` → `[new, owner]`; and `[old, owner]` → `[new, owner]`.
5. **event settlement** `payerParticipantId`/`recipientParticipantId`/`createdBy` `oldUid` → `newUid`; **`payerName`/`recipientName` UNCHANGED**.
6. **group settlement** (`groups/{g}/settlements`) same as (5).
7. **soft-deleted expense untouched** (active-only residual is intentional) — a `isDeleted:true` expense with `payerParticipantId: oldUid` keeps `oldUid`.
8. **partial-failure gate still holds** — extend/keep the existing `#46 AC1` test: a group whose ledger migration throws must NOT delete the `oldUid` Auth user and must preserve the cleanup intent.
9. Existing membership/participant/createdBy tests stay green (no regression).

Run: `cd functions && npm test -- cleanupAnonUidArtifacts` (Jest under Java 21 + emulator), then the full functions suite.

---

## 7. Definition of done

- [ ] RED tests written and failing for the right reason (run + capture output).
- [ ] `processGroup` migrates expense financial fields + event & group settlements, merge-safe `splitDistribution`.
- [ ] Full `functions` jest suite green; no regression in deleteAccount / membership tests.
- [ ] Auth-delete gate behavior unchanged (partial failure preserves `oldUid`).
- [ ] Activity-log migration filed as a follow-up issue (note the `ln`/`n` vs `activity_logs` schema discrepancy).
- [ ] One concern only; conventional commit; PR reviews whole-branch diff.
