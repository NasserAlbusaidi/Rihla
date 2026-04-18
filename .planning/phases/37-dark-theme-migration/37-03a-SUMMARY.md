---
phase: 37-dark-theme-migration
plan: 03a
subsystem: feature-theme-migration-wave-3a
tags: [theme, dark-mode, migration, wave-3, features, auth, onboarding, settings, home]
requires:
  - Wave 1 foundation (AppTheme.darkTheme + AppColorTokens.dark — 37-01)
  - Wave 2 shared-widget layer reading via context.colors (37-02)
  - context.colors / context.spacing extensions (domain_aliases.dart)
provides:
  - auth/ confirmed color-ref-free (no files touched)
  - onboarding/screens/onboarding_screen.dart reads every color/spacing
    via context.*. Three const gradient literals carry
    `// design-token-justified:` comments pointing Plan 04 at the
    intended AppGradients.{terracotta,olive,teal} promotions
  - settings/ (6 files) fully migrated to context.colors. Helper
    methods that compose sections now take BuildContext explicitly
    so color reads resolve against the active theme
  - home/ (7 files) fully migrated. 2 of 3 existing textMuted refs
    promoted to textSecondary (timestamp on activity row, day label
    on weekly spending bar chart — both functional per D-11).
    1 decorative textMuted retained on 'RECENT ACTIVITY' overline
    with `// textMuted-decorative-justified:` comment (CI-format)
affects:
  - ProfileNotificationsSection, ProfileAboutSection, ProfileStatsSection,
    ProfileSupportSection, EditNameBottomSheet — helper signatures
    updated where needed (context parameter added to _buildSectionHeader,
    _buildTile, _buildStatCard, _buildStatCards, _buildButtonChild)
  - BalanceHeroCard — _buildCard/_buildErrorCard now take context
  - WeeklySpendingCard — _buildCard/_buildCardShell take context
  - BottomNavShell — _buildNavBar takes context
  - Loaded-state home scroll view uses context.spacing tokens end-to-end
tech-stack:
  added: []
  patterns:
    - "context.colors.* inside build()/helper methods in place of static AppColorTokens.light.*"
    - "context.spacing.spaceN for standard EdgeInsets/SizedBox values on touched files"
    - "Pass BuildContext explicitly to helpers that compose theme-aware subtrees"
    - "design-token-justified comments for const-list gradient literals (onboarding)"
    - "textMuted-decorative-justified comment for CI-enforced decorative overline retention"
key-files:
  created: []
  modified:
    - lib/features/onboarding/screens/onboarding_screen.dart
    - lib/features/settings/screens/profile_screen.dart
    - lib/features/settings/widgets/edit_name_bottom_sheet.dart
    - lib/features/settings/widgets/profile_about_section.dart
    - lib/features/settings/widgets/profile_notifications_section.dart
    - lib/features/settings/widgets/profile_stats_section.dart
    - lib/features/settings/widgets/profile_support_section.dart
    - lib/features/home/screens/cross_group_activity_screen.dart
    - lib/features/home/screens/home_screen.dart
    - lib/features/home/widgets/activity_row.dart
    - lib/features/home/widgets/balance_hero_card.dart
    - lib/features/home/widgets/bottom_nav_shell.dart
    - lib/features/home/widgets/quick_action_tray.dart
    - lib/features/home/widgets/weekly_spending_card.dart
