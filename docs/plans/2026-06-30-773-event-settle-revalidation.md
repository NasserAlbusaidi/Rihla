# #773 — Event-level settle: pre-write stale-amount revalidation

**Issue:** #773 (P3, money, follow-up of #719/#200 Scope 6)
**Spec:** mirror the #719 group-path pre-write revalidation onto the **event**
settle path (`settle_up_screen.dart`), which has the identical stale-amount
window but is structurally simpler (one direct write, no decompose).

## Problem

`lib/features/ledger/screens/settle_up_screen.dart` `_showRecordPaymentSheet`
validates `editedAmount > suggestedAmount` against the **screen-load** suggested
amount (captured when the tile was tapped) and then calls `_recordSettlement`
WITHOUT re-reading live balances. If another device pays / adds an expense while
the record sheet is open, the user records against a stale (too-large) suggestion
and overpays a debt that already shrank.

This is the same gap #719 closed for the group screen (`group_settle_up_screen.dart`,
merged PR #771 @3f980592). `BalanceCalculator.outstandingForPair` — the conservative
directed-pair cap — already landed in that PR and is on `main`.

## Why simpler than #719

The group path DECOMPOSES into per-event writes, so #719 also propagated the
fresh balances into the write (`writeBalances = fresh`). The **event** path writes
exactly ONE settlement via `_recordSettlement(from, to, amount, currency)` — the
write does not consume a balances object at all. So #773 needs only the
revalidation **gate** (block if stale), not fresh-balance propagation.

## What `outstandingForPair` guarantees (no false-block)

`outstandingForPair(bucket, from, to) = max(0, min(|fromNet|, toNet))`. The
optimizer's suggested amount for a pair is `min(remaining_debtor, remaining_creditor)`,
and both remainders only ever shrink from the full nets — so the suggestion is
always `<=` this cap. Revalidating an edited amount (which is itself `<= suggested`,
enforced by the existing `editedAmount > suggestedAmount` guard) against the cap
therefore NEVER false-blocks an unchanged balance; it fires only when the live net
actually dropped below the amount being recorded. (Pure function, already pinned by
`test/unit/outstanding_for_pair_test.dart`.)

## Parity: re-read must use the SAME universe as `build()`

`build()` computes balances via:
`eventBalanceUniverse(event, expenses, settlements, allMemberIds, liveMemberIds)`
→ `participants` → `BalanceCalculator.calculateBalances(expenses, settlements, participants)`
→ `bucketed[currency]`.

The revalidation re-read MUST reconstruct from the identical providers so the cap
it computes matches the suggestion's basis:

- `event` ← `eventDetailProvider(eventRef).valueOrNull`
- `expenses` ← `eventExpensesProvider(eventRef).valueOrNull`
- `settlements` ← `eventSettlementsProvider(eventRef).valueOrNull ?? const []`
- `allMemberIds` / `liveMemberIds` ← `groupMembersProvider(groupId).valueOrNull ?? const []`
  (`m.userId`; `liveMemberIds` excludes `m.isTombstone` — exactly as build() lines 176-180)

`calculateBalances` uses `participant.id` ONLY for the net math (verified:
`expense_provider.dart` — seeds buckets by `p.id`, accumulates by `p.id`, output
`participantId: p.id`; `p.displayName` feeds only the output `UserBalance.displayName`,
which `outstandingForPair` never reads). So the revalidation participants can be
reconstructed minimally (`displayName: id`) WITHOUT the build()'s name-resolution /
disambiguation — the directed-pair nets are byte-identical to build()'s. (Independently,
each participant's net is invariant to which OTHER former-actors populate the universe,
because the owed-drop guard only zeroes a key's OWN owed when that key is outside the
universe — and from/to are always in it.)

## Data-unavailable → skip (never a new blocker)

If `event == null || expenses == null` (offline cold / still loading), the helper
returns `null` and the caller SKIPS revalidation — behaves exactly as today. This is
a safety add-on, mirroring #719's `if (fresh != null)` guard. It must never introduce
a new offline failure mode.

## Changes

### 1. `lib/features/ledger/screens/settle_up_screen.dart`

**New private helper on `_SettleUpScreenState`:**

```dart
/// #773: the LIVE directed-pair outstanding for [currency], recomputed from a
/// FRESH read of the event ledger — or null when the data isn't available
/// (offline / still loading), in which case the caller skips revalidation
/// (safety add-on, never a new blocker). Reconstructs build()'s
/// universe→participants→calculateBalances; participant display names are
/// irrelevant to the net math so they're minimised to the id.
Decimal? _freshOutstandingForPair({
  required String currency,
  required String fromUserId,
  required String toUserId,
}) {
  final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
  final event = ref.read(eventDetailProvider(eventRef)).valueOrNull;
  final expenses = ref.read(eventExpensesProvider(eventRef)).valueOrNull;
  if (event == null || expenses == null) return null;
  final settlements =
      ref.read(eventSettlementsProvider(eventRef)).valueOrNull ?? const [];
  final groupMembers =
      ref.read(groupMembersProvider(widget.groupId)).valueOrNull ?? const [];
  final allMemberIds = groupMembers.map((m) => m.userId).toSet();
  final liveMemberIds = groupMembers
      .where((m) => !m.isTombstone)
      .map((m) => m.userId)
      .toSet();
  final universe = eventBalanceUniverse(
    event: event,
    expenses: expenses,
    settlements: settlements,
    allMemberIds: allMemberIds,
    liveMemberIds: liveMemberIds,
  );
  final participants = [
    for (final id in universe)
      Participant(
        id: id,
        tripId: event.id,
        role: ParticipantRole.member,
        joinedAt: event.createdAt,
        displayName: id,
      ),
  ];
  final bucketed = BalanceCalculator.calculateBalances(
    expenses: expenses,
    settlements: settlements,
    participants: participants,
  );
  return BalanceCalculator.outstandingForPair(
    bucket: bucketed[currency] ?? const <UserBalance>[],
    fromUserId: fromUserId,
    toUserId: toUserId,
  );
}
```

