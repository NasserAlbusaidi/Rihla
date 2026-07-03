# Split-editor money parity — #853 (equal preview) + #856 (exact/percent seeding)

**Date:** 2026-07-03 (line numbers re-verified @ `3ca3d3af`; the intervening commits since `b0e02329` did not touch `split_card.dart` or `custom_split_sheet.dart`)
**Issues:** Closes #853, Closes #856 (Refs #818)
**Gate category:** money. Author-gate BEFORE code (`/run-the-gate`); each PR also re-gated at merge via `/automerge`.
**Shape:** ONE spec, TWO independent PRs (disjoint source files — verified). Do **not** bundle into one PR (one-PR-one-thing; different risk classes: #853 is INBOUND display, #856 is OUTBOUND write-seed).

---

## Shared context — the oracle these two must mirror

`BalanceCalculator` (`lib/features/ledger/providers/expense_provider.dart`) is the cross-implementation ORACLE.
- `allocateExpenseOwed(...)` is the single entry point every split mode should go through.
- Equal path → `_allocateEqual` (~L791-820): whole-subunit per-head via `_toCurrencyPrecision` (subunit round-trip, `#596`), remainder → **alphabetically-last** recipient, dedupes recipients via `.toSet()`.
- Weighted path → `_allocateWeighted` (~L754-780): quantizes the derived owed to subunits.
- **Do NOT modify `expense_provider.dart`.** Both PRs CALL the allocator read-only; the allocator is the source of truth and stays byte-for-byte identical to the TS server oracle (`recomputeNet`). Any allocator edit is out of scope and a parity risk.

**Invariants both PRs must preserve**
1. `Decimal` only, never `double`. Per-doc currency = `group.currency` default but each money doc carries its own; here the editor's `currency`/`widget.currency` is authoritative — never assume OMR.
2. Currency scale: OMR/KWD/BHD=1000, USD/EUR/GBP/SAR/AED/QAR=100, **JPY=1**. Quantize via the allocator's `_toCurrencyPrecision` path, **never** raw `Decimal.toDecimal(scaleOnInfinitePrecision:)` (that only rounds non-terminating divisions — the `#596` trap).
3. Remainder always lands on the **alphabetically-last** recipient so `sum(shares) == total`.
4. No allocator may emit a negative owed (allocator already defends; we don't reintroduce a path around it).

---

## PR-1 — #853: equal-split preview shows naive per-head under a "✓ Adds up to {total}" badge

### Problem (verified @ 3ca3d3af)
`split_card.dart` equal mode never routes through the allocator, so the preview rows can sum ≠ the total shown in the green reconcile badge.
- `_recomputeOwed` (~L150-171): `if (!_isNonEqual) { _owed = null; return; }` — equal splits skip `allocateExpenseOwed` (called ~L160).
- `_isNonEqual` (~L96-99): false when `splitMode == SplitMode.equally`.
- `_personRow` (~L293-296): `each = (amount / len).toDecimal(scaleOnInfinitePrecision: 3)`; `share = _owed != null ? _owed![id] : each`. For OMR 10.000/3 → 3.333 ×3 = 9.999 (persisted oracle charges alphabetically-last 3.334).
- `_descriptor` (~L334-349): second naive `each`; the `editorAmountsVary` vs `editorEachAmount("X each")` branch.
- Green badge: `_ReconcileFooter` (~L753-795), mounted ~L256-261 with `editorSplitAddsUpTo(formatCurrency(amount, currency))`, renders unconditionally (~L779-787).

### Classification
INBOUND / display-only. Equal splits persist with `splitDistribution = null` (`expense_editor_body.dart` `_submit`) and are recomputed at balance/persist time by the SAME `allocateExpenseOwed`. **No persisted-math change** — this only makes the display equal the already-correct persisted math. Zero write-path/oracle risk.

### Change (`split_card.dart` only)
1. `_recomputeOwed` (L150-171): **delete the `if (!_isNonEqual) { _owed = null; return; }` early-return (L151-154).** The existing `allocateExpenseOwed(...)` call (L160-170) then runs for ALL modes; for equal, `widget.splitMode == SplitMode.equally` + `widget.splitDistribution == null` route to the scope/equal arm → `_allocateEqual` (`.toSet()` dedupe, `_toCurrencyPrecision` quantize, remainder → alphabetically-last). Every other arg (`scope`, `customSplitParticipants`, `payerId`, `participantIds`, `currency`) is already passed correctly — **no call change**. Update the now-stale comment "Equal splits keep the uniform `each`" (L159). `debugSplitPreviewOwedComputes++` now fires for equal too (memo test inverts — see Tests).
2. `_personRow` (L293-296): `_owed` is now always non-null → `share = _owed![id] ?? Decimal.zero`; delete the naive `each` (L293-294).
3. `_descriptor` (L335): change `} else if (_owed != null) {` → **`} else if (_isNonEqual) {`**. This (a) keeps the `_isNonEqual` getter live so there is **no `unused_element` / analyze break** (its only other use, L151, is removed), and (b) shows "Amounts vary" only for non-equal modes; equal falls to the `else` branch. The `else` "X each" **summary label** keeps its representative `formatCurrency(amount/count)` (display-only single value; the reconciling per-ROW figures now come from `_owed`). Grep confirms `_isNonEqual` has no third reference.

### Acceptance criteria (RED-first)
- [ ] Equal-mode rows come from `allocateExpenseOwed`; the **per-ROW** naive `scaleOnInfinitePrecision: 3` computation (`_personRow`) is removed. The `_descriptor` "X each" summary label **intentionally keeps** `formatCurrency(amount/count)` (change #3) — that is NOT an unmet box.
- [ ] Non-divisible equal split: displayed rows **sum exactly to the badge total** (regression `OMR 10.000/3 → 3.333/3.333/3.334`).
- [ ] Remainder on the alphabetically-last recipient (preview == persisted).
- [ ] Values currency-quantized: cover OMR (3dp), USD (2dp), JPY (0dp) in the new test.
- [ ] Equal mode still shows "X each", NOT "Amounts vary" (guards the `_descriptor` trap).
- [ ] `debugSplitPreviewOwedComputes` still memoizes — no per-keystroke re-alloc beyond a real money-input change (`#485/#627`).
- [ ] `flutter analyze` clean; theme purity PASS.

### Tests
- `test/features/ledger/split_card_test.dart` — ADD a non-divisible regression (OMR 10.000/3, plus USD 2dp + JPY 0dp) asserting row-sum == badge total. The existing "shows real per-person figures" test uses 48.000/2 (divisible) and stays green — it cannot catch this.
- `test/features/ledger/expense_editor_split_preview_memo_test.dart` — **MUST MODIFY.** The test "equal split never runs the owed allocation" (~L206-219) asserts `debugSplitPreviewOwedComputes == 0` twice; the fix inverts that to ≥1. Rewrite: equal now allocates AND still memoizes (no per-keystroke re-alloc). RED before fix.

### Known non-reachable edge (no action — Gate adversary P3)
Post-fix, `_personRow` rows iterate the raw `_splitParticipantIds` List while `_owed` comes from the `.toSet()`-deduped allocator. A duplicate id in `event.participantIds` would render two rows both reading the same `_owed[id]` → displayed sum > badge. NOT reachable in-app (`participantIds` is built from a `Set` at create, `create_event_screen.dart`), display-only, and the pre-fix `amount/list.length` is already inconsistent with the deduped persisted balance — so this fix does not regress it. No dedup of the row loop required; noted for completeness.

---

## PR-2 — #856: Exact/Percent split editors open blank (no baseline seeding)

### Problem (verified @ 3ca3d3af)
Switching split mode to Exact or Percent opens every per-person field empty; Shares seeds 1-each. User must hand-balance before the reconcile gate (`_canApply`) enables Apply.
- Seeding lives entirely in `custom_split_sheet.dart` (NOT `expense_editor_body.dart` — the caller already passes `initialMode: mode` (`showCustomSplitSheet` ~L719) and `initialDistribution: sameMode ? _splitDistribution : null` (~L730), deliberately null on a mode switch, comment "a mode switch starts that tab fresh").
- `_readInitialExact` (~L298-303) / `_readInitialPercent` (~L305-310): return `''` when `initialMode != exact/percent` OR when `initialDistribution?[id] == null`. On a fresh switch to exact/percent, `initialMode` IS exact/percent but `initialDistribution` is null → blank.
- `_initExact`/`_initPercent` (~L277-289) build the controllers from those.
- `_canApply` (~L449-462): `exact → _exactRemainder.abs() <= _tolerance`; `percent → _percentRemainder.abs() <= _tolerance`; Apply button `onPressed: _canApply ? _apply : null` (~L667). Blank ⇒ Σ=0 ⇒ remainder=total/100 ⇒ disabled.
- Sheet already has `total` (L136), `currency` (L137), `participants` (L138) and already imports+calls `BalanceCalculator` (L16, L433, L516).

### Classification
**BOTH → treat as OUTBOUND.** Seeded controller text is read back by `_buildResult` (~L485-504) → `SplitResult.distribution` → `expense_editor_body.dart` `_splitDistribution` → persisted as `splitDistribution`. Money Gate applies; `#596` quantization on the derived owed.

### Change (`custom_split_sheet.dart` only)

**Import:** add `import '../models/expense_model.dart' show ExpenseScope;`. The sheet imports `expense_provider.dart show BalanceCalculator` and `core/models/split_mode.dart` (SplitMode) — `ExpenseScope` (`expense_model.dart:8`) is NOT in scope and NOT re-exported.

**Exact seed helper** — reuse the oracle equal arm; the EXACT call (params verified `expense_provider.dart:390-399`):
```dart
final Map<String, Decimal> seed = BalanceCalculator.allocateExpenseOwed(
  amount: widget.total,
  splitMode: SplitMode.equally,     // → scope/equal arm → _allocateEqual
  splitDistribution: null,          // NB: param is `splitDistribution:`, not `distribution:`
  scope: ExpenseScope.global,       // recipients = participantIds.toSet()
  customSplitParticipants: null,
  payerId: '',                      // unused on the global/equal path
  participantIds: _participantIds,  // L404, the sheet's ids
  currency: widget.currency,
  onFallback: null,                 // suppress preview-path Sentry
);
```
`Σ(seed) == widget.total` exactly (remainder on alphabetically-last), whole-subunit for OMR(3)/USD(2)/JPY(0). Fill each exact controller via the sheet's existing plain-decimal formatter (`_formatPlainDecimal`). **TRAP:** do NOT pass `splitMode: SplitMode.exact` + a map — that routes to `_allocateExact` (re-normalizes an existing distribution), not an equal seed.

**Percent seed:** `base = 100 / n` at the percent field precision (dp=3, `custom_split_sheet_editors.dart:69`); alphabetically-last id = `100 − base·(n−1)` so `Σ == 100` within `_tolerance`. Percent weights are NOT money — do NOT subunit-quantize the percent text; only the derived owed is subunit-quantized (by `_allocateWeighted` at read time).

**WHERE to seed — BOTH entry points, blank-only (resolves the round-1 [P1]):** seeding must fire whenever the editor ENTERS exact/percent with that mode's controllers all-empty. There are two reachable entries and `initState` only covers the first:
1. **Card-entry** — sheet opens directly in the mode (`_openSplitModeSheet` passes `initialMode: exact/percent`, `expense_editor_body.dart:717`). Seed inside `_initExact`/`_initPercent` (run once in `initState`, L187-188) when `widget.initialMode` is that mode AND every value is blank (no persisted `initialDistribution`).
2. **In-sheet switch** — `_ModeSegmented.onMode` (L567-574) currently does `setState(_mode = next; _itemized = false)` and never re-inits the exact/percent controllers, so a user who opens on Shares/Equally and taps Exact/Percent gets BLANK fields. After setting `_mode = next`, if `next` is exact/percent and that mode's controllers are all-empty, fill them from the seed **inside the same `setState`**.

**Blank-only guard (spec rule):** never overwrite a controller that already holds a value (persisted `initialDistribution` OR in-progress input). This keeps three cases correct: same-mode reopen (hydrates from `initialDistribution`, not re-seeded), switch-away-and-back (edits preserved), and a genuinely blank entry (seeded).

**Accepted trade-off (Gate adversary P2, documented decision):** seeding a mode on the in-sheet switch also *enables Apply immediately*. When editing an EXISTING exact expense `{5,10,15}` and switching to Percent, the Percent tab now seeds to equal and Apply is enabled — a careless `switch→Apply` overwrites `{5,10,15}` with the equal baseline. This is **accepted as-designed**: the mode switch already discards the other mode's distribution (`initialDistribution: null` on switch — carrying it across is explicitly out-of-scope, below), so the loss is inherent to switching modes, not new; the fix only changes whether Apply is *gated*, and the seeded values are visible before Apply. #856's whole intent is "Apply reachable from a valid seed." If this proves a real footgun in QA, the follow-up is: on a mode switch (not a fresh open) seed but leave Apply disabled until the user touches a field. Not doing that now.

**Shares** unchanged (still 1-each via `_initShares`/`_readInitialShare`).

### Acceptance criteria (RED-first)
- [ ] Seeding fires on **both** entries: (a) card-entry `initialMode: exact/percent`, and (b) in-sheet `onMode` switch into exact/percent. Both leave Apply enabled immediately.
- [ ] Card-entry Exact with n≥2 and no prior distribution pre-fills each row so Σ == total exactly.
- [ ] In-sheet: open on Equally/Shares, tap Exact → rows pre-seeded to Σ == total (was blank pre-fix); tap Percent → rows pre-seeded to 100/n.
- [ ] Exact remainder (indivisible subunit) on the alphabetically-last id; seeded exact values whole-subunit for OMR(3dp)/USD(2dp)/JPY(0dp).
- [ ] Percent remainder on the alphabetically-last id so Σ == 100 within `_tolerance`.
- [ ] Same-mode reopen of an existing Exact/Percent expense hydrates from `initialDistribution` — seeding does not clobber persisted values.
- [ ] Switch away from a seeded+edited mode and back does NOT re-seed (in-progress edits preserved).
- [ ] Shares unchanged (1-each).
- [ ] `flutter analyze` clean; theme purity PASS.

### Tests
- `test/features/ledger/custom_split_sheet_test.dart` (NOTE: the existing exact/percent tests, ~L167-286, drive the **in-sheet switch** — open on default `initialMode: equally` then tap "Exact amounts"/"Percent". Post-fix that switch SEEDS, so their "starts blank → hand-fill → reconcile" premise breaks; they must be rewritten, not left green):
  - REWRITE "exact — Apply disabled until sum equals total" (~L167-213): after the in-sheet switch seeds a=b=c=10 for total 30, Apply is already enabled; drive Σ **off**-total (edit one row) to prove the gate still bites.
  - REWRITE "percent — Apply disabled until sum is 100" (~L241-286): this is a **premise-fix** (the seeded 100/n start means the test's blank-start assumption no longer holds), not a genuine RED-first — the exact test is the true RED-first proof. Rewrite so it seeds to 100/n (Apply enabled), then edit Σ off-100 to prove the gate still bites.
  - KEEP "Apply disabled when every share is zero" (~L120-163) — documents the shares baseline this brings Exact/Percent up to.
  - ADD (in-sheet path): open on Equally, tap Exact → assert rows pre-seeded to Σ==total & Apply enabled; tap Percent → rows pre-seeded to 100/n.
  - ADD (card-entry path): open with `initialMode: SplitMode.exact` (+ null `initialDistribution`) → rows pre-seeded, Apply enabled. Same for percent.
  - ADD (no-clobber): open with `initialMode: exact` + a persisted `initialDistribution` → hydrates from it, NOT re-seeded; and switch exact→percent→exact after editing → edits preserved.
  - ADD (currency matrix): seeded Exact Σ==total with remainder on alphabetically-last + whole-subunit for OMR/USD/JPY.
- Safety net (unchanged, cite): `test/unit/issue_195_exact_split_renormalize_boundary_test.dart` already forces a +0.001 over-allocation onto the alphabetically-last recipient that can absorb it without going negative.

---

## Out of scope (do not touch)
- `expense_provider.dart` allocators / `money_serializer.dart` (oracle — no edits).
- `splitExplanation` / itemized path (`allocateItemizedDistribution` stays as-is).
- Any `firestore.rules` / server change (no new negatives; rules already block them).
- Carrying a distribution ACROSS a mode-switch (deliberately rejected — `expense_editor_body.dart` ~L661-662).
- `expense_editor_body.dart` (neither PR needs it; keeps #853/#856 file-disjoint from each other and from the merged #854).

## Delegation note
Each PR built by Codex (`codex exec`) in its own isolated git worktree off `main`, from this gated spec. Both re-gated at merge via `/automerge` (fresh Opus diff review + refuter). PR-1 and PR-2 touch disjoint files (`split_card.dart` vs `custom_split_sheet.dart`) → safe to build in parallel worktrees; only the runtime coupling is that PR-1's memo test boots the editor body (re-run after any editor-body change lands).