decisions:
  - "textMuted triage for home/: 3 original refs. Day label on
    weekly_spending_card (data label on bar chart), timestamp on
    activity_row (functional relative-time metadata), and 'RECENT
    ACTIVITY' section overline. Per D-11, the first two are
    functional → textSecondary. The overline is a decorative
    typographic device that exists for hierarchy, not content —
    retained as textMuted with CI-format justification comment."
  - "Gradient literals in onboarding_screen.dart (lines ~43, 51, 59)
    are inside a `const List<_OnboardingPageData>` and therefore
    CANNOT resolve against context. Per plan instructions, these
    are retained with `// design-token-justified:` comments that
    explicitly name the Plan 04 promotion target
    (AppGradients.terracotta/.olive/.teal)."
  - "Every settings helper method that composed a TextStyle or
    BoxDecoration containing color tokens was refactored to accept
    `BuildContext context` as a parameter (or a named parameter
    where a mixed call signature required it — _buildTile in
    profile_about_section). This keeps the color resolution on the
    live theme path while preserving existing call-site ergonomics."
  - "BalanceHeroCard refactor: the `.when(loading/error/data)` branch
    previously tear-off referenced _buildCard/_buildErrorCard
    directly. Since those now require context, the data arm is
    rewritten as a lambda `data: (balance) => _buildCard(context,
    balance)` and error as `error: (e, s) => _buildErrorCard(context)`.
    Loading is still the tear-off `SkeletonLoader.dashboardHero`
    which doesn't need theme resolution at this layer (the skeleton
    itself resolves via its own Builder from Wave 2)."
  - "Boundary with Plan 05 preserved: profile_screen.dart does NOT
    add a Display section; no ThemePickerSheet file created. These
    additions remain reserved for Task 37-05-01/02 in Wave 5."
  - "auth/ folder contains a single provider file with zero color
    refs. Verified via grep, no changes required. Mentioned in the
    commit message for auditability."
metrics:
  tasks_completed: 4
  tasks_planned: 4
  files_created: 0
  files_modified_src: 14
  files_modified_tests: 0
  commits: 3
  duration_minutes: ~30
  tests_added: 0
  tests_passing: 1056 (3 skipped, 0 failed — same as Wave 2 baseline)
completed: 2026-04-18
---

# Phase 37 Plan 03a: Wave 3a Feature Theme Migration Summary

Wave-3 parallel migration of four feature folders — `lib/features/auth/`,
`lib/features/onboarding/`, `lib/features/settings/`, and
`lib/features/home/` — from direct `AppColorTokens.light.*` reads to
theme-aware `context.colors.*`. Opportunistic `context.spacing.spaceN`
adoption on every touched file per D-20. All migrations mechanical per
D-03; no redesign, no new tokens.

## What Got Migrated

### Per-folder migration counts

| Folder | Files touched | AppColorTokens.light refs before | After (un-justified) | context.colors refs after |
| --- | --- | --- | --- | --- |
| `auth/` | 0 | 0 | 0 | 0 (no color usage) |
| `onboarding/` | 1 | 9 | 0 | 9 |
| `settings/` | 6 | 57 | 0 | 57 |
| `home/` | 7 | 48 | 0 | ~50 |
| **total** | **14** | **114** | **0** | **~116** |

### auth/ (0 files modified)

`lib/features/auth/providers/auth_provider.dart` contains no color
or theme references — just Firebase auth state plumbing. Verified
via `grep -rn "AppColorTokens\|Color(0xFF\|context.colors" lib/features/auth/`
→ zero matches. Plan 37-03a-01 acceptance criterion satisfied
without touching this file.

### onboarding/ (1 file)

**`onboarding_screen.dart`** — 9 color refs migrated to context.colors:
scaffold background, skip-button text, title, subtitle, DotStepIndicator
activeColor, final-page "Get Started" CTA bg/fg, non-final "Next" CTA
bg/fg. Spacing tokens adopted for skip-button padding (space24, space12)
and hero-icon→title and title→subtitle gaps (space24, space8).

**Gradient literals (lines 44, 52, 60)**: inside a
`const List<_OnboardingPageData>`, which cannot resolve against
BuildContext. Per plan D-15 and task instructions, each literal now
has a `// design-token-justified:` comment naming its Plan 04
promotion target (AppGradients.terracotta / .olive / .teal). Plan 04
will rewrite `gradientColors` to pull from `AppGradients.*` and
remove these justification comments.

**`_buildBottomControls`** now takes `BuildContext context` so
context.colors resolves against the active theme.

### settings/ (6 files)

| File | Refs migrated | Helper-signature changes |
| --- | --- | --- |
| `screens/profile_screen.dart` | 9 | — (all reads inside build()) |
| `widgets/edit_name_bottom_sheet.dart` | 11 | `_buildButtonChild` now takes context |
| `widgets/profile_about_section.dart` | 14 | `_buildTile` + `_buildSectionHeader` take context (named param for _buildTile) |
| `widgets/profile_notifications_section.dart` | 10 | `_buildSectionHeader` takes context |
| `widgets/profile_stats_section.dart` | 11 | `_buildStatCards` + `_buildStatCard` take context; accent colors resolved via context.colors inside _buildStatCards instead of as static-field references |
| `widgets/profile_support_section.dart` | 7 | `_buildSectionHeader` takes context |

