---
phase: 37-dark-theme-migration
plan: 02
subsystem: shared-widgets-theme-migration
tags: [theme, dark-mode, migration, shared-widgets, wave-2]
requires:
  - Wave 1 foundation (AppTheme.darkTheme + AppColorTokens.dark landed in 37-01)
  - context.colors / context.spacing / context.shadows extensions (domain_aliases.dart)
provides:
  - Shared-widget layer that reads every color via context.colors and every
    standard spacing value via context.spacing
  - test/features/shared_widgets/shared_widgets_theme_test.dart — 70-case
    smoke harness asserting zero-throw render under both ThemeModes
  - AnimatedCurrencyText._colorForValue now takes AppColorTokens as a param
  - SkeletonLoader.card() wraps its body in a Builder (keeps zero-arg call
    sites stable while resolving shimmer colors against the active theme)
  - _SplashScreen text migrated to context.colors; sand background retained
    with // design-token-justified: comment
  - NetworkErrorWidget gains a private _IconTint enum + _withTint factory so
    named factories (loadingError, offline) stop baking literal colors into
    constructor defaults
affects:
  - Every feature screen in Wave 3 — they now inherit a correctly-themed
    shared-widget layer and can ship the remaining feature migrations without
    visible dark-mode regression from shared primitives
  - Existing widget / integration tests — ~50 test files now pass
    `theme: AppTheme.lightTheme` to their `MaterialApp` / `MaterialApp.router`
    harnesses so ThemeExtensions register during widget tests
tech-stack:
  added: []
  patterns:
    - "context.colors.* over AppColorTokens.light.* — theme-aware reads via BuildContext"
    - "context.spacing.spaceN for standard EdgeInsets/SizedBox values"
    - "design-token-justified comment for intentional hex literals (brand splash)"
    - "Builder wrapping static widget factories that need theme context"
    - "Private enum + factory constructor for expressing 'which theme role' without pinning a Color at build-time"
key-files:
  created:
    - test/features/shared_widgets/shared_widgets_theme_test.dart
  modified:
    - lib/shared/widgets/animated_currency_text.dart
    - lib/shared/widgets/app_tab_bar.dart
    - lib/shared/widgets/dot_step_indicator.dart
    - lib/shared/widgets/empty_state_view.dart
    - lib/shared/widgets/initials_circle.dart
    - lib/shared/widgets/loading_button.dart
    - lib/shared/widgets/module_header.dart
    - lib/shared/widgets/offline_banner.dart
    - lib/shared/widgets/search_filter_bar.dart
    - lib/shared/widgets/skeleton_loader.dart
    - lib/shared/widgets/skeleton_primitives.dart
    - lib/shared/widgets/smart_module_card.dart
    - lib/core/theme/error_widgets.dart
    - lib/core/router/app_router.dart
    - ~50 test files (bulk-updated to pass theme into MaterialApp)
decisions:
  - "textMuted triage: every shared-widget textMuted reference was functional
    (labels, chevrons, subtitles, amounts) — all migrated to textSecondary.
    Zero decorative-justified exceptions in this wave."
  - "Splash background kept as literal `Color(0xFFF2E8D6)` with
    design-token-justified comment — it's a deliberate brand identity choice
    for the pre-hydration frame, not a theme-aware surface."
  - "AnimatedCurrencyText helper refactored to take AppColorTokens as a
    parameter rather than defaulting to `AppColorTokens.light`. Resolved
    from context.colors inside the TweenAnimationBuilder builder (Research
    §Risks R3 pattern)."
  - "SkeletonLoader.card() preserved its zero-arg signature by wrapping the
    body in a `Builder` — avoids breaking two existing callers
    (category_selection_step.dart, split_scope_selector.dart) which Wave 3
    will migrate proper."
  - "NetworkErrorWidget factories (.loadingError, .offline) previously baked
    `AppColorTokens.light.warning` into their constructor defaults. Replaced
    with a private `_IconTint` enum + `_withTint` factory constructor so the
    tint resolves against the live theme in build()."
  - "DotStepIndicator is no longer a const widget — its default activeColor
    now resolves from context.colors.focusBorderWarm. activeColor remains
    optional."
  - "Widget tests relying on bare `MaterialApp()` / `MaterialApp.router(routerConfig:)`
    were failing after the migration because the ThemeExtension wasn't
    registered. Bulk-updated ~50 test files (widget + integration) to pass
    `theme: AppTheme.lightTheme` into their MaterialApp wrapper. Treated as
    Rule 3 (blocker fix) per plan execution deviation rules."
metrics:
  tasks_completed: 3
  tasks_planned: 3
  files_created: 1
  files_modified_src: 14
  files_modified_tests: ~50
  commits: 3
  duration_minutes: ~45
  tests_added: 70
  tests_passing: 1056 (3 skipped, 0 failed across full suite)
completed: 2026-04-18
---

# Phase 37 Plan 02: Shared Widgets Theme Migration Summary

