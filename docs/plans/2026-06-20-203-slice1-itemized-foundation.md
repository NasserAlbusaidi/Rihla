# #203 Slice 1 — Itemized Split Foundation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Land the *not-user-visible* schema + allocator foundation for itemized expense splitting: a `splitExplanation` display-metadata field, a pure `items → splitDistribution` allocator, and the `firestore.rules` allowlist/bound — so the itemized editor (Slice 2) and bill-level adjustments (#605) become purely additive.

**Architecture:** Itemized splits persist as a **standard `SplitMode.exact` expense** plus an opaque `splitExplanation` map. There is **no new `SplitMode` and no new balance algorithm.** A pure client-side producer (`BalanceCalculator.allocateItemizedDistribution`) folds line-items into the exact `splitDistribution` (integer-subunit, per-item alphabetically-last remainder, conservation Σ=bill). `splitExplanation` is **INBOUND/display-only** — it reconstructs the editor on reopen and is *never* read by balance math, the server oracle, or any Cloud Function. That display-only property is the entire safety case.

**Tech Stack:** Flutter / Dart, `decimal` package, `MoneySerializer` (subunit boundary), Riverpod, Firestore security rules (CEL), Jest + Firebase rules emulator.

---

## Scope boundary — Slice 1 vs Slice 2 (read first)

Per the #203 decision comment (2026-06-20), Slice 1 is the **irreversible schema lock-in + the pure allocator + tests — NOT user-visible.**

**IN (Slice 1):**
- `SplitExplanation` + `SplitItem` model (`fromMap`/`toMap`, reserved opaque `adjustments`).
- `Expense.splitExplanation` field threaded through `fromFirestore` (read) + `toFirestore` (write) + `copyWith`.
- `BalanceCalculator.allocateItemizedDistribution` — pure `items → Map<String,Decimal>` exact distribution.
- `firestore.rules`: add `splitExplanation` to BOTH expense allowlists + a `splitExplanationBounded` wrapper guard.
- Tests: allocator money tests, model round-trip, rules emulator accept/reject.

