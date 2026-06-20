# #587 — Partial-payment honesty in the record-payment sheet

**Date:** 2026-06-20
**Issue:** #587 — `design(settle-up): partial payments are hidden + copy says "close out the balance" on partials`
**Branch:** `fix/587-partial-payment-honesty`
**Scope:** Phase 1 (conditional copy) + Phase 2 (remaining-after hint). Phase 3 (discoverability redesign) is explicitly **out of scope** — it is a UX-direction choice the loop force-flagged.

## Problem (verified against live code on main @ 770437f3)

Partial settlements already work end-to-end: both callers allow any `edited ∈ (0, suggested]` and net it correctly. The **shared** record-payment sheet, however, lies on a partial:

- **G2** — body `settleUpMarkThisPaidBody` = *"We'll close out the balance between {fromName} and {toName}."* renders **unconditionally** (`record_payment_sheet.dart:229-233`), so it shows verbatim when you record 40 of a 100 outstanding — the balance is *not* closed out, 60 remains.
- **G3** — no "still owes N after this" feedback anywhere; the only number while editing is `settleUpSuggestedAmount` (*"Suggested: {amount}"*).
- (G1 discoverability is Phase 3 — not touched here.)

## Why this is the loop's pick

`isMoneyOrIntegrity = true` (the sheet asserts a balance is closed when it isn't — settle-up **display** honesty), `gateRequired` folded to true by the engine's conservative belt even though **no money-math file / rules / routing / schema field is touched**. Client-only, copy + a pure display subtraction.

## Files

- **EDIT** `lib/features/groups/widgets/record_payment_sheet.dart` — the only behavioural change.
- **EDIT** `lib/l10n/app_en.arb` + `lib/l10n/app_ar.arb` — 3 new keys each.
- **EDIT** `lib/features/groups/keys/group_keys.dart` — 1 new test key.
- **EDIT** `test/features/groups/record_payment_sheet_test.dart` — RED-first partial/full tests.
- **No change** to either caller (`settle_up_screen.dart`, `group_settle_up_screen.dart`), `BalanceCalculator`, `MoneySerializer`, rules, the write shape, or the over-pay cap.

## Verification principles (run while writing the spec)

1. **Callsite classification.** The sheet's `_amountController.text` is read on confirm (OUTBOUND, returned as `RecordPaymentResult.amount`). My new read of it for copy is **INBOUND (display only)** — I do not alter what is returned. The returned string is unchanged; only the title/body/extra-line displayed change.
2. **Concrete claims vs code.** Both callers parse identically: `Decimal.tryParse(normalizeLocalizedDecimalInput(result.amount)) ?? suggestedAmount`, over-pay cap `editedAmount > suggestedAmount` (`settle_up_screen.dart:476-498`, `group_settle_up_screen.dart:477-499`). The field's `inputFormatter` already normalizes to ASCII `.`-decimal as typed, so in-sheet `_amountController.text` is already canonical; I mirror the caller's parse exactly so the sheet's partial/full split == the recorded amount.
3. **Read-path per write-path.** No write-path changes. The displayed `remaining` is read-only.
4. **Fields from the type.** `RecordPaymentResult { amount, note }` — unchanged. Sheet inputs: `currency, fromName, toName, suggestedAmount, perspective, stepLabel` — all already present.
5. **Data contract.** `suggestedAmount` (Decimal) = the outstanding the sheet presents for this transaction (the over-pay cap's reference). `remaining = suggestedAmount − edited`, same `currency`, formatted via `AppFormatters.formatCurrency` (per-currency decimals, JPY=0).
6. **Arithmetic decomposition.** Recording a `from→to` settlement of `edited` against an outstanding `suggested` between the same two parties leaves `suggested − edited` outstanding (netting `(totalPaid + settlementAdj) − totalOwed`; a `from→to` settlement moves the pair's net by exactly `edited`). The over-pay cap guarantees `edited ≤ suggested ⇒ remaining ≥ 0`.
7. **Adversarial pass (orthogonal axis — the optimizer/synthetic-edge case).** In a Simplify-Debts stepped walk each `step.suggestedAmount` is an **optimizer transaction**, not necessarily the raw pairwise net. "{from} will still owe {to} {remaining} after this" is the residual of *the presented transaction* (consistent with the sheet's own *"{from} pays {to} [suggested]"* line and the cap), **not** a claim about the raw A↔B pairwise net. This is the one line I flag for the Gate: is "still owe" acceptable framing for a synthetic optimizer edge, or should it read "remaining on this payment"? Default position: keep "still owe" — the sheet already frames the step as a debt (`settleUpPays`), so the residual of that debt is coherent; changing it would contradict the existing transaction framing.

## Change detail

### New ARB keys (EN)

- `settleUpRecordPartialTitle` = `"Record a partial payment?"`
- `settleUpRecordPartialBody` = `"This is a partial payment — the balance between {fromName} and {toName} stays open."` (placeholders: fromName, toName) — **symmetric** naming `between X and Y` (mirrors the full body), so it is perspective-neutral (no debtor `owes` lean for the creditor view); avoids the substring `"close out"` so the acceptance assertion `find.textContaining('close out')` → nothing holds on partials.
- `settleUpRemainingAfter` = `"{fromName} will still owe {toName} {amount} after this."` (placeholders: fromName, toName, amount) — third-person, consistent with the payee card `settleUpPays` ("{from} pays {to}").

### AR

- `settleUpRecordPartialTitle` = `"تسجيل دفعة جزئية؟"`
- `settleUpRecordPartialBody` = `"هذه دفعة جزئية — يبقى الرصيد بين {fromName} و{toName} مفتوحًا."`
- `settleUpRemainingAfter` = `"سيظل {fromName} مدينًا لـ{toName} بمبلغ {amount} بعد ذلك."`

### Gate P2 resolution (perspective-neutral partial copy — intentional)

The partial **title** and **body** are a single neutral pair across all three perspectives (paying / receiving / recording). This is DELIBERATE and safe because `_bannerText` is **unchanged** and remains perspective-aware (e.g. receiving → *"This records Bob's payment to you immediately."*), so who-paid-whom framing is preserved by the banner. The partial body uses symmetric `between X and Y` naming (like the full body), so it never debtor-frames the creditor's view. Pinned by a new `receiving`-perspective partial test (below).

### `record_payment_sheet.dart`

1. `initState`: add `_amountController.addListener(_onAmountChanged)`; `dispose`: remove it. `_onAmountChanged() => setState(() {})`.
2. In `build()`, derive:
   ```dart
   final edited = Decimal.tryParse(normalizeLocalizedDecimalInput(_amountController.text));
   final isPartial = edited != null && edited > Decimal.zero && edited < widget.suggestedAmount;
   final remaining = isPartial ? widget.suggestedAmount - edited : null;
   ```
   Everything outside the strict `(0, suggested)` band (empty/garbage/zero/full/over-pay) → full copy, no remaining line — matching the caller's fallback (`?? suggestedAmount`) and the cap.
3. Title: `_titleText(context, isPartial)` → `settleUpRecordPartialTitle` when partial, else the existing perspective switch.
4. Body (line ~229): `isPartial ? settleUpRecordPartialBody(from, to) : settleUpMarkThisPaidBody(from, to)`.
5. Remaining-after: after the `_PayeeCard` padding, `if (remaining != null)` render a start-aligned `Text` keyed `GroupKeys.settleUpRemainingAfter` with `settleUpRemainingAfter(from, to, formatCurrency(remaining, currency))`.

### `group_keys.dart`

- `static const settleUpRemainingAfter = Key('group_settle_up_remaining_after');`

## Test plan (RED first)

In `record_payment_sheet_test.dart` (existing harness `openAndReturn` + `tester.tap(find.text('Tap to edit amount'))`):

- **partial OMR**: suggested `100.000`, edit → `40.000`, pump. Assert: title `"Record a partial payment?"`; `"Mark this paid?"` absent; remaining line key present + text contains `OMR 60.000`; `find.textContaining('close out')` absent.
- **full default**: suggested `100.000`, no edit. Assert: title `"Mark this paid?"`; body contains `close out the balance`; remaining key absent.
- **partial JPY (0dp)**: suggested `1000`, edit → `400`. Assert remaining text contains `JPY 600` (no decimal tail) — pins JPY×1 correctness.
- Re-run full `flutter test test/features/groups/record_payment_sheet_test.dart test/features/groups/group_settle_up_screen_test.dart test/features/ledger/settle_up_screen_test.dart` for regressions; `flutter analyze` clean; regenerate l10n.

## Acceptance ↔ plan map

- below-outstanding no longer "close out" → §body conditional + partial-test assertion.
- remaining-after live/correct/JPY → §remaining line + JPY test.
- full copy unchanged at equality → full-default test.
- both surfaces → single shared sheet (callers verified identical).
- EN+AR keys, ordered placeholders → ARB section.
- widget test partial vs full → test plan.
- no BalanceCalculator/write-shape/rules/cap change → files list + principle 1/3.
