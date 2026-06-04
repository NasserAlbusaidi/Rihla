# Spec: #220 client money tails — allocator negative guard + settlement read fence

**Date:** 2026-06-03  ·  **Issue:** #220 (partial — `Refs #220`)  ·  **Tails:** #192 (allocator), #193 (settlement read)

The **rules half** of #192/#193/#194 is deployed + verified live in prod (commit `72aeac3`, 2026-06-02). These are the **client-side tails** — defense-in-depth for a pre-existing / forged / legacy Firestore doc that predates or evades the now-deployed rules. Neither change touches a write path.

## Scope (this PR)

1. **Tail #192** — per-entry negative guard in `_allocateShares` + `_allocatePercent`.
2. **Tail #193** — `isSupported` read-crash fence in `Settlement.fromFirestore`.

**Out of scope** (named so #220 stays honestly open):
- Tail #194 — client free-text validator + inline editor feedback (**pure UX**) → split to a new issue; #220 re-scoped to it.
- #193 event-settlement currency equality → **deferred to #61** (event settle-up hardcodes `'OMR'`; equality is a tautology until multi-currency lands).

---

## Change 1 — allocator negative-entry guard (#192 tail)

**File:** `lib/features/ledger/providers/expense_provider.dart`

`_allocateShares` (`:299`) checks only `totalShares <= Decimal.zero`; `_allocatePercent` (`:397`) checks only `(totalPercent - _hundred).abs() > _splitTolerance`. **Neither checks per-entry sign.** A distribution like shares `{p1: 5, p2: -2, p3: 1}` has `totalShares = 4 > 0`, passes, and reaches `_allocateWeighted`, which emits a **negative allocation** for `p2` → negative `totalOwed` → breaks the non-negative-owed invariant. Percent `{p1: 150, p2: -50}` sums to 100, passes, same outcome.

`_allocateExact` (`:336`) **already** guards this exact way — mirror it:

```dart
// In _allocateShares, BEFORE the totalShares<=0 check:
if (distribution.values.any((value) => value < Decimal.zero)) {
  debugPrint(
    'Negative shares split entry for expense ${expense.id}; falling back to equal split.',
  );
  return _allocateEqual(expense.amount, distribution.keys, currency);
}

// In _allocatePercent, BEFORE the totalPercent check:
if (distribution.values.any((value) => value < Decimal.zero)) {
  debugPrint(
    'Negative percent split entry for expense ${expense.id}; falling back to equal split.',
  );
  return _allocateEqual(expense.amount, distribution.keys, currency);
}
```

- **Guard is `< 0`, not `<= 0`:** a zero share/percent is valid (that participant owes nothing); only a negative is invalid. Matches `_allocateExact`.
- **Order:** negative check FIRST, before the existing total checks — matches `_allocateExact` (negative at `:336`, tolerance at `:348`).

**Read-path classification (Principle 1):** the allocator *output* is **INBOUND** — it feeds `owedMap` for balance **display** only. The persisted `splitDistribution` is the user's *input*, written by the editor; the allocator never writes it back. So no OUTBOUND/write path is touched.

**Conservation (Principle 6):** the fallback `_allocateEqual` is remainder-safe (truncated per-head to all but the alphabetically-last recipient, who absorbs the remainder) ⇒ `sum(owed) == amount` exactly, and every entry ≥ 0 ⇒ `sum(netBalance) == 0` holds. The guard strictly prevents a negative `owed`; it cannot itself introduce one.

---

## Change 2 — settlement read-crash fence (#193 tail)

**File:** `lib/features/ledger/models/settlement_model.dart`

`Settlement.fromFirestore` (`:94`) reads `final currency = data['currency'] as String? ?? 'OMR';` then at `:111` calls `MoneySerializer.fromSubunits(amountFils, currency)`. `fromSubunits` → `_scale(currency)` **throws `ArgumentError` on an unsupported code** (`money_serializer.dart:55-60`). A single pre-existing / crafted settlement doc with an unsupported currency therefore **throws inside the stream `.map`, erroring the entire settle-up stream for every member** — they all lose their balances. The expense read path already fences this (`expense_provider.dart:171-173`, #47); the settlement read path does not.

```dart
// Replace:
final currency = data['currency'] as String? ?? 'OMR';
// With:
final rawCurrency = data['currency'] as String? ?? 'OMR';
// Unknown/garbage currency (a forged/legacy doc the deployed rules now reject
// on write) must not throw in MoneySerializer and error the whole settle-up
// stream for every member. Fall back to OMR, mirroring the expense read fence
// (#47). #193 client tail of #220.
final currency =
    MoneySerializer.isSupported(rawCurrency) ? rawCurrency : 'OMR';
```

**Read-path classification (Principle 1, 3):** `Settlement.fromFirestore` is **READ-only / INBOUND**. The fenced `currency` is used solely to scale `amountFils` into the in-memory `amount` for balance display. Settlements are **append-only** — there is no `deleteSettlement`/update that re-serializes this `amount` back (`settlement_service.dart:123`: "settlements are append-only"). `toFirestore` independently hardcodes `currency = 'OMR'` and re-derives `amountFils` from `amount`, and is not reachable from a read of a fenced doc. ⇒ No write path consumes the fenced value.

**Note (no info loss that matters):** `Settlement` has **no `currency` field** (enumerated from the type: id, tripId, payer/recipientParticipantId, amount, note, settledAt, payer/recipientName, isDeleted, deletedAt, scope, groupId, createdBy). The currency is transient to the decode. For an unsupported code we cannot know the true scale, so OMR (1000) is the documented fallback — identical posture to the expense path. `isSupported` is case-insensitive (`toUpperCase`), so a lowercase `'omr'` doc is *supported* and decodes normally; only a genuinely unknown code (e.g. `'XYZ'`) hits the fence.

---

## Tests (table-driven — money/legal/safety code)

### Allocator negative guard — `test/unit/balance_calculations_test.dart`

For **shares** and **percent** (both modes):

| case | distribution | expectation |
|---|---|---|
| clean (regression) | shares `{p1:2, p2:1, p3:1}`, amount 8.000 | p1 4.000 / p2 2.000 / p3 2.000; no fallback |
| **negative entry** | shares `{p1:5, p2:-2, p3:1}`, amount 9.000 | equal-split fallback: 3.000 each; **no negative owed**; `sum(owed)==9.000` |
| zero entry stays valid (boundary) | shares `{p1:2, p2:0, p3:1}`, amount 9.000 | weighted: p1 6.000 / p2 0.000 / p3 3.000; **not** fallback |
| percent negative | percent `{p1:150, p2:-50}`, amount 10.000 | equal-split fallback: 5.000 each; no negative owed |
| **adversarial (orthogonal axis — identity):** payer is also a split recipient with a negative entry | payer `p1`, shares `{p1:-3, p2:1}`, amount 6.000 | equal fallback 3.000 each; assert `sum(netBalance)==0` and every `totalOwed >= 0` |

### Settlement read fence — new `test/unit/settlement_read_fence_test.dart` (or extend `settlement_service_test.dart`)

| case | doc `currency` / `amountFils` | expectation |
|---|---|---|
| supported (regression) | `USD` / 999 | `amount == 9.99`, no throw |
| supported OMR (regression) | `OMR` / 10500 | `amount == 10.500`, no throw |
| **unsupported** | `XYZ` / 5000 | **does NOT throw**; `amount == 5.000` (OMR fallback) |
| missing currency (regression) | absent / 5000 | defaults OMR; `amount == 5.000`, no throw |
| lowercase supported | `omr` / 10500 | case-insensitive → decodes `10.500`, no throw |

All allocator tests assert two invariants explicitly: **no `totalOwed < 0`** and **`sum(netBalance) == 0`**.

---

## Verification checklist run while writing this spec

- **P1 callsite classification:** both changes are INBOUND read-path only; no OUTBOUND. ✅
- **P2 claims vs code:** line numbers re-grepped live (allocators 299/324/397; fence 171-173; `fromSubunits`/`_scale` throw confirmed; `_allocateExact` guard at 336 confirmed). ✅
- **P3 one read per write:** no write path changed; settlement append-only confirmed (`settlement_service.dart:123`). ✅
- **P4 fields from type:** `Settlement` fields enumerated from `settlement_model.dart` — no `currency` field exists. ✅
- **P5 data contracts:** fallback returns `_allocateEqual(amount, keys, currency)`; fence returns `String` currency. Exact. ✅
- **P6 arithmetic decomposition:** fallback preserves `sum(owed)==amount`; guard cannot create a negative. ✅
- **P7 adversarial orthogonal axis:** negative-allocator example exercised on the **identity** axis (payer-is-recipient) + conservation assertion, not just the same split-math axis. ✅
