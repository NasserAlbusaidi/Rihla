# Issue 665 UpdateExpense Exact-Split Currency Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ExpenseService.updateExpense` reject exact-split distribution writes when no currency is supplied, so it can never silently encode non-OMR exact amounts at the OMR scale.

**Architecture:** Keep the existing nullable `currency` API because note-only, clear-only, shares, and percent updates do not serialize money. Move the hard requirement to the money serialization boundaries: `amount != null` already requires `currency`; `SplitMode.exact` distribution encoding must now require it too. The production caller already passes `original.currency`, so this is defensive hardening of the service boundary.

**Tech Stack:** Flutter/Dart, Riverpod service layer, `decimal`, `fake_cloud_firestore`, `flutter test`.

---

## Live-Code Findings

- Issue `#665` is open and scoped as P3 defensive hardening: exact-split update with `currency == null` falls back to OMR even though production currently passes a non-null currency.
- `lib/features/ledger/services/expense_service.dart:235-282` has `String? currency`; amount updates throw on null currency, but split updates call `_encodeDistribution(..., currency ?? 'OMR')`.
- `lib/features/ledger/services/expense_service.dart:360-377` encodes `SplitMode.exact` with `MoneySerializer.toSubunits(entry.value, currency)`, so the currency scale is load-bearing only for exact mode.
- `lib/features/ledger/screens/edit_expense_screen.dart:135-142` is the only production `updateExpense` caller and passes `currency: original.currency`.
- `test/unit/expense_service_test.dart:429-462` currently documents the old split-only exemption using a shares split; that should remain valid because shares are raw weights, not currency subunits.
- `test/unit/expense_service_test.dart:1039-1046` has an exact-split itemized update that must pass `currency: 'OMR'` after this hardening.
- Gate R1 returned `0 P1 / 2 P2 / 1 P3`. The P2s are handled below by pinning a positive non-OMR exact update and making the split-only exact caller contract explicit. The P3 is handled by naming the server reader.

## Data Contract

`ExpenseService.updateExpense` keeps this relevant signature:

```dart
Future<void> updateExpense({
  required String groupId,
  required String eventId,
  required String expenseId,
  Decimal? amount,
  String? currency,
  SplitMode? splitMode,
  Map<String, Decimal>? splitDistribution,
  bool clearSplit = false,
  // other existing optional fields unchanged
})
```

Firestore write keys stay unchanged:

```dart
'amountFils'        // integer subunits; written only when amount != null
'currency'          // written only when amount != null
'splitMode'         // written only for non-equal split updates
'splitDistribution' // exact values are integer subunits; shares/percent are weights
```

New invariant:

```dart
amount != null || splitMode == SplitMode.exact
  => currency must be non-null before serializing money
```

Caller contract for split-only exact updates:

```dart
amount == null && splitMode == SplitMode.exact
  => pass the expense's existing stored currency
```

`updateExpense` must not persist `currency` in that split-only case, because changing the document currency without changing `amountFils` would re-interpret the existing amount at a different scale. The currency parameter is the serialization context for the new exact distribution, not a target currency change.

Shares and percent remain allowed with `currency == null` because they do not serialize money:

```dart
SplitMode.shares  => entry.value.toBigInt().toInt()
SplitMode.percent => (entry.value * Decimal.fromInt(1000)).toBigInt().toInt()
```

## Verification Principles

1. Callsite classification:
   - `edit_expense_screen.dart` is OUTBOUND and already passes `original.currency`.
   - `expense_service_test.dart` direct service calls are OUTBOUND test write boundaries.
   - `Expense.fromFirestore` is INBOUND and decodes `splitDistribution` with the stored/fenced currency.
2. Concrete claims verified against code:
   - Only production `updateExpense` caller: `rg -n "updateExpense\\(" lib test -g'*.dart'`.
   - OMR fallback location: `expense_service.dart:278-282`.
   - exact encoder scale: `expense_service.dart:368-369` and `money_serializer.dart:8-19`.
