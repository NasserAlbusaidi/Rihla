# Issue #63 — Display precision wrong for JPY/KWD/BHD/QAR (RAmount + formatters)

Branch: `fix/issue-63-display-precision` (from `main` @ c25388d)

## Problem (verified firsthand on main)

- `lib/shared/widgets/r_amount.dart:84`: `final decimalPlaces = currency == 'OMR' ? 3 : 2;`
  → JPY renders 2dp (want **0**), KWD/BHD 2dp (want **3**), QAR 2dp (correct by luck).
- `lib/features/groups/widgets/record_payment_sheet.dart:71`: same `== 'OMR' ? 3 : 2` antipattern (settlement-amount prefill).
- `lib/core/utils/formatters.dart`: `formatCurrency` (`:31`) and six other callers read
  `currencyConfig[c]?.decimals ?? 3`. JPY/KWD/BHD/QAR are **missing** from `currencyConfig`
  → fall to `?? 3` → JPY 3dp (want 0), QAR 3dp (want 2), KWD/BHD 3dp (correct by luck).
- Authority already exists: `MoneySerializer.fractionDigits` (`money_serializer.dart:45`) —
  OMR/KWD/BHD→3, USD/EUR/GBP/SAR/AED/QAR→2, JPY→0 (added in #47).

## Callsite classification (verification principle #1)

Every money-display callsite is **INBOUND** (render-only). No write path consumes a formatted
string — `MoneySerializer.toSubunits` is what persists, independent of these formatters
(confirmed by grep of `formatCurrency`/`toStringAsFixed` callers). So this is safe to change
without touching any write path.

The seven `currencyConfig[c]?.decimals` readers (formatCurrency, expense_card×2, settlement_row,
expense_editor_body×2, custom_split_sheet, record_payment_sheet:441) all become correct for the
10 supported currencies the moment the map is complete — no per-callsite edit needed. l10n
strings (`ledgerOwedToYou`, `ledgerYouOweAmount`) interpolate an already-formatted amount string,
so they inherit the fix.

## Fix — single display authority = `currencyConfig`, bound to `fractionDigits` by test

1. `formatters.dart`: complete `currencyConfig` with JPY(¥,0), KWD(د.ك,3), BHD(د.ب,3), QAR(ر.ق,2).
   Fixes `formatCurrency` + all six other `?.decimals` callers for free. `formatCurrency` body unchanged.
2. `r_amount.dart:84`: `AppFormatters.currencyConfig[currency]?.decimals ?? 2` (+ add import).
3. `record_payment_sheet.dart:71`: `AppFormatters.currencyConfig[widget.currency]?.decimals ?? 2`.

Unknown-currency fallbacks unchanged (RAmount/record-sheet keep 2, formatCurrency keeps 3); all 10
real currencies are in the map, so fallbacks never fire in practice.

## Out of scope (follow-up issue)

- ~12 hardcoded `toStringAsFixed(3)` display sites (ledger_hero_block, event_card,
  group_balance_hero, ledger_roster_strip, animated_currency_text, …) — OMR-assuming, **not**
  currency-parameterized; fixing them needs a per-site currency context and overlaps #61.
- Symbol completeness beyond the 4 added currencies.
- Both are latent today: every write hardcodes `'OMR'` (#61), so no non-OMR currency reaches
  any display path at runtime yet. This PR fixes the primitives so they are correct when #61 lands.

## The Gate

Display-only, one-sentence-diff per file, no money-**math**/rules/routing/schema surface →
CLAUDE.md's explicit carve-out applies ("Outside those categories … skip the gate, just do it").
Skipping the heavyweight `/codex` Gate. Compensating with money-grade discipline:
table-driven tests (RED first) across all 10 currencies **+** a drift-guard test binding
`currencyConfig.decimals` to `MoneySerializer.fractionDigits` so the two never silently diverge.

## Tests (RED → GREEN)

- `test/unit/formatters_test.dart`:
  - `formatCurrency` precision+symbol for JPY(0,¥), QAR(2,ر.ق), KWD(3,د.ك), BHD(3,د.ب) — FAIL today.
  - drift guard: ∀ supported currency `c`, `currencyConfig[c]?.decimals == MoneySerializer.fractionDigits(c)`.
- `test/shared/widgets/r_amount_test.dart`:
  - rendered decimal-part length per currency: JPY 0, KWD 3, BHD 3, QAR 2, OMR 3, USD 2 — JPY/KWD/BHD FAIL today.

## Verify

`flutter analyze` clean → `flutter test` (full) → confirm the RED cases are now green.
