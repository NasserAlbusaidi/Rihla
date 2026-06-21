# #203 Slice 2 — Itemized Split Editor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let a user build an expense by listing its line items, assigning each to one or more people (or "Everyone"), and have the app compute the exact per-person split — persisted as a normal `SplitMode.exact` + opaque `splitExplanation` metadata so balances and the server oracle are unchanged.

**Architecture:** Itemized is **not** a new `SplitMode`. It is a 5th option in the existing `custom_split_sheet.dart` ("How to split") that, on Apply, runs the already-deployed pure allocator `BalanceCalculator.allocateItemizedDistribution` and returns `SplitMode.exact` + the allocated `splitDistribution` + the `List<SplitItem>`. The editor body persists the items as `splitExplanation` through the **inline map builders** in `expense_service.dart` (NOT `Expense.toFirestore`, which has zero prod callers). Reopen reconstructs the editor from `splitExplanation.items`.

**Tech Stack:** Flutter, Riverpod 2.x, `decimal`, `MoneySerializer` (subunit round-trip), `fake_cloud_firestore` for service tests, `flutter_test` widget tests.

**Design (signed off):** `docs/design/mockups/203-itemized-split-editor.html` Frame B.

**Backend:** CLIENT-ONLY. No `firestore.rules` change, no Cloud Functions, **no deploy.** Slice 1 (`29abede0`, deployed) already shipped the rules surface for `splitExplanation` on both create and update.

---

## Load-Bearing Context (read before touching code)

- **No new `SplitMode`.** `enum SplitMode { equally, shares, exact, percent }` (`lib/core/models/split_mode.dart:6`) stays frozen (storageKeys are persisted on devices). Itemized persists AS `exact`.
- **The write path is the inline maps, not the model.** `ExpenseService.stageExpense` builds an inline `data` map (`expense_service.dart:183-211`); `updateExpense` builds an inline `updates` map (`:245-294`). `Expense.toFirestore` is dead for writes — do not route through it.
- **`splitExplanation` is a TOP-LEVEL field**, not nested in the `splitMode`/`splitDistribution` block (`expense_model.dart:255-257` comment). The S1 allocator's output IS the `splitDistribution`; the items are separate display metadata.
- **Deployed rules contract** (`security/firestore.rules`):
  - `validExpenseBase` `hasOnly([...])` includes `'splitExplanation'` (`:595`) — allowed on create + update.
  - `splitExplanationBounded(d)`: `!d.keys().hasAny(['splitExplanation']) || (d.splitExplanation is map && d.splitExplanation.size() <= 64)` (`:542-545`). `size()` = TOP-LEVEL entry count. Our map = `{type, version, items[, adjustments]}` = 3–4 entries. ✓
  - Create enforces it unconditionally (`:624`); update enforces it diff-gated (`:700-701`).
  - `FieldValue.delete()` on update → key absent → `!hasAny(['splitExplanation'])` → true. So orphan-delete is rules-legal. ✓
- **`ledgerRevisionProvider` is already bumped** in `add_expense_screen.dart:83` and `edit_expense_screen.dart:157` — itemized reuses these write paths, so **no new bump site.**
- **Allocator preconditions** (`allocateItemizedDistribution`, `expense_provider.dart:531-567`): throws `ArgumentError` on negative `amountFils` or a zero-assignee item. The editor MUST validate (amount ≥ 0, ≥1 assignee) before calling — the reconcile gate covers this.
- **Currency scale** is per-expense (`effectiveCurrency`): OMR/KWD/BHD ×1000, USD/EUR/GBP/SAR/AED/QAR ×100, **JPY ×1**. `SplitItem.amountFils` is integer subunits in that currency; build via `MoneySerializer.toSubunits(decimal, currency)`.
- **Reconcile tolerance:** mirror Exact mode — `_tolerance = Decimal.parse('0.001')` (`custom_split_sheet.dart:106`). Apply gated on `(Σitems − total).abs() <= tolerance`.

---

## Data Contracts (exact)

**`SplitResult`** (`custom_split_sheet.dart:21`):
```dart
class SplitResult {
  const SplitResult({required this.mode, required this.distribution, this.items});
  final SplitMode mode;
  final Map<String, Decimal>? distribution;
  /// Non-null ONLY for an itemized result. When set, [mode] is always
  /// SplitMode.exact and [distribution] is allocateItemizedDistribution(items).
  final List<SplitItem>? items;
}
```

