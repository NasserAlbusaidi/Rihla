# Design unification — enforcement backlog (2026-06-06)

Contract: [docs/DESIGN.md](../DESIGN.md). Goal: close the ~50% token-adherence gap
and the foundation drift in DESIGN.md §13. Each row = one atomic PR. None touch
money math / routing / rules / schema → **no Gate**; all are pure presentation, so
each PR must keep widget + golden tests green (goldens are macOS-only, CI-excluded
— regen locally).

## Drift snapshot (re-run greps in DESIGN.md §13 to update)

| area | files | tok% | edgeLit | sbLit | radLit | rawTS |
|---|---|---|---|---|---|---|
| home | 10 | 70% | 8 | 36 | 12 | 5 |
| ledger | 25 | 56% | 35 | 77 | 53 | 18 |
| groups | 27 | 66% | 25 | 109 | 33 | 27 |
| events | 17 | 64% | 16 | 62 | 27 | 25 |
| settings | 10 | 80% | 6 | 37 | 20 | 5 |
| auth | 14 | 57% | 1 | 23 | 7 | 0 |
| activity | 5 | 20% | 4 | 8 | 3 | 0 |
| shared | 14 | 71% | 0 | 3 | 1 | 7 |
| core | 44 | 9% | 3 | 5 | 23 | 7 |

(core is mostly non-UI services/router — low priority. shared is already clean.)

## Phase 1 — Foundation reconcile (FIRST — these change what screens adopt)

Doing screen migration before this means migrating to values we're about to change.

- **P1a — Radius semantic tokens (D2). ✅ DONE** (`refactor/design-foundation`).
  Added `radiusInput` 14 · `radiusCard` 20 · `radiusSheet` 28 · `radiusPill` 9999 to
  `AppSpacingTokens` as the canonical scale. *Additive* — values equal what `AppTheme`
  already renders, so no visual change / no golden churn. `AppTheme` left as the
  already-canonical reference (re-pointing its `const` shapes at field access buys
  nothing and breaks const). Per-screen migration of the ~19 legacy
  `radiusMedium`/`radiusLarge` call sites → Phase 2.
- **P1b — Motion tokens (D6). ✅ DONE.** New `AppMotionTokens` (`context.motion`):
  `quick` 120 · `standard` 200 · `emphasis` 300 + `curveStandard`/`curveEmphasis`,
  registered in both themes. Additive. Migrating the ~20 ad-hoc durations → Phase 2.
- **P1c + P1d — Dead-token cleanup (D3, D4, D7) → SEPARATE PR.** Re-scoped: code
  shows `AppGroupAvatarColors`/`groupAvatarSlot()` (the teal/emerald/amber "group
  palette") has **zero live callers** — it's dead, not an off-brand live palette
  (groups already use on-brand `RAvatar`). So this is one deletion PR: drop
  `AppGradients` + `AppGroupAvatarColors`/`groupAvatarSlot` + dead module color
  fields, **with** their tests (`token_promotions_test`, `design_tokens_test`
  gradient cases). Kept out of the additive-tokens PR (one-PR-one-thing); watch the
  80% coverage gate (delete tests alongside code). Touches `color_tokens` copyWith/
  lerp/`_allBlack` (50-field surgery) — careful, but inert.

## Phase 2 — Per-screen adherence (one PR per feature, ordered by impact × visibility)

Each PR: literals → `context.spacing` / token radii / `AppTypography`, hand-rolled
widgets → shared primitives. Keep diffs mechanical and reviewable.

1. **home** — pilot. High visibility, modest size; proves the pattern + Phase-1 tokens.
2. **ledger** — money screens; highest radius (53) + edge (35) drift.
3. **groups** — highest SizedBox (109) + raw TextStyle (27).
4. **events** — high raw TextStyle (25) + radius (27).
5. **settings + activity + auth** — smaller; can batch as 1–2 cleanup PRs.

## Definition of done (whole effort)
- Adherence greps (DESIGN.md §13) trend to near-zero literals in `features/`.
- DESIGN.md §13 drift table emptied (or remaining items explicitly deferred to a milestone).
- No new `Color(0x…)` outside tokens; `flutter analyze` clean; coverage ≥ 80%.
