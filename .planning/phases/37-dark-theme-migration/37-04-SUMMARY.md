---
phase: 37-dark-theme-migration
plan: 04
subsystem: token-promotions-cleanup
tags: [theme, dark-mode, tokens, cleanup, wave-4]
requires:
  - Wave 1 foundation (AppTheme.darkTheme + AppColorTokens.dark — 37-01)
  - Wave 2 shared-widget migration (37-02)
  - Wave 3 feature migrations (37-03a/03b/03c/03d — all handoff literals pre-annotated)
provides:
  - lib/core/theme/tokens/group_avatar_colors.dart (AppGroupAvatarColors.lightSlots/.darkSlots, 5 each)
  - lib/core/theme/tokens/gradient_tokens.dart (AppGradientPair + AppGradients.terracotta/.olive/.teal/.gray)
  - AppColorTokens gains brightness field + groupAvatarSlot(String) method
  - context.gradient(AppGradientPair) extension on BuildContext
  - EventTypeConfig refactored to EventTypeColorRole + resolveColor(AppColorTokens)
  - ExpenseCategory.colorValue getter replaced with resolveColor(AppColorTokens)
  - test/unit/token_promotions_test.dart (8 tests, shape assertions)
affects:
  - Plan 05 (Wave 5 — CI guard + goldens) can now enforce zero-literal policy without false positives
  - Every Wave 3 handoff annotation (gradients, avatar slots, category roles) resolved
  - event_model_test.dart EventTypeConfig color tests rewritten around resolveColor()
  - group_card.dart _accentColors static list deleted (replaced by token accessor)
tech-stack:
  added: []
  patterns:
    - "Role-based color resolution — enum + resolveColor(AppColorTokens) for model-owned palettes"
    - "AppGradientPair with identical begin/end across brightness — only colors differ"
    - "Deterministic FNV-like _stableGroupHash — groupId → slot index, stable across Dart versions"
    - "AppColorTokens.brightness field powers theme-aware method dispatch from within the token instance"
    - "context.gradient(AppGradientPair) — mirrors context.colors ergonomics"
key-files:
  created:
    - lib/core/theme/tokens/group_avatar_colors.dart
    - lib/core/theme/tokens/gradient_tokens.dart
    - test/unit/token_promotions_test.dart
  modified:
    - lib/core/theme/tokens/color_tokens.dart
    - lib/core/theme/tokens/domain_aliases.dart
    - lib/features/groups/widgets/group_card.dart
    - lib/features/onboarding/screens/onboarding_screen.dart
    - lib/features/ledger/screens/ledger_screen.dart
    - lib/features/activity/screens/activity_feed_screen.dart
    - lib/features/events/models/event_type_config.dart
    - lib/features/events/widgets/event_type_badge.dart
    - lib/features/events/screens/event_type_picker_screen.dart
    - lib/features/ledger/models/expense_category_model.dart
    - lib/core/router/app_router.dart (comment-only: single-line justification)
    - test/unit/event_model_test.dart
    - test/unit/design_tokens_test.dart
