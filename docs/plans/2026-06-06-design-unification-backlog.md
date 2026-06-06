# Design unification — enforcement backlog (2026-06-06)

Contract: [docs/DESIGN.md](../DESIGN.md). Goal: close the ~50% token-adherence gap
and the foundation drift in DESIGN.md §13. Each row = one atomic PR. None touch
money math / routing / rules / schema → **no Gate**; all are pure presentation, so
each PR must keep widget + golden tests green (goldens are macOS-only, CI-excluded
— regen locally).

## Drift snapshot (2026-06-06, post-#314)

Counts = lines with a **bare** literal still present (tokens stripped before counting,
so a partially-tokenised `EdgeInsets.symmetric(horizontal: space16, vertical: 14)`
still counts via the `14`). Columns: `edgeLit` = EdgeInsets line w/ a bare int ·
`sbLit` = `SizedBox((height|width): N` · `radLit` = `BorderRadius.circular(N` ·
`rawTS` = `TextStyle(`. Whole-`lib` headline (D1): 160 literal SizedBox · 141
`BorderRadius.circular` · 89 raw `TextStyle` · 82/172 files use `context.*`.

| area | files | tok% | edgeLit | sbLit | radLit | rawTS | pass |
|---|---|---|---|---|---|---|---|
| home | 10 | 70% | 10 | 23 | 4 | 0 | ✅ #310 |
| ledger | 25 | 56% | 36 | 33 | 39 | 18 | ✅ #312 |
| groups | 27 | 66% | 17 | 56 | 28 | 27 | ✅ #314 |
| events | 17 | 64% | 8 | 17 | 25 | 25 | ✅ #315 |
| settings | 10 | 80% | 10 | 19 | 17 | 5 | ✅ #316 |
| auth | 14 | 57% | 0 | 0 | 3 | 0 | ✅ #316 |
| activity | 5 | 20% | 6 | 4 | 1 | 0 | ✅ #316 |
| shared | 14 | 71% | 2 | 3 | 1 | 7 | clean |
| core | 43 | 9% | 5 | 5 | 23 | 7 | n/a |

**All UI features ✅ (home/ledger/groups/events/settings/activity/auth)** = no-op spacing/radius
pass shipped; the residual literals above are the deliberately-deferred **off-scale spacing +
legacy/off-scale radii** (8/12/16/…) — snapping those to canonical is a *visual* change for a
separate golden-reviewed pass. (`edgeLit` is a rough indicator — its baseline was inconsistently
measured; `sbLit`/`radLit` are exact direct-greps.)
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

1. **home** — pilot. ✅ **DONE (#310).** Proved the no-op-swap template + Phase-1 tokens.
2. **ledger** — money screens. ✅ **DONE (#312).** Spacing + canonical radii; off-scale/legacy deferred.
3. **groups** — highest SizedBox. ✅ **DONE (#314).** Spacing + canonical radii; 27 raw `TextStyle` deferred.
4. **events** — high raw TextStyle (25) + radius (27). ✅ **DONE (#315).** Spacing + canonical radii; 25 raw `TextStyle` + off-scale/legacy radii deferred.
5. **settings + activity + auth** — smaller; batched as one cleanup PR. ✅ **DONE (#316).** Spacing + canonical radii; off-scale/legacy + raw `TextStyle` deferred.

**Phase-2 no-op sweeps COMPLETE across all UI features.** Remaining design-unification work = the two cross-cutting *visual* passes (need golden review, not no-ops): **`TextStyle → AppTypography`** (ledger 18 · groups 27 · events 25 · settings 5 raw `TextStyle` left) and the **off-scale-spacing / legacy-radius reconcile**.

## Definition of done (whole effort)
- Adherence greps (DESIGN.md §13) trend to near-zero literals in `features/`.
- DESIGN.md §13 drift table emptied (or remaining items explicitly deferred to a milestone).
- No new `Color(0x…)` outside tokens; `flutter analyze` clean; coverage ≥ 80%.