**Gate inserted in `_showRecordPaymentSheet`** — immediately AFTER the existing
`editedAmount > suggestedAmount` block (~line 527) and BEFORE the
`_recordSettlement(...)` call (~line 529):

```dart
// #773 (event mirror of #719 / #200 Scope 6): `suggestedAmount` was captured
// when the tile was tapped; the sheet may have been open long enough for another
// device to pay or add an expense. Re-read the LIVE event balances and revalidate
// the directed-pair outstanding before writing — if it dropped below `editedAmount`
// abort and force review-again rather than silently overpaying a stale debt.
// Data unavailable (offline / loading) → skip (safety add-on, never a new blocker).
final freshOutstanding = _freshOutstandingForPair(
  currency: currency,
  fromUserId: fromUserId,
  toUserId: toUserId,
);
if (freshOutstanding != null && editedAmount > freshOutstanding) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.settleUpBalanceChangedReviewAgain(
            AppFormatters.formatCurrency(freshOutstanding, currency),
          ),
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }
  return const _StepOutcome(_StepOutcomeKind.invalid);
}
```

Notes:
- Runs for BOTH the single-tile path and the stepped multi-currency walk
  (`_runSteppedSettle`), since both route through `_showRecordPaymentSheet` and both
  have the same staleness window — consistent with #719 (no `stepLabel` special-case).
- Imports already present: `Participant`/`ParticipantRole` (`trip/models/trip_model.dart`),
  `eventBalanceUniverse` + `BalanceCalculator` + `UserBalance` (`providers/expense_provider.dart`),
  `AppFormatters` (`core/utils/formatters.dart`), `eventDetailProvider`/`groupMembersProvider`.
  `Settlement` is NOT imported but is unneeded — `valueOrNull ?? const []` infers the
  element type from `eventSettlementsProvider`'s `List<Settlement>?`.

### 2. l10n — NONE

`settleUpBalanceChangedReviewAgain` already exists in `app_en.arb` (L988) and
`app_ar.arb` (L398) from #719. Reused verbatim.

### 3. Test — `test/features/ledger/settle_up_revalidation_test.dart` (new, dedicated)

Mirrors `group_settle_up_revalidation_test.dart`. A `StateProvider<List<Settlement>>`
backs the `eventSettlementsProvider` override so it can be mutated mid-test to model
another device paying while the sheet is open. A recording `SettlementService` fake
counts `addSettlement` calls.

Fixture: event `alice`+`bob`; expense `alice` pays **10.000 OMR** split equally
→ bob owes 5.000 → optimizer suggests bob→alice **5.000**.

- **Test A (stale shrink → block):** open sheet (captures 5.000) → mutate settlements
  to add a bob→alice **4.000** settlement (fresh net = 1.000 each side; outstanding
  = 1.000) → confirm full 5.000 → expect "Balance changed" + "1.000" snackbar, and
  `service.addCalls == 0` (nothing written).
- **Test B (unchanged → records):** open sheet → confirm → no "Balance changed",
  `service.addCalls == 1`.

RED expectation before impl: Test A FAILS because the screen writes the stale 5.000
(`addCalls == 1`, no "Balance changed" snackbar).

## Verification (principles run at spec time)

1. **Callsite classification.** `_showRecordPaymentSheet` is the sole confirm chokepoint
   for the event write (single-tile via `onRecord`, stepped via `_runSteppedSettle`).
   `onCorrect` calls `_recordSettlement` DIRECTLY (offsetting reverse) — intentionally
   NOT revalidated (a correction must record the exact offset regardless of current net;
   same as #719, where the correct path also bypasses the sheet). The gate sits on the
   OUTBOUND forward-record path only. ✓
2. **Concrete claims vs code.** `outstandingForPair` @ `expense_provider.dart:952` ✓;
   l10n key present both ARBs ✓; `calculateBalances` participant.id-only math verified ✓;
   keys `settleUpRecordPaymentButton`/`markAsPaidButton` shared from `GroupKeys` ✓.
3. **One read-path per write-path.** Who reads `freshOutstanding`? Only the new gate,
   which either blocks (return invalid) or falls through to the unchanged `_recordSettlement`.
   No persisted field added; `freshOutstanding` is INBOUND/transient. ✓
4. **Fields from the type.** No schema/field change. `Participant` fields enumerated from
   `trip_model.dart` (id, tripId, role, joinedAt, displayName). ✓
5. **Data contracts.** Helper returns `Decimal?`; gate compares `editedAmount > freshOutstanding`
   (both `Decimal`). Snackbar arg is `AppFormatters.formatCurrency(freshOutstanding, currency)`. ✓
6. **Arithmetic decomposition.** Not an aggregate=sum claim. The cap is `min(|fromNet|, toNet)`
   read directly from the fresh per-currency bucket — same construction as the suggestion. ✓
7. **Adversarial (orthogonal axis).** Fix is on the TIME axis (stale snapshot). Orthogonal
   exercises: (identity) a former-member counterparty — universe folds them so their net still
   computes; the gate never errors. (money-flow) a mid-sheet ADD-expense that GROWS the debt →
   freshOutstanding ≥ suggested ≥ edited → never blocks (correct: only shrink blocks). (scope)
   multi-currency stepped walk — each step revalidates its OWN bucket via the `currency` arg.

## Out of scope
- No backend/rules/Functions/deploy (client + display only; `outstandingForPair` already shipped).
- No new l10n.
- `onCorrect` offset path stays un-revalidated (by design).