decisions:
  - "Added `Brightness brightness` field to AppColorTokens instead of creating a
    separate AppAvatarSlotExtension on BuildContext. This keeps the call convention
    `context.colors.groupAvatarSlot(group.id)` consistent with every other
    `context.colors.*` read (W6 checker feedback)."
  - "Used deterministic FNV-like hash (`h = (h * 31 + c) & 0xffffffff`) rather
    than `String.hashCode` — the latter is not guaranteed stable across Dart
    versions, and a group's avatar color flipping on app upgrade would be a
    silent regression (RESEARCH R10)."
  - "Refactored EventTypeConfig from `Color color` field to `EventTypeColorRole`
    enum + `resolveColor(AppColorTokens)` method (Approach A per plan). 2 call
    sites updated (event_type_badge.dart + event_type_picker_screen.dart).
    event_model_test.dart updated to assert resolveColor output matches the
    intended AppColorTokens.light field, plus a new test that proves colors
    flip between light and dark palettes."
  - "ExpenseCategory renamed `colorValue` getter → `resolveColor(AppColorTokens)`
    method. The persisted hex string remains the primary source; fallback now
    comes from `tokens.success` (theme-aware) instead of a hardcoded emerald.
    Zero existing callers — no call-site migration required."
  - "onboarding_screen.dart _OnboardingPageData model refactored: `gradientColors:
    List<Color>` field → `gradient: AppGradientPair` field. _buildPage gains
    BuildContext parameter and reads `context.gradient(data.gradient)`. All
    three const page data entries remain `const` because AppGradientPair
    and its nested LinearGradients are const-constructable."
  - "Collapsed the splash background justification in app_router.dart from a
    4-line block comment (Plan 37-02's wording) to a single preceding
    `// design-token-justified:` line. Plan 05's CI regex only checks the
    immediately-preceding line."
  - "Added brightness-aware handling in AppColorTokens.lerp: discrete snap at
    t >= 0.5 (brightness cannot be interpolated). Material's ThemeExtension
    lerp protocol applies across theme transitions, though D-09 specifies
    no animated theme switch so this is defensive."
metrics:
  tasks_completed: 4
  tasks_planned: 4
  files_created: 3
  files_modified: 13
  commits: 5
  duration_minutes: ~25
  literals_promoted: 16
  tests_added: 8
  tests_passing: 1065 (3 skipped, 0 failed — same as Waves 3 baseline)
completed: 2026-04-18
---

# Phase 37 Plan 04: Token Promotions (Wave 4) Summary

Promoted every Wave 3 handoff literal to named tokens per D-15. Two new
token files (`group_avatar_colors.dart`, `gradient_tokens.dart`) plus
role-based color resolution on category models. After this plan, the ONLY
remaining `Color(0xFF...)` literals in `lib/` outside `tokens/` carry a
`// design-token-justified:` comment on the preceding line — Plan 05's CI
guard can now enforce zero-unjustified literals without false positives.

## What Got Built

### New token files

**`lib/core/theme/tokens/group_avatar_colors.dart`** — 5 `lightSlots` and 5
`darkSlots`, each with an inline `// design-token-justified:` comment
naming the slot number and semantic role. Dark slots are lightened
variants (teal 400, terracotta lightened, emerald 400, amber 400, warm
umber lightened) chosen for WCAG AA on Slate 800.

**`lib/core/theme/tokens/gradient_tokens.dart`** — `AppGradientPair` value
class + `AppGradients.terracotta/.olive/.teal/.gray`, each a const
`AppGradientPair(light:, dark:)`. Invariant: every pair shares `begin`
and `end` across brightnesses — only `colors` differ. Asserted by
`token_promotions_test.dart`.

### Accessors

**`AppColorTokens.groupAvatarSlot(String groupId)`** — instance method on
the existing ThemeExtension. Uses a deterministic FNV-like hash (not
`String.hashCode`). Dispatches on the new `brightness` field so
`context.colors.groupAvatarSlot(group.id)` resolves to the correct slot
list automatically.

**`context.gradient(AppGradientPair)`** — extension method on
`BuildContext` via `domain_aliases.dart`. Returns `.light` or `.dark` per
`Theme.of(context).brightness`. Same ergonomics as `context.colors.*`.

### Migrated call sites