3. Read path per write path:
   - `splitDistribution` written by `ExpenseService.updateExpense` is read by `Expense.fromFirestore`, then by ledger display and `BalanceCalculator.calculateBalances`; the persisted server-side map is also read by `functions/src/callables/groupNetBalance.ts` for server recomputation.
4. Fields from the type:
   - `Expense` carries `id`, `tripId`, `payerParticipantId`, `amount`, `description`, `scope`, `subGroupId`, `customSplitParticipants`, `splitMode`, `splitDistribution`, `splitExplanation`, `receiptUrl`, `createdAt`, `categoryId`, `note`, `createdBy`, `lastEditedBy`, `categoryName`, `categoryIcon`, `payerName`, `payerAvatarUrl`, `isDeleted`, `deletedAt`, and currency via `currency`.
5. Exact contracts:
   - `SplitMode.exact` distribution values are money amounts and must use `MoneySerializer.toSubunits(value, currency)`.
   - `SplitMode.shares` and `SplitMode.percent` values are not money subunits.
6. Arithmetic decomposition:
   - USD `10.00` exact share must encode as `1000`; OMR fallback would encode it as `10000`.
   - JPY `1200` exact share must encode as `1200`; OMR fallback would encode it as `1200000`.
7. Orthogonal axis:
   - Preserve non-money split updates: a shares split without `currency` still writes raw weights.
   - Preserve metadata-only itemized behavior by passing `currency` only when the update also writes the exact split distribution.

## Task 1: Add the Failing Exact-Split Currency Regression

**Files:**
- Modify: `test/unit/expense_service_test.dart`

- [ ] **Step 1: Write the failing test**

Add this test in the `group('updateExpense', ...)` block after the existing amount-currency tests:

```dart
test(
  'exact split update without currency throws before writing (#665)',
  () async {
    final expense = await service.addExpense(
      createdBy: 'uidA',
      groupId: 'g1',
      eventId: 'e1',
      payerParticipantId: 'p1',
      amount: Decimal.parse('20.00'),
      currency: 'USD',
      splitMode: SplitMode.exact,
      splitDistribution: {
        'p1': Decimal.parse('10.00'),
        'p2': Decimal.parse('10.00'),
      },
    );

    await expectLater(
      service.updateExpense(
        groupId: 'g1',
        eventId: 'e1',
        expenseId: expense.id,
        splitMode: SplitMode.exact,
        splitDistribution: {
          'p1': Decimal.parse('12.34'),
          'p2': Decimal.parse('7.66'),
        },
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('currency'),
        ),
      ),
    );

    final snap = await fakeDb
        .collection('groups')
        .doc('g1')
        .collection('events')
        .doc('e1')
        .collection('expenses')
        .doc(expense.id)
        .get();

    expect(snap.data()!['splitDistribution'], {'p1': 1000, 'p2': 1000});
  },
);
```

- [ ] **Step 2: Verify RED**

Run:

```bash
flutter test test/unit/expense_service_test.dart --plain-name "exact split update without currency throws before writing (#665)"
```

Expected: FAIL because `updateExpense` currently completes and writes `splitDistribution` using `currency ?? 'OMR'`.

## Task 2: Make Exact Split Encoding Fail Safe

**Files:**
- Modify: `lib/features/ledger/services/expense_service.dart`
- Modify: `test/unit/expense_service_test.dart`

- [ ] **Step 1: Update the service implementation**

Change the `updateExpense` doc comment to remove the OMR-default claim and state the new invariant:

```dart
/// Only non-null parameters are included in the Firestore update to avoid
/// overwriting fields with null. [currency] is required for every update path
/// that serializes money: [amount] and [SplitMode.exact] distributions.
```

Keep the existing amount guard, but update the message:

```dart
if (amount != null) {
  if (currency == null) {
    throw ArgumentError(
      'updateExpense requires a currency when amount is set',
    );
  }
  updates['amountFils'] = MoneySerializer.toSubunits(amount, currency);
  updates['currency'] = currency;
}
```