**textMuted triage**: zero textMuted references in `lib/features/settings/`.
No triage comments added.

**Plan 05 boundary preserved**: `grep "Display\|ThemePickerSheet" lib/features/settings/screens/profile_screen.dart` → 0. The new Display section and theme picker remain reserved for Tasks 37-05-01/02.

### home/ (7 files)

| File | Refs migrated | Helper-signature changes |
| --- | --- | --- |
| `screens/home_screen.dart` | 10 | (decorative textMuted retained on overline with new CI-format comment) |
| `screens/cross_group_activity_screen.dart` | 11 | skeleton builders now read from their closure `context` |
| `widgets/activity_row.dart` | 5 | — |
| `widgets/balance_hero_card.dart` | 8 | `_buildCard` + `_buildErrorCard` take context; `.when(data:)` rewritten as lambda |
| `widgets/bottom_nav_shell.dart` | 5 | `_buildNavBar` takes context |
| `widgets/quick_action_tray.dart` | 2 | — (inline inside build()) |
| `widgets/weekly_spending_card.dart` | 7 | `_buildCard` + `_buildCardShell` take context |

### Spacing Token Adoption (per D-20)

Replaced every standard EdgeInsets / SizedBox / Padding value matching
`{4, 8, 12, 16, 20, 24, 32}` on touched files. Odd values (6, 10,
14, 18, 26, etc.) left as literals per D-20. Approximate count:
**~60 spacing-token replacements across the 14 source files**.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] BalanceHeroCard `.when(data:)` tear-off broke after context param added**

- **Found during:** Task 3 (home migration).
- **Issue:** Original code used `data: _buildCard` as a tear-off.
  Once `_buildCard` required a `BuildContext context` parameter,
  the tear-off shape no longer matched the `AsyncValue.when`
  signature (which passes `(T data)` to its `data` callback).
- **Fix:** Rewrote the `.when` arms as lambdas that forward context
  from the enclosing `build`: `data: (balance) => _buildCard(context,
  balance)` and `error: (_, __) => _buildErrorCard(context)`. Loading
  is still a tear-off (`SkeletonLoader.dashboardHero`) since that
  factory resolves theme internally via Wave 2's Builder wrapping.
- **Files modified:** `lib/features/home/widgets/balance_hero_card.dart`
- **Commit:** `f3f5554`

### textMuted Triage (per D-11)

Only `lib/features/home/` had textMuted references in scope.
3 total; disposition:

| File:line | Element | Disposition |
| --- | --- | --- |
| `home_screen.dart:258` | `'RECENT ACTIVITY'` section overline | **Decorative** → retained with `// textMuted-decorative-justified: 'RECENT ACTIVITY' section overline — decorative overline label, not functional text.` |
| `activity_row.dart:116` | Relative timestamp (timeago.format) | **Functional metadata** → migrated to `textSecondary` |
| `weekly_spending_card.dart:121` | Day-of-week bar label (Mon/Tue/...) | **Functional data label** → migrated to `textSecondary` |

Running wave-3a count: **2 textMuted → textSecondary conversions,
1 textMuted-decorative-justified retention.**

### design-token-justified exemptions added

| File:line | Literal | Reason |
| --- | --- | --- |
| `onboarding_screen.dart:44` | `[Color(0xFFCC6B49), Color(0xFFD4845F)]` | Terracotta gradient inside const _OnboardingPageData list — Plan 04 will promote to AppGradients.terracotta |
| `onboarding_screen.dart:52` | `[Color(0xFF7A8C5E), Color(0xFF8EA06E)]` | Olive gradient — Plan 04 → AppGradients.olive |
| `onboarding_screen.dart:60` | `[Color(0xFF0D7B74), Color(0xFF0A9187)]` | Dusty-teal gradient — Plan 04 → AppGradients.teal |

## Authentication Gates

