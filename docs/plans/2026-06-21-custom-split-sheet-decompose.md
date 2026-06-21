# Plan — Decompose `custom_split_sheet.dart` (1343L → ~574L)

**Date:** 2026-06-21
**Type:** Refactor (relocation-only). **Gate:** EXEMPT (see Money safety).
**Branch:** `refactor/split-sheet-decompose` (worktree off `origin/main`).

## Goal

`lib/features/ledger/widgets/custom_split_sheet.dart` is 1343 lines (project max 800).
Extract its 12 private leaf `StatelessWidget`s into new `part of` files so the entry
file drops under 800, with **zero behavior change** and **zero public-API change**.

This extends the pattern already used for this exact library: `custom_split_sheet_itemized.dart`
is already a `part of 'custom_split_sheet.dart'` (added by #203 S2). A `part` shares the
library's private scope, so every `_Widget` stays private + reachable from `_CustomSplitSheetState`.

## Public contract — must stay byte-identical (verified vs code)

- `SplitResult` (OUTBOUND — feeds `ExpenseEditorPayload` → Firestore write)
- `showCustomSplitSheet` (OUTBOUND entry fn)
- `SplitParticipant` (INBOUND input; also used by the itemized part)
- `CustomSplitSheet` (public StatefulWidget)
- **`export '../../../core/models/split_mode.dart' show SplitMode;` (line 18)** — LOAD-BEARING:
  `expense_editor_body.dart` and `custom_split_sheet_test.dart` resolve `SplitMode` ONLY through
  this re-export (neither imports `split_mode.dart` directly). A `part` cannot host an `export`.
  **Leave line 18 untouched.**

Consumers: `expense_editor_body.dart` (only in-lib importer; `expense_provider.dart` merely
*mentions* the file in a comment — not an import). Tests touch only public API + 3 widget Keys
(`split_sheet_apply`, `split_exact_$id`, `split_percent_$id`).

## Money safety → Gate-exempt

All OUTBOUND distribution-building (`_buildResult`/`_buildItemizedResult`, the per-mode maps,
both `BalanceCalculator.allocateItemizedDistribution` calls) and every reconcile/tolerance gate
live in **`_CustomSplitSheetState` (142–571), which never leaves the entry file.**

The 12 leaf widgets carry only INBOUND display logic. The **one** exception: `_EqualReadout`
(987–1038) has a display-only per-head division `(total / Decimal.fromInt(equalCount)).toDecimal(
scaleOnInfinitePrecision: 3)` — equal mode persists `distribution: null`, so this is never
written. **HARD CONSTRAINT: relocate it byte-for-byte. Do NOT tidy / re-quantize / swap to
`_toCurrencyPrecision`** — touching any arithmetic line re-enters the money Gate.

→ One-sentence diff ("move 12 display widgets into sibling part files; no field renamed, no
arithmetic edited, no public API touched"). Gate-exempt per the Operating Contract.

## Decomposition (3 new `part of` files)

| New file | Widgets | Source lines |
|---|---|---|
| `custom_split_sheet_chrome.dart` | `_Header`, `_Footer`, `_StatusPill` | 573–626 + 1183–1343 |
| `custom_split_sheet_mode_selector.dart` | `_ModeSegmented`, `_SegChip`, `_ModeBody`, `_ParticipantRow` | 628–921 |
| `custom_split_sheet_editors.dart` | `_Editor`, `_EqualReadout`, `_SharesStepper`, `_StepperButton`, `_NumberInput` | 923–1181 |

Entry file keeps lines 1–571 (imports + line-18 re-export + `SplitResult`/`showCustomSplitSheet`/
`SplitParticipant`/`CustomSplitSheet`/`_CustomSplitSheetState`) + 3 new `part` directives after
line 22 → **~574 lines**. Orphan blanks 572/627/922/1182 dropped.

## Steps

1. Create the 3 part files: `part of 'custom_split_sheet.dart';` + banner + the verbatim
   `sed`-extracted ranges (byte-exact, money constraint).
2. Rewrite the entry file: lines 1–22 + 3 new `part` directives + lines 23–571.
3. Update the stale `_ModeSegmented` reference in `custom_split_sheet_itemized.dart`'s header
   comment (now lives in the mode_selector part).
4. Verify (see below).
5. Commit `refactor(ledger): split custom_split_sheet into part files`. Client-only, no deploy.

## Verification

- `git diff -w HEAD -- custom_split_sheet.dart` shows ONLY: 3 added `part` directives + removed
  class blocks — no changed expression (esp. nothing inside `_EqualReadout`).
- Byte-check `_EqualReadout` identical: `git show HEAD:…:987,1038` == extracted block.
- `flutter analyze` clean.
- 4 pinning tests green: `custom_split_sheet_test.dart`, `custom_split_sheet_itemized_test.dart`,
  `expense_editor_body_test.dart`, `issue_195_exact_split_renormalize_boundary_test.dart`.
- `flutter test` full suite green.
- `bash tool/check_theme_purity.sh` (CI-only; whole-class moves keep any justification comments).

## Out of scope (follow-ups, do NOT bundle)

- `custom_split_sheet.dart:1334` — `(r > Decimal.zero ? colors.error : colors.error)` has both
  ternary arms identical (over/under exact remainders render the same color). Looks like vestigial
  intent to differentiate. Moved verbatim here; fix is a behavior change → separate issue.

## Provenance

Verified by a Map+Design workflow (5 agents): structure / public-contract+tests / money-core
analyses → decomposition synthesis + adversarial critic (verdict: **ship**, 0 P1/P2, 4 cosmetic
P3s). Corroborated by hand-read of the entry file (public surface, state brain, leaf arithmetic).