Change the split branch to pass the nullable currency into `_encodeDistribution` without an OMR fallback:

```dart
updates['splitDistribution'] = _encodeDistribution(
  splitMode,
  splitDistribution ?? const {},
  currency,
);
```

Change `_encodeDistribution` to accept `String? currency` and throw for exact mode before encoding:

```dart
static Map<String, int> _encodeDistribution(
  SplitMode mode,
  Map<String, Decimal> distribution,
  String? currency,
) {
  if (mode == SplitMode.exact && currency == null) {
    throw ArgumentError(
      'updateExpense requires a currency when exact split is set',
    );
  }

  return {
    for (final entry in distribution.entries)
      entry.key: switch (mode) {
        SplitMode.exact =>
          MoneySerializer.toSubunits(entry.value, currency!),
        SplitMode.percent =>
          (entry.value * Decimal.fromInt(1000)).toBigInt().toInt(),
        SplitMode.shares ||
        SplitMode.equally =>
          entry.value.toBigInt().toInt(),
      },
  };
}
```

- [ ] **Step 2: Update exact-split tests that intentionally write exact distributions**

In `test/unit/expense_service_test.dart`, add `currency: 'OMR'` to the itemized `updateExpense` call that writes `splitMode: SplitMode.exact`.

Keep the existing shares split-mode test without currency, but rename it so its scope is precise:

```dart
test('shares split edit without amount does not require currency (#665)', () async {
  // existing body unchanged
});
```

Add this positive non-OMR test next to the new throwing test:

```dart
test(
  'exact split update with currency uses that currency scale (#665)',
  () async {
    final cases = <(String, Map<String, Decimal>, Map<String, int>)>[
      (
        'USD',
        {
          'p1': Decimal.parse('12.34'),
          'p2': Decimal.parse('7.66'),
        },
        {'p1': 1234, 'p2': 766},
      ),
      (
        'JPY',
        {
          'p1': Decimal.parse('1200'),
          'p2': Decimal.parse('800'),
        },
        {'p1': 1200, 'p2': 800},
      ),
    ];

    for (final (currency, distribution, expected) in cases) {
      final expense = await service.addExpense(
        createdBy: 'uidA',
        groupId: 'g1',
        eventId: 'e1',
        payerParticipantId: 'p1',
        amount: Decimal.parse('20'),
        currency: currency,
      );

      await service.updateExpense(
        groupId: 'g1',
        eventId: 'e1',
        expenseId: expense.id,
        currency: currency,
        splitMode: SplitMode.exact,
        splitDistribution: distribution,
      );

      final snap = await fakeDb
          .collection('groups')
          .doc('g1')
          .collection('events')
          .doc('e1')
          .collection('expenses')
          .doc(expense.id)
          .get();

      expect(snap.data()!['currency'], currency);
      expect(snap.data()!['splitDistribution'], expected);
    }
  },
);
```

- [ ] **Step 3: Verify GREEN**

Run:

```bash
flutter test test/unit/expense_service_test.dart --plain-name "exact split update without currency throws before writing (#665)"
```

Expected: PASS.

Then run:

```bash
flutter test test/unit/expense_service_test.dart
```

Expected: PASS.

## Task 3: Full Verification

**Files:**
- No code changes.

- [ ] **Step 1: Analyze**

Run:

```bash
flutter analyze --no-fatal-infos
```

Expected: completes without errors.

- [ ] **Step 2: Theme purity**

Run:

```bash
bash tool/check_theme_purity.sh
```

Expected: PASS. This change does not touch UI colors, but this is cheap and catches accidental widget drift.

- [ ] **Step 3: Diff hygiene**

Run:

```bash
git diff --check
```

Expected: no whitespace errors.

## Gate Stop Condition

Before Task 1 implementation, run the Rihla Gate on this spec with a fresh-context subagent. Do not touch production code until the reviewer returns `0 P1`.
