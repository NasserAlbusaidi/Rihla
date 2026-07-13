# #605 (remaining slice) — `assigned` discount mode for itemized adjustments

**Issue:** #605 (re-scoped after PR #621) · **Area:** money-math + editor UX ·
**Gate-category:** yes (BalanceCalculator)

## Scope

The ONE remaining slice of #605: manual **assigned**-discount mode — pick who bears the
discount — via `SplitAdjustment.participantIds` + an `'assigned'` branch in
`BalanceCalculator.allocateItemizedDistribution`, plus its table-driven money test and the
editor UI. Everything else in #605 shipped in PR #621.

**No server change. No rules change.** `splitExplanation` is opaque
(`is map && size()<=64`); `participantIds` on an adjustment is purely additive; balance
truth remains the folded exact `splitDistribution`. Never wire the server to read
`splitExplanation` (pinned contract).

## Model — `lib/features/ledger/models/split_explanation.dart`

Add to `SplitAdjustment`:

```dart
/// Who bears an 'assigned' discount. Null/empty for every other
/// type/allocation (key omitted on write). Display-only, like everything here.
final List<String>? participantIds;
```

- Constructor: optional named param, default `null`.
- `fromMap` (lenient, never throws): same shape as `SplitItem.participantIds` —
  `(map['participantIds'] as List?)?.map((e) => e.toString()).toList()`.
- `toMap`: `if (participantIds != null && participantIds!.isNotEmpty) 'participantIds': participantIds` — byte-identical serialization for every existing doc (no version bump; matches the reserved v1 shape on the issue).

## Allocator — `expense_provider.dart` `allocateItemizedDistribution` Phase 3

Today: all discounts pool into `totalDiscount`, then ONE proportional-to-pre-discount
reallocation of the remaining bill. New contract:

1. **Partition** discounts: `assigned` = `type == 'discount' && allocation == 'assigned'`
   (scoped to BOTH fields — a forged/legacy ADDITIVE adjustment carrying
   `allocation:'assigned'` must stay in Phase 2 on its existing equal-spread branch, never
   route into the subtract-style reallocation); everything else keeps
   the pooled proportional fold (unchanged, including the normalize-on-write behavior).
   **Explicitly: the existing pooled loop (`expense_provider.dart:551-555`) gains
   `&& adj.allocation != 'assigned'` so an assigned discount is NEVER also summed into
   `totalDiscount`** — without the exclusion it would be double-counted.
2. **Strict producer validation** for an assigned discount — a NEW sibling
   `_validateAssignedAdjustment(SplitAdjustment adj, List<String> equalBase)` (the existing
   `_validateAdjustment` takes only `adj`; the membership check needs `equalBase` threaded
   in — Gate R1 rubric P3). Lenient `fromMap` still displays anything:
   - `participantIds` non-empty after dedup, and every id ∈ the full `participantIds`
     (equalBase) table — else `ArgumentError` (mirrors the existing item guards).
3. **Apply assigned discounts FIRST, sequentially in list order**, each against the
   *current* owed state:
   ```
   subset      = adj.participantIds (deduped, sorted)
   subsetPre   = current owed of subset members (absent key → 0)
   subsetTotal = Σ subsetPre
   remaining   = subsetTotal - adj.amountFils
   if (remaining < 0) throw ArgumentError   // discount exceeds what the subset owes
   reallocated = _spreadProportional(remaining, subsetPre, subset)  // fallbackBase = subset
   replace the subset's entries with reallocated (non-subset entries untouched)
   ```
   Key-set note: `_spreadProportional` returns positive-weight keys only, so a subset
   member with ZERO pre-discount owed is DROPPED from the replaced entries rather than
   kept at 0 — harmless for balances (absent ≡ 0) and consistent with the existing
   pooled-discount fold; state it in the code comment and pin it in the money test.
   Non-negativity: same argument as the existing whole-table discount — reallocating a
   non-negative `remaining` proportionally within the subset can never produce a negative
   (the #1203 remainder nuance — last key may exceed its pre-discount share by ≤ n-1
   subunits — carries over identically and is documented, not "fixed").
   Conservation: `Σ out = Σ pre - Σ assignedDiscounts - pooledDiscount` = bill total minus
   all discounts. `remaining == 0` with all-zero weights falls back to an equal spread of 0
   over the subset — harmless; `remaining < 0` throws before the fallback can misfire.
