# Slice 6 of #202 — `spendingSnapshot`: freeze the spending recap at close

**Date:** 2026-06-30
**Epic:** #202 (event closeout + recap). Builds directly on Slice 5 / #723 (event close lifecycle, MERGED+DEPLOYED @90d67bb6).
**Category:** Gate-required — schema field with read+write paths, `security/firestore.rules` change, recap money projection.
**Spec:** this file.

---

## 1. Goal (the epic's §5 "Snapshot Rule")

> Spending recap should be snapshot-based once the event is closed. Settlement status can remain live.
> Rationale: the spending story should not casually change after close; settlements usually happen after the trip ends; payment status must still update after closeout.

So: when an event is **closed**, the recap's **spending** half is served from a **frozen snapshot** captured at close time; the **settlement** half is still computed **live**. On **reopen**, the snapshot is cleared and the recap goes fully live again.

### Why a snapshot is genuinely needed (not redundant with #723's expense-freeze)

#723 froze expense **writes** on a closed event (`eventAcceptsExpenseWrites` checks `isClosed==false`). But closed events still accept **participant edits**: `validEventLightUpdate`/`validEventAdminUpdate` gate on `eventAllowsClientWrites` (not-deleted only — *not* not-closed), so a participant can be **added** (light, additive) or **removed** (admin) after close (`firestore.rules:498-541`, confirmed). That drifts the *live* recap's person-aggregates even though expenses are frozen:

- `participantCount` (= `Event.participantIds.length`, `event_recap.dart:242`) — drifts directly.
- `payerTotalsByCurrency` / per-participant `owed` — built from the **balance universe** (`event.participantIds ∪ formerActors`, `expense_provider.dart:95-101`); removing a participant with no residual drops them from the universe (the #249 conservation gap).

Pure expense aggregates (`totalSpentByCurrency`, `biggestExpenseByCurrency`, `categoryTotalsByCurrency`) are invariant to membership and already frozen by the expense-freeze — but freezing them in the snapshot too keeps the spending story one atomic, internally-consistent unit. The snapshot makes "the spending story doesn't casually change after close" an **explicit durable guarantee**, not an emergent side effect of the expense-write rules.

---

## 2. Architecture decision — client-written opaque blob (splitExplanation-class)

**Chosen:** at close, the **client** computes the spending projection (reusing the existing `EventRecap.from` output it already displays) and writes it as an **opaque `spendingSnapshot` map** on the event doc, captured atomically in the close `.update()`. It is **display-only, never read by the oracle / `recomputeNet` / any Cloud Function** — exactly the `splitExplanation` / `groupSettleUpId` contract.

**Rejected: server trigger recomputes the snapshot in TS.** A Firestore trigger on `isClosed false→true` could recompute the spending projection server-side (more authoritative — sees every expense). Rejected because it creates a **brand-new oracle-parity surface**: the TS snapshot would have to mirror `EventRecap.from`'s spending logic byte-for-byte (biggest-expense id tie-break, `categoryId ?? 'other'` bucketing, payer desc-sort, per-participant owed). The project's contract explicitly warns against new parity surfaces, and this is for a **display-only cache**. The client already computes the exact projection; reusing it = zero parity surface. (Same reasoning that keeps `splitExplanation` client-side and oracle-invisible.)

**Accepted tradeoff of the client approach:** the snapshot is only as complete as the closing admin's loaded ledger. Mitigated by **gating the Close action on the event's expenses having loaded** (`AsyncData`, not loading) so we never freeze a false-empty view. And it is display-only — balance truth stays in expenses/settlements, recomputed live by the oracle for actual settle-up — so a stale snapshot is at worst a cosmetic recap, never a money-truth error. The settlement half stays live regardless.

**Serialization:** `MoneySerializer.toSubunits(Decimal, ccy)` / `fromSubunits(int, ccy)` per currency (the canonical Firestore money boundary; matches `splitExplanation.amountFils`). The field is read **only by the Dart client**, never by a JS Function, so the #528 JS-safe-int concern does not apply; amounts stay Dart `int64`.

---

## 3. Field classification — what freezes vs what stays live (verification principle #1)

Every `EventRecap` field, classified by its source (from the understand pass against `event_recap.dart` + `expense_provider.dart:353-358`):

| Field | Source | When closed |
|---|---|---|
| `eventId`, `eventName`, `startDate`, `endDate` | event meta | passthrough (live event doc) |
| `participantCount` | `participantIds.length` | **FROZEN** (snapshot) |
| `expenseCount` | expenses.length | **FROZEN** |
| `totalSpentByCurrency` | `calculateTotalExpensesByCurrency` (expense sum) | **FROZEN** |
| `userPaidByCurrency` | `UserBalance.totalPaid` (expense-derived) | **FROZEN** (via snapshot `payers` lookup) |
| `userShareByCurrency` | `UserBalance.totalOwed` (expense-derived) | **FROZEN** (via snapshot `owed` lookup) |
| `biggestExpenseByCurrency` | raw expense max | **FROZEN** |
| `payerTotalsByCurrency` | `UserBalance.totalPaid` per payer | **FROZEN** |
| `categoryTotalsByCurrency` | expense aggregation | **FROZEN** |
| `isEmpty` | `expenseCount==0` | **FROZEN** |
| `userSettledByCurrency` | `netBalance − totalPaid + totalOwed` (settlement term) | **LIVE** |
| `userNetByCurrency` | `UserBalance.netBalance` (settlement-folded) | **LIVE** |
| `participantNetsByCurrency` | `UserBalance.netBalance` per person | **LIVE** |
| `isSettledByCurrency` | `netBalance==0` | **LIVE** |

`net = paid − share + settled`: paid+share frozen, settled live, net recombines. In the normal case (no post-close participant drift) live `netBalance` equals `frozenPaid − frozenShare + liveSettled`, so the on-screen reconciliation holds. In the rare post-close-participant-removal case they may diverge; both halves remain independently correct per the epic (spending = as-of-close; settlement = current). Documented as an accepted edge.

**Display names are NOT snapshotted** — the snapshot stores participant **ids**; the recap screen resolves them to names live via `view.rosterDisplayNames` (a renamed participant should show the new name; identity ≠ money). A fully-departed id degrades to the existing `ledgerSomeone` fallback.

---

## 4. Data contract — the `spendingSnapshot` map (verification principle #5)

Exact Firestore shape written on the event doc under key `spendingSnapshot`. All amounts are integer subunits in the **bucket's currency**.

```jsonc
{
  "v": 1,                                   // int schema version
  "participantCount": 7,                    // int
  "expenseCount": 23,                       // int
  "totals":     { "OMR": 145500, "USD": 4000 },              // ccy -> subunits
  "biggest":    { "OMR": { "id": "exp_9", "amt": 30000,
                           "desc": "Hotel", "cat": "stay",   // desc/cat omitted when null
                           "payer": "uid_a" } },             // ccy -> ref
  "payers":     { "OMR": [ { "id": "uid_a", "amt": 90000 },  // ccy -> desc-sorted list (zero-paid excluded)
                           { "id": "uid_b", "amt": 55500 } ] },
  "categories": { "OMR": [ { "cat": "stay", "amt": 80000 },  // ccy -> desc-sorted list
                           { "cat": "food", "amt": 65500 } ] },
  "owed":       { "OMR": { "uid_a": 72750, "uid_b": 72750 } } // ccy -> participantId -> owed subunits
}
```

- **8 top-level keys.** Opaque rules guard caps top-level `size() <= 16` (generous; the 1 MB doc limit is the real backstop, mirroring `splitExplanation`'s note). Nested maps are *not* counted by `size()`.
- New model file `lib/features/events/models/spending_snapshot.dart`: `class SpendingSnapshot` with `toMap()` / `SpendingSnapshot.fromMap(Map)` using the TOTAL-PARSE pattern (never throw on malformed Firestore data; drop unsupported currencies via `MoneySerializer.isSupported`; missing/garbage → empty bucket). Built via `SpendingSnapshot.from({required EventRecap recap, required Map<String,List<UserBalance>> balances})` — the viewer-independent spending fields come from `recap`; the per-participant **`owed`** map comes from `balances` (`UserBalance.totalOwed` per participant). **`EventRecap` carries only the _current user's_ `userShareByCurrency`, NOT a per-participant owed map** (verified `event_recap.dart:57-58,147-154`), so `recap` alone cannot populate `owed` — this was the **Gate R1 [P1]**.
- `userPaid` reconstruction: lookup uid in `payers[ccy]` (absent → 0). `userShare`: `owed[ccy][uid]` (absent → 0, which is a genuinely zero-owed participant). The `owed` map carries **every** participant, so every viewer — not just the closing admin — reconstructs their own frozen share and `net = paid − share + settled` reconciles for all.

---

## 5. File-by-file changes

### 5.1 `lib/features/events/models/spending_snapshot.dart` (new)
- `SpendingSnapshot` immutable model holding the §4 fields as `Decimal` maps internally.
- `factory SpendingSnapshot.from({required EventRecap recap, required Map<String,List<UserBalance>> balances})` — viewer-independent spending fields (counts, totals, biggest, payers, categories) from `recap`; the per-participant `owed` map from `balances` (`UserBalance.totalOwed`). **`EventRecap` has no per-participant owed map** (only the current user's `userShareByCurrency`), so `recap` alone cannot populate `owed` — Gate R1 [P1].
- `Map<String,dynamic> toMap()` — serialize via `MoneySerializer.toSubunits`, omit null `desc`/`cat`.
- `factory SpendingSnapshot.fromMap(Map<String,dynamic>)` — TOTAL-PARSE, `fromSubunits`, drop unsupported ccy.

### 5.2 `lib/features/events/models/event_model.dart`
- Add `final SpendingSnapshot? spendingSnapshot;` (nullable, default null).
- `fromDoc`: `spendingSnapshot: data['spendingSnapshot'] is Map ? SpendingSnapshot.fromMap(...) : null`.
- **`toFirestoreMap` is NOT touched** — the key stays out of the create payload so `validEventCreate`'s exhaustive `keys().hasOnly([18 keys])` (`firestore.rules:459-478`) is unaffected. The snapshot is written **only** by the close partial-`.update()`. (Same omit-when-absent discipline as `groupSettleUpId`.)
- `copyWith`: **no new exposed param** (nothing sets the snapshot via `copyWith` — close/reopen use partial `.update()` like the close triple), **BUT its internal `Event(...)` constructor call MUST pass `spendingSnapshot: this.spendingSnapshot`** to preserve it. Omitting that line silently drops the snapshot to the constructor default (null) on any `copyWith` call. `Event.copyWith` is exercised by `event_model_test.dart` (copyWith group) and `ledger_screen_overflow_test.dart` — add a copyWith-preserves-spendingSnapshot assertion to the test group.

### 5.3 `lib/features/events/services/event_service.dart`
- `closeEvent({groupId, eventId, closedBy, Map<String,dynamic>? spendingSnapshot})` — when non-null, add `'spendingSnapshot': spendingSnapshot` to the `.update()` map (now ≤5 keys).
- `reopenEvent`: add `'spendingSnapshot': FieldValue.delete()` to the update map. **`delete()`, not `null`** — the opaque rules guard is `is map` and would reject an explicit `null`; deletion removes the key so the `!hasAny([...])` branch passes and `fromDoc` reads it back as absent→null.

### 5.4 `lib/features/events/widgets/event_danger_section.dart`
- `_executeClose`: before calling `closeEvent`, read the live recap **and balances**: `final r = (groupId: groupId, eventId: eventId); final recap = ref.read(eventRecapProvider(r)); final view = ref.read(ledgerViewProvider(r));` and pass `spendingSnapshot: recap.isEmpty ? null : SpendingSnapshot.from(recap: recap, balances: view.balances).toMap()`.
- Gate the **Close** action on expenses being loaded: watch `eventExpensesProvider(eventRef)` and disable/guard the Close confirm until `AsyncData` (prevents freezing a false-empty cold view). Reopen unchanged except the service now clears the snapshot.

### 5.5 `lib/features/events/models/event_recap.dart`
- Factor the **settlement-half** computation (the `balances.forEach` building `participantNets`/`isSettled` + the per-uid `userSettled`/`userNet` extraction) into a private static helper reused by both factories. **The helper covers ONLY `participantNetsByCurrency`/`isSettledByCurrency`/`userSettledByCurrency`/`userNetByCurrency`. `payerTotalsByCurrency` is FROZEN (from snapshot) and must NOT be dragged into the live helper — even though live `EventRecap.from` builds `payerTotals` in the same `balances.forEach` loop (`event_recap.dart:206-235`), `fromSnapshot` takes payers from the snapshot, not from live balances (Gate R1 [P3]).**
- Add `factory EventRecap.fromSnapshot({ required SpendingSnapshot snapshot, required String eventId, required String eventName, DateTime? startDate, DateTime? endDate, required Map<String,List<UserBalance>> balances, required String? uid })`:
  - Viewer-independent spending fields (`totalSpentByCurrency`, `participantCount`, `expenseCount`, `biggestExpenseByCurrency`, `payerTotalsByCurrency`, `categoryTotalsByCurrency`, `isEmpty`) ← `snapshot`.
  - **Four current-user maps** (`userPaid`/`userShare`/`userSettled`/`userNet`) — preserve the documented "share ONE key set" invariant (`event_recap.dart:53-56`, Gate R2 [P2]). Build over a shared key set = currencies where `uid` appears in the snapshot (`payers`/`owed`) **OR** in live `balances`. Per key: `paid` = frozen `snapshot.payers[ccy]` lookup (else 0); `share` = frozen `snapshot.owed[ccy][uid]` (else 0); `net` = **live** `balances[ccy]` `mine.netBalance` (else `paid − share`); `settled` = **`net − paid + share`** (the residual — mirrors live `settlementAdj = netBalance − totalPaid + totalOwed` at `event_recap.dart:147`, so `net == paid − share + settled` holds by construction for every viewer, no-drift or drift).
  - Live settlement collection fields (`participantNetsByCurrency`, `isSettledByCurrency`) ← shared helper over **live** `balances` (see helper note above — `payerTotals` is NOT in this helper).

### 5.6 `lib/features/events/providers/event_recap_provider.dart`
- Branch: if `event != null && event.isClosed && event.spendingSnapshot != null` → `EventRecap.fromSnapshot(snapshot: event.spendingSnapshot!, …, balances: view.balances, uid: uid)`; else current `EventRecap.from(...)` (live). Closed-with-no-snapshot (legacy/empty) → live, unchanged.

### 5.7 `lib/features/events/screens/event_recap_screen.dart`
- When `event.isClosed && event.spendingSnapshot != null`, render a small "spending frozen" caption under the header (display-only; settlement sections keep their live data). **`closedAt` is nullable and is still null during the offline-close / serverTimestamp-unresolved window while `isClosed && spendingSnapshot != null` is already true (Gate R2 [P2]) — so the date is conditional: `closedAt != null` → `recapSpendingFrozen(date)` ("Spending frozen · closed {date}"); `closedAt == null` → the dateless `recapSpendingFrozenNoDate` ("Spending frozen"). Never `closedAt!`.** Update the stale comment at `:26`.

### 5.8 `security/firestore.rules` — `validEventCloseToggle` (L557-577)
- Extend the cheap-first diff gate to 5 keys: `diff().affectedKeys().hasOnly(['isClosed','closedAt','closedBy','updatedAt','spendingSnapshot'])`.
- Add an opaque guard mirroring `splitExplanationBounded` (L623-626):
  ```
  function spendingSnapshotBounded(d) {
    return !d.keys().hasAny(['spendingSnapshot'])
      || (d.spendingSnapshot is map && d.spendingSnapshot.size() <= 16);
  }
  ```
  AND the literal `&& spendingSnapshotBounded(request.resource.data)` to `validEventCloseToggle`'s return, **after** the cheap diff gate so it only evaluates on a close/reopen-shaped write (matches how `splitExplanationBounded(request.resource.data)` is invoked at `firestore.rules:709/787`; expression-ceiling discipline).
- Close branch: snapshot may be present (a map) — guard passes. Reopen branch: snapshot deleted (absent) — `!hasAny` passes; do **not** require it present.
- `validEventBase` is **not** touched (it already omits the close triple for the ceiling; the snapshot must never be validated there). Light/admin diff allow-lists already exclude `spendingSnapshot`, so no other path can write it.

### 5.9 l10n
- `recapSpendingFrozen` ("Spending frozen · closed {date}", one `{date}` placeholder) **and** `recapSpendingFrozenNoDate` ("Spending frozen", no placeholder) in `app_en.arb` + `app_ar.arb` — the second covers the null-`closedAt` window (§5.7). Mirror the placeholder/ICU style of the existing recap keys.

---

## 6. Test matrix (money/legal/safety → table-driven, per global rules)

**Model round-trip** (`test/features/events/spending_snapshot_test.dart`, new): `fromRecap → toMap → fromMap` round-trips every field exactly across OMR (×1000), USD (×100), JPY (×1), multi-currency; desc/cat omitted-when-null; unsupported ccy dropped on read; malformed map → empty (no throw).

**`EventRecap.fromSnapshot`** (extend `event_recap_test.dart`): spending fields == snapshot; settlement fields == live `balances`; **`expectReconciles` holds for EVERY viewer** (not just the closing admin) in the no-drift case — i.e. each participant's `userShare` reconstructs from `owed[ccy][uid]` (a genuinely zero-owed participant → 0); per-currency isolation (never cross-summed).

**Provider branch** (`event_recap_provider` test): open → live; closed+snapshot → frozen spending + live settlement; closed+no-snapshot → live; **drift proof**: after snapshot, mutate live balances' `totalPaid`/participant set → frozen spending fields unchanged, settlement fields move.

**Service** (`event_service_test.dart`, extend #723 group): `closeEvent` with snapshot writes the `spendingSnapshot` map (+ isClosed/closedAt/closedBy/updatedAt); without snapshot writes 4 keys; `reopenEvent` removes the key (reads back absent).

**Rules** (`firestore-rules-publish-readiness.test.ts`, extend #723 describe): close **with** a bounded `spendingSnapshot` map ACCEPTED; close with `spendingSnapshot.size() > 16` REJECTED; close with `spendingSnapshot` not a map REJECTED; reopen that **deletes** `spendingSnapshot` ACCEPTED; a light/admin update that tries to write `spendingSnapshot` REJECTED (not in their allow-lists); existing #723 cases still green. **Expression-ceiling check: the `spendingSnapshot` edit is confined to `validEventCloseToggle` in the event-doc `allow update` OR-chain (NOT the expense `/{module}/{docId}` path), so the meaningful no-regression target is the heaviest event-doc admin-update test, not the expense-update tests (Gate R1 [P3]); `spendingSnapshotBounded` (~2-3 expressions) sits behind the cheap diff gate so it only evaluates on a close/reopen-shaped write.**

**Widget** (`event_recap_screen_test.dart`, extend): closed+snapshot renders the "frozen" caption; open does not.

RED-first for every behavioral test (write failing, watch it fail for the right reason, then implement).

---

## 7. Verification principles applied

1. **Classify callsites** — §3 table classifies every recap field FROZEN/LIVE; the only write path is the close `.update()`; the snapshot is INBOUND/display-only everywhere (never feeds a settle-up/oracle write).
2. **Claims vs code** — all paths/line-refs verified first-hand this session (`event_model.dart:176-196`, `event_service.dart:207-256`, `firestore.rules:459-478/498-577/623-626`, `event_recap.dart:118-256`, `money_serializer.dart:30-55`, `event_danger_section.dart:332-360`).
3. **One read-path per write-path** — the snapshot is written by `closeEvent`; read by `eventRecapProvider`→`EventRecap.fromSnapshot`→recap screen. Named, single reader. The oracle/`recomputeNet` is **not** a reader (grep=0; contract preserved).
4. **Enumerate fields from the type** — §3 enumerated all 17 `EventRecap` fields + all 5 `UserBalance` fields + all 18 `Event` fields from the source, not memory.
5. **Exact data contract** — §4 gives exact keys, nesting, subunit encoding, and the userPaid/userShare reconstruction lookups.
6. **Arithmetic decomposition** — `net = paid − share + settled`; snapshot freezes paid+share (settlement-independent `totalPaid`/`totalOwed`), keeps settled live; the §3 note states where it reconciles and the one edge where it deliberately doesn't.
7. **Adversarial pass (orthogonal axis)** — the fix is on the **time/lifecycle** axis (freeze at close); the drift test exercises the **identity/membership** axis (post-close participant change) to prove the freeze actually holds where the live path would drift.

---

## 8. Open items / accepted edges
- Post-close participant removal can make live `userNet` diverge from `frozenPaid − frozenShare + liveSettled`. Accepted: spending = as-of-close, settlement = current; both independently correct per epic §5. Not "fixed" by re-freezing settlement.
- The closing admin's snapshot completeness depends on their loaded ledger; mitigated by the loaded-expenses gate on Close. **The Close gate covers expense-emptiness, not owed-completeness** (Gate R2 [P3]) — the `owed` universe also depends on `groupMembersProvider` (`ledger_view_provider.dart:69-101`), so an unloaded departed-member residual could be under-populated in the frozen `owed`. Accepted: display-only, settlement stays live, worst case is a cosmetic recap, never a wrong settle-up.
- Snapshot grows the event doc by a few KB (well under 1 MB). No pagination needed.

## 9. PR shape
Single PR (one coherent feature). **`Closes #766`** (Slice 6 of #202). Order: model+serializer (RED→GREEN) → recap factory/provider → rules → service+danger-section → UI/l10n → full suite + `flutter analyze` + theme purity + rules emulator tests. Backend (rules) deploys freely post-merge (no users; deploy-ceremony advances `backend-deployed`). Commit body must carry `Closes #766` (squash-merge auto-closes from the commit message, not the PR body).
