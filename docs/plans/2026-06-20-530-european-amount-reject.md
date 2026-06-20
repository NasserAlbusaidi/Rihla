# #530 — Reject ambiguous European-format pasted amounts (don't silently truncate)

**Date:** 2026-06-20
**Issue:** #530 (bug, money, l10n, P3, milestone 1.6.0)
**Owner decision (2026-06-19):** *"Reject, do not truncate. When a money input contains BOTH a dot/٫ and a comma (ambiguous European grouping like `1.234,56`), reject with a validation error instead of silently normalizing to `1.23`. Not closing as by-design. Single-separator input keeps the existing en/ar dot-wins behavior (test-pinned at `localized_decimal_input_test.dart:26-28`)."*

## Problem (verified on main)

`normalizeLocalizedDecimalInput` (`lib/core/utils/localized_decimal_input.dart:9`) computes
`hasDotDecimal` over the whole string (`:10`) and treats `,` as a decimal only when
`!hasDotDecimal` (`:28`). For a pasted European amount `1.234,56` the `.` wins as the
decimal point, the `,` is ignored, and the fraction is clamped to currency precision →
`1.234,56` becomes `1.23` (a ~1000× understatement) with **no error**.

The corruption point is the **live formatter** `LocalizedDecimalTextInputFormatter`
(`formatEditUpdate`, runs on every keystroke AND on paste), so fixing only the parse
helpers is insufficient — the formatter eats the string before any parse site sees it.

## The rule (not "reject when both separators present")

`'1,234.50' → '1234.50'` is **pinned** (`localized_decimal_input_test.dart:27`) — that's US
grouping (comma thousands, dot decimal) and must keep working. So the ambiguity test is:

> Reject **iff** a comma is present AND a dot-family char (`.` / `٫` U+066B) is present AND
> the **comma is the last separator** (i.e. `lastIndexOf(',') > max(lastIndexOf('.'), lastIndexOf('٫'))`).

- `1.234,56` → lastComma(5) > lastDot(1) → **reject** (European).
- `1,234.50` → lastComma(1) < lastDot(5) → keep → strip commas → `1234.50` (US, pinned).
- `1.234.567,89` → comma last → reject. `1,234,567.89` → dot last → `1234567.89`.
- Single separator (`12,50`, `١٢٣٫٤٥٦`, `100.5`) → not ambiguous → unchanged (pinned).

On ambiguous input the normalizer **returns the raw `value` unchanged** — it does not pick a
separator. That makes the formatter show the literal pasted text (visibly not a clean number)
and makes every downstream `Decimal.parse`/`Decimal.tryParse` fail, which the existing
validators turn into a user-facing error.

## Callsite classification (every consumer of the function)

Grep (`normalizeLocalizedDecimalInput` + `LocalizedDecimalTextInputFormatter`) — complete set:

| Site | Kind | Reject path AFTER the normalizer change |
|---|---|---|
| `expense_editor_body.dart:977` (formatter) + `:751` `_sanitizeAmount` → `_amount` | BOTH→OUTBOUND (expense write) | `_submit` already does `Decimal.parse(_amount)` in try/catch → `editorPleaseEnterValidAmount` snackbar (`:265-269`). **Auto-rejects. No change.** |
| `custom_split_sheet.dart:949` (formatter) → `_exactSum`/`_percentSum`/`_buildResult` `Decimal.tryParse(c.text)` | BOTH→OUTBOUND (`splitDistribution`) | unparseable value is skipped from the sum → `_canApply` (`:214-226`) stays false (won't balance to total) → Apply disabled. **Auto-rejects. No change.** |
| `record_payment_sheet.dart:525` (formatter) | INBOUND collector | sheet is a **pure input collector — performs no blocking validation by contract** (pinned: `record_payment_sheet_test.dart:18-21,245-258`). **No change.** |
| `settle_up_screen.dart:476` `Decimal.tryParse(normalize(result.amount)) ?? suggestedAmount` | OUTBOUND (settlement write) | **MUST CHANGE** — silently falls back to `suggestedAmount`, re-introducing silent coercion. |
| `group_settle_up_screen.dart:476` (identical) | OUTBOUND (settlement write) | **MUST CHANGE** — same silent fallback. |

The settle screens are the only callers of `showRecordPaymentSheet`, so fixing them covers
both settle flows while respecting the sheet's "caller validates" contract.

## Changes

### 1. `lib/core/utils/localized_decimal_input.dart`
- Compute `lastDot = max(lastIndexOf('.'), lastIndexOf('٫'))`, `lastComma = lastIndexOf(',')`.
- If `lastComma >= 0 && lastDot >= 0 && lastComma > lastDot` → `return value;` (raw, unchanged) **before** the normalization loop.
- Update the doc comment to record the reject-not-truncate contract and why raw is returned.
- No other behavior changes — single-separator and US-grouping paths are byte-identical.

### 2. `lib/features/ledger/screens/settle_up_screen.dart` + `lib/features/groups/screens/group_settle_up_screen.dart`
Replace the `?? suggestedAmount` one-liner with:
```dart
final parsedAmount = Decimal.tryParse(normalizeLocalizedDecimalInput(result.amount));
// Empty field = "settle the full suggested amount". A NON-empty but unparseable
// value (ambiguous European 1.234,56 — #530) is rejected, never silently coerced.
if (parsedAmount == null && result.amount.trim().isNotEmpty) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(context.l10n.settleUpEnterValidAmount)),
  );
  return const _StepOutcome(_StepOutcomeKind.invalid);
}
final editedAmount = parsedAmount ?? suggestedAmount;
```
The empty→suggested affordance is preserved.

### 3. l10n — `lib/l10n/app_en.arb` + `lib/l10n/app_ar.arb`
Add `settleUpEnterValidAmount`:
- EN: `"Please enter a valid amount"`
- AR: `"الرجاء إدخال مبلغ صالح"`

## Tests (RED first)

### `test/unit/localized_decimal_input_test.dart`
- RED: `normalizeLocalizedDecimalInput('1.234,56', decimalDigits: 2)` is `'1.234,56'` (raw), and `Decimal.tryParse(result)` is `null`. (Currently returns `'1.23'` → fails → RED for the right reason.)
- Regression guards: `'1,234.50' → '1234.50'`; `'1.234.567,89'` rejected (raw); `'1,234,567.89' → '1234567.89'`; single-separator cases unchanged.

### `test/features/ledger/settle_up_screen_test.dart` + `test/features/groups/group_settle_up_screen_test.dart`
- Drive the real sheet: open settle-up, reveal the amount editor, `enterText('1.234,56')`, tap Mark as paid → assert **no settlement write** (`addCalls` empty) and the `settleUpEnterValidAmount` snackbar. Mirror each screen's existing zero/too-large test harness.

## Out of scope / deferred
- Polishing how `_AmountHero` renders a transiently-raw string (it `split('.')`s, so no crash — shows `1 .234,56`, which is the visible reject). Not money-wrong; deferred.
- Stripping leading-group dots to *accept* European grouping — explicitly rejected by the owner decision (reject, don't guess).

## Gate
isMoneyOrIntegrity = true (a pasted amount silently becoming a different number is money
corruption) → fresh-context Opus Gate required before code, per the Operating Contract.