4. **Then** the pooled proportional discounts exactly as today, proportional to the
   post-assigned owed state. Document the ordering in the Phase-3 comment.

## Editor — `lib/features/ledger/widgets/custom_split_sheet_itemized.dart`

- `_AdjustmentDraft`: add `List<String> participantIds` (mutable, default empty). The
  existing discount normalization ("always `'proportional'`", lines ~106-113) becomes:
  discount allocation ∈ {`'proportional'` (default), `'assigned'`}. **The empty/invalid
  `'assigned'`-selection → `'proportional'` fallback MUST live inside
  `_AdjustmentDraft.toAdjustment` (`custom_split_sheet_itemized.dart:~108-114`) — the
  OUTBOUND path feeding BOTH the preview and `_buildItemizedResult` — not merely at widget
  build (Gate R1 rubric P2: a build-only normalization lets an `'assigned'`+empty draft
  reach the allocator and throw).** Non-discount types: `participantIds` always emitted
  empty/omitted.
- The adjustment editor sheet `_AddAdjustmentSheet` (which today HIDES the allocation
  choice for a discount) instead offers the two discount modes; choosing `'assigned'`
  reveals a member multi-select (reuse the existing item-assignee chip pattern in the same
  file — same widgets, same selection retention rules). **`_AddAdjustmentSheet` currently
  has NO participant data** (`_AddAdjustmentSheet({required draft, required currency})`,
  `custom_split_sheet_itemized.dart:~984`, invoked at `custom_split_sheet.dart:~264`) —
  thread the SAME participant list + display-name resolution the item-assignee chips
  already receive, as a named `participants` constructor param on `_AddAdjustmentSheet`,
  updated at that one callsite (Gate R1 rubric P2).