| File | Before | After |
| --- | --- | --- |
| `group_card.dart` | `static const List<Color> _accentColors = [5 literals]` + `_accentColor(String)` | `context.colors.groupAvatarSlot(group.id)` inline |
| `onboarding_screen.dart` | `_OnboardingPageData.gradientColors: List<Color>` on 3 entries | `.gradient: AppGradientPair` on 3 entries; `_buildPage(context, ...)` resolves via `context.gradient(data.gradient)` |
| `ledger_screen.dart:378` | `LinearGradient(colors: [Color(0xFFCC6B49), Color(0xFFE0896A)])` | `context.gradient(AppGradients.terracotta)` |
| `activity_feed_screen.dart:150` | `LinearGradient(colors: [Color(0xFFA67C5B), Color(0xFFC29A7A)])` | `context.gradient(AppGradients.gray)` |
| `event_type_config.dart` | `Color color` field + 5 hex literals | `EventTypeColorRole` enum + `resolveColor(AppColorTokens)` method |
| `event_type_badge.dart` | `typeConfig.color` (3 reads) | `typeConfig.resolveColor(context.colors)` resolved once, reused |
| `event_type_picker_screen.dart` | `config.color.withValues(...)` + `config.color` | `Builder` wraps the icon container; `config.resolveColor(context.colors)` resolved once |
| `expense_category_model.dart` | `Color get colorValue` with `Color(0xFF22C55E)` fallback | `Color resolveColor(AppColorTokens tokens)` with `tokens.success` fallback |

### Tests

- `test/unit/token_promotions_test.dart` — **8 tests**, all green.
  Shape assertions for `AppGroupAvatarColors.{lightSlots,darkSlots}`
  length + distinctness, and `AppGradients.{terracotta,olive,teal,gray}`
  shape (LinearGradient with 2 colors, light/dark begin+end identity).
- `test/unit/event_model_test.dart` — **4 tests rewritten** (3 old
  `.color` assertions + 1 new "colors flip between light and dark"
  coverage). All resolve `resolveColor(AppColorTokens.light)` and
  `AppColorTokens.dark` and assert inequality across themes.
- `test/unit/design_tokens_test.dart` — 2 `AppColorTokens` test
  constructors updated with `brightness: Brightness.light` (required
  named param after the field was added).

### Comment collapse

`lib/core/router/app_router.dart:454` had a 4-line multi-line
justification comment above the splash `Color(0xFFF2E8D6)` literal.
Plan 05's CI regex matches only the immediately-preceding line.
Collapsed the block so the `// design-token-justified:` marker now sits
on the prior line directly.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocker] `AppColorTokens` gained required `brightness` field → 2 test constructors broke**

- **Found during:** Task 37-04-02, after `flutter analyze`.
- **Issue:** Adding `required this.brightness` to the `AppColorTokens`
  constructor broke 2 `const AppColorTokens(...)` test instances in
  `test/unit/design_tokens_test.dart` (lerp t=0.0 and t=1.0 tests).
- **Fix:** Added `brightness: Brightness.light` to both constructors.
  Both tests still assert the expected lerp semantics.
- **Commit:** d30f09a (bundled with Task 02).

**2. [Rule 3 — Blocker] Splash justification comment on multi-line block**

- **Found during:** final CI-style justification check.
- **Issue:** `app_router.dart:454` had its `// design-token-justified:`
  marker on the 4th-from-last line before the literal, not the
  immediately-preceding line. The single-line regex used by Plan 05's
  CI script `tool/check_theme_purity.sh` would flag this as a false
  positive.
- **Fix:** Collapsed the comment block so the marker sits directly
  above the literal. Explanatory text remains in the two lines above
  the marker. Zero semantic change, zero behavior change.
- **Commit:** 776e4c2.

### textMuted Triage

None in scope. Wave 3 plans exhausted the textMuted migration surface;
Wave 4 does not introduce new textMuted reads.

### design-token-justified exemptions added

None net-new. The 10 inline justifications inside `group_avatar_colors.dart`
and `gradient_tokens.dart` live in `lib/core/theme/tokens/` — always
exempt from the CI lint per D-16.

## Authentication Gates

None. Wave 4 is a palette/token refactor — no auth, network, or storage
code touched.

## Verification Results

- `flutter analyze` — 0 errors (344 pre-existing info-level lints
  unchanged).
- `flutter test` — **1065 pass, 3 skipped, 0 fail** (up from 1056 by
  the 8 new token_promotions tests + 1 new theme-flip event_model test).
