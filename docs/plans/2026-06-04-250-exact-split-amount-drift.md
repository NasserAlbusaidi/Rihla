# #250 — out-of-tolerance split silently re-splits equally (no user signal)

**Branch:** `fix/money-correctness-cluster`
**Touches:** split-vs-amount validation on the expense **write path** (money math) → **Gate before code.** Client-only.
**Bug-fix discipline:** failing test first.

## 1. The issue's premise is mostly already mitigated — verified against `main`

The issue describes "user enters an out-of-tolerance exact/percent split → it's accepted → calculator silently re-splits equally." **Against current code, the direct-entry path is BLOCKED:**
- `custom_split_sheet.dart:204-216` `_canApply`: exact requires `_exactRemainder.abs() <= _tolerance` (`:212`), percent requires `_percentRemainder.abs() <= _tolerance` (`:214`), shares requires `_totalShares > 0` (`:210`).
- `custom_split_sheet.dart:371` `onPressed: _canApply ? _apply : null` — the Apply button is **disabled** while out-of-tolerance. The user cannot apply (and thus cannot persist) a direct out-of-tolerance exact/percent split. **The issue's reproduction is invalid against current code.**
- Scope / custom-participant change resets a stale distribution to equal: `expense_editor_body.dart:323-326`.

## 2. The ONE real, UI-reachable silent re-split: exact-split amount drift

`expense_editor_body.dart:439-440` — the amount field's `onChanged` does only `setState(() => _amount = _sanitizeAmount(value))`. It does **not** clear or revalidate `_splitDistribution`. So:
1. amount = 10.000; open split sheet; apply `exact {A: 6.000, B: 4.000}` (valid, sums to 10) → `_splitDistribution = {A:6, B:4}`, `_splitMode = exact`.
2. change amount to 20.000 in the editor (no sheet reopen) — `_splitDistribution` stays `{A:6, B:4}`.
3. `_submit` (`:174-237`) validates amount > 0 and payer, but **NOT** split-vs-amount, and persists `splitDistribution {A:6,B:4}` with amount 20.000.
4. read path `_allocateExact` (`expense_provider.dart`): `(total − amount).abs() = |10 − 20| = 10 > 0.001` → silent `debugPrint` + `_allocateEqual` → `{A:10, B:10}`. The user's stated split is destroyed; they're never told.

**Mode-specificity (load-bearing):** only **exact** distributions are absolute amounts that go stale on an amount change. **percent** (sums to 100) and **shares** (relative weights) are amount-independent — they re-derive correctly at any amount via `_allocateWeighted`, so they must NOT be flagged. The fix is exact-only.

## 3. Fix — validate exact-split-sums-to-amount at `_submit`

In `expense_editor_body.dart` `_submit`, after the existing amount (`:179-188`) and payer (`:197-201`) guards, before building the payload:
```dart
// #250: an exact split is absolute amounts; if the amount changed after the
// split was set, the stored distribution no longer sums to the total and the
// balance calculator would SILENTLY re-split equally, destroying intent.
// (percent/shares are amount-independent and stay valid.) Reject so the user
// can reopen the split and fix it, rather than persist a stale split.
if (_splitMode == SplitMode.exact && _splitDistribution != null) {
  final splitSum = _splitDistribution!.values
      .fold(Decimal.zero, (acc, v) => acc + v);
  if ((splitSum - amount).abs() > _splitTolerance) {
    _showSnack(context.l10n.editorExactSplitOutOfSync);
    return;
  }
}
```
- Add `static final Decimal _splitTolerance = Decimal.parse('0.001');` to the State (matches `custom_split_sheet._tolerance` and `BalanceCalculator._splitTolerance` — same 0.001 contract).
- Add l10n key `editorExactSplitOutOfSync` (EN + AR; ARB parity) — e.g. EN: "The exact amounts no longer add up to the total. Reopen the split to update them."
- Uses the existing `_showSnack` + early-return validation pattern (`:181/186/199`). No calculator change.

## 4. Verification principles
1. **Callsite classification:** `_submit` → `widget.onSubmit(ExpenseEditorPayload)` → `add_expense_screen.dart:66` / `edit_expense_screen.dart:111` → `ExpenseService` write. **OUTBOUND** (the write boundary). The guard sits before the persist → blocks a stale exact split from being written.
2. **Claims verified:** `_canApply` gate `custom_split_sheet.dart:204-216,371`; amount `onChanged` no split-reset `expense_editor_body.dart:439-440`; `_submit` validation order `:174-237`; scope-change reset `:323-326`; calculator drift fallback `_allocateExact` (the `(total-amount).abs() > _splitTolerance → _allocateEqual` branch). Re-grepped on branch HEAD.
3. **Read-path per write-path:** the write is the exact `splitDistribution`; its reader is `BalanceCalculator._allocateExact`, whose drift branch is exactly what silently re-splits. The guard prevents the stale write that triggers it.
4. **Fields from the type:** `ExpenseEditorPayload{amount, description, scope, categoryId, payerParticipantId, customSplitParticipants, splitMode, splitDistribution}` — the guard reads `splitMode`+`splitDistribution`+`amount`; persists unchanged. No field added.
5. **Data contract:** guard fires iff `splitMode == exact && splitDistribution != null && |sum(values) − amount| > 0.001`. percent/shares/equally never fire it.
6. **Arithmetic decomposition:** the invariant restored is `sum(exact entries) == amount` at write time, which is what `_allocateExact`'s tolerance branch checks at read time — aligning write-time validation with the read-time contract so the calculator's silent fallback is never reached via the UI.
7. **Adversarial pass (orthogonal axis = split mode + edit-vs-add):**
   - **percent**: set `{A:50,B:50}` (sums 100), change amount 10→20 → MUST still save (percent re-derives 10/10 at 20) — the guard must NOT fire. Test it.
   - **shares**: set `{A:1,B:1}`, change amount → MUST save. Test it.
   - **edit path**: open an existing exact-split expense (`edit_expense_screen`), change the amount, save → guard fires (same `_submit`). The edit screen's own `splitChanged`/`goingEqual` logic (`edit_expense_screen.dart:91-112`) is downstream of `_submit`'s payload; the guard blocks before that. Confirm the guard is in shared `ExpenseEditorBody._submit`, so both add & edit inherit it.
   - **equally**: never has a distribution → never fires.

## 5. Tests (widget; clean / warning / per-mode)
Reuse the editor widget-test harness (find existing `add_expense`/`expense_editor` test):
- exact split valid → change amount so it drifts → tap Save → snackbar `editorExactSplitOutOfSync` shown, `onSubmit` NOT called.
- exact split that still sums to amount → Save proceeds (`onSubmit` called).
- percent split, change amount → Save proceeds (guard does not fire) — orthogonal-axis fence.
- shares split, change amount → Save proceeds — orthogonal-axis fence.
- (If editor `_submit` is hard to drive in a widget test, extract the predicate to a pure top-level `bool isExactSplitStale(SplitMode, Map?, Decimal)` and unit-test it table-driven; wire `_submit` to call it.)

## 6. Out of scope (named follow-ups)
- **Calculator-fallback telemetry:** the five+ `debugPrint` + `_allocateEqual` sites in `_allocateShares/_allocateExact/_allocatePercent` fire for forged/legacy/Admin writes (no user to warn — defense-in-depth that must stay non-throwing, #47). Replacing `debugPrint` with a real signal (Sentry breadcrumb / metric) so those re-splits are observable is **observability, not money-safety** — file as a follow-up; do not bundle (touches the read-path calculator + Sentry).
- #249 (deferred coordinated), #244 (shipped), #247 — separate.
