# Issue #144 — Unify currency notation (ISO code, code-first, everywhere)

**Status:** spec, gate round 2
**Labels:** money, decision, design, rtl, P2
**Decision date:** 2026-05-30

## Decision (DEC-1)

**One rule: every money amount is displayed as `<ISO_CODE> <amount>`
(code-FIRST, Latin code, Western digits, LTR) in BOTH English and Arabic UI.
The currency *symbol* (`ر.ع.`, `$`, `€`, …) is never used for amount display,
and the code is never placed AFTER the amount.**

The issue text proposed EN→code / AR→symbol. Rejected on a verified hard
constraint: money is always rendered in **Geist Mono**, which has **no Arabic
glyphs** and **no `fontFamilyFallback`**; `RAmount` force-LTRs money and shrinks
the currency token to **0.42×**. An Arabic symbol there = `.notdef` boxes,
broken tabular alignment, and bidi reordering (it would *cause* BUG-6).
Digits are already Western for money by prior decision; a Latin ISO code is
internally consistent. User confirmed ISO-code-everywhere on 2026-05-30. The
issue's AC explicitly permits "whichever single rule is chosen."

Code-FIRST (not -last) is chosen because it is the dominant existing style
(`RAmount`, `ledger_hero_block`, the `ledgerYouOwe*`/`ledgerOwedToYou` ARB
family). The code-suffix occurrences are the accidental outliers.

## Notation surface (exhaustive — gate-corrected)

Every site that concatenates a currency token with an amount, display OR
persisted-and-displayed. Verified by grep, not memory.

### Already on-rule (code-first) — NO CHANGE
- `RAmount` (`lib/shared/widgets/r_amount.dart`) — code-first, force-LTR, mono.
  ~25 callsites. Conformant.
