# #242 — WYSIWYG split preview (real per-person amounts for shares/exact/percent)

**Status:** spec — **Gate PASSED R1 (0 P1 / 2 P2 / 2 P3, 2026-06-20)**; P2/P3 folded in below. Ready to implement.
**Date:** 2026-06-20
**Issue:** #242 (milestone: Post-release features; labels enhancement/P3/money/design/l10n)
**Gate:** REQUIRED (touches `BalanceCalculator` / money math) — run `/run-the-gate` on this spec before any code.

---

## 1. Problem (verified against live code)

The expense editor's **"Split between" preview** (`_SplitPreviewCard`, `lib/features/ledger/widgets/expense_editor_body.dart:1430`) always shows the **equal** per-person amount, even when the user picked **shares / exact / percent**. The split is *persisted correctly* — this is a **display-only** lie.

- `expense_editor_body.dart:1474-1478` — the card computes the only amount it ever shows as `each = (amount / count).toDecimal(scaleOnInfinitePrecision: 3)`. Equal division, always.
- `expense_editor_body.dart:685-692` — the call site passes `event, amount, currency, scope, payerId, customSplitParticipants`. It does **not** pass `_splitMode` (state line 164) or `_splitDistribution` (state line 169), so the card *cannot* reflect the chosen mode.
- `_ParticipantSplitTile` (`:1589`) receives a pre-computed `share` Decimal (`:1572-1578`).

**Confirmed this is display-only, not a math bug:** `test/unit/jabal_trip_settlement_test.dart` (the SH362P 8-person dogfood) proves `calculateBalances` conserves exactly — the "Rihla vs Splid discrepancy" was Splid being wrong. The persisted math is right; only the preview misleads.

### What the issue got WRONG (it predates #382/#247 — verified stale):

