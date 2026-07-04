# Plan — #811: Open-event Recap entry has weak scent (icon+tooltip only)

- **Issue:** #811 (`enhancement, P3, design, l10n, rtl, post-release`)
- **Date:** 2026-07-04
- **Gate-category?** **No.** No money math, `firestore.rules`, route-tree, or schema/field-name surface. It reuses the existing `AppRoutes.eventRecap` route and touches one screen widget + two ARB files + tests. → skip `/run-the-gate`, standard TDD.
- **Convention:** design-canvas-first (per project convention + issue body). Mockup precedes implementation.

## Problem (verified @ current `main`)

On an **open** event, the only entry to the Recap/closeout screen is a tooltip-only cup icon in the header icon row:

- `event_command_center.dart:422-428` — `RIconButton(key: recapButton, icon: Iconsax.cup, tooltip: recapButtonTooltip, onTap: onRecap!)`.
- Visibility gate: `event_command_center.dart:194-201` — shown only when `!event.isClosed && expenses.isNotEmpty`; pushes `/group/:gid/event/:eid/recap`.
- Only localized text is the tooltip `recapButtonTooltip` = "Recap" / "الملخّص" (`app_en.arb:2702`, `app_ar.arb:1036`). Tooltips are not touch-discoverable → weak scent.
- **Closed** events already solve this: `_ClosedBanner` (`event_command_center.dart:206-217, 784-853`) renders a slim labelled "View recap →" affordance below the header. Open events have no labelled equivalent.

The header row is provably cramped, which is why the earlier option-A (icon+label pill *inside* the row) is rejected: the `Row` (`:377-440`) already packs back-button + optional `_CompactAmounts` (collapsed state) + recap + search + settings around an `Expanded` **ellipsizing** title. Adding a text pill risks overflow at narrow width / RTL — the #811 triage comment (2026-07-04) reached the same conclusion independently.

## Decision — Option C (relocate to a labelled CTA outside the icon row)

**Reverses the earlier option-A pick.** Two moves:

1. **Remove** the header cup `RIconButton` (`:422-428`) and its `onRecap` plumbing into `_EventHeader`. Safe: **no test references `recapButton` / `recapButtonTooltip`** (grep of `test/` = 0 hits). Declutters the cramped row (removes one icon button).
2. **Add** a labelled recap entry for open events, mirroring the proven `_ClosedBanner` affordance, in the same layout slot.

### Placement — resolve on the mockup (canvas-first)

- **P1 (recommended): open-event counterpart banner.** A new `_OpenRecapEntry` (or a shared banner param) rendered in the header→body seam right where `_ClosedBanner` sits (`:205-217`), only when `!event.isClosed && expenses.isNotEmpty`. Slim tinted bar (`colors.textPrimary.withValues(alpha: 0.04)`), leading `Iconsax.cup`, short lead text (e.g. `recapOpenLead` "Trip so far") + right-aligned `InkWell` "View recap →" (`eventViewReceipt` + `DirectionalIcon(Iconsax.arrow_right)`). Best scent, mirrors an affordance the user already accepted, zero overflow risk.
- **P2 (lighter): right-aligned labelled InkWell in the header `Column`**, directly below `_BalanceBlock` (`:445-461`), no full-width bar. Less chrome, still labelled + out of the icon row. Consider it collapses with the balance block on scroll.

Mockup will pick P1 vs P2; both satisfy "labelled CTA outside the icon row."

### Copy / l10n

- Reuse **`eventViewReceipt`** = "View recap" / "عرض الملخّص" (`app_en.arb:1791`, `app_ar.arb:702`) for the action label — already localized, identical intent. (Its `@description` mentions the closed banner; broaden the description, don't fork a key, unless P1's lead text needs a new key.)
- If P1's lead text is used: add `recapOpenLead` (EN + AR). If P2 (label only): **no new key** — pure reuse.
- Keep or drop `recapButtonTooltip`: drop it if the cup is fully removed and it's otherwise unused (grep first; remove obsolete key + `@`-meta rather than orphan it).

## Files touched

- `lib/features/events/screens/event_command_center.dart` — remove cup from `_EventHeader` (`:422-428`) + its `onRecap` field/wiring (`:341,352-354`); add the open-recap entry widget + wire its visibility/onTap (reuse the existing push at `:194-201`).
- `lib/l10n/app_en.arb` + `lib/l10n/app_ar.arb` — only if a new lead-text key is needed; possibly remove `recapButtonTooltip`.
- `test/features/events/…` — new widget test (below); update any `event_tabs_test.dart` assumptions if they touched the header (they assert tab behavior, not the cup — expected no change).
- `docs/design/mockups/811-open-recap.html` + register in `docs/design/mockups/index.html` — the canvas.

## Test plan (TDD — scent regression is the definition of done)

Write the failing test first (RED) — today the open event shows no visible recap **text**:

1. **Scent:** open event + ≥1 expense → a visible "View recap" **text** node is findable (`find.text`), not merely a tooltip. (Fails on current `main`.)
2. **Route:** tapping it pushes `/group/:gid/event/:eid/recap` (mock GoRouter / assert location).
3. **Empty gate:** open event + 0 expenses → affordance absent.
4. **Closed unchanged:** closed event → Recap **tab** present, open CTA absent (no double entry).
5. **RTL / narrow no-overflow:** pump at a narrow width in `TextDirection.rtl` → no `RenderFlex` overflow (the failure mode option A would have caused). Golden optional (macOS-only, CI-excluded).

Then `flutter analyze` clean + run `test/features/events/` + `bash tool/check_theme_purity.sh` (mirroring `_ClosedBanner`'s `context.colors` usage keeps it token-pure — but the script is CI-only, run it locally).

## Gotchas

- **Theme purity:** use `context.colors` only (copy `_ClosedBanner`'s pattern; no hardcoded `Color(0xFF…)`). Copying a styled block can drop a `// design-token-justified:` comment → red CI (#615) — `_ClosedBanner` has none to drop, but re-check.
- **RTL:** the arrow must be `DirectionalIcon` (as `_ClosedBanner` does), not a raw `Iconsax.arrow_right`.
- **const:** mark const-eligible literals `const` (`prefer_const_constructors` fails CI).
- **No cup-key test coupling** confirmed, but grep `EventKeys.recapButton` across `lib/` before deleting the key from `event_keys.dart`.

## Out of scope

- Closed-event Recap tab/banner (unchanged).
- Trip Receipt CSV/PDF export (#704) and its l10n (#784).
- Any recap **screen** content change.

## Rollout

1. Mockup (`811-open-recap.html`) → confirm P1 vs P2.
2. RED test (scent #1).
3. Implement C (remove cup, add labelled entry).
4. `flutter analyze` + `test/features/events/` + theme-purity locally.
5. PR: `Closes #811`; one concern only.
