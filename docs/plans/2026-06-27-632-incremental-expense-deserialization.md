# #632 — Incremental expense deserialization on snapshot ticks

**Branch:** `perf/632-incremental-expense-deser` · **Milestone:** 1.7.0 · **Labels:** P2, money, tech-debt, performance
**Gate:** money-deserialization / data-path → **Gate-category** (fresh-context Opus review before code).

## Problem (verified against live code, origin/main @9f43b57c)

`ExpenseService.watchExpenses` (`lib/features/ledger/services/expense_service.dart:35-47`) maps the
**entire** snapshot on the UI isolate every tick:

```dart
.snapshots().map((snap) => snap.docs
    .map((doc) => Expense.fromFirestore({...doc.data(), 'id': doc.id}))
    .toList());
```

Each `Expense.fromFirestore` (`expense_model.dart:177-230`) runs `MoneySerializer.fromSubunits`
(amount) + `_splitDistributionFromPersisted` (per-participant `_splitValueFromPersisted` →
MoneySerializer/Decimal) + 2× `DateTime.parse`. The `{...doc.data()}` spread also copies every doc
map. So **every** live emission — any add/edit/soft-delete by any member, plus the initial open —
re-deserializes ALL N expenses over P participants → O(N×P) synchronous Decimal allocations before
the first frame of the update. On a large event this drops frames on the add round-trip and on
ledger open.

`watchExpensesInRange` (`:75-94`) has the identical pattern (test-only consumer today).
`getExpenses` (`:55-63`) is a one-shot `.get()` (single emission) — no per-tick waste, untouched.

## Fix — deserialize only `docChanges`, cache the rest (per-subscription)

Firestore re-emits the FULL document set on every snapshot, but its `docChanges` delta names only
the **added / modified / removed** docs (the initial snapshot reports every doc as `added`). Keep an
`id → Expense` cache scoped to the subscription; re-run `Expense.fromFirestore` only for changed
docs and reuse the cached immutable `Expense` for every unchanged doc. Per-tick cost drops from
O(N×P) to O(changed×P) — typically O(P) for a single add/edit. The initial open still parses all N
once (they are all `added`), which is unavoidable and matches the issue's primary complaint
("re-deserializes ALL N expenses on every tick", not "on first load").

`watchExpenses` / `watchExpensesInRange` create a fresh per-call `cache` and `.map` each snapshot
through a shared reconcile helper:

```dart
List<Expense> _reconcileExpenses(
  Map<String, Expense> cache,
  QuerySnapshot<Map<String, dynamic>> snap,
) {
  for (final change in snap.docChanges) {
    final doc = change.doc;
    if (change.type == DocumentChangeType.removed) {
      cache.remove(doc.id);
      continue;
    }
    final data = doc.data(); // DocumentChange.doc.data() is nullable
    if (data != null) {
      cache[doc.id] = Expense.fromFirestore({...data, 'id': doc.id});
    }
  }
  return [
    for (final doc in snap.docs)
      cache[doc.id] ??= Expense.fromFirestore({...doc.data(), 'id': doc.id}),
  ];
}
```

The `cache[doc.id] ??= …` in the build loop is a defensive parse-on-miss; in practice docChanges
always populates the cache first.

### Why `.map` + per-call cache (not `async*`)
The Gate reviewed an `async*` generator variant. It is functionally correct, BUT cancelling a
subscription to an `async*` stream that is parked in `await for` over a never-closing **broadcast**
source (the `fake_cloud_firestore` `BehaviorSubject`) hangs — a known Dart `await for`-cancellation
wrinkle that timed out the TDD tests at 30s. `.map` over the source stream cancels cleanly (it just
cancels the underlying `.snapshots()` subscription, no parked generator). The `cache` is created
inside each `watchExpenses`/`watchExpensesInRange` call, so each returned stream owns its own cache;
production `.snapshots()` is single-subscription (real Firestore rejects a second `.listen`), so
per-call == per-subscription with no cross-subscription bleed. Same reconcile logic, strictly lower
risk.

