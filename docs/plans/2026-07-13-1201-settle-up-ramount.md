# #1201 — Settle-up money through RAmount Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Route every *standalone displayed* amount on the settle-up surfaces (both scopes) through `RAmount`/Spline mono, codify the composed-string carve-out in DESIGN.md §8, and pin it all with RED→GREEN widget tests.

**Architecture:** `SettleUpPageBody` is shared by BOTH scopes (the event `SettleUpScreen` embeds it), so fixing `settle_up_page_body.dart` + `group_settlement_tile.dart` covers the whole feature. 12 live `formatCurrency` sites split 5 fix / 7 keep: standalone amounts become `RAmount` widgets (one new additive `AmountTone.muted`), the stepped-card caption gets a mono `TextSpan`, and amounts embedded in composed l10n sentences / plain-text share strings stay `formatCurrency` (matching the exemplar `record_payment_sheet.dart`, which the #1201 re-scorer certified compliant).

**Tech Stack:** Flutter, `RAmount` (`lib/shared/widgets/r_amount.dart`), `AppTypography.mono`, flutter_test.

**Issue:** Closes #1201. Gate-exempt per the issue itself (display-only; no money math, rules, routing, or schema surface — verified: no `BalanceCalculator`/`MoneySerializer` logic, `firestore.rules`, `app_router.dart`, or model field is touched; the one `MoneySerializer.fromSubunits` read at `settle_up_screen.dart:929` is untouched).

---

## Verified facts (re-checked against main @ 2ce0891c — do not re-derive, but re-grep before editing)

- **12 live sites** (issue said 11; `settle_up_page_body.dart:1217` is new since filing):

| # | Site | What renders | Verdict |
|---|------|--------------|---------|
| 1 | `settle_up_page_body.dart:577` | stepped-card caption `'{count} · OMR 1.400 · USD 41.00'` (amounts joined, appended after l10n text) | **FIX** — mono TextSpan for the amounts segment |
| 2 | `settle_up_page_body.dart:728` | `_NetBalanceRow` trailing net balance, sans w800, successText/errorText/textSecondary(zero) | **FIX** — RAmount |
| 3 | `settle_up_page_body.dart:1046` | correction confirm-dialog body via `l10n.settleUpCorrectBody(amountStr, …)` | **KEEP** — composed l10n sentence |
| 4 | `settle_up_page_body.dart:1094` | `_composeReceipt` share text (#359, LTR, code-first #144) | **KEEP** — plain-text share string |
| 5 | `settle_up_page_body.dart:1217` | settlement-history row trailing amount, sans w800 textPrimary | **FIX** — RAmount |
| 6 | `settle_up_screen.dart:696` | snackbar `settleUpAmountExceedsOutstanding(…)` | **KEEP** — composed l10n sentence |
| 7 | `settle_up_screen.dart:724` | snackbar `settleUpBalanceChangedReviewAgain(…)` (#773) | **KEEP** — composed l10n sentence |
| 8 | `settle_up_screen.dart:790` | `settleNotifyMessage(amountDisplay: …)` WhatsApp share (#367) | **KEEP** — plain-text share string |
| 9 | `settle_up_screen.dart:928` | snackbar #1129 over-outstanding copy | **KEEP** — composed l10n sentence |
| 10 | `group_settlement_tile.dart:170` | suggestion-tile amount chip, sans w800, `_amountColor` = errorText/successText/textPrimary | **FIX** — RAmount |
| 11 | `group_settlement_tile.dart:324` | expanded per-event breakdown row amount, sans w600 textSecondary | **FIX** — RAmount muted |
| 12 | `group_settlement_summary.dart:35` | `settleUpSummaryTotal(…)` chip label (composed l10n) — same flow, outside the issue's 3 files | **KEEP** — composed l10n sentence; add the carve-out comment |

- **RAmount API** (read in full): `value` (Decimal), `currency`, `size`, `sign`, `tone` (`AmountTone` auto/sage/rust/ink/sageText/rustText), `weight` (default w500), `semanticsLabel` auto-derived. Renders `Text.rich` (fragments the string — breaks `find.text`), forces `textDirection: ltr`, `maxLines: 1`, `softWrap: false`.
- **Spline Sans Mono ships static 400/500/700 only** (`pubspec.yaml:173-180`) — w800/w600 would silently nearest-fall-back. Emphasized sites map w800→`FontWeight.w700`; the w600 breakdown/caption sites take the mono defaults (w500).
- **No RAmount tone maps `textSecondary`** — `_NetBalanceRow`'s zero case and the breakdown rows need a new additive `AmountTone.muted → colors.textSecondary`.
- **Tile colors already use the WCAG text siblings** (`errorText`/`successText`) → RAmount's `rustText`/`sageText` map 1:1.
- **Sign rendering changes shape**: `formatCurrency` renders negatives as `OMR -5.000`; RAmount with `sign: true` renders `−OMR 5.000` (typographic minus before the code) — this matches the app-wide idiom (home hero, `group_balance_breakdown_sheet.dart:276-281` uses `sign: true`). Accepted visual change.
- **Test idiom for RAmount** is `find.textContaining('…', findRichText: true)` (see `test/features/home/balance_hero_card_test.dart`). `test/features/groups/settle_up_logical_row_widget_test.dart` L119-121/129/160/181-183 assert exact `find.text('OMR 7.000')` etc. against the history row (site 5) — **all must convert, INCLUDING the `findsNothing` ones** (an absence assertion left on the plain finder false-passes forever).
- **Dark goldens cover settle-up**: `test/goldens/group_settle_up_golden_test.dart` — the font swap changes them; regenerate on this Mac (goldens are macOS-only, CI-excluded).
- **Edge (no code change):** for a currency missing from `currencyConfig`, `formatCurrency` defaults to 3 decimals, RAmount to 2. Unreachable — the config covers all 10 supported currencies and group currency is create-time-validated.
- `_amountColor` in `group_settlement_tile.dart` has exactly one consumer (L177) — safe to replace with a tone getter. Re-grep before deleting.

## Verification-principles report (run while speccing)

1. **Callsite classification:** all 12 classified above. All 5 FIX sites are INBOUND (display-only). The two OUTBOUND-to-share strings (sites 4, 8) are untouched, so no display formatting newly reaches a write/share path. No Firestore write is touched anywhere.
2. **Concrete claims re-verified against code:** live grep counts (12, not the issue's 11), RAmount full read, `formatCurrency` impl read (`formatters.dart:39-43`), bundled font weights read, DESIGN.md L44-46 + §8 L326-336 read, `_amountColor`/`amountColor` derivations read.
3. **Read-path per write-path:** N/A — zero write paths change.
4. **Fields from the type:** RAmount params enumerated from the class, not memory.
5. **Data contracts:** exact per-site replacements specified in tasks below.
6. **Arithmetic decomposition:** none — both formatters render `toStringAsFixed(config.decimals)`; byte-identical digits for all supported currencies.
7. **Orthogonal axes checked:** RTL (RAmount forces LTR per the money-stays-LTR contract — an improvement for AR; Rows use Expanded+trailing, direction-safe), a11y (RAmount supplies spoken labels; `sign: true` sites now announce polarity), tests (the absence-assertion trap above), goldens (regeneration required).

---

### Task 1: Branch

```bash
git checkout -b fix/1201-settle-up-ramount origin/main
flutter pub get
```

### Task 2: RED — pinning tests

**Files:**
- Modify: `test/features/groups/group_settlement_tile_test.dart`
- Modify: `test/features/groups/group_settle_up_screen_test.dart`

**Step 1: Write failing tests**

In `group_settlement_tile_test.dart` (reuse its existing pump helpers), add a `#1201` group:

```dart
testWidgets('amount chip renders through RAmount (mono contract, #1201)', (tester) async {
  // pump a tile the way the existing "renders payer/recipient" test does
  expect(
    find.descendant(of: find.byType(GroupSettlementTile), matching: find.byType(RAmount)),
    findsOneWidget,
  );
});

testWidgets('expanded per-event breakdown rows render RAmount muted (#1201)', (tester) async {
  // pump with a breakdown map + expand, as the existing breakdown test does
  final amounts = tester.widgetList<RAmount>(find.byType(RAmount)).toList();
  expect(amounts.length, greaterThan(1)); // chip + breakdown rows
  expect(amounts.where((a) => a.tone == AmountTone.muted), isNotEmpty);
});
```

In `group_settle_up_screen_test.dart`, inside the group that pumps `_balancesOwed` (near L727):

```dart
testWidgets('net-balance rows render through RAmount (#1201)', (tester) async {
  // same pump as 'GROUP TOTAL PENDING shows 7.750 OMR'
  expect(find.byType(RAmount), findsWidgets);
});
```

Import `package:safar/shared/widgets/r_amount.dart` as the existing tests import shared widgets (match the file's import style).

**Step 2: Run to verify RED**

```bash
flutter test test/features/groups/group_settlement_tile_test.dart test/features/groups/group_settle_up_screen_test.dart
```
Expected: the three new tests FAIL (`findsNothing` — no RAmount on these surfaces today). Paste this output into the PR later (RED evidence, #329).

**Step 3: Commit**

```bash
git add test/ && git commit -m "test(settle-up): RED — pin RAmount on settle-up money surfaces (#1201)"
```

### Task 3: `AmountTone.muted`

**Files:**
- Modify: `lib/shared/widgets/r_amount.dart`
- Check: `grep -rn "AmountTone" test/` — if a dedicated RAmount test exists, add a muted-tone case there.

**Step 1:** Extend the enum (keep the doc comment style):

```dart
/// `muted` renders in `colors.textSecondary` — for de-emphasized amounts on
/// secondary rows (per-event breakdowns, zero balances) where ink would
/// over-weight the row (#1201).
enum AmountTone { auto, sage, rust, ink, sageText, rustText, muted }
```

**Step 2:** Add the switch arm in `_resolveColor`:

```dart
AmountTone.muted => colors.textSecondary,
```

**Step 3:** `flutter analyze` — clean. Commit: `feat(shared): AmountTone.muted for de-emphasized amounts (#1201)`.

### Task 4: Swap the 5 FIX sites

**Files:**
- Modify: `lib/features/groups/widgets/settle_up_page_body.dart` (sites 1, 2, 5)
- Modify: `lib/features/groups/widgets/group_settlement_tile.dart` (sites 10, 11)
- Both files must import `../../../shared/widgets/r_amount.dart`.

**Site 2 — `_NetBalanceRow` (L722-733).** Replace the `amountColor` local + trailing `Text` with:

```dart
RAmount(
  value: balance.netBalance,
  currency: currency,
  size: 14,
  sign: true,
  weight: FontWeight.w700, // Spline ships 400/500/700 — w800 would synthesize
  tone: balance.netBalance > Decimal.zero
      ? AmountTone.sageText
      : balance.netBalance < Decimal.zero
      ? AmountTone.rustText
      : AmountTone.muted,
),
```

(Explicit tone keeps the current WCAG text-sibling colors; `AmountTone.auto` would give the surface tones.)

**Site 5 — history row (L1216-1226).** Replace the trailing `Text` with:

```dart
RAmount(
  value: overrideAmount ?? settlement.amount,
  currency: settlement.currency,
  size: 14,
  weight: FontWeight.w700,
  tone: AmountTone.ink,
),
```

**Site 1 — stepped-card caption (L576-580 build + L617-625 render).** Keep the `amounts` join; drop the `caption` concat; replace the caption `Text` with a `Text.rich` so ONLY the amounts segment goes mono (the l10n count text stays sans — no l10n surgery):

```dart
Text.rich(
  TextSpan(
    children: [
      TextSpan(
        text: '${context.l10n.settleUpSettleAllWithCount(steps.length)} · ',
        style: AppTypography.sans(
          color: context.colors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      TextSpan(
        text: amounts,
        style: AppTypography.mono(
          fontSize: 12,
          color: context.colors.textSecondary,
        ),
      ),
    ],
  ),
  overflow: TextOverflow.ellipsis,
),
```

**Site 10 — tile amount chip (L169-179).** Replace `_amountColor` getter with a tone getter (re-grep first that L177 is the only consumer):

```dart
AmountTone get _amountTone {
  if (widget.isYourAction) return AmountTone.rustText;
  if (widget.isCreditor) return AmountTone.sageText;
  return AmountTone.ink;
}
```

and the chip `Text` with:

```dart
RAmount(
  value: widget.amount,
  currency: widget.currency,
  size: 16,
  weight: FontWeight.w700,
  tone: _amountTone,
),
```

**Site 11 — breakdown row (L323-333).** Replace the trailing `Text` with:

```dart
RAmount(
  value: e.value,
  currency: widget.currency,
  size: 12,
  tone: AmountTone.muted,
),
```

**Then:** `flutter analyze` clean (watch `prefer_const_constructors` and now-unused imports — if `formatters.dart`/`typography_tokens.dart` lose all uses in a file, remove the import; in `settle_up_page_body.dart` both stay used by the KEEP sites/caption).

### Task 5: GREEN + convert string assertions

**Step 1:** Run the pinning tests — the three Task-2 tests now PASS.

**Step 2:** Convert `test/features/groups/settle_up_logical_row_widget_test.dart` amount assertions to the repo idiom — presence AND absence:

```dart
expect(find.textContaining('OMR 7.000', findRichText: true), findsOneWidget);
expect(find.textContaining('OMR 3.000', findRichText: true), findsNothing);
```

(Do not delete any assertion; convert in place. L129 already uses `textContaining` — add `findRichText: true`.)

**Step 3:** Run the full affected suites and fix any other string-match fallout the same way (convert, never delete):

```bash
flutter test test/features/groups/ test/features/ledger/
```
Expected: all green.

**Step 4:** Commit: `fix(settle-up): render standalone amounts through RAmount/Spline mono (#1201)` — body carries `Closes #1201` (squash-merge closes from the COMMIT body, not the PR body).

### Task 6: KEEP-site comments + docs

**Step 1:** Add a one-line comment above each KEEP site (3, 6, 7, 8, 9, 12 — site 4 already documents its plain-text/LTR contract):

```dart
// #1201: amount embedded in a composed l10n sentence — stays formatCurrency;
// RAmount governs standalone displayed amounts (DESIGN.md §8).
```

(For sites 8/12 say "share string" / "composed l10n chip label" respectively.)

**Step 2:** DESIGN.md §8 — add after the tone bullet:

```markdown
- `tone: AmountTone.muted` (textSecondary) for de-emphasized amounts on
  secondary rows (per-event breakdowns, zero balances).
- **Carve-out:** an amount *embedded inside* a composed l10n sentence (dialog
  bodies, snackbars, chip labels) or a plain-text share/receipt string keeps
  `AppFormatters.formatCurrency` — splitting localized sentences to restyle
  the number is an l10n hazard, and share strings carry no styling. RAmount /
  the mono role govern every *standalone displayed* amount (#1201).
```

**Step 3:** `grep -n "AmountTone" docs/SHARED-WIDGETS.md` — if RAmount's tones are listed there, add `muted`.

**Step 4:** Commit: `docs(design): codify RAmount composed-string carve-out + muted tone (#1201)`.

### Task 7: Goldens

```bash
flutter test --update-goldens test/goldens/group_settle_up_golden_test.dart
git status --short test/goldens/
```
Inspect that ONLY settle-up PNGs changed; then run the golden test WITHOUT the flag to confirm it passes. Commit: `test(goldens): regenerate settle-up goldens for RAmount swap (#1201)`.

### Task 8: Full verification

```bash
flutter analyze
bash tool/check_theme_purity.sh
flutter test
```
All three must be clean/green (theme purity is CI-only — running it locally is the #615 trap guard). Fix anything found; never patch a test to avoid a real failure.

### Task 9: PR

```bash
git push -u origin fix/1201-settle-up-ramount
gh pr create --title "fix(settle-up): render money through RAmount/Spline mono (#1201)" --body "..."
```

PR body: summary, the 5-fix/7-keep classification table (condensed), `Spec: docs/plans/2026-07-13-1201-settle-up-ramount.md`, **RED evidence** (pasted Task-2 failing output), test plan (suites run + goldens regenerated), `Closes #1201`. Review the whole branch diff (`git diff origin/main...HEAD`) before opening.

**Out of scope (do NOT bundle):** `formatCurrency` sites in `custom_split_sheet_chrome.dart`, `ledger_hero_block.dart`, `split_card.dart` (add-expense surfaces, separate audit), and any l10n restructuring.