- **Over-discount gate — single-chokepoint fold; the sheet has NO existing try/catch
  (Gate R1 rubric P1, verified: the only guard is the whole-bill scalar
  `keepDiscounts = (_itemizedSum + _adjAdditiveSum - _adjDiscountSum) >= 0` at
  `custom_split_sheet.dart:~490`, which is blind to subsets — items 100 {A:50,B:50},
  assigned discount 60 on {A} passes it, then `_itemizedPreview` (read in `build()`, ~659)
  throws `ArgumentError` → red-screen while typing; `_itemizedCanApply` (~502-508) and
  `_adjValid` (~441) are also subset-blind so Apply stays enabled and
  `_buildItemizedResult` (~577) throws on tap.** Required design: ONE private helper that
  attempts the full `allocateItemizedDistribution` fold in a try/catch and returns a sealed
  result — either the distribution or a structured `assignedDiscountExceedsSubset`-style
  failure (memoize per draft-state if trivially easy; correctness first). `_itemizedPreview`,
  `_itemizedCanApply`, and `_buildItemizedResult` ALL consume that single helper: build
  never throws, Apply disables on failure, and the inline l10n error names the failing
  discount. **On failure the preview shows the LAST VALID per-person distribution (or the
  pre-adjustment item fold) alongside the error — never a zeroed/blank preview** (a
  subset-overshoot mid-edit must not flash misleading zeros; pinned by the widget test).
  **Preserve the EXISTING pooled-overshoot behavior (Gate R2 adversary P2):** today
  `_itemizedPreview` gracefully DEGRADES a whole-bill pooled overshoot by dropping
  discounts (`keepDiscounts`) so items keep rendering while typing — the new helper must
  keep that degrade path for pooled discounts (only the ASSIGNED-subset overshoot gets the
  error state), or, if unifying, spec the pooled-overshoot copy explicitly and update the
  existing widget test intent (`custom_split_sheet_itemized_test.dart:~432` only asserts
  no-crash + Apply-disabled, so a silent behavior change would be invisible to CI —
  don't let it slip through unpinned). Default decision: KEEP degrade-for-pooled,
  error-for-assigned.
  The allocator's throw is the authoritative check (sequential fold order makes
  per-subset owed state-dependent); do NOT duplicate the subset math in the sheet.
- Reopen round-trip: `participantIds` persists inside `splitExplanation.adjustments[]` and
  reconstructs the draft (pinned by test). **The reopen touch-point is
  `_AdjustmentDraft.fromAdjustment` (`custom_split_sheet_itemized.dart:89-98`)** — it
  currently copies type/amountFils/allocation only and MUST also copy
  `a.participantIds`.
- **Explanation-equality gates MUST learn the new field (Gate R1 adversary P1).** Both
  `_explanationEquals` (`edit_expense_screen.dart:286-292`) and `_explanationValueEquals`
  (`expense_editor_body.dart:981-987`) hand-compare adjustments by
  `type`/`amountFils`/`allocation` only. Without a `participantIds` compare, re-targeting
  an assigned discount ({A,B} → {A,C}, same type/amount/allocation) moves the money
  (`moneyDirty` fires via `!mapEquals` on the distribution) but skips the
  `splitExplanation` rewrite (`explanationDirty` stays false, `edit_expense_screen.dart:204-213`)
  → the persisted doc is internally inconsistent, reopen reconstructs the WRONG subset,
  and the next save re-folds from the stale subset and silently reverts the money. Add an
  order-independent `participantIds` SET-compare to BOTH methods, and correct their doc
  comments (the "belt-and-braces — `!mapEquals` catches it" justification is false for
  this field: `explanationDirty` gates the explanation WRITE, not just dirty detection).
  Regression test required: re-target assigned discount → save → reopen shows the new
  subset → re-save preserves the distribution.
- **Collapsed adjustment row shows the subset (Gate R2 adversary P2 — decided: INCLUDE).**
  `_AdjustmentRow` (`custom_split_sheet_itemized.dart:~940-975`) today renders type+amount
  only, so an assigned discount would be visually identical to proportional. Add a short
  "who bears it" caption on assigned rows (names, same style as item-assignee captions).
  Its EN **and AR** keys are part of the l10n enumeration below (#857 scar class).
- l10n: new EN + AR keys for the assigned-mode label, member-picker prompt, the
  subset-over-discount error, AND the collapsed-row assigned caption.
  `generated_l10n_surface_test` enumerates keys — update it.

## Tests

1. **Table-driven money test** (existing itemized allocator test file; clean/edge/error per
   the money contract):
   - clean: subset of 2 bears a discount, third member untouched; exact expected map.
   - edge: assigned member with ZERO item subtotal in the subset (weight 0 — excluded by
     `_spreadProportional`'s positive-weight filter; discount lands on the others).
   - edge: discount == subset owed exactly ⇒ subset owed goes to 0, conservation holds.
   - edge: assigned + pooled proportional discount together (ordering pinned).
   - error: discount > subset owed ⇒ `ArgumentError`.
   - error: assigned with empty/unknown participantIds ⇒ `ArgumentError`.
   - non-negativity + conservation asserted on every clean/edge row.
2. Model round-trip: `SplitAdjustment.toMap/fromMap` with and without `participantIds`;
   absent key ⇒ null (legacy docs unchanged).
3. Editor widget test: assigned mode select → preview matches allocator; reopen round-trip;
   subset-over-discount → no crash, Apply disabled, inline error shown (the rubric-P1
   scenario: items {A:50,B:50}, assigned discount 60 on {A}); re-target regression (the
   adversary-P1 scenario: {A,B}→{A,C} re-target → save → reopen shows new subset →
   re-save preserves the distribution).
4. l10n surface test entries for the new keys.

## Verification-principles evidence

- **Fields enumerated from the type:** `SplitAdjustment` currently = `{type, amountFils, allocation}` (read this session); adding `participantIds` is the reserved v1 shape.
- **Callsite classification:** `allocateItemizedDistribution` is OUTBOUND (produces the
  persisted exact distribution). `SplitAdjustment` maps are INBOUND display
  (`splitExplanation`) — the server never reads them (pinned contract, unchanged).
- **Read-path per write-path:** the folded `splitDistribution` is read by
  `calculateBalances`/`recomputeNet` as an ordinary exact split — no consumer change.
- **Orthogonal axes for reviewers:** interaction with #1206's BigInt fix (this spec's
  subset reallocation goes through the same `_spreadProportional`); the #1203
  remainder-overshoot nuance scoped to a subset; RTL/l10n for the new picker.

## Sequencing

Lands AFTER #1203 (comment/test) and #1206 (BigInt) merge — same Phase-3 region; the fixer
rebases onto main before opening the PR. Commit message carries `Closes #605` ONLY if both
remaining acceptance boxes (assigned mode + money test) ship; otherwise `Refs #605` in the
commit body too (squash-merge auto-close trap).

## Out of scope

Receipt OCR, %-entry, item-level allocation modes, per-item assigned adjustments,
multi-currency conversion, any rules/server change.