- `ledger_hero_block.dart:261` — `'OMR ${total.toStringAsFixed(3)}'` — single
  all-Latin Text run; bidi-safe in any direction. (Hardcoded OMR is #70/#61.)
- Hardcoded `'OMR'` label (`balance_hero_card.dart:109`) — single code label.
- Bare-code label ARB strings — `editorAmountLabel` "AMOUNT · {currency}",
  `settleUpAmountLabel` "Amount ({currency})", `homeWeeklySpending`
  "Weekly Spending ({currency})". Code as a label, no amount concatenation.
- `ledgerOwedToYou` "Owed to you {currency} {amount}", `ledgerYouOweAmount`
  "You owe {currency} {amount}" — already prefix (the template to match).

### Off-rule — CHANGE

1. **`AppFormatters.formatCurrency`** (`formatters.dart:33-38`).
   `return '$symbol ${amount.toStringAsFixed(decimals)}';`
   → `return '$currencyCode ${amount.toStringAsFixed(decimals)}';`
   - `decimals` resolution UNCHANGED (`config?.decimals ?? 3`). Precision is
     untouched (JPY 0 / USD·EUR·AED·QAR 2 / OMR·KWD·BHD 3). Only the prefix flips
     symbol→code. Fixes ~12 callers + BUG-1.
   - `CurrencyConfig.symbol` is now unread by formatCurrency; field kept (picker
     decision below). Removing it is out of scope.

2. **Composite `code · symbol` (3 sites)** → code only:
   - `create_group_screen.dart:448` hardcoded `'OMR · ر.ع.'` → `'OMR'`.
   - `profile_screen.dart:1106` `_currencyTrailing` `'$code · $symbol'` → `code`.
   - `currency_picker_sheet.dart:74` subtitle `'$code · $symbol'` → `code`
     (title stays the localized name via `currencyDisplayName`).

3. **Code-SUFFIX display outliers → prefix:**
   - `event_card.dart:186` and `:196` — `'${totalSpent.toStringAsFixed(3)} OMR'`
     → `'OMR ${totalSpent.toStringAsFixed(3)}'` (two sites in
     `_buildExpenseCountLine`).
   - ARB `eventYouOweAmount` (en `app_en.arb:1184`, ar `app_ar.arb:529`):
     `"You owe {amount} {currency}"` / `"أنت مدين {amount} {currency}"`
     → `"You owe {currency} {amount}"` / `"أنت مدين {currency} {amount}"`.
   - ARB `eventYouAreOwedAmount` (en `:1191`, ar `:530`):
     `"… {amount} {currency}"` → `"… {currency} {amount}"`.
   - **Mechanism (l10n landmine):** change the MESSAGE STRING ONLY. Leave each
     `@`-block `placeholders` order as `{amount, currency}`. gen-l10n derives the
     method signature from placeholder-DECLARATION order, not string position, so
     the signature stays `eventYouOweAmount(Object amount, Object currency)` and
     the call sites (`event_card.dart:157`, `:164`, passing `(amount, 'OMR')`)
     need **no change**. After edit run `flutter gen-l10n` (generated files are
     committed). Result strings become "You owe OMR 25.500", now identical to the
     `ledgerYouOweAmount` sibling.

4. **[P1 r2/r3] bidi: `ledger_hero_block.dart:124-140` `_inlineMoney`.** The hero
   statement amount is built as a `Row` (`mainAxisSize.min`, NO `textDirection`)
   of `[Padding(EdgeInsetsDirectional.only(end:3), Text('${sign}OMR')),
   Text(whole), Text(frac)]`. In Arabic (RTL) three things break: the `Row` lays
   children right-to-left (pieces reverse), each child `Text` inherits RTL base
   direction (the `−`/prefix can render as `OMR−`), and `EdgeInsetsDirectional
   .end` resolves to the left. `Row.textDirection: ltr` alone fixes ONLY child
   order. **Wrap the whole `Row` in `Directionality(textDirection:
   TextDirection.ltr, child: Row(...))`** — that sets ambient LTR for the subtree,
   fixing order + each Text's base direction + the directional padding at once.
   Live V5R ledger-hero surface.

5. **[P2 r1] bidi: `custom_split_sheet.dart:1061`** `Text(text, …)` where
   `text = '$sign$formatted'` (`:1083`, `formatted` = formatCurrency output) has
   no explicit direction. Add `textDirection: TextDirection.ltr` to match the
   sibling at `expense_editor_body.dart:1201`, enforcing AC#3 for the signed
   amount path.

### Out of scope (named, not touched)
- `formatOMR` (`formatters.dart:28`, `'${amount} OMR'` suffix) — dead in app
  code (only tests/README). Never displayed. Left as-is.
- `expense_service.dart:203` `logText` (`'${amount} $currency'`, suffix,
  persisted) — **NOT displayed** in the normal path: `activity_display.dart:8-18`
  maps `('MONEY','CREATE') → l10n.activityEventMoneyCreated` (a localized
  generic); `log.logText` is only the `_ =>` fallback for unknown types. Changing
  a persisted-but-unshown string (and its pinned test `expense_service_test
  .dart:117`) for no display benefit is out of scope. Left as-is.
- Hardcoded-English activity descriptions; dynamic currency wiring (#70/#61);
  `activity_service.dart:66` (`'$actorName $action'`, no currency).
- **POL-8 / currency-PRESENCE (`RAmount(showCurrency: false)`) — separate
  decision, carved out.** ~10 dense-row sites render a bare amount with no code
  (`ledger_day_card.dart:255,264,427`, `group_detail_screen.dart:512,724,932`,
  `group_activity_screen.dart:459,468`, `balance_hero_card.dart:122`,
  `profile_screen.dart:531`). Verified deliberate: `balance_hero_card` prints
  `OMR` as a sibling 9px mono label (`:108-115`) above the 44px number, so
  `showCurrency:false` exists to avoid a double `OMR`; the ledger establishes its
  currency in the hero/header so per-row repetition is intentional density.
  #144's 5 acceptance criteria govern *how* currency is written *when shown*
  (NOTATION); none mandates a token on every row (PRESENCE). The user's decision
  ("ISO code everywhere") answered a code-vs-symbol question, not "force the code
  onto every dense row." Flipping these is a visible UX change needing design
  sign-off → tracked as a POL-8 follow-up, not bundled here.

## Callsite classification (verification principle #1)

All `formatCurrency` callers are INBOUND (display) except `group_settle_up_screen
.dart:368` — OUTBOUND, persisted into the settlement `description`. That string is
likewise NOT displayed (`activity_display.dart:27` maps `'group_settlement' →
activityGroupSettlementDescription`), so the formatCurrency change only rewrites
the persisted free-text; no display, no parse-back, no money-math consumes it.
The real money is in structured fields. grep confirms no
`contains('ر`/`split(`/symbol-parsing of formatted output anywhere.

## Tests

### Must flip to code-first (RED → GREEN)
- `test/unit/formatters_test.dart`
  - L46-67 `formatCurrency`: `'OMR 10.000'`, `'USD 25.50'`, `'EUR 99.99'`,
    `'AED 100.00'`, unknown `XYZ`→`'XYZ 50.000'` (fallback code==input, 3dp).
  - L97-118 (#63 precision): `'JPY 1234'`, `'QAR 50.00'`, `'KWD 50.000'`,
    `'BHD 50.000'`, `'OMR 10.000'`, `'USD 25.50'` — precision identical, prefix
    flips to code.
  - `formatOMR` tests L14-43 UNCHANGED.
- `test/features/ledger/add_expense_screen_test.dart` L110-114 — `'ر.ع. 2.500'`
  → `'OMR 2.500'`; summary `'ر.ع. 2.500 لكل شخص'`→`'OMR 2.500 لكل شخص'`. Update
  the bidi-explainer comment: the Latin code is what *fixes* the scrambling this
  test guarded (BUG-6 root cause).
- `test/features/groups/create_join_group_test.dart` L109 —
  `find.text('OMR · ر.ع.')` → `find.text('OMR')`.
- `test/features/events/group_detail_events_test.dart` L424,452 —
  `'25.500 OMR'`→`'OMR 25.500'`, `'0.000 OMR'`→`'OMR 0.000'`.
- (`expense_service_test.dart:117` — UNCHANGED; expense_service left as-is.)

### Leave alone
- `onboarding_screen_test.dart:63` `'RIHLA · ر.ح.ل.ة'` — brand wordmark, not
  currency. Onboarding archived.
- `r_amount_test.dart` — already pins code-first.

### New (issue AC#5: "a widget/golden test pins EN and AR rendering")
- Unit (`formatters_test.dart`): explicit code-first contract group over one 3dp
  (OMR), one 2dp (USD), one 0dp (JPY) currency; assert output starts with the
  code and never contains `ر.ع.`/`$`/`¥`. Guard for "never symbol, never suffix".
- Widget: in an **Arabic** locale, an amount via `formatCurrency` and one via
  `RAmount` both render `OMR …` and contain no `ر.ع.`. Pin EN + AR.
- [P2 r2] Widget `event_card`: with `personalBalance` positive AND negative, in
  EN AND AR, assert the row reads `OMR …` (prefix) — pins the ARB reorder of
  `eventYouOweAmount`/`eventYouAreOwedAmount`, not just the totals.
- [P1 r2] Widget `ledger_hero_block` (or its host) in **Arabic**: the hero money
  pieces render left-to-right (`Directionality.of(...) == ltr` on the inline
  money, or `find.text` order), proving the Row no longer reverses.

## Out-of-scope sub-decision (default chosen)
Currency picker subtitle → bare `OMR` (symbol dropped). Title already carries the
localized name, so name+code disambiguates. If product wants the symbol back in
the picker only, that's a one-line follow-up.

## Done checklist
- [x] `formatCurrency` code-first; precision unchanged (#63 tests pass).
- [x] 3 composite sites → code; `event_card` 2 suffix totals → prefix; 2 ARB
      families reordered (message-string only) + `flutter gen-l10n` (signatures
      unchanged, call sites untouched).
- [x] `ledger_hero_block` `_inlineMoney` Row wrapped in `Directionality(ltr)`;
      `custom_split_sheet` amount Text given `TextDirection.ltr`.
- [x] grep clean: only the kept `CurrencyConfig.symbol` definition and dead
      `formatOMR` remain; no symbol/suffix in any `lib/` amount-display path.
- [x] Existing tests flipped; new EN+AR pins added (formatCurrency no-symbol,
      event_card balance rows EN/AR, ledger_hero_block AR bidi).
- [x] `flutter analyze` clean; full suite green (1235 pass, 3 macOS-golden skip).
- [x] Gate: codex round 4 → VERDICT: NO P1 (within agreed notation scope).