**`ExpenseEditorPayload`** (`expense_editor_body.dart:59`): add
```dart
/// Itemized display metadata (#203 S2). Non-null ⇒ splitMode is exact and the
/// distribution came from allocateItemizedDistribution. Null for every other mode.
final SplitExplanation? splitExplanation;
```

**`ExpenseService.stageExpense` / `addExpense`**: add param `SplitExplanation? splitExplanation`. In the `data` map, top-level:
```dart
if (splitExplanation != null) 'splitExplanation': splitExplanation.toMap(),
```

**`ExpenseService.updateExpense`**: add params `SplitExplanation? splitExplanation, bool clearExplanation = false`. After the existing split block:
```dart
if (clearExplanation) {
  updates['splitExplanation'] = FieldValue.delete();
} else if (splitExplanation != null) {
  updates['splitExplanation'] = splitExplanation.toMap();
}
```

**`edit_expense_screen._save` orphan logic** (the adversarial-axis crux):
```dart
final explanationChanged =
    !_explanationEquals(payload.splitExplanation, original.splitExplanation);
// ... in updateExpense(...):
splitExplanation:
    explanationChanged && payload.splitExplanation != null
        ? payload.splitExplanation
        : null,
clearExplanation:
    explanationChanged && payload.splitExplanation == null,
```
`splitExplanation` is written through its OWN param, **independent of `splitChanged`** — so a **relabel-only** edit (distribution byte-identical, only a label changed) still persists the new metadata even though `splitMode`/`splitDistribution` are correctly left untouched. The existing `splitChanged` definition is unchanged (do NOT fold `explanationChanged` into it — that would needlessly rewrite an identical `splitDistribution`). Rules accept a `{splitExplanation, lastEditedBy}`-only update (proven by `firestore-rules-publish-readiness.test.ts`). The relabel-only edit's `affectedKeys` = `{splitExplanation, lastEditedBy}`.

---

## PR1 — Write-path plumbing (Gate-category: schema write path + money; client-only)

No UI yet; `payload.splitExplanation` stays null in app flow. Proven entirely at the service layer. This isolates the **serialization-shape** risk (the exact write-map keys) in a small diff. NB: `FakeFirebaseFirestore` does NOT enforce rules — rules-conformance for `splitExplanation` is already proven by the TS emulator test `functions/test/firestore-rules-publish-readiness.test.ts` (green, deployed in S1). PR1's Dart tests prove the client serializes the right shape, not that the rules accept it.

### Task 1: `SplitResult.items` field

**Files:**
- Modify: `lib/features/ledger/widgets/custom_split_sheet.dart:21-26`

**Step 1:** Add the `items` field + import `SplitItem` (from `../models/split_explanation.dart`). No behavior change (always null).
**Step 2:** `flutter analyze` clean.
**Step 3:** Commit `feat(ledger): SplitResult carries optional itemized items (#203 S2 PR1)`.

### Task 2: payload field + body state plumbing

**Files:**
- Modify: `lib/features/ledger/widgets/expense_editor_body.dart` — `ExpenseEditorPayload` (`:59`), `_ExpenseEditorBodyState` (`:143`), `_submit` (`:322`).

**Step 1: Write the failing test** — `test/features/ledger/expense_editor_payload_test.dart`: construct an `ExpenseEditorBody` in edit mode with an `initial` expense carrying a `splitExplanation`, submit unchanged, assert the captured payload's `splitExplanation` round-trips. (Use the existing editor test harness.)
**Step 2:** Run → FAIL (no field).
**Step 3: Implement:**
- `ExpenseEditorPayload`: add `final SplitExplanation? splitExplanation;` + ctor param.
- State: `SplitExplanation? _splitExplanation;`; in `initState` edit branch `_splitExplanation = initial.splitExplanation;` else `null`.
- `_submit` payload: `splitExplanation: _splitMode == SplitMode.equally ? null : _splitExplanation,`.
- Import `../models/split_explanation.dart`.
**Step 4:** Run → PASS. `flutter analyze` clean.
**Step 5:** Commit `feat(ledger): thread splitExplanation through ExpenseEditorPayload (#203 S2 PR1)`.

### Task 3: `stageExpense` / `addExpense` write `splitExplanation`

**Files:**
- Modify: `lib/features/ledger/services/expense_service.dart:100-220`
- Test: `test/features/ledger/expense_service_test.dart` (or `test/unit/`)