- `flutter test test/unit/token_promotions_test.dart` — 8 pass / 0 fail.
- `flutter test test/unit/event_model_test.dart` — 40 pass / 0 fail.
- `grep -c "groupAvatarSlot(String" lib/core/theme/tokens/color_tokens.dart` → **1**
- `grep -c "context\.colors\.groupAvatarSlot" lib/features/groups/widgets/group_card.dart` → **2** (declaration + runtime call)
- `grep -c "Color(0xFF" lib/features/groups/widgets/group_card.dart` → **0**
- `grep -c "Color(0xFFCC6B49)" lib/features/onboarding/screens/onboarding_screen.dart lib/features/ledger/screens/ledger_screen.dart | awk -F: '{sum+=$2} END {print sum}'` → **0**
- `grep -c "Color(0xFFA67C5B)" lib/features/activity/screens/activity_feed_screen.dart` → **0**
- `grep "AppGradients\." lib/features/onboarding/ lib/features/ledger/screens/ledger_screen.dart lib/features/activity/screens/activity_feed_screen.dart | wc -l` → **5+**
- `grep -rn "Color(0xFF" lib/features/events/models/event_type_config.dart lib/features/ledger/models/expense_category_model.dart | grep -v "// design-token-justified:" | wc -l` → **0**
- `grep -c "resolveColor\|ColorRole\|tokens\." lib/features/events/models/event_type_config.dart` → **15**
- `grep -c "resolveColor\|tokens\." lib/features/ledger/models/expense_category_model.dart` → **4**

### Final lib/ scan (the check Plan 05 will enforce)

Running the Plan 05 CI-style justification check:

```bash
grep -rn "Color(0xFF" lib/ --include='*.dart' \
  | grep -v "lib/core/theme/tokens/" \
  | while read -r match; do <check prior line for justified comment>; done
```

Result: **zero unjustified literals remain.** The only `Color(0xFF...)`
usages outside `lib/core/theme/tokens/` sit inside the two `app_theme.dart`
warm-input cases (lines 116, 123) and the splash background (`app_router.dart:454`)
— all three with prior-line `// design-token-justified:` comments.

## Commits

| Hash | Scope | Message |
| --- | --- | --- |
| 95a697f | test | `test(37-04): add token_promotions_test stub (RED)` |
| d30f09a | feat | `feat(37-04): promote group avatar palette to AppGroupAvatarColors tokens` |
| f63eef8 | feat | `feat(37-04): promote hero gradients to AppGradients tokens` |
| 55bbfaa | refactor | `refactor(37-04): source category colors from tokens via resolver funcs` |
| 776e4c2 | chore | `chore(37-04): move splash justification to prior-line so Plan 05 CI matches` |

## Known Stubs

None. Every token promoted has at least one concrete call site. The
test file `token_promotions_test.dart` is NOT a stub — it covers the
exact shape contract (5 slots, 2-color gradients, cross-brightness
begin/end identity) that downstream phases will rely on.

## Threat Flags

None. Plan 04 is purely a palette/token refactor — no network endpoints,
no auth paths, no new storage keys, no schema changes at trust boundaries.
T-37-04-01 (stable avatar hash): mitigated — unit test asserts
`AppGroupAvatarColors.lightSlots.length == 5` and the hash is a
deterministic FNV-like fold over `codeUnits`, not Dart's unstable
`String.hashCode`. T-37-04-02 (avatar accessor as extension): kept as
`accept` — it's a pure UI accessor with no data exposure.

## Self-Check: PASSED

- Files created exist on disk:
  - `lib/core/theme/tokens/group_avatar_colors.dart` FOUND
  - `lib/core/theme/tokens/gradient_tokens.dart` FOUND
  - `test/unit/token_promotions_test.dart` FOUND
- Commits exist in `git log`:
  - 95a697f FOUND
  - d30f09a FOUND
  - f63eef8 FOUND
  - 55bbfaa FOUND
  - 776e4c2 FOUND
- `flutter test` final status: "All tests passed!" (1065 tests, 3 skip) FOUND
- Zero unjustified `Color(0xFF...)` literals outside `tokens/` FOUND
- Final-metadata commit (SUMMARY + STATE + ROADMAP) is the orchestrator's
  responsibility.