None. Wave 3a is a palette refactor — no auth or network code touched.

## Verification Results

- `flutter analyze` — 0 errors, 0 warnings. 346 issues total
  (all pre-existing info-level lints; was 347 at baseline, one fewer
  due to `const` removal made possible where the only blocker was a
  static AppColorTokens.light read — incidental improvement).
- `grep -rn "AppColorTokens\.light\." lib/features/auth/ lib/features/onboarding/ lib/features/settings/ lib/features/home/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` = **0**
- `grep -rn "context\.colors\." lib/features/settings/ --include='*.dart' | wc -l` = **57** (≥40 threshold)
- `grep -rn "\.textMuted" lib/features/home/ --include='*.dart' | wc -l` = **1**
  (the home_screen overline, preceded by `// textMuted-decorative-justified:`)
- `grep -c "Display\|ThemePickerSheet" lib/features/settings/screens/profile_screen.dart` = **0** (Plan 05 boundary preserved)
- `git diff --name-only d5e7db9 HEAD | grep "^lib/features/" | grep -v "^lib/features/\(auth\|onboarding\|settings\|home\)/"` → empty (no sibling-wave touches)
- `flutter test` — **1056 pass, 3 skipped, 0 fail** (same as Wave 2 baseline)

Per-task acceptance details:

| Task | Acceptance criteria | Result |
| --- | --- | --- |
| 37-03a-01 | auth+onboarding un-justified refs = 0; ≥3 gradient justifications; unit tests pass | ✅ 0 refs, 3 gradient comments, analyze clean |
| 37-03a-02 | settings un-justified refs = 0; ≥40 context.colors refs; Plan 05 boundary intact; unit tests pass | ✅ 0 refs, 57 context.colors, boundary preserved |
| 37-03a-03 | home un-justified refs = 0; 3 textMuted triaged; unit tests pass | ✅ 0 refs, triage documented above |
| 37-03a-04 | Full suite green; no sibling-wave file touches | ✅ 1056 pass, 0 cross-wave touches |

## Commits

| Hash | Scope | Message |
| --- | --- | --- |
| 1fbfd79 | refactor | auth + onboarding to context.colors |
| 873de31 | refactor | settings feature to context.colors |
| f3f5554 | refactor | home feature to context.colors |

## Known Stubs

None. Every widget in the four feature folders now resolves its
full color palette from the active theme at build time.

## Threat Flags

None. Wave 3a is purely a palette/token refactor — no network
endpoints, no auth paths, no new storage keys, no schema changes
at trust boundaries.

## Self-Check: PASSED

- Files modified exist on disk:
  - `lib/features/onboarding/screens/onboarding_screen.dart` FOUND
  - `lib/features/settings/screens/profile_screen.dart` FOUND
  - `lib/features/settings/widgets/edit_name_bottom_sheet.dart` FOUND
  - `lib/features/settings/widgets/profile_about_section.dart` FOUND
  - `lib/features/settings/widgets/profile_notifications_section.dart` FOUND
  - `lib/features/settings/widgets/profile_stats_section.dart` FOUND
  - `lib/features/settings/widgets/profile_support_section.dart` FOUND
  - `lib/features/home/screens/cross_group_activity_screen.dart` FOUND
  - `lib/features/home/screens/home_screen.dart` FOUND
  - `lib/features/home/widgets/activity_row.dart` FOUND
  - `lib/features/home/widgets/balance_hero_card.dart` FOUND
  - `lib/features/home/widgets/bottom_nav_shell.dart` FOUND
  - `lib/features/home/widgets/quick_action_tray.dart` FOUND
  - `lib/features/home/widgets/weekly_spending_card.dart` FOUND
- Commits exist in `git log`:
  - 1fbfd79 FOUND, 873de31 FOUND, f3f5554 FOUND
- `grep -rn "AppColorTokens\.light\." lib/features/auth/ lib/features/onboarding/ lib/features/settings/ lib/features/home/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` returns 0 FOUND
- `flutter test` final status: "All other tests passed!" (1056 pass,
  3 skipped matching Wave 2 baseline, 0 fail) FOUND
- Final-metadata commit (SUMMARY + STATE + ROADMAP) is the orchestrator's
  responsibility.