**Step 1: Write the failing test** (table-driven, money code → non-negotiable):
```dart
test('stageExpense persists splitExplanation at top level (itemized → exact)', () async {
  final firestore = FakeFirebaseFirestore();
  final service = ExpenseService.withFirestore(firestore); // the only injecting ctor (expense_service.dart:27)
  final explanation = SplitExplanation(items: const [
    SplitItem(label: 'Pastries', amountFils: 1200, participantIds: ['n','s','k','h']),
    SplitItem(label: 'Americano', amountFils: 1600, participantIds: ['n']),
  ]);
  final staged = service.stageExpense(
    groupId: 'g', eventId: 'e', payerParticipantId: 'n',
    amount: Decimal.parse('2.800'), currency: 'OMR', createdBy: 'n',
    splitMode: SplitMode.exact,
    splitDistribution: {'n': Decimal.parse('1.900'), 's': Decimal.parse('0.300'),
                        'k': Decimal.parse('0.300'), 'h': Decimal.parse('0.300')},
    splitExplanation: explanation,
  );
  await staged.ack;
  final doc = await firestore.collection('groups').doc('g')
      .collection('events').doc('e').collection('expenses').doc(staged.expense.id).get();
  expect(doc.data()!['splitExplanation'], isA<Map>());
  expect((doc.data()!['splitExplanation'] as Map)['type'], 'itemized');
  expect(Expense.fromFirestore(doc.data()!).splitExplanation?.items.length, 2);
});
```
**Step 2:** Run → FAIL (param doesn't exist).
**Step 3: Implement** — add `SplitExplanation? splitExplanation` to both `addExpense` (forward it) and `stageExpense`; in `data` add the top-level conditional entry (see Data Contracts). Import `../models/split_explanation.dart`.
**Step 4:** Run → PASS.
**Step 5:** Commit `feat(ledger): stageExpense writes splitExplanation (#203 S2 PR1)`.

### Task 4: `updateExpense` set + orphan-delete

**Files:**
- Modify: `lib/features/ledger/services/expense_service.dart:227-304`
- Test: same service test file.

**Step 1: Write failing tests** (table: set / overwrite / orphan-delete / preserve):
```dart
group('updateExpense splitExplanation', () {
  // a) set on an itemized edit → map present
  // b) clearExplanation:true → field deleted (read back: splitExplanation == null)
  // c) neither passed → existing splitExplanation preserved (untouched edit, e.g. note only)
});
```
Seed an expense doc with a `splitExplanation`, then update, read back via `Expense.fromFirestore`.
**Step 2:** Run → FAIL.
**Step 3: Implement** — add `SplitExplanation? splitExplanation, bool clearExplanation = false`; insert the set/delete block (see Data Contracts) after the existing `clearSplit`/split block, before `note`.
**Step 4:** Run → PASS. **Verify (c):** a note-only update with neither flag leaves the stored map intact (no `FieldValue.delete`).
**Step 5:** Commit `feat(ledger): updateExpense sets/clears splitExplanation with orphan-delete (#203 S2 PR1)`.

### Task 5: wire screens

**Files:**
- Modify: `lib/features/ledger/screens/add_expense_screen.dart:58-77`
- Modify: `lib/features/ledger/screens/edit_expense_screen.dart:100-151`

**Step 1: Write failing test** — `edit_expense_screen` test: edit an itemized expense to equal → assert `updateExpense` called with `clearExplanation: true`; relabel-only itemized edit → asserts `splitExplanation` passed AND `splitMode/splitDistribution` written (mock `ExpenseService` with mocktail, capture args).
**Step 2:** Run → FAIL.
**Step 3: Implement** — add `splitExplanation: payload.splitExplanation` to `stageExpense` call; add `explanationChanged` and pass `splitExplanation`/`clearExplanation` per Data Contracts, **independent of `splitChanged`** (do NOT fold it in — a relabel-only edit must not rewrite an identical distribution); add `_explanationEquals` (compare `items` length + each item's `label`/`amountFils`/`participantIds` set/`quantity`).
**Step 4:** Run → PASS. `flutter analyze` + `flutter test test/features/ledger/` green.
**Step 5:** Commit `feat(ledger): screens persist itemized splitExplanation + orphan-delete (#203 S2 PR1)`.

### Task 6: PR1 open + Gate-category /automerge

Branch `feat/203-s2-pr1-plumbing` (worktree). PR body `Refs #203` + `Spec: docs/plans/2026-06-21-203-itemized-split-editor.md`. Run `/automerge <N>` (Gate-category → fresh-context review + refuter). Client-only, no deploy.

---

## PR2 — Itemized editor UI (Gate-category: money allocation + write trigger; client-only)

### Task 7: itemized tab + body in `custom_split_sheet.dart`

**Files:**
- Modify: `lib/features/ledger/widgets/custom_split_sheet.dart`
- Modify: `showCustomSplitSheet` + `CustomSplitSheet` — add `List<SplitItem>? initialItems`, `bool initialItemized`.
- Test: `test/features/ledger/custom_split_sheet_itemized_test.dart`

**Design notes:**
- Segmented control renders the 4 `SplitMode.values` tabs PLUS an "Itemized" tab. State: keep `_mode` for the 4; add `bool _itemized`. Selecting Itemized → `_itemized = true`; selecting a SplitMode → `_itemized = false`.
- **Concrete state-contract thread-through (avoid the exhaustive-`SplitMode`-switch trap):** the existing `_ModeSegmented`/`_ModeBody`/`_Footer` are `StatelessWidget`s that take `SplitMode mode` and switch exhaustively on it (`custom_split_sheet.dart:472,526,989`). Itemized is NOT a `SplitMode`, so do NOT widen those switches. Instead:
  - `_ModeSegmented`: change its prop to `{required bool itemized, required SplitMode mode, required ValueChanged<SplitMode> onMode, required VoidCallback onItemized}`. Render `[...SplitMode.values, <Itemized pseudo>]`; the Itemized chip is selected iff `itemized`, its tap calls `onItemized`; a SplitMode chip is selected iff `!itemized && m == mode`.
  - The sheet body: `_itemized ? _ItemizedBody(...) : _ModeBody(mode: _mode, ...)` — `_ModeBody` is untouched and never sees itemized.
  - `_canApply`: `if (_itemized) return _itemizedCanApply; ` BEFORE the existing `switch (_mode)`.
  - `_buildResult`: `if (_itemized) return _buildItemizedResult();` BEFORE the existing `switch (_mode)` (which stays 4-arm exhaustive and returns `items: null` implicitly via the unchanged `SplitResult` ctor).
  - `_Footer`: itemized renders its own reconcile status (Σitems vs total) — branch on a new `bool itemized` prop before the `switch (_mode)`; do not add a `SplitMode` arm.
- Itemized body state: `List<_ItemDraft>` where `_ItemDraft { TextEditingController label; TextEditingController amount; Set<String> assignees; }`. Seed from `initialItems` (label, `MoneySerializer.fromSubunits` → string, participantIds) when `initialItemized`, else one empty draft.
- Row: label field · amount field (currency-scaled formatter) · assignee summary (tap → `_AssignSheet` checkbox list with an "Everyone" action that toggles all). "+ Add item" appends a draft; swipe/trash removes.
- Live preview: `BalanceCalculator.allocateItemizedDistribution(items: _draftsToItems(), currency: widget.currency)` inside a try/catch (a mid-edit zero-assignee draft throws — show the row as "needs someone", exclude from preview). Per-person card + reconcile footer.
- `_canApply` (itemized): `drafts.isNotEmpty && drafts.every((d) => amount parses > 0 && d.assignees.isNotEmpty) && (Σamounts − total).abs() <= _tolerance`.
- `_buildResult` (itemized):
```dart
final items = _draftsToItems(); // SplitItem with amountFils via MoneySerializer.toSubunits(parsed, currency)
final dist = BalanceCalculator.allocateItemizedDistribution(items: items, currency: widget.currency);
return SplitResult(mode: SplitMode.exact, distribution: dist, items: items);
```

**TDD steps (RED→GREEN per behavior):**
1. itemized tab selectable; empty body shows one draft + "Add item".
2. reconcile gate: items summing ≠ total → Apply disabled; == total → enabled.
3. "Everyone" assigns all; allocator splits equally (Pastries 1.200 / 4 = 0.300 each; remainder → alphabetically-last per the S1 contract).
4. Apply returns `mode: exact`, `distribution` == `allocateItemizedDistribution(items)`, `items` populated.
5. `initialItems` + `initialItemized` seed the drafts (reopen).
6. Money table: OMR 6.100 coffee-run scenario (per-person N 1.900 / S 1.500 / K 2.400 / H 0.300); JPY ×1 (amountFils == yen); single-assignee item; zero-assignee draft excluded from preview + blocks Apply.

Commit per behavior. Final: `feat(ledger): itemized split editor body in custom_split_sheet (#203 S2 PR2)`.

### Task 8: wire editor body "How" → itemized + reopen

**Files:**
- Modify: `lib/features/ledger/widgets/expense_editor_body.dart` — `_openSplitModeSheet` (`:508-561`), `_SplitModeCard` (`:1706`).

**Step 1: Write failing test** — open the How sheet on an expense whose `splitExplanation != null` → the itemized tab is preselected and item rows render (reconstruction); switching to Equally and applying → `_splitExplanation` becomes null (orphan cleared in UI).
**Step 2:** Run → FAIL.
**Step 3: Implement:**
- `showCustomSplitSheet(... initialItems: _splitExplanation?.items, initialItemized: _splitExplanation != null)`.
- result handler:
```dart
setState(() {
  _splitMode = result.mode;
  _splitDistribution = result.distribution;
  _splitExplanation = result.items == null ? null : SplitExplanation(items: result.items!);
});
```
- `_SplitModeCard`: pass `isItemized: _splitExplanation != null`; label shows `context.l10n.editorSplitItemized` when itemized (else `splitModeDisplayName(mode)`); subtitle e.g. "N items".
**Step 4:** Run → PASS.
**Step 5:** Commit `feat(ledger): wire itemized into the expense editor + reopen reconstruction (#203 S2 PR2)`.

### Task 9: l10n

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` (+ regen).

Keys (EN / AR): `editorSplitItemized` ("Itemized" / "حسب الأصناف"), `itemizedAddItem`, `itemizedItemsLabel`, `itemizedWhoHadThis`, `itemizedEveryone`, `itemizedItemsMatchTotal`, `itemizedAmountLeft(amount)`, `itemizedForName(name)`, `itemizedEachOwes`, `itemizedSharedNeedsSomeone`, `itemizedNItems(count)`. Mirror placeholder syntax of existing editor keys. Run `flutter gen-l10n` (or the project's gen step); `flutter analyze` clean.
Commit `feat(l10n): itemized split strings EN+AR (#203 S2 PR2)`.

### Task 10: PR2 open + Gate-category /automerge

Branch `feat/203-s2-pr2-editor` (worktree, off PR1's merge). PR body `Closes #203` (S2 is the last MVP slice; if #605 keeps #203 open, use `Refs #203` in the COMMIT body too). `Spec:` line. `/automerge <N>`. Client-only, no deploy.

---

## Edge cases the tests MUST cover (adversarial / orthogonal axes)

- **Relabel-only edit** (identity axis): change an item label, distribution byte-identical → `splitExplanation` still written (via its OWN `updateExpense` param, gated on `explanationChanged`, independent of `splitChanged`). Without this the new label is silently dropped; folding into `splitChanged` would instead needlessly rewrite an identical distribution.
- **Switch-away orphan** (state axis): itemized → equal → `updateExpense(clearExplanation: true)` → stored `splitExplanation` deleted; itemized → plain exact → also deleted (it's no longer itemized). No orphaned metadata on a non-itemized expense.
- **Reopen reconstruction** (read-path): persisted `splitExplanation.items` re-seed the editor drafts; a legacy expense with no metadata opens the existing exact view (no crash).
- **Conservation** (money axis): `Σ(distribution) == amount` for OMR 3dp shared-item scenario; remainder lands alphabetically-last (S1 contract) — pin the exact per-person figures.
- **JPY ×1** (currency axis): `amountFils == yen`; no ×100/×1000 drift.
- **Zero-assignee / negative guard**: a draft with no assignee blocks Apply and is excluded from the live preview (never reaches the throwing allocator); negative amount impossible via the formatter, but the allocator throw is the backstop.
- **Scope interaction**: itemized assignees ⊆ the sheet's participant set ⊆ event participants ⇒ `splitDistribution.keys().hasOnly(participants())` holds (rules `:516`).

## Verification gate (before "done")

- `flutter analyze` clean.
- `flutter test test/features/ledger/ test/unit/` green.
- The Gate (`/run-the-gate`) on THIS spec before PR1 implementation — schema write+read path + money. Apply P1s, re-run fresh subagent each round until no P1s.
- Each PR: `/automerge` (Gate-category → fresh review + refuter).