**OUT (Slice 2 — the itemized editor, co-dependent with the value's producer):**
- `ExpenseEditorPayload` / `add_expense_screen` / `edit_expense_screen` plumbing.
- The three inline write-map builders in `expense_service.dart` (`stageExpense`/`updateExpense`/`deleteExpense`). **Note:** `Expense.toFirestore()` has zero production callers today; the service builds its own maps. So Slice 1 wiring `toFirestore` does **not** persist `splitExplanation` in production — and that is correct: nothing *produces* a `splitExplanation` until Slice 2's editor exists, so wiring the service now would add unused params. `Expense.fromFirestore` *reading* it IS wired (forward-compat: Slice 2's writes round-trip on read).
  - **Slice 2 hand-off (named, so it can't be missed):** replicate the exact **omit-when-null** conditional `if (splitExplanation != null) 'splitExplanation': splitExplanation!.toMap()` in each inline builder that should carry it — `stageExpense`'s `data` map (`expense_service.dart` ~`:183-211`), `updateExpense`'s `updates` map (~`:245-288`, gated like `splitChanged` so an explanation-only edit persists), and `deleteExpense` (~`:308-334`) only if it must survive soft-delete. `toFirestore` is the *reference shape* but is NOT the runtime source. Writing `splitExplanation: null` is rejected by the `is map` rules bound, so the conditional is **mandatory, not stylistic**. Also: the split block is omitted when `splitMode==equally` — itemized is always `exact`, so this doesn't bite, but don't nest `splitExplanation` inside that gate.
- The itemized sub-sheet UI, live preview, reconcile-to-total.

**OUT (#605):** bill-level adjustments (service/tax/tip/discount). The `splitExplanation.adjustments[]` slot is *reserved* and round-tripped opaquely in Slice 1.

---

## Verification principles — run against live code (results out loud)

1. **Classify every callsite on a shared read/write path.** `splitExplanation` is **INBOUND only** — it is written by the (future) editor and read solely to reconstruct the editor display. It never feeds `calculateBalances`/`allocateExpenseOwed`/the oracle. The OUTBOUND money artifact is `splitDistribution` (persisted `SplitMode.exact`), produced by the allocator. The allocator's *inputs* (`SplitItem.amountFils`/`participantIds`) are OUTBOUND (feed the persisted distribution) → treated with money rigor (integer subunits, conservation, whole-subunit shares). Invalid inputs (negative `amountFils`, zero-assignee items) are **rejected at the producer (throws `ArgumentError`)** — not silently tolerated — so this write-time producer can never emit a negative owed or a non-conserving distribution. (Read-time consumers like `_allocateExact` *defend* against forged persisted data via fallback; a producer of fresh data *rejects* — that asymmetry is deliberate.)

2. **Verify every concrete claim against code.** Verified via the understand fan-out (`wf_174e4648-a79`): `validExpenseBase` hasOnly at `firestore.rules:527-548`; `validExpenseUpdate` affectedKeys hasOnly at `:629-646` (SEPARATE allowlist); `splitValuesNonNegative` wrapper at `:494-498` wired unconditionally on create (`:575`) + diff-gated on update (`:648-649`); publish-readiness test at `functions/test/firestore-rules-publish-readiness.test.ts` (`validExpense()` factory `:157-177`). Allocator contract read directly: `_allocateEqual`/`_toCurrencyPrecision` (`expense_provider.dart:664-700`). Re-grep at edit time before each change.

3. **Trace one read-path per write-path.** Write-path: allocator → exact `splitDistribution` → (Slice 2 service) → Firestore. Read-path: `Expense.fromFirestore` → `splitDistribution` decoded → `BalanceCalculator.allocateExpenseOwed` → `_allocateExact`. **Named answer for "who reads this after it changes":** `_allocateExact` (`expense_provider.dart:540-605`). Because Σ(distribution)==amount exactly, `residual == Decimal.zero` (`:568-569`) → returns `Map.from(distribution)` unchanged → WYSIWYG round-trip is automatic, no fallback fires. `splitExplanation` itself is read only by the (Slice 2) editor — confirmed 0 reads in `functions/src` and 0 in balance math.

4. **Enumerate fields from the type.** `Expense` fields enumerated from `expense_model.dart:25-93` (19 persisted Firestore keys; matches the rules allowlist exactly). New field `splitExplanation` added to: field decl, const ctor, `fromFirestore`, `toFirestore`, `copyWith`. `SplitExplanation` = `{type, version, items, adjustments?}`; `SplitItem` = `{label, amountFils, quantity, participantIds, allocation}` — exact per the #203 locked schema.

5. **Spell out data contracts.** Persisted map keys (exact): `splitExplanation: {type:'itemized', version:1, items:[{label, amountFils, quantity, participantIds, allocation}], adjustments?:[...]}`. `amountFils` = **integer subunit LINE TOTAL** (quantity already folded in; the allocator never multiplies by `quantity`). Allocator signature: `allocateItemizedDistribution({required List<SplitItem> items, required String currency}) → Map<String,Decimal>`.

6. **Verify arithmetic decomposition.** Conservation is exact **by construction**: each item's `amountFils` is fully distributed (integer `base*n + remainder == amountFils`), so `Σ_person owed == Σ_item amountFils == billTotalFils`. This is `aggregate = sum(slices)` where each slice is a complete integer partition — no fractional residue escapes. **This only holds if no item is dropped**, so the allocator REJECTS (throws) a zero-assignee item — otherwise its cost would vanish and `Σ distribution < Σ items`, forcing `_allocateExact` into the tolerance fallback (itemization silently discarded). **Contract: `Σ(distribution) == Σ(item amountFils)`; Slice 2 persists `Expense.amount := Σ items`** (not a separately typed bill) so the exact read-back never drifts. Whole-subunit invariant (#596): every owed value is an integer subunit count (we accumulate `int` subunits and convert once via `MoneySerializer.fromSubunits`), so `netBalance` stays whole-subunit and the settle-up cap won't reject.

7. **Adversarial pass on an orthogonal axis.** The fix axis is *itemization/allocation*. Orthogonal axes exercised in tests: **currency** (OMR 3dp vs USD 2dp vs JPY ×1 — scale landmine), **identity/sort** (out-of-order `participantIds` → remainder still lands alphabetically-last, proving sort-by-id not insertion-order), **multi-item accumulation** (one person across several items sums correctly), and **absence** (a member in no item is absent from the distribution → owes 0.000 via the existing drop-guard). RTL exercised via an Arabic `label` round-trip.

**Oracle / parity note (pre-empting the false alarm):** itemized is a *client-side write-time producer* of a standard `SplitMode.exact` distribution — **not** a new mode the server must mirror. `recomputeNet` reads `splitMode`+`splitDistribution`(+amount/scope/payer/custom) and already decodes exact mode identically. It never reads `splitExplanation` (0 matches in `functions/src`). So there is **zero server change** and **no parity risk** — parity holds precisely because itemized reduces to exact at persistence.

---

## Task 1: `SplitItem` + `SplitExplanation` model

**Files:**
- Create: `lib/features/ledger/models/split_explanation.dart`
- Test: `test/unit/split_explanation_model_test.dart`

**Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/models/split_explanation.dart';

void main() {
  group('SplitItem round-trip', () {
    test('toMap/fromMap preserves all fields incl. Arabic label (RTL)', () {
      const item = SplitItem(
        label: 'قهوة',
        amountFils: 1500,
        quantity: 2,
        participantIds: ['p2', 'p1'],
        allocation: 'equal',
      );
      final restored = SplitItem.fromMap(item.toMap());
      expect(restored.label, 'قهوة');
      expect(restored.amountFils, 1500);
      expect(restored.quantity, 2);
      expect(restored.participantIds, ['p2', 'p1']);
      expect(restored.allocation, 'equal');
    });

    test('fromMap tolerates missing optional keys', () {
      final item = SplitItem.fromMap({
        'label': 'Tea',
        'amountFils': 500,
        'participantIds': ['p1'],
      });
      expect(item.quantity, 1);
      expect(item.allocation, 'equal');
    });
  });

  group('SplitExplanation round-trip', () {
    test('toMap/fromMap preserves type, version, items', () {
      const exp = SplitExplanation(items: [
        SplitItem(label: 'Pizza', amountFils: 3000, participantIds: ['p1', 'p2']),
      ]);
      final restored = SplitExplanation.fromMap(exp.toMap());
      expect(restored.type, 'itemized');
      expect(restored.version, 1);
      expect(restored.items.length, 1);
      expect(restored.items.first.label, 'Pizza');
      expect(restored.items.first.amountFils, 3000);
    });

    test('omits adjustments key when null, round-trips it opaquely when present', () {
      const noAdj = SplitExplanation(items: []);
      expect(noAdj.toMap().containsKey('adjustments'), isFalse);

      final withAdj = SplitExplanation(items: const [], adjustments: const [
        {'type': 'service_charge', 'amountFils': 250, 'allocation': 'equal'},
      ]);
      final restored = SplitExplanation.fromMap(withAdj.toMap());
      expect(restored.adjustments, isNotNull);
      expect((restored.adjustments!.first as Map)['type'], 'service_charge');
    });
  });
}
```

**Step 2: Run to verify failure** — `flutter test test/unit/split_explanation_model_test.dart` → FAIL (file/class not found).

**Step 3: Implement**

```dart
// lib/features/ledger/models/split_explanation.dart

/// One line item on an itemized bill (#203). Display-only metadata that
/// reconstructs the itemized editor on reopen; balance truth lives in the
/// expense's `splitDistribution` (persisted as `SplitMode.exact`).
///
/// [amountFils] is the integer-subunit LINE TOTAL (quantity already folded in
/// by the editor). [quantity] is display-only ("2× Coffee"); the allocator
/// never multiplies by it. [allocation] is `'equal'` in v1.
class SplitItem {
  final String label;
  final int amountFils;
  final int quantity;
  final List<String> participantIds;
  final String allocation;

  const SplitItem({
    required this.label,
    required this.amountFils,
    this.quantity = 1,
    required this.participantIds,
    this.allocation = 'equal',
  });

  factory SplitItem.fromMap(Map<String, dynamic> map) {
    return SplitItem(
      label: map['label'] as String? ?? '',
      amountFils: (map['amountFils'] as num?)?.toInt() ?? 0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      participantIds:
          (map['participantIds'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      allocation: map['allocation'] as String? ?? 'equal',
    );
  }

  Map<String, dynamic> toMap() => {
    'label': label,
    'amountFils': amountFils,
    'quantity': quantity,
    'participantIds': participantIds,
    'allocation': allocation,
  };
}

/// Opaque display metadata for an itemized expense (#203). Reconstructs the
/// itemized editor on reopen. **INBOUND/display-only** — NEVER read by balance
/// math, the server oracle, or any Cloud Function. firestore.rules guards it as
/// `is map` + bounded only.
class SplitExplanation {
  final String type;
  final int version;
  final List<SplitItem> items;

  /// RESERVED for #605 (bill-level adjustments). Slice 1 round-trips it
  /// opaquely so a #605-written doc never loses adjustments when read here.
  final List<dynamic>? adjustments;

  const SplitExplanation({
    this.type = 'itemized',
    this.version = 1,
    required this.items,
    this.adjustments,
  });

  factory SplitExplanation.fromMap(Map<String, dynamic> map) {
    return SplitExplanation(
      type: map['type'] as String? ?? 'itemized',
      version: (map['version'] as num?)?.toInt() ?? 1,
      items:
          (map['items'] as List?)
              ?.whereType<Map>()
              .map((e) => SplitItem.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      adjustments: map['adjustments'] as List?,
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type,
    'version': version,
    'items': [for (final i in items) i.toMap()],
    if (adjustments != null) 'adjustments': adjustments,
  };
}
```

**Step 4: Run to verify pass.** **Step 5: Commit** `feat(ledger): SplitExplanation/SplitItem itemized-split model (#203 Slice 1)`.

---

## Task 2: `allocateItemizedDistribution` allocator (the money core)

**Files:**
- Modify: `lib/features/ledger/providers/expense_provider.dart` (add public static to `BalanceCalculator`, after `allocateExpenseOwed` ~`:503`; add `import '../models/split_explanation.dart';`)
- Test: `test/unit/itemized_split_allocator_test.dart`

**Step 1: Write the failing tests** (table-driven, mirroring `balance_calculations_test.dart` — exact `Decimal`, fold-conservation, `subunits.isInteger`).

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/models/split_explanation.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

Decimal _d(String s) => Decimal.parse(s);

void main() {
  group('allocateItemizedDistribution', () {
    test('coffee case: each item solo-assigned; a non-buyer is absent (owes 0)', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'Latte', amountFils: 1500, participantIds: ['p1']),
          SplitItem(label: 'Mocha', amountFils: 2000, participantIds: ['p2']),
        ],
        currency: 'OMR',
      );
      expect(dist['p1'], _d('1.500'));
      expect(dist['p2'], _d('2.000'));
      expect(dist.containsKey('p3'), isFalse); // non-buyer absent → owes 0.000
      // conservation: Σ == bill total 3.500
      expect(dist.values.fold(Decimal.zero, (s, v) => s + v), _d('3.500'));
    });

    test('shared item OMR 3dp: 1.000/3 → remainder on alphabetically-last', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          // deliberately out-of-order ids to prove sort-by-id, not insertion
          SplitItem(label: 'Pizza', amountFils: 1000, participantIds: ['p3', 'p1', 'p2']),
        ],
        currency: 'OMR',
      );
      expect(dist['p1'], _d('0.333'));
      expect(dist['p2'], _d('0.333'));
      expect(dist['p3'], _d('0.334')); // alphabetically-last absorbs +1 baisa
      expect(dist.values.fold(Decimal.zero, (s, v) => s + v), _d('1.000'));
      for (final v in dist.values) {
        expect((v * Decimal.fromInt(1000)).isInteger, isTrue); // whole-subunit (#596)
      }
    });

    test('multi-item accumulation across items', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [
          SplitItem(label: 'Starter', amountFils: 500, participantIds: ['p1']),
          SplitItem(label: 'Shared', amountFils: 1000, participantIds: ['p1', 'p2']),
        ],
        currency: 'OMR',
      );
      expect(dist['p1'], _d('1.000')); // 0.500 solo + 0.500 share
      expect(dist['p2'], _d('0.500'));
      expect(dist.values.fold(Decimal.zero, (s, v) => s + v), _d('1.500'));
    });

    test('USD 2dp scale: 10.00/3 shared → 3.33/3.33/3.34', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [SplitItem(label: 'Tab', amountFils: 1000, participantIds: ['a', 'b', 'c'])],
        currency: 'USD',
      );
      expect(dist['a'], _d('3.33'));
      expect(dist['c'], _d('3.34'));
      expect(dist.values.fold(Decimal.zero, (s, v) => s + v), _d('10.00'));
    });

    test('JPY ×1 scale: 1000/3 shared → 333/333/334', () {
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [SplitItem(label: 'Set', amountFils: 1000, participantIds: ['a', 'b', 'c'])],
        currency: 'JPY',
      );
      expect(dist['a'], _d('333'));
      expect(dist['c'], _d('334'));
      expect(dist.values.fold(Decimal.zero, (s, v) => s + v), _d('1000'));
    });

    test('throws on a zero-assignee item (its cost must land somewhere)', () {
      expect(
        () => BalanceCalculator.allocateItemizedDistribution(
          items: const [SplitItem(label: 'Orphan', amountFils: 900, participantIds: [])],
          currency: 'OMR',
        ),
        throwsArgumentError,
      );
    });

    test('throws on negative amountFils (producer never emits a negative owed)', () {
      expect(
        () => BalanceCalculator.allocateItemizedDistribution(
          items: const [SplitItem(label: 'Bad', amountFils: -300, participantIds: ['p1', 'p2'])],
          currency: 'OMR',
        ),
        throwsArgumentError,
      );
    });

    test('conservation contract: Σ distribution == Σ item amountFils (the persisted amount)', () {
      const items = [
        SplitItem(label: 'A', amountFils: 1500, participantIds: ['p1']),
        SplitItem(label: 'B', amountFils: 1000, participantIds: ['p1', 'p2', 'p3']),
        SplitItem(label: 'C', amountFils: 333, participantIds: ['p2', 'p3']),
      ];
      final dist = BalanceCalculator.allocateItemizedDistribution(items: items, currency: 'OMR');
      final sumItemsFils = items.fold<int>(0, (s, i) => s + i.amountFils);
      expect(sumItemsFils, 2833);
      expect(dist.values.fold(Decimal.zero, (s, v) => s + v), _d('2.833'));
    });

    test('round-trips byte-clean through the persisted exact read-back path', () {
      // distribution feeds calculateBalances exactly (sum==amount → _allocateExact residual 0)
      final dist = BalanceCalculator.allocateItemizedDistribution(
        items: const [SplitItem(label: 'X', amountFils: 1000, participantIds: ['p1', 'p2', 'p3'])],
        currency: 'OMR',
      );
      final owed = BalanceCalculator.allocateExpenseOwed(
        amount: _d('1.000'),
        splitMode: SplitMode.exact,
        splitDistribution: dist,
        scope: ExpenseScope.global,
        customSplitParticipants: null,
        payerId: 'p1',
        participantIds: const ['p1', 'p2', 'p3'],
        currency: 'OMR',
      );
      expect(owed, dist); // exact read-back, no mutation
    });
  });
}
```

(`SplitMode` import resolves via `expense_provider.dart` re-exports; if not, add `import 'package:safar/core/models/split_mode.dart';`.)

**Step 2: Run to verify failure** — method undefined.

**Step 3: Implement** (add to `BalanceCalculator`):

```dart
/// Pure itemized → exact-distribution producer (#203 Slice 1). Each
/// [SplitItem.amountFils] (integer-subunit LINE TOTAL) is split equally among
/// its [SplitItem.participantIds]; the per-item integer remainder lands on the
/// alphabetically-last assignee (the project-wide remainder contract). Owed
/// accumulates across items.
///
/// Returns the `SplitMode.exact` splitDistribution to persist:
///  - Σ(values) == Σ(item amountFils) exactly (conservation), and
///  - every value is a whole number of subunits (#596 — keeps netBalance
///    whole-subunit so client↔server oracle parity + the settle-up cap hold).
///
/// This is a WRITE-TIME producer, NOT part of the read-time oracle surface:
/// the persisted artifact is a standard exact split that `recomputeNet`/
/// `_allocateExact` already decode, so there is no server mirror to keep in
/// lockstep.
///
/// Preconditions — ENFORCED here (throws `ArgumentError`), so this producer can
/// never emit a negative owed or a non-conserving distribution:
///  - non-negative [SplitItem.amountFils] — a negative price is invalid input.
///    The Slice 2 editor validates pre-call; `firestore.rules`
///    `splitValuesNonNegative` is the write backstop; `_allocateExact` guards
///    forged docs on read. The producer rejects rather than emit a negative.
///  - ≥1 assignee per item — every item's cost must land somewhere, else
///    `Σ distribution < Σ items` and the bill cannot reconcile (`_allocateExact`
///    would then drift into the tolerance fallback and silently discard the
///    itemization).
///
/// CONTRACT for Slice 2: `Σ(returned values) == Σ(item amountFils)`, which is
/// the `Expense.amount` to persist. The Slice 2 editor enforces ≥1 assignee +
/// reconcile-to-total in the UI (and avoids/handles the throw during live
/// mid-edit states, e.g. an item just added with no assignee yet).
static Map<String, Decimal> allocateItemizedDistribution({
  required List<SplitItem> items,
  required String currency,
}) {
  final fenced = MoneySerializer.isSupported(currency) ? currency : 'OMR';
  final owedSubunits = <String, int>{};

  for (final item in items) {
    if (item.amountFils < 0) {
      throw ArgumentError.value(
        item.amountFils, 'amountFils', 'itemized item "${item.label}" is negative');
    }
    final assignees = item.participantIds.toSet().toList()..sort();
    if (assignees.isEmpty) {
      throw ArgumentError.value(
        item.participantIds, 'participantIds',
        'itemized item "${item.label}" has no assignees');
    }
    final n = assignees.length;
    final base = item.amountFils ~/ n;
    final remainder = item.amountFils - base * n;
    for (var i = 0; i < n; i++) {
      final share = base + (i == n - 1 ? remainder : 0);
      owedSubunits[assignees[i]] = (owedSubunits[assignees[i]] ?? 0) + share;
    }
  }

  return {
    for (final entry in owedSubunits.entries)
      entry.key: MoneySerializer.fromSubunits(entry.value, fenced),
  };
}
```

**Step 4: Run to verify pass.** **Step 5: Commit** `feat(ledger): pure itemized→exact distribution allocator (#203 Slice 1)`.

---

## Task 3: Thread `splitExplanation` through the `Expense` model

**Files:**
- Modify: `lib/features/ledger/models/expense_model.dart` (import; field; ctor; `fromFirestore`; `toFirestore`; `copyWith`)
- Test: `test/unit/split_explanation_model_test.dart` (extend with Expense-level cases)

**Step 1: Add failing Expense round-trip tests**

```dart
// (append to split_explanation_model_test.dart)
import 'package:decimal/decimal.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/core/models/split_mode.dart';

// inside main():
group('Expense splitExplanation persistence', () {
  Expense base() => Expense(
    id: 'e1', tripId: 't1', payerParticipantId: 'p1',
    amount: Decimal.parse('1.000'), scope: ExpenseScope.global,
    splitMode: SplitMode.exact,
    splitDistribution: {'p1': Decimal.parse('0.500'), 'p2': Decimal.parse('0.500')},
    createdAt: DateTime.utc(2026, 6, 20), currency: 'OMR',
  );

  test('toFirestore OMITS splitExplanation when null (null fails the is-map rules bound)', () {
    expect(base().toFirestore().containsKey('splitExplanation'), isFalse);
  });

  test('toFirestore writes + fromFirestore restores splitExplanation', () {
    final e = base().copyWith(
      splitExplanation: const SplitExplanation(items: [
        SplitItem(label: 'Latte', amountFils: 500, participantIds: ['p1']),
        SplitItem(label: 'Mocha', amountFils: 500, participantIds: ['p2']),
      ]),
    );
    final map = e.toFirestore();
    expect(map['splitExplanation'], isA<Map>());
    final restored = Expense.fromFirestore({...map, 'id': 'e1'});
    expect(restored.splitExplanation, isNotNull);
    expect(restored.splitExplanation!.items.length, 2);
    expect(restored.splitExplanation!.items.first.label, 'Latte');
  });
});
```

**Step 2: Run to verify failure** — `copyWith`/field absent.

**Step 3: Implement** — in `expense_model.dart`:
- Add `import 'split_explanation.dart';`
- Field (near `splitDistribution`): `final SplitExplanation? splitExplanation;`
- Const ctor param: `this.splitExplanation,`
- In `fromFirestore` (after `splitDistribution:` ~`:204`):
```dart
splitExplanation: data['splitExplanation'] != null
    ? SplitExplanation.fromMap(
        Map<String, dynamic>.from(data['splitExplanation'] as Map))
    : null,
```
- In `toFirestore` (after the `if (splitMode != null) {...}` block ~`:239`) — **conditional, never write null:**
```dart
if (splitExplanation != null)
  'splitExplanation': splitExplanation!.toMap(),
```
- In `copyWith`: add param `SplitExplanation? splitExplanation,` and body `splitExplanation: splitExplanation ?? this.splitExplanation,`. (No `clear` flag in Slice 1 — YAGNI; the editor adds it in Slice 2 when an itemized→non-itemized edit needs it.)

**Do NOT** thread through `fromJson`/`toJson` (legacy Supabase snake_case paths; Firebase-only live path is `fromFirestore`/`toFirestore`). Document inline.

**Step 4: Run to verify pass.** **Step 5: Commit** `feat(ledger): persist splitExplanation on Expense Firestore round-trip (#203 Slice 1)`.

---

## Task 4: `firestore.rules` allowlist + opaque bound

**Files:**
- Modify: `security/firestore.rules` (2 allowlists + 1 helper + 2 wirings)
- Test: `functions/test/firestore-rules-publish-readiness.test.ts` (accept/reject cases)

**Read first** (per contract — don't edit from the fan-out snippet): re-open `security/firestore.rules` at `:494-498`, `:527-548`, `:570-585`, `:629-646`, `:648-649` and confirm line numbers before editing.

**Step 1: Add failing emulator tests** (in the expense block; mirror `assertSucceeds`/`assertFails` + `validExpense({...})`; every UPDATE includes `lastEditedBy == acting uid`; do **not** add `splitExplanation` to the `validExpense()` factory default).

```ts
test('#203 splitExplanation accepted as opaque display-only map (create)', async () => {
  const member = testEnv.authenticatedContext('member').firestore();
  await assertSucceeds(
    member.doc('groups/g1/events/e1/expenses/expSE').set(validExpense({
      id: 'expSE', createdBy: 'member', lastEditedBy: 'member',
      splitExplanation: { type: 'itemized', version: 1,
        items: [{ label: 'Latte', amountFils: 500, quantity: 1, participantIds: ['member'], allocation: 'equal' }] },
    })),
  );
});

test('#203 splitExplanation accepted on update (proves the SECOND allowlist)', async () => {
  // seed a plain expense first, then update only splitExplanation + lastEditedBy
  const member = testEnv.authenticatedContext('member').firestore();
  const ref = member.doc('groups/g1/events/e1/expenses/expUpd');
  await assertSucceeds(ref.set(validExpense({ id: 'expUpd', createdBy: 'member', lastEditedBy: 'member' })));
  await assertSucceeds(ref.update({ splitExplanation: { type: 'itemized', version: 1, items: [] }, lastEditedBy: 'member' }));
});

test('#203 splitExplanation rejected when not a map (pins is map)', async () => {
  const member = testEnv.authenticatedContext('member').firestore();
  await assertFails(
    member.doc('groups/g1/events/e1/expenses/expBad').set(validExpense({
      id: 'expBad', createdBy: 'member', lastEditedBy: 'member',
      splitExplanation: 'not-a-map',
    })),
  );
});

test('#203 splitExplanation rejected with >64 top-level keys (entry-count cap, NOT array length — Firestore 1MB doc limit bounds payload)', async () => {
  const member = testEnv.authenticatedContext('member').firestore();
  const big: Record<string, number> = {};
  for (let i = 0; i < 65; i++) big[`k${i}`] = i;
  await assertFails(
    member.doc('groups/g1/events/e1/expenses/expBig').set(validExpense({
      id: 'expBig', createdBy: 'member', lastEditedBy: 'member', splitExplanation: big,
    })),
  );
});
```

**Step 2: Run to verify failure** (the accept cases fail — un-allowlisted key rejected):
```
RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/firestore-rules-publish-readiness.test.ts" npm --prefix functions run test:emulator
```
Expected: the two ACCEPT tests FAIL (write rejected — `splitExplanation` not yet allowlisted), the two REJECT tests may pass vacuously. Confirm the RED is in the #203 block (scoping trap).

**Step 3: Implement rules** (3 additive edits):

(a) Add `'splitExplanation'` to the `validExpenseBase` hasOnly array (`:527-548`) — covers create + base-shape-on-update.

(b) Add `'splitExplanation'` to the `validExpenseUpdate` `affectedKeys().hasOnly([...])` array (`:629-646`) — the SEPARATE update allowlist.

(c) Add the wrapper guard near `splitValuesNonNegative` (`:494-498`):
```
// #203 — splitExplanation is OPAQUE display-only metadata (balance truth stays
// in splitDistribution). Guard type + a generous top-level entry-count cap only;
// value content is intentionally unvalidated. NOTE: map.size() counts entry
// COUNT, not value weight — the 1MB Firestore doc limit is the hard size
// backstop. Kept in the create/update WRAPPERS (not validExpenseBase) so a
// legacy/forged oversized doc stays soft-deletable (#192/#194 pattern).
function splitExplanationBounded(d) {
  return !d.keys().hasAny(['splitExplanation'])
    || (d.splitExplanation is map && d.splitExplanation.size() <= 64);
}
```
Wire unconditionally into `validExpenseCreate` (append `&& splitExplanationBounded(request.resource.data)` after the `splitValuesNonNegative` clause ~`:575`), and diff-gated into `validExpenseUpdate` (mirroring `:648-649`):
```
&& (!request.resource.data.diff(resource.data).affectedKeys().hasAny(['splitExplanation'])
    || splitExplanationBounded(request.resource.data))
```

**Do NOT** touch `validEventSettlementUpdate`/`validGroupSettlementUpdate` (DEAD code — settlements hard-deny update; `splitExplanation` flows only through the expense validators).

**Step 4: Run to verify pass** (all four #203 cases green; full file green).

**Step 5: Commit** `feat(rules): allow opaque splitExplanation on expenses, bounded (#203 Slice 1)`.

---

## Final verification (Task 6 gate)

```bash
flutter analyze                                  # clean
flutter test test/unit/itemized_split_allocator_test.dart test/unit/split_explanation_model_test.dart
flutter test                                     # full suite (no regressions)
RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/firestore-rules-publish-readiness.test.ts" npm --prefix functions run test:emulator
```
Paste failing-before / passing-after output. No "done" without it.

## Deploy / merge

- Rules change → after merge, deploy ceremony (`deploy-ceremony` skill). No-real-users → deploy freely (no client-compat gating). Functions unchanged (oracle untouched) — rules-only deploy.
- Commit/PR carry **`Refs #203`** (partial slice — #203 stays OPEN re-scoped to Slice 2). `Refs #203` MUST be in the **commit body** (squash auto-closes from the commit message), not only the PR body.
- Gate-category PR → `/automerge` runs the fresh-context diff review + refuter.

## Out of scope (do not build here)
Itemized editor UI / sub-sheet, live preview, reconcile-to-total, `ExpenseEditorPayload`/screen/service write-path wiring (Slice 2); bill-level adjustments (#605); receipt OCR, item detection, menu/catalog, multi-currency conversion, recap.