Migrated every color read in `lib/shared/widgets/` (13 files), plus
`lib/core/theme/error_widgets.dart` and the `_SplashScreen` in
`lib/core/router/app_router.dart`, from direct `AppColorTokens.light.*`
reads to theme-aware `context.colors.*`. Opportunistically adopted
`context.spacing.spaceN` tokens on the same files. Added a smoke
harness that exercises every migrated widget in both `ThemeMode.light`
and `ThemeMode.dark` to guard against regressions in downstream waves.

## What Got Built

### Shared-Widget Migration (13 files)

| File | Refs migrated | Notes |
| --- | --- | --- |
| `animated_currency_text.dart` | 1 helper | `_colorForValue` now takes `AppColorTokens` param; caller passes `context.colors` |
| `app_tab_bar.dart` | 3 | unselectedLabelColor textMuted → textSecondary |
| `dot_step_indicator.dart` | 1 | activeColor default now theme-aware; widget no longer const |
| `empty_state_view.dart` | 3 | textMuted → textSecondary (message + icon default) |
| `grain_overlay.dart` | 0 | no refs — verified |
| `initials_circle.dart` | 4 | both default backgroundColor and textColor resolve per theme |
| `loading_button.dart` | 7 | covers LoadingButton, GlassCard, GradientContainer, ShimmerPlaceholder |
| `module_header.dart` | 5 | both light and dark variants; gradient from context.colors.headerGradient |
| `offline_banner.dart` | 3 | warning fill + icon + text all theme-aware |
| `search_filter_bar.dart` | 5 | textMuted chip → textSecondary |
| `skeleton_loader.dart` | 6 | 11 factories rebuilt to use context.spacing; `.card()` wrapped in Builder |
| `skeleton_primitives.dart` | 5 | every primitive reads cardSurface from context |
| `smart_module_card.dart` | 7 | textMuted (chevron + description) → textSecondary |

### error_widgets.dart

- `NetworkErrorWidget` refactored: new private `_IconTint` enum and `_withTint`
  factory constructor. The two named factories (`.loadingError`, `.offline`)
  no longer bake literal colors — they specify a tint role and the color is
  resolved inside `build()` against the active theme.
- `InlineErrorWidget` migrated every color ref to `context.colors`.
- Spacing switched to `context.spacing.space*` and `context.spacing.radiusMedium`.

### app_router.dart

- `_SplashScreen.build` text color → `context.colors.textPrimary`.
- Warm-sand `Color(0xFFF2E8D6)` background kept with
  `// design-token-justified:` comment (brand identity choice for
  pre-hydration splash).
- Route/redirect logic untouched.

### Smoke Test (test/features/shared_widgets/shared_widgets_theme_test.dart)

- 35 widget scenarios × 2 ThemeModes = 70 test cases, all passing
- Wraps everything in `ProviderScope` with `connectivityProvider` forced
  offline so `OfflineBanner` builds its populated branch
- AppTabBar gets `DefaultTabController` + `Builder` harness for its
  TabController dependency
- Asserts `tester.takeException()` is null under each theme

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocker] Existing widget / integration tests lacked theme registration**

- **Found during:** running `flutter test` after Task 1 & Task 2.
- **Issue:** ~50 widget/integration test files built their harnesses around
  bare `MaterialApp()` or `MaterialApp.router(routerConfig: router)` with
  no `theme:` parameter. That meant `Theme.of(context).extension<AppColorTokens>()`
  returned `null` at runtime, and `context.colors.*` threw in any migrated
  shared widget used inside those tests. All flutter_test failures traced
  back to the same root cause — no theme extensions registered.
- **Fix:** Bulk-updated the affected test files to pass
  `theme: AppTheme.lightTheme` into their `MaterialApp` / `MaterialApp.router`
  call. Also added the `import 'package:safar/core/theme/app_theme.dart';`
  import where missing. Handled the duplicate-theme case in ~10 files that
  already parameterised their harness — kept the existing theme arg.
- **Files modified:** ~50 test files across `test/features/`,
  `test/integration/`, `test/helpers/`, `test/shared/`, and `test/unit/`.
