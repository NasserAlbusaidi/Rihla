# Split-mode clarity — Itemized as a first-class option on the card

**Branch:** `feat/split-mode-clarity` · **Mockup:** `docs/design/mockups/add-expense-split-clarity.html`
**Design pick:** Variation **A** (all modes on the card, icons + helper) — signed off 2026-07-02.

## Problem (audited)
The Split card's *How* control shows only 4 modes (`split_card.dart` `_ModeSegment`). **Itemized** exists
only as a 5th ellipsis-cramped chip *inside* the custom-split bottom sheet, reachable only by first tapping
an unrelated mode (Exact/Shares/%). Result: itemized is buried two levels deep and discovered by accident.
Prior memory note ("itemized discoverability improvements shipped") is **stale** — never done; code confirms.

## Not a Gate change
No money/rules/routing/schema surface. Itemized still persists as `SplitMode.exact` + opaque
`splitExplanation` (#203 contract, unchanged). The sheet ALREADY accepts `initialItemized: true`
(`custom_split_sheet` via `_openSplitModeSheet`). This is pure IA/affordance on the card. Gate skipped.

## Change
1. **`split_card.dart`** — replace `_ModeSegment`'s 4-chip equal-width `_Segmented` with a wrapping
   icon-chip control of **5** options (Equal / Shares / Exact / Percent / **Itemized**), each an Iconsax
   glyph + label. Selected = `isItemized ? chip==Itemized : (!isItemized && chip==mode)` — fixes the
   reopened-itemized-shows-"Exact" bug. Add a subtle one-line helper for the selected mode.
   - Icons: `element_equal` / `chart_2` / `hashtag` / `percentage_square` / `receipt_item`.
   - New required callback `onPickItemized` (VoidCallback); the 4 real modes keep `onPickMode`.
2. **`expense_editor_body.dart`** — wire `onPickItemized: () => _openSplitModeSheet(event, forceItemized: true)`;
   add `forceItemized` to `_openSplitModeSheet` → opens the sheet in itemized mode (`initialItemized: true`,
   `initialMode: exact`, seeding items/adjustments from the current `_splitExplanation` if already itemized).
3. **l10n** — 5 new `splitModeHelp*` strings (en + ar), regenerate.

## Tests (RED first) — `split_card_test.dart`
- Itemized chip is present on the card (currently absent → RED).
- Tapping Itemized fires `onPickItemized`, not `onPickMode`.
- With `splitExplanation != null` (itemized), the itemized helper shows (proves Itemized is the active
  selection, not Exact).
- Existing callbacks/labels tests updated for the new required param + kept green.

## Verify
`flutter analyze` clean · `flutter test test/features/ledger/` (221 green) ·
`bash tool/check_theme_purity.sh` PASS · fresh-context adversarial review (2 lenses + refute).

## Review outcome (2026-07-02, 2-lens fresh-context + refute)
- **P2 FIXED** — an already-itemized expense: tapping the (un-highlighted) *Exact* chip reopened the
  itemized editor instead of plain exact (my `(sameMode && alreadyItemized)` term was vestigial once
  Itemized became its own chip). Fix: itemized is entered *only* via `forceItemized`; `initialItemized`,
  `initialItems`, `initialAdjustments` all key off it. Regression test added
  (`expense_editor_itemized_test.dart` — "tapping Exact … opens plain exact, not the itemized editor").
- Reviewers confirmed the `forceItemized:false` path is byte-equivalent to prior behavior (no regression).

## Deferred (documented, not in this PR — one concern only)
- **In-sheet `_ModeSegmented` still ellipsizes** (`custom_split_sheet_mode_selector.dart`). Pre-existing;
  now a secondary surface since the card is the primary entry. Follow-up: give it the same wrapping chips.
- **Tap target ~33dp (<48dp Material min)** — matches the app's existing segmented controls (scope
  selector is identical); an app-wide a11y bump, tracked separately.
- Adjacent add-expense friction from the audit (reactive mandatory-category marker, silent ≥2 gate,
  no amount autofocus, itemized items default to zero assignees) — see the mockup's ALSO block.
