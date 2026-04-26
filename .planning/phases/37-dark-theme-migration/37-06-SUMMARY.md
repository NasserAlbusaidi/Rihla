---
phase: 37-dark-theme-migration
plan: 06
subsystem: shadow-token-end-to-end-coverage
tags: [theme, dark-mode, shadows, gap-closure, wave-6, ci]
gap_closure: true
closes_gaps:
  - "VERIFICATION.md SC5 — dark theme renders end-to-end (elevation/shadow layer)"
requires:
  - Wave 1 theme infrastructure (37-01)
  - Wave 2 shared widget migration (37-02)
  - Wave 5 goldens + CI guard (37-05)
provides:
  - Theme-aware shadow reads across every feature/settings widget
    (32 files / 37 call sites now resolve AppShadowTokens via
    context.shadows instead of the static AppShadowTokens.standard alias)
  - Golden harness resolves shadows via Builder + context.shadows.raised
    so dark baselines capture the dark shadow tint
  - AppShadowTokens.standard alias deleted — theme-independent elevation
    can no longer slip past code review by aliasing `= light`
  - tool/check_theme_purity.sh Check 4 forbidding
    AppShadowTokens.standard.* reads outside lib/core/theme/tokens/
  - 10 regenerated dark golden baselines (visible byte-size delta from
    light → dark shadow tint)