| Issue claim | Reality (verified) |
|---|---|
| `_tripCurrency => 'OMR'` hardcoded (`:116`) | **GONE.** Currency fully threaded: `widget.currency` (`:105`) → `effectiveCurrency` getter (`:185`); card already receives `currency: effectiveCurrency` (`:688`). Only `OMR` literals left are doc-comments *warning against* defaulting (`:103`, `:877`). The multi-currency "dependency" is already satisfied. |
| Payer force-inserted into split set (`~:1025-1038`) → null-key risk | **GONE (#247).** Preview previews the custom set verbatim (`:1447-1463`); custom-empty → `event.participantIds`. No payer insert. |
| `scaleOnInfinitePrecision: 3` only coincidentally matches OMR | True, but moot once we route through the real allocator (which uses `MoneySerializer.fractionDigits(currency)`). Fixed as a side benefit. |
| Goldens must be regenerated | **N/A.** `test/goldens/add_expense_golden_test.dart` is a `GoldenHarness` token-smoke with hardcoded rows (`Split: 'Even'`), **not** a real `_SplitPreviewCard` render. Editor copy/layout changes cannot diff it. Confirmed by reading the file. The real editor is covered by `test/features/ledger/*` widget tests (which DO run in CI). |

---

## 2. The core design — one allocator, no second copy

### Verification principle 6 (arithmetic decomposition): the per-expense owed math lives in TWO branches of `calculateBalances`

Read the field-construction lines, not the flow. `calculateBalances` (`expense_provider.dart:341` loop) computes each expense's owed via **two mutually-exclusive paths**:

1. **Mode-allocator path** — gated at `:360-363` on `splitMode != null && splitMode != equally && distribution != null && distribution.isNotEmpty`. Dispatches `_allocateShares` / `_allocateExact` / `_allocatePercent` (`:364-370`), each returning `Map<String,Decimal>` owed-by-id over **`distribution.keys`** (scope is ignored here).
2. **Scope path** — the `else` inline block (`:380-435`). Recipients derived from `expense.scope`: `personal → {payerId}`, `global/subGroup → all participants`, `custom → customSplitParticipants (empty→all)`. Then an equal per-head split with remainder → alphabetically-last id (`:412-435`).

**A faithful preview must replicate BOTH paths.** A naive "expose the three mode allocators" extraction silently mis-previews equally-mode and scope-based expenses.

### Decision: extract one pure per-expense allocator; `calculateBalances` delegates to it

```dart
/// Pure, side-effect-free owed allocation for ONE expense. Returns owed-by-id,
/// byte-for-byte identical to what [calculateBalances] accumulates for this
/// expense (before the participant-universe drop-guard). [currency] is fenced
/// internally (isSupported ? : 'OMR') so callers never crash MoneySerializer.
/// [onFallback] is invoked (NOT the static Sentry hook) when a malformed split
/// falls back to equal — pass null to stay silent (the preview path).
static Map<String, Decimal> allocateExpenseOwed({
  required Decimal amount,
  required SplitMode? splitMode,
  required Map<String, Decimal>? splitDistribution,
  required ExpenseScope scope,
  required List<String>? customSplitParticipants,
  required String payerId,
  required Iterable<String> participantIds, // event universe, for the scope path
  required String currency,
  void Function(SplitFallbackReason reason)? onFallback,
});
```

- The three private `_allocate*` lose their `Expense` param; they take `(amount, distribution, currency, onFallback)`. Mechanical, behavior-preserving.
- The scope path (`:380-435`) moves *into* `allocateExpenseOwed` as well, so the function owns the full gate-and-dispatch.
- `calculateBalances`'s loop shrinks to: fence currency → add to `paidMap` → `final owed = allocateExpenseOwed(... onFallback: (r) => onSplitFallback(r, expense))` → accumulate `owed` through the existing `owedMap.containsKey` drop-guard (`:373` / `:428` unchanged).
- **No logic duplicated. No behavior change.** Pinned by the existing `balance_calculations_test.dart` + `delete_group_balance_parity_test.dart` + `group_balance_provider_test.dart` staying green — that's the safety net (verification principle 2 + the parity ORACLE contract).
- **[Gate P3b — the single load-bearing line]** The closure `onFallback: (r) => onSplitFallback(r, expense)` is what keeps `test/unit/issue_250_split_fallback_telemetry_test.dart:58` green (it overrides `onSplitFallback = (reason, expense){…}` and asserts `expense.id`/`reason` per case). The extracted `allocateExpenseOwed` takes `void Function(SplitFallbackReason)?` (NO `Expense` arg); `calculateBalances` re-attaches the `expense` via this closure. Write it exactly so. (Verified `:58` exists with that 2-arg shape.)
- **[Gate P3a — fence stays]** `allocateExpenseOwed` fences currency defensively at its top (`isSupported ? : 'OMR'`), but `calculateBalances`'s OUTER fence (`:347-349`) MUST stay — it also selects the per-currency bucket key and feeds `paidMap`. The inner fence is idempotent/redundant for `calculateBalances`, load-bearing for the preview. Do not "dedupe" by removing the outer fence.

### Side effects the preview MUST NOT trigger (verified `:270-295`, `:319`)

- `onSplitFallback` → `_reportSplitFallbackToSentry` does `debugPrint` + `Sentry.captureMessage('ledger.split_fallback', warning)`. The preview passes `onFallback: null` → no telemetry on transient/edit states.
- `debugCalculateBalancesCount++` (`:319`) lives in `calculateBalances`, NOT in `allocateExpenseOwed`, so the preview never bumps it.

### Parity guard (verification principle 7 — adversarial, orthogonal axis)

`calculateBalances` is the cross-impl ORACLE mirrored byte-for-byte by the TS server `recomputeNet` (deleteGroup/leaveGroup/removeMember). The extraction must NOT change: guard ORDER (negative-FIRST, then tolerance), `_splitTolerance` (`0.001`), the alphabetically-last remainder target, or `_allocateExact`'s non-negative-absorb residual scan. The refactor is a *move*, not a rewrite — verified line-by-line against `:487-670`.

---

## 3. Wiring the preview (minimal, scope-stable)

`isNonEqual` mirrors the calculateBalances gate exactly (and `_isNonEqualSplit` in `ledger_day_card.dart:309`):
```
isNonEqual = _splitMode != null && _splitMode != SplitMode.equally
          && _splitDistribution != null && _splitDistribution!.isNotEmpty
```

1. **Thread** `_splitMode` + `_splitDistribution` into `_SplitPreviewCard` (constructor `:1431-1438`, call site `:685-692`). Both are already in scope in the same `build()` (state lines 164/169).
2. **Per-tile amount** (`:1572-1578`):
   - `isNonEqual` → compute once in `build`: `owed = BalanceCalculator.allocateExpenseOwed(... onFallback: null)`. Tile `share = owed[id] ?? Decimal.zero`. (The `?? 0` is the "custom-scope id with no distribution key renders sensibly" guarantee — show 0, never null/crash.)
   - else (equal/null) → **unchanged**: keep `each` (`:1474-1478`). Equal-split display does not change; no surprising revealed-remainder for the common case.
3. **The "Each: X" chip** (`:1514-1524`, gated `count >= 2`):
   - `isNonEqual` → render new `editorAmountsVary` ("Amounts vary per person.").
   - else → **unchanged** `editorEachAmount(formatCurrency(each, currency))`.
   - **Preserve** the `count >= 2` guard and the sibling summary ternary (`:1502-1507`).
4. **Preserve** per-tile `Directionality(TextDirection.ltr)` (`:1634-1639`, #151 bidi) — untouched; only the `share` value feeding it changes.
5. **Tile SET stays `_splitParticipantIds`** (the scope-derived set, `:1447-1463`) — we only correct the *amounts*, not which tiles render. **[Gate P2b — verified]** For non-equal modes `_splitDistribution.keys` ALWAYS covers exactly the participant set: `custom_split_sheet.dart:241-246` emits a key for *every* `widget.participants` id (0-weight included), and `expense_editor_body.dart:439-441` resets `_splitMode=equally; _splitDistribution=null` whenever scope/custom changes — so a stale distribution can never outlive its participant set. Therefore the per-tile `owed[id] ?? Decimal.zero` `?? 0` is **defensive-only and never visibly fires in the happy path**; it exists solely so a forged/legacy edited expense can't NPE the preview. Decision stands: keep the tile set stable, look up by id.

### Localization (verified conventions)

New key, placeholder-free, no `@`-block (matches `editorPerPersonAmounts` sibling), inserted after `editorPerPersonPercents`:
- `app_en.arb` (after `:825`): `"editorAmountsVary": "Amounts vary per person."`
- `app_ar.arb` (after `:295`): `"editorAmountsVary": "تختلف المبالغ لكل شخص."`
- Run `flutter gen-l10n`. EN is the template (placeholders declared once); AR carries no `@`-blocks (gen-l10n convention) — keep it that way.

---

## 4. Ledger-row consistency decision (acceptance box)

**Decision: DEFER the ledger-row WYSIWYG to a follow-up; document the divergence.**

- `ledger_day_card.dart:318-335` `_userShare` returns `Decimal.zero` for non-equal splits (hides the per-person sub-line), by intent (#125 comment `:305-308`: "omits the share line rather than show a misleading equal figure it cannot reproduce").
- The row HAS the data (`splitMode`/`splitDistribution` on the `Expense`, `:310-311`) but only knows equal division (`:328`). Once `allocateExpenseOwed` exists, the row can reuse it cheaply — but that's a **separate surface** (glanceable history vs. live split editing) and bundling it widens blast radius. One PR does one thing.
- The editor-vs-row divergence is defensible: the editor is where you actively *decide* the split (so show real amounts); the row is a summary (Splitwise shows different detail in edit vs list too).
- **Follow-up:** file a small issue "ledger row reuses `allocateExpenseOwed` for non-equal per-person amounts (signed, current-user-relative — preserve `sign: true`, `:266`)."

---

## 5. TDD plan (RED → GREEN, each step leaves the tree green)

This is a feature → red-green-refactor. Money code → table-driven (clean / warning / error).

**Step 0 — extraction safety net (refactor, no behavior change).**
- Extract `allocateExpenseOwed`; make `calculateBalances` delegate. Existing `balance_calculations_test.dart`, `delete_group_balance_parity_test.dart`, `group_balance_provider_test.dart`, `jabal_trip_settlement_test.dart`, and `issue_250_split_fallback_telemetry_test.dart` must stay GREEN with zero edits. (If any needs editing, the extraction changed behavior → stop.)
- **[Gate P2a — scope-path dedup]** The scope path (`:383-410`) `.toSet()`s recipients (`:386/392/399/402/408`), deduping; `_allocateEqual` (`:650`) sorts an `Iterable` WITHOUT deduping. **Move the inline `:380-435` block verbatim into `allocateExpenseOwed` — do NOT "simplify" the scope-equal split by reusing `_allocateEqual`.** A duplicate `customSplitParticipants` id would otherwise over-divide. (`customSplitParticipants` is `List<String>?` on the model, so a dup is type-possible even if the editor's `Set` makes it unlikely.)

**Step 1 — RED: pure allocator unit tests** (`test/unit/allocate_expense_owed_test.dart`, new). Table-driven:
- shares `{a:2,b:1}` on 9.000 OMR → `{a:6.000, b:3.000}`; remainder lands alphabetically-last.
- exact `{a:1.600,b:2.100,c:1.200}` summing to amount → returned verbatim; in-tolerance residual → closed onto last absorbable (NOT a 0.000 entry → phantom-credit guard).
- percent `{a:60,b:40}` on 10.000 → `{a:6.000,b:4.000}`; the percent NUMBER (60) is NOT rendered as 60.000 currency.
- equal/null mode + scope (global/custom/personal) → equal per-head, remainder last.
- **warning/error rows:** negative share/exact/percent → equal fallback; out-of-tolerance drift → equal fallback; `onFallback: null` → asserts NO throw and NO Sentry (override `onSplitFallback` to a spy, assert spy NOT called when `onFallback` is null and IS called via the `calculateBalances` closure path).
- **parity row:** `allocateExpenseOwed(...)` for a single expense == that expense's contribution inside `calculateBalances` (build a 1-expense event, compare owed maps). **Include a parity case with a DUPLICATE `customSplitParticipants` id** (Gate P2a) — proves the scope path's `.toSet()` dedup is preserved and `_allocateEqual` wasn't substituted.
- Implement extraction → GREEN.

**Step 2 — RED: preview widget test** (`test/features/ledger/expense_editor_split_preview_test.dart`, new or extend `expense_editor_body_test.dart`). Pump the editor (override `sharedPreferencesProvider`; `EmptyStateView` rule N/A here), set a shares/exact/percent split, assert:
- tiles show the REAL per-person amounts (e.g. shares 2:1 on 9.000 → finds "6.000" and "3.000", not "4.500" each).
- the chip reads `editorAmountsVary`, not `{amount} each`, for non-equal modes.
- equal mode still shows `{amount} each` and uniform per-tile amounts (no regression).
- `count < 2` still suppresses the chip (preserve `add_expense_screen_test.dart:151-166` intent).
- a custom-scope tile id absent from the distribution renders `0.000`, no crash.
- Wire the preview → GREEN.

**Step 3 — l10n + analyze + full suite.** `flutter gen-l10n`; `flutter analyze` clean (`prefer_const_constructors`!); `flutter test`.

---

## 6. Acceptance criteria (issue) → status

- [ ] Public pure `allocateExpenseOwed`; `calculateBalances` delegates (existing tests stay green). — Step 0/1
- [ ] Tiles show correct per-person amounts for shares/exact/percent, summing to `amount` (remainder alphabetically-last). — Step 2
- [ ] `editorEachAmount` chip replaced by `editorAmountsVary` for non-equal modes; new ARB en+ar; RTL verified. — Step 2/3
- [ ] `count < 2` "no each" guard preserved. — Step 2
- [ ] Per-tile `Directionality.ltr` preserved (#151). — untouched
- [ ] Custom-scope id with no distribution key renders sensibly (`?? 0`). — Step 2
- [ ] Ledger-row consistency decision recorded. — §4 (DEFER + follow-up)
- [x] ~~Goldens regenerated on macOS~~ — **N/A** (token-smoke harness, verified).
- [ ] Gate run to clean (no-P1) verdict before merge. — next

## 7. Out of scope (do not bundle — one PR does one thing)

- Changing how splits are persisted (already correct).
- The interim "suppress misleading equal figure" ungated change.
- Ledger-row WYSIWYG (§4 follow-up).
- Unifying the OTHER equal-split copies (scope path inline `:412-435`; custom_split_sheet `_EqualReadout:806`; preview `:1474-1478` for equal mode). Tempting, but separate refactor.
- The committed-but-untracked `test/unit/jabal_trip_settlement_test.dart` / `_probe_rounding_test.dart` — not part of this PR (they're a separate regression-test commit).

## 8. Open questions for the Gate

1. Non-equal tile SET: keep `_splitParticipantIds` (+`??0`) or switch to `owed.keys`? (§3.5)
2. Should equal-mode preview ALSO route through `allocateExpenseOwed` (revealing the sub-fils remainder on the last tile), for true single-source consistency — or keep the current uniform `each` to avoid surprising the 90% case? (Spec chooses: keep `each` for equal.)
3. ~~Does any existing test assert the OLD (wrong) equal-figure preview for a non-equal split?~~ **RESOLVED — no.** Grepped `test/features/ledger` + `test/unit`: the only preview-amount tests (`add_expense_screen_test.dart:114` #151 LTR; `:152` #152 solo count<2; `add_expense_currency_test.dart:228` #382 USD) all use **equal** splits (`5/2=2.500`, `10/2=5`), which this change leaves untouched. No test encodes the bug; the new non-equal tests are purely additive. `generated_l10n_surface_test.dart:219` pins `editorEachAmount` reachability → add an `editorAmountsVary` line there.