- **Rationale:** This is the only pragmatic way to prevent a global test
  regression from a mechanical palette swap. Without it, every test that
  uses a migrated shared widget would fail. This aligns with the plan's
  scope boundary ("do NOT touch files outside lib/shared/widgets/ in this
  task") — touching tests that consume those widgets is a direct blocker
  fix, not feature work.
- **Commits:** Bundled with Task 1 and Task 2 commits to keep the test
  harness fix adjacent to the widget change that needed it.

**2. [Rule 1 — Bug] `const` regression on const constructors that composed AppColorTokens.light**

- **Found during:** Task 1 implementation on `dot_step_indicator.dart`.
- **Issue:** `DotStepIndicator` had `const DotStepIndicator({... activeColor})`
  whose default resolved to `AppColorTokens.light.focusBorderWarm` via the
  constructor initializer list. Removing the `AppColorTokens.light` read
  breaks the `const` eligibility. Plan expected this.
- **Fix:** Dropped the constructor's initializer list; made `activeColor`
  an optional `Color?` field that resolves inside `build()` via
  `context.colors.focusBorderWarm` when null. Constructor stays `const`.
- **Commit:** Included in the Task 1 commit.

**3. [Rule 3 — Blocker] `SkeletonLoader.card()` used from two features**

- **Found during:** Task 1 — needed to migrate the static `card()`
  method but it's called zero-arg from `category_selection_step.dart`
  and `split_scope_selector.dart` (out-of-scope features for Wave 2).
- **Fix:** Wrapped the body in a `Builder`. Keeps the zero-arg signature,
  resolves `context.colors` via the Builder's context at layout time.
  Those two feature-layer call sites will migrate in Wave 3 without any
  API-breaking change.
- **Commit:** Included in the Task 1 commit.

### textMuted Triage (per D-11)

Every `textMuted` reference in the migrated files was functional
(labels, chevrons, subtitles, hint colors, amounts). Per D-11, all
migrated to `textSecondary`. No decorative-justified exemptions
added in this wave.

| File | Before | After |
| --- | --- | --- |
| `app_tab_bar.dart:49` | `unselectedLabelColor: textMuted` | textSecondary |
| `empty_state_view.dart:28, 72` | iconColor default + message color | textSecondary |
| `module_header.dart:69` | subtitle color | textSecondary |
| `search_filter_bar.dart:111` | search icon inactive tint | textSecondary |
| `smart_module_card.dart:140` | description color (empty state) | textSecondary |
| `smart_module_card.dart:155` | chevron color (empty state) | textSecondary |

Running count: **6 textMuted → textSecondary conversions, 0 decorative-justified retentions.**

### Spacing Token Adoption (per D-20)

Replaced every standard EdgeInsets / SizedBox numeric value matching
`{4, 8, 12, 16, 20, 24, 32}` on touched files. Odd values (6, 14, 18,
etc.) left as literals — intentional design choices per D-20.

Approximate count: **~40 spacing token replacements across the 14 source files.**

### design-token-justified exemptions added

| File:line | Literal | Reason |
| --- | --- | --- |
| `app_router.dart:~455` | `Color(0xFFF2E8D6)` | Warm-sand brand splash; pre-hydration frame; not theme-aware on purpose |

No `textMuted-decorative-justified` exemptions added — every textMuted
use in these files was functional.

## Authentication Gates

None. Wave 2 is a palette refactor — no auth or network code touched.

## Verification Results

- `flutter analyze` — 0 errors introduced, 0 new warnings in `lib/`.
  (Pre-existing info-level lints + 11 pre-existing warnings unchanged.)
- `flutter test test/features/shared_widgets/shared_widgets_theme_test.dart`
  — 70 tests pass, 0 fail.
- `flutter test` (full suite) — **1056 pass, 3 skipped, 0 fail.**
- `grep -rn "AppColorTokens\.light\." lib/shared/widgets/ --include='*.dart' | wc -l` = **0**
- `grep -c "AppColorTokens\.light\." lib/core/theme/error_widgets.dart lib/core/router/app_router.dart` = **0, 0**
- `grep -rn "context\.colors\." lib/shared/widgets/ --include='*.dart' | wc -l` = **47** (exceeds ≥40 acceptance threshold)
- `grep -c "Color(0xFF" lib/core/router/app_router.dart` = **1**, preceded by `// design-token-justified:`
- `grep -rn "\.textMuted" lib/shared/widgets/ --include='*.dart' | wc -l` = **0** (all migrated to textSecondary)
- Smoke test covers 13 migrated widget classes + their sub-widgets
  (GlassCard, GradientContainer, ShimmerPlaceholder, Skeleton primitives,
  3 SmartModuleCard variants, 2 SearchFilterBar variants, 2 EmptyStateView
  variants, 2 LoadingButton states, 2 ModuleHeader variants) = 35 scenarios.

## Commits

| Hash | Scope | Message |
| --- | --- | --- |
| 286872a | refactor | migrate shared widgets to context.colors + spacing tokens |
| a3d7b3c | refactor | migrate error_widgets + app_router splash to context.colors |
| d5e7db9 | test | smoke-test all migrated shared widgets in both themes |

## Known Stubs

None. Every widget now resolves its full color palette from the active
theme at build time.

## Threat Flags

None. Wave 2 is purely a palette/token refactor — no network endpoints,
no auth paths, no new storage keys, no schema changes at trust boundaries.

## Self-Check: PASSED

- Files created exist on disk:
  - `test/features/shared_widgets/shared_widgets_theme_test.dart` FOUND
- Commits exist in `git log --all`:
  - 286872a FOUND, a3d7b3c FOUND, d5e7db9 FOUND
- `grep -rn "AppColorTokens\.light\." lib/shared/widgets/` returns 0 FOUND
- `flutter test` final status: "All tests passed!" (1056 tests) FOUND
- Final-metadata commit (SUMMARY + STATE + ROADMAP) is orchestrator's responsibility.