affects:
  - All feature/settings widgets that render elevated surfaces
  - lib/core/theme/app_theme.dart — light ThemeData registers
    AppShadowTokens.light explicitly (was: .standard alias)
  - test/unit/design_tokens_test.dart — 5 AppShadowTokens.standard
    references swapped to .light (functionally identical)
  - test/goldens/goldens/*_dark.png — 10 baselines regenerated
tech-stack:
  added: []
  patterns:
    - "context.shadows.raised / .floating — theme-aware BoxShadow reads"
    - "Builder wrapping structural cards so boxShadow resolves via the
      Builder's theme-scoped BuildContext (defensive even when the outer
      context is already theme-scoped)"
    - "Check 4 no-justification ban — post-alias-deletion, any
      AppShadowTokens.standard.* usage is a regression (no exemption
      window needed)"
key-files:
  modified:
    - lib/features/activity/widgets/activity_entry_card.dart
    - lib/features/activity/widgets/activity_hero_card.dart
    - lib/features/events/screens/event_expense_hero.dart
    - lib/features/events/screens/event_type_picker_screen.dart
    - lib/features/events/widgets/event_danger_section.dart
    - lib/features/events/widgets/event_details_card.dart
    - lib/features/events/widgets/event_info_section.dart
    - lib/features/events/widgets/event_modules_card.dart
    - lib/features/events/widgets/event_participants_card.dart
    - lib/features/gear/widgets/gear_hero_card.dart
    - lib/features/gear/widgets/gear_item_card.dart
    - lib/features/home/screens/cross_group_activity_screen.dart
    - lib/features/home/widgets/balance_hero_card.dart
    - lib/features/home/widgets/weekly_spending_card.dart
    - lib/features/ledger/screens/add_expense_screen.dart
    - lib/features/ledger/widgets/expense_card.dart
    - lib/features/ledger/widgets/expense_success_dialog.dart
    - lib/features/ledger/widgets/ledger_hero_card.dart
    - lib/features/ledger/widgets/settlement_row.dart
    - lib/features/ledger/widgets/settlement_summary_card.dart
    - lib/features/ledger/widgets/settlement_tile.dart
    - lib/features/ledger/widgets/split_scope_selector.dart
    - lib/features/logistics/widgets/logistics_hero_card.dart
    - lib/features/logistics/widgets/sub_group_card.dart
    - lib/features/memories/widgets/memories_hero_card.dart
    - lib/features/settings/widgets/profile_about_section.dart
    - lib/features/settings/widgets/profile_display_section.dart
    - lib/features/settings/widgets/profile_notifications_section.dart
    - lib/features/settings/widgets/profile_stats_section.dart
    - lib/features/settings/widgets/profile_support_section.dart
    - lib/features/vault/screens/vault_screen.dart
    - lib/features/vault/widgets/vault_hero_card.dart
    - lib/core/theme/tokens/shadow_tokens.dart
    - lib/core/theme/app_theme.dart
    - test/goldens/golden_harness.dart
    - test/unit/design_tokens_test.dart
    - tool/check_theme_purity.sh
    - test/goldens/goldens/add_expense_dark.png
    - test/goldens/goldens/gear_dark.png
    - test/goldens/goldens/group_detail_dark.png
    - test/goldens/goldens/group_settle_up_dark.png
    - test/goldens/goldens/home_dark.png
    - test/goldens/goldens/ledger_dark.png
    - test/goldens/goldens/logistics_dark.png
    - test/goldens/goldens/memories_dark.png
    - test/goldens/goldens/onboarding_dark.png
    - test/goldens/goldens/settings_profile_dark.png
decisions:
  - "Took the default 'delete the alias' branch from the plan. Escape-hatch
    grep found 0 pre-hydration readers (no utility files, no non-widget
    screens, no non-harness tests read AppShadowTokens.standard outside
    the 32 feature files + harness + design_tokens_test). Every consumer
    is reachable through the widget tree or is a test helper — the
    contingency branch (keep alias with justification comment) was not
    needed."
  - "Auto-fixed three additional non-feature consumers as Rule 3 blockers
    (deletion would have caused compile errors): (1) lib/core/theme/
    app_theme.dart:181 — light ThemeData now registers
    AppShadowTokens.light explicitly; (2) test/unit/design_tokens_test.dart
    — 5 AppShadowTokens.standard references swapped to .light; (3) the
    `Use [AppShadowTokens.standard]` doc comment in shadow_tokens.dart:6
    rewritten to steer consumers toward context.shadows for widget code
    and .light/.dark for ThemeExtension registration sites."
  - "Wrapped _buildHeroCard and _buildRowsCard in Builder before reading
    context.shadows.raised. The outer context is already theme-scoped
    (it's the StatelessWidget's build context under MaterialApp.theme),
    so the Builder is defensive, not load-bearing — it survives any
    future refactor that might insert a Theme override between the
    harness and the card (e.g., Theme(data: someOtherTheme, child: ...))."
  - "Used Check 4 with no justification window (unlike Check 2 / Check 3's
    5-line comment windows). The alias was eliminated entirely; there is
    no legitimate call-site for AppShadowTokens.standard post-deletion,
    so any occurrence is a pure regression signal."
  - "Regenerated only the 10 dark PNGs (not light). Light baselines were
    byte-identical after regeneration because AppShadowTokens.light on
    the light path matches the prior AppShadowTokens.standard alias
    (which was `= light`). Git confirmed this — the --update-goldens run
    wrote identical bytes for all 10 *_light.png files, so no staged
    changes for the light set."
metrics:
  tasks_completed: 6
  tasks_planned: 6
  files_modified_src: 34
  files_modified_goldens: 10
  commits: 5
  shadow_call_sites_migrated: 37
  files_migrated: 32
  alias_lines_deleted: 1
  ci_checks_added: 1
  dark_goldens_regenerated: 10
  tests_before: 1088
  tests_after: 1088
  tests_skipped: 3
  tests_failed: 0
  duration_minutes: ~6
completed: 2026-04-18
---

# Phase 37 Plan 06: Shadow Token End-to-End Coverage (Wave 6, Gap Closure)

Closes the one remaining gap from Phase 37's verification report
(SC5 — dark theme renders end-to-end). `AppShadowTokens.standard` was
declared as a static alias `= light`, which meant the 32 feature
widgets reading it directly got the light shadow palette regardless of
`ThemeMode`. The golden harness itself used the same alias, so
baselines couldn't detect the regression. This plan mechanically
migrated all 37 call sites to `context.shadows.*`, fixed the harness,
deleted the alias, added CI Check 4, and regenerated the 10 dark
baselines.

## Pre/Post Grep Counts

| Query | Before | After |
| --- | --- | --- |
| `AppShadowTokens.standard.` in `lib/features/` | 37 | **0** |
| `AppShadowTokens.standard` anywhere in `lib/` and `test/` | 12 | **0** |
| `context.shadows.` in `lib/features/` | 12 | **49** |
| Alias line in `shadow_tokens.dart` | 1 (`static final AppShadowTokens standard = light;`) | **0** |
| `Check 4` in `check_theme_purity.sh` | 0 | **2** (label + heading) |

## What Got Built

### Task 1 — Mechanical feature sweep (commit `ae5e7b2`)

- sed-replaced `AppShadowTokens.standard.raised` → `context.shadows.raised`
  and `AppShadowTokens.standard.floating` → `context.shadows.floating`
  across 32 files / 37 call sites.
- Removed the `import '../../../core/theme/tokens/shadow_tokens.dart';`
  line from all 32 files — domain_aliases.dart was already imported in
  every one of them (provides `context.colors` and `context.spacing`
  that these files use).
- 30 of 32 files had a single substitution. 3 files had multiples:
  balance_hero_card.dart (×2), settlement_tile.dart (×2),
  add_expense_screen.dart (×4).
- Ternary shapes (`isSelected ? AppShadowTokens.standard.raised : null`
  in split_scope_selector.dart and `isUrgent ? … : null` in
  settlement_tile.dart) handled by the same substring substitution.

### Task 2 — Golden harness fix (commit `61393fb`)

- Wrapped `_buildHeroCard` and `_buildRowsCard` return values in
  `Builder(builder: (context) => Container(...))` so the `boxShadow`
  property reads `context.shadows.raised` via a theme-scoped context.
- Swapped `_goldenTheme`'s light-path extension registration from
  `AppShadowTokens.standard` to `AppShadowTokens.light`. The runtime
  behavior is identical (`standard` was `= light`), but after Task 3
  the alias no longer exists.

### Task 3 — Delete the alias (commit `c7845c4`)

- Ran the plan's escape-hatch grep. Found 0 matches in the exempt-
  paths-excluded set — no pre-hydration reader, no utility file, no
  non-harness test. Default path (delete) was safe.
- Deleted `static final AppShadowTokens standard = light;` (was line 25).
- Updated the class doc comment: removed the `Use [AppShadowTokens.standard]`
  steer, replaced with guidance to use `context.shadows.*` for widget
  code and `.light` / `.dark` for ThemeExtension registration sites.
- Auto-fixed 3 Rule-3 blocker consumers that would have compile-failed
  after deletion:
  - `lib/core/theme/app_theme.dart:181` (light ThemeData extensions)
  - `test/unit/design_tokens_test.dart` (5 `.standard` references — test
    harness + 4 raised/floating/flat assertions)
  - doc comment in `shadow_tokens.dart:6`

### Task 4 — Check 4 in CI guard (commit `51cd53b`)

- Inserted Check 4 before the final exit block in
  `tool/check_theme_purity.sh`. Greps `lib/` for
  `AppShadowTokens\.standard\.` outside `lib/core/theme/tokens/` and
  fails on any match.
- No justification-window logic (unlike Checks 2 and 3) because the
  alias is eliminated — any occurrence is a pure regression signal.
- Executable bit preserved.
- Negative test verified: injected `var __violation = AppShadowTokens.standard.raised;`
  into balance_hero_card.dart, confirmed exit code 1 with `::error::`
  annotation, then reverted.

### Task 5 — Regenerate dark golden baselines (commit `0b7f5d6`)

- Ran `flutter test test/goldens/ --update-goldens`. 10 tests passed,
  all 20 baselines refreshed.
- Only the 10 `*_dark.png` files showed byte diff. Sizes grew
  uniformly by ~300-700 bytes — consistent with the light shadow tint
  (`Color(0xFF111827)` at 4% alpha) being replaced by the dark tint
  (`Color(0xFF000000)` at 35% alpha), which PNG compresses into more
  bytes because the pixels are less uniform.
- Re-ran without `--update-goldens` — 10/10 pass, 0 fail.

| PNG | Before (bytes) | After (bytes) | Delta |
| --- | --- | --- | --- |
| add_expense_dark | 26238 | 26634 | +396 |
| gear_dark | 23719 | 24310 | +591 |
| group_detail_dark | 26698 | 27061 | +363 |
| group_settle_up_dark | 22840 | 23523 | +683 |
| home_dark | 23235 | 23921 | +686 |
| ledger_dark | 23824 | 24393 | +569 |
| logistics_dark | 22365 | 23052 | +687 |
| memories_dark | 22738 | 23415 | +677 |
| onboarding_dark | 20937 | 21610 | +673 |
| settings_profile_dark | 22993 | 23637 | +644 |

### Task 6 — Full suite verification (no commit — verification only)

- `bash tool/check_theme_purity.sh` → `Theme purity check PASS` (all 4 checks green)
- `flutter analyze` → 348 issues / **0 errors** (baseline match with Plan 05)
- `flutter test` → **1088 passed / 3 skipped / 0 failed** (baseline match)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocker] 3 additional non-feature consumers of `.standard` would compile-fail after deletion**

- **Found during:** Task 3's escape-hatch grep revealed matches in
  `lib/core/theme/app_theme.dart`, `test/unit/design_tokens_test.dart`,
  and `lib/core/theme/tokens/shadow_tokens.dart` itself (doc comment).
- **Issue:** Plan's file list for Task 1 was scoped to
  `lib/features/` and `lib/features/settings/`. It correctly
  excluded `lib/core/theme/tokens/` (source of truth — retains the
  `.light`/`.dark` statics). But it did not include app_theme.dart's
  light ThemeExtensions registration nor design_tokens_test.dart's
  test assertions, both of which read `AppShadowTokens.standard`
  directly. The plan assumed only the 32 feature files used it.
- **Fix:** Swapped all 6 `AppShadowTokens.standard` references in those
  two non-feature files to `AppShadowTokens.light`. Behavior is
  identical because the alias was literally `= light`. The doc comment
  in shadow_tokens.dart:6 was updated to match the new API surface.
- **Files modified:** lib/core/theme/app_theme.dart (1 ref),
  test/unit/design_tokens_test.dart (5 refs),
  lib/core/theme/tokens/shadow_tokens.dart (doc comment).
- **Commit:** `c7845c4`, bundled with the alias deletion.

No Rule 1, Rule 2, or Rule 4 deviations. No architectural changes.
No auth gates.

## Authentication Gates

None. Plan 37-06 is a mechanical refactor + CI extension + golden
regeneration — no auth, network, or storage-write code touched.

## Verification Results

- `bash tool/check_theme_purity.sh` — **PASS** (4 checks, 0 violations)
- `flutter analyze` — 0 errors, 348 issues (info-only, baseline-matching)
- `flutter test` — **1088 pass / 3 skip / 0 fail** (1:20 runtime)
- `flutter test test/goldens/` — 10 pass (no `--update-goldens` flag)
- VERIFICATION.md gap[0].missing deliverables:
  - [x] #1: 0 `AppShadowTokens.standard.` reads in `lib/features/`
  - [x] #2: `context.shadows.raised` appears twice in harness (inside Builders)
  - [x] #3: Alias deleted; Check 4 present in CI guard script
  - [x] #4: 10 dark goldens regenerated with non-trivial byte diff

## Commits

| Hash | Scope | Message |
| --- | --- | --- |
| `ae5e7b2` | refactor | migrate 32 feature files from `AppShadowTokens.standard` to `context.shadows` |
| `61393fb` | refactor | resolve harness shadows via Builder + `context.shadows` |
| `c7845c4` | refactor | delete `AppShadowTokens.standard` alias |
| `51cd53b` | chore | add Check 4 to `check_theme_purity.sh` — ban `AppShadowTokens.standard.*` |
| `0b7f5d6` | test | regenerate 10 dark golden baselines with proper shadow tint |

## Known Stubs

None. Every migrated call site has a live theme-aware read; the
deleted alias has no replacement because it was redundant by design.

## Threat Flags

None. Plan 37-06's surface is: 37 mechanical substring replacements,
1 line deletion, a grep-only CI check, and 10 PNG regenerations. No
new network endpoints, auth paths, storage keys, or schema changes.
No trust-boundary crossing.

## Edge Cases Encountered

1. **37 call sites across 32 files (not 1:1)** — balance_hero_card.dart
   (×2), settlement_tile.dart (×2), add_expense_screen.dart (×4)
   contributed the extra 5 hits. Handled by a single sed `g` flag
   global substitution per file.
2. **Ternary expressions** — split_scope_selector.dart and
   settlement_tile.dart used the alias inside `? … : null` ternaries.
   The mechanical substring replacement worked unmodified.
3. **.floating read** — Only settlement_summary_card.dart used
   `.floating` (single call site). The sed script handled both
   `.raised` and `.floating` in one invocation.
4. **Non-feature consumers** — app_theme.dart and design_tokens_test.dart
   were missed from the plan's file list but caught by the escape-hatch
   grep before deletion. Rule 3 blocker fix applied inline.

## Gap Closure Status

**VERIFICATION.md gap[0] (SC5 — dark theme renders end-to-end) is closed.**
Ready for re-verification by `/gsd-verify-phase 37`.

## Self-Check: PASSED

- Files modified exist on disk:
  - 32 feature/settings files — verified via `git diff --name-only`
  - `lib/core/theme/app_theme.dart` FOUND
  - `lib/core/theme/tokens/shadow_tokens.dart` FOUND
  - `test/goldens/golden_harness.dart` FOUND
  - `test/unit/design_tokens_test.dart` FOUND
  - `tool/check_theme_purity.sh` FOUND (executable)
  - 10 `test/goldens/goldens/*_dark.png` FOUND
- Commits exist in `git log`:
  - `ae5e7b2` FOUND
  - `61393fb` FOUND
  - `c7845c4` FOUND
  - `51cd53b` FOUND
  - `0b7f5d6` FOUND
- Automated verification:
  - `grep -rn 'AppShadowTokens\.standard\.' lib/features/` → 0 FOUND
  - `grep -rn 'AppShadowTokens\.standard' lib/ test/` → 0 FOUND
  - `grep -c 'context\.shadows\.raised' test/goldens/golden_harness.dart` → 2 FOUND
  - `grep -c 'Check 4' tool/check_theme_purity.sh` → 2 FOUND
  - `bash tool/check_theme_purity.sh` → RC=0 with `Theme purity check PASS` FOUND
  - `flutter analyze` → 0 errors FOUND
  - `flutter test` → `All tests passed!` (1088 pass / 3 skip / 0 fail) FOUND
- Pre-existing uncommitted state on main preserved:
  - `.planning/ROADMAP.md`, `.planning/STATE.md`, all `??` untracked
    files listed in the initial `git status` still untouched —
    verified via `git status --short`.
- Final-metadata commit (this SUMMARY + STATE + ROADMAP) is the
  orchestrator's responsibility per the sequential_execution brief.