## Correctness — invariants preserved

- **Order:** output is built from `snap.docs` order (the query's `orderBy createdAt desc`), reusing
  cached instances by id. Identical ordering to today.
- **Soft-delete:** the query filters `isDeleted == false`, so a soft-deleted doc leaves the result
  → reported `removed` → evicted from cache → absent from output. Same as today.
- **Edit:** a content change is reported `modified` → re-parsed into a fresh `Expense` with the new
  values. Same observable result as today; the only change is unchanged siblings are not re-parsed.
- **Offline replay:** a staged offline add emits once (`added`, `hasPendingWrites`); on server-ack
  with `includeMetadataChanges` false (default) Firestore emits NO new snapshot because content is
  unchanged (`createdAt` is a client ISO string, not a `serverTimestamp`) — so no double-parse, no
  spurious `modified`. Same as today.
- **Downstream rebuilds:** each tick yields a NEW `List` object; `List ==` is identity-based so
  Riverpod always propagates a real content change. Reusing immutable `Expense` instances for
  unchanged docs cannot suppress a needed rebuild (BalanceCalculator reads fields, not identity).
- **Errors:** source-stream errors propagate out of `await for` to the listener, same as `.map`.

## Verification principles (run now, reported out loud)

1. **Callsite classification:** `watchExpenses` is INBOUND (read/display path → BalanceCalculator).
   No write path touched. `Expense.fromFirestore` is unchanged.
2. **Concrete claims vs code:** paths/line numbers verified above against origin/main @9f43b57c.
3. **Read-path per write-path:** no write-path changes. The single read consumer is
   `eventExpensesProvider` (`expense_provider.dart:70`); `watchExpensesInRange` has no prod consumer
   (test-only — grep-confirmed).
4. **Enumerate from the type:** `DocumentChange.type ∈ {added, modified, removed}` — all three
   handled (added/modified collapse to "parse+store", removed → evict).
5. **Data contract:** `_incrementalExpenseStream` consumes `Stream<QuerySnapshot<Map<String,
   dynamic>>>` (exactly what `eventSubcollection(...).snapshots()` yields) and emits
   `List<Expense>` (unchanged public contract of both methods).
6. **Arithmetic decomposition:** N/A — no balance math touched; `Expense.fromFirestore` byte-for-byte
   unchanged, so per-expense deserialized values are identical.
7. **Adversarial axis (identity/time):** the cache could leak across subscriptions (identity axis) →
   neutralized by `async*` per-frame cache. Re-ordering by time → output re-derived from `snap.docs`
   each tick, so order can never drift from the query.

## TDD (RED first)

New tests in `test/unit/expense_service_test.dart`, `watchExpenses` group — multi-emission, asserting
**instance identity** (the perf contract: unchanged docs are NOT re-deserialized ⇒ reused instance):

- **added:** seed A,B,C → subscribe → add D → unchanged A,B,C are `identical` across the two
  emissions; D is a fresh instance. (RED on current code: every tick maps fresh → none identical.)
- **modified:** seed A,B → edit B's amount → B is a NEW instance carrying the new amount; A stays
  `identical`. (Proves modified docs DO re-parse — correctness — while siblings stay cached.)
- **removed (soft-delete):** seed A,B,C → soft-delete C → C absent; A,B stay `identical`.

Multi-emission drained with `pumpEventQueue` between mutations. Existing `.first` tests and
`event_stream_passthrough_test` (provider pass-through) must stay green.

## Out of scope (follow-ups, not bundled)
- Moving the initial full parse to an isolate via `compute()` — bigger change, object-transfer risk;
  the per-tick win is the high-leverage part. Note in PR.
- `SettlementService.watchSettlements` likely shares the pattern — separate issue/PR.
