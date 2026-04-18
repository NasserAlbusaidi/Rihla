---
phase: 37-dark-theme-migration
reviewed: 2026-04-18T12:05:00Z
depth: quick
files_reviewed: 141
files_reviewed_list:
  - .github/workflows/release_android.yml
  - lib/core/models/app_settings_model.dart
  - lib/core/router/app_router.dart
  - lib/core/theme/app_theme.dart
  - lib/core/theme/error_widgets.dart
  - lib/core/theme/tokens/color_tokens.dart
  - lib/core/theme/tokens/domain_aliases.dart
  - lib/core/theme/tokens/gradient_tokens.dart
  - lib/core/theme/tokens/group_avatar_colors.dart
  - lib/core/theme/tokens/shadow_tokens.dart
  - lib/features/activity/screens/activity_feed_screen.dart
  - lib/features/activity/widgets/activity_entry_card.dart
  - lib/features/activity/widgets/activity_hero_card.dart
  - lib/features/events/models/event_type_config.dart
  - lib/features/events/screens/create_event_screen.dart
  - lib/features/events/screens/event_command_center.dart
  - lib/features/events/screens/event_expense_hero.dart
  - lib/features/events/screens/event_settings_screen.dart
  - lib/features/events/screens/event_type_picker_screen.dart
  - lib/features/events/widgets/event_card.dart
  - lib/features/events/widgets/event_danger_section.dart
  - lib/features/events/widgets/event_details_card.dart
  - lib/features/events/widgets/event_info_section.dart
  - lib/features/events/widgets/event_module_list.dart
  - lib/features/events/widgets/event_modules_card.dart
  - lib/features/events/widgets/event_participants_card.dart
  - lib/features/events/widgets/event_type_badge.dart
  - lib/features/gear/screens/gear_screen.dart
  - lib/features/gear/widgets/gear_add_input.dart
  - lib/features/gear/widgets/gear_hero_card.dart
  - lib/features/gear/widgets/gear_item_card.dart
  - lib/features/gear/widgets/gear_list_view.dart
  - lib/features/groups/screens/create_group_screen.dart
  - lib/features/groups/screens/group_activity_screen.dart
  - lib/features/groups/screens/group_detail_screen.dart
  - lib/features/groups/screens/group_settings_screen.dart
  - lib/features/groups/screens/group_settle_up_screen.dart
  - lib/features/groups/screens/join_group_screen.dart
  - lib/features/groups/widgets/all_settled_state.dart
  - lib/features/groups/widgets/group_activity_tile.dart
  - lib/features/groups/widgets/group_balance_hero.dart
  - lib/features/groups/widgets/group_card.dart
  - lib/features/groups/widgets/group_danger_section.dart
  - lib/features/groups/widgets/group_info_section.dart
  - lib/features/groups/widgets/group_member_balance_card.dart
  - lib/features/groups/widgets/group_member_tile.dart
  - lib/features/groups/widgets/group_members_section.dart
  - lib/features/groups/widgets/group_settlement_summary.dart
  - lib/features/groups/widgets/group_settlement_tile.dart
  - lib/features/groups/widgets/group_spending_stats.dart
  - lib/features/groups/widgets/group_stats_grid.dart
  - lib/features/groups/widgets/invite_code_display.dart
  - lib/features/groups/widgets/record_payment_sheet.dart
  - lib/features/groups/widgets/settle_up_history_tab.dart
  - lib/features/groups/widgets/settlement_tab_content.dart
  - lib/features/home/screens/cross_group_activity_screen.dart
  - lib/features/home/screens/home_screen.dart
  - lib/features/home/widgets/activity_row.dart
  - lib/features/home/widgets/balance_hero_card.dart
  - lib/features/home/widgets/bottom_nav_shell.dart
  - lib/features/home/widgets/quick_action_tray.dart
  - lib/features/home/widgets/weekly_spending_card.dart
  - lib/features/ledger/models/expense_category_model.dart
  - lib/features/ledger/screens/add_expense_screen.dart
  - lib/features/ledger/screens/edit_expense_screen.dart
  - lib/features/ledger/screens/ledger_screen.dart
  - lib/features/ledger/screens/settle_up_screen.dart
  - lib/features/ledger/widgets/amount_input_section.dart
  - lib/features/ledger/widgets/category_selection_step.dart
  - lib/features/ledger/widgets/edit_expense_form.dart
  - lib/features/ledger/widgets/edit_expense_payer_selector.dart
  - lib/features/ledger/widgets/edit_expense_scope_section.dart
  - lib/features/ledger/widgets/expense_card.dart
  - lib/features/ledger/widgets/expense_success_dialog.dart
  - lib/features/ledger/widgets/ledger_hero_card.dart
  - lib/features/ledger/widgets/receipt_picker_section.dart
  - lib/features/ledger/widgets/recent_expenses_section.dart
  - lib/features/ledger/widgets/recorded_settlements_section.dart
  - lib/features/ledger/widgets/settlement_row.dart
  - lib/features/ledger/widgets/settlement_summary_card.dart
  - lib/features/ledger/widgets/settlement_tile.dart
  - lib/features/ledger/widgets/split_scope_selector.dart
  - lib/features/logistics/screens/logistics_screen.dart
  - lib/features/logistics/widgets/logistics_group_dialog.dart
  - lib/features/logistics/widgets/logistics_hero_card.dart
  - lib/features/logistics/widgets/logistics_member_picker_sheet.dart
  - lib/features/logistics/widgets/sub_group_card.dart
  - lib/features/memories/screens/memories_screen.dart
  - lib/features/memories/widgets/full_screen_photo.dart
  - lib/features/memories/widgets/memories_hero_card.dart
  - lib/features/onboarding/screens/onboarding_screen.dart
  - lib/features/settings/screens/profile_screen.dart
  - lib/features/settings/widgets/edit_name_bottom_sheet.dart
  - lib/features/settings/widgets/profile_about_section.dart
  - lib/features/settings/widgets/profile_display_section.dart
  - lib/features/settings/widgets/profile_notifications_section.dart
  - lib/features/settings/widgets/profile_stats_section.dart
  - lib/features/settings/widgets/profile_support_section.dart
  - lib/features/settings/widgets/theme_picker_sheet.dart
  - lib/features/vault/screens/vault_screen.dart
  - lib/features/vault/widgets/vault_hero_card.dart
  - lib/main.dart
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
  - test/features/gear/widgets/gear_add_input_test.dart
  - test/features/logistics/widgets/logistics_hero_card_test.dart
  - test/features/logistics/widgets/logistics_member_picker_sheet_test.dart
  - test/features/profile/profile_screen_test.dart
  - test/features/settings/theme_picker_test.dart
  - test/features/shared_widgets/shared_widgets_theme_test.dart
  - test/flutter_test_config.dart
  - test/goldens/add_expense_golden_test.dart
  - test/goldens/gear_golden_test.dart
  - test/goldens/golden_harness.dart
  - test/goldens/group_detail_golden_test.dart
  - test/goldens/group_settle_up_golden_test.dart
  - test/goldens/home_golden_test.dart
  - test/goldens/ledger_golden_test.dart
  - test/goldens/logistics_golden_test.dart
  - test/goldens/memories_golden_test.dart
  - test/goldens/onboarding_golden_test.dart
  - test/goldens/README.md
  - test/goldens/settings_profile_golden_test.dart
  - test/unit/dark_theme_contrast_test.dart
  - test/unit/design_tokens_test.dart
  - test/unit/event_model_test.dart
  - test/unit/settings_theme_mode_test.dart
  - test/unit/shared_test_contrast_helpers.dart
  - test/unit/theme_wiring_test.dart
  - test/unit/token_promotions_test.dart
  - tool/check_theme_purity.sh
findings:
  critical: 0
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 37: Code Review Report

**Reviewed:** 2026-04-18T12:05:00Z
**Depth:** quick
**Files Reviewed:** 141
**Status:** issues_found

## Summary

The dark-theme migration is mostly mechanically sound. Token files (`color_tokens.dart`, `shadow_tokens.dart`, `gradient_tokens.dart`, `group_avatar_colors.dart`, `domain_aliases.dart`) are well-structured with explicit `lerp`/`copyWith` overrides and theme-aware instances. The `context.colors`/`context.spacing`/`context.shadows` extension pattern is used consistently across new/updated widgets. `tool/check_theme_purity.sh` runs clean against the tree (PASS).

However, one migration gap is substantive: **`AppShadowTokens.standard` is statically aliased to the light instance** (line 25 of `shadow_tokens.dart`), and 37 widget call-sites still read `AppShadowTokens.standard.raised` / `.floating` directly. In dark mode these widgets render light-mode shadows (gray-900 base @ 2–7% opacity) on a Slate-900 scaffold, which is the exact visual bug `AppShadowTokens.dark` was introduced to fix. The purity script does not guard against this — it checks color-token purity only, not shadow-token purity.

Everything else is minor: one purity-script portability nit, two info-level cleanups, and a first-paint overlay quirk in `_SystemChromeThemeSync`.

## Warnings

### WR-01: Dark-mode shadows never render — 37 widgets bypass ThemeExtension via `AppShadowTokens.standard`

**File:** `lib/core/theme/tokens/shadow_tokens.dart:25` (root cause) + 37 widget call-sites (see list below)

**Issue:** `AppShadowTokens.standard` is defined as `static final AppShadowTokens standard = light;` — a hard alias to the light-palette instance. Widgets that read `AppShadowTokens.standard.raised` therefore always get light shadows (`Color(0xFF111827)` @ 2–7% alpha) regardless of active theme. These shadows are almost invisible on the dark scaffold (`Color(0xFF0F172A)` Slate-900). The dark theme registers `AppShadowTokens.dark` as a ThemeExtension in `app_theme.dart:319`, but only widgets reading via `context.shadows.raised` benefit from it (13 files); the other 32 still use the global static.

Affected call-sites (grep `AppShadowTokens\.standard\.` returns 37 occurrences across 32 files):

- `lib/features/home/widgets/balance_hero_card.dart:65,123`
- `lib/features/home/widgets/weekly_spending_card.dart:151`
- `lib/features/home/screens/cross_group_activity_screen.dart:53`
- `lib/features/ledger/screens/add_expense_screen.dart:375,395,476,529`
- `lib/features/ledger/widgets/{expense_card,expense_success_dialog,ledger_hero_card,settlement_row,settlement_summary_card,settlement_tile,split_scope_selector}.dart`
- `lib/features/events/widgets/{event_danger_section,event_details_card,event_info_section,event_modules_card,event_participants_card}.dart`
- `lib/features/events/screens/{event_expense_hero,event_type_picker_screen}.dart`
- `lib/features/gear/widgets/{gear_hero_card,gear_item_card}.dart`
- `lib/features/vault/screens/vault_screen.dart:246`, `lib/features/vault/widgets/vault_hero_card.dart:34`
- `lib/features/activity/widgets/{activity_entry_card,activity_hero_card}.dart`
- `lib/features/memories/widgets/memories_hero_card.dart:42`
- `lib/features/logistics/widgets/{logistics_hero_card,sub_group_card}.dart`
- `lib/features/settings/widgets/{profile_about_section,profile_display_section,profile_notifications_section,profile_stats_section,profile_support_section}.dart`

**Fix:** Replace every `AppShadowTokens.standard.<level>` with `context.shadows.<level>`. Example:

```dart
// Before
Container(
  decoration: BoxDecoration(
    color: context.colors.cardSurface,
    borderRadius: BorderRadius.circular(16),
    boxShadow: AppShadowTokens.standard.raised, // always light shadows
  ),
)

// After
Container(
  decoration: BoxDecoration(
    color: context.colors.cardSurface,
    borderRadius: BorderRadius.circular(16),
    boxShadow: context.shadows.raised, // resolves to dark on dark theme
  ),
)
```

Then extend `tool/check_theme_purity.sh` with a Check 4 to prevent regression:

```bash
echo "Check 4: Direct AppShadowTokens.(standard|light|dark).* reads outside tokens/"
V4=$(grep -rn 'AppShadowTokens\.\(standard\|light\|dark\)\.' lib/ \
    --include='*.dart' \
    | grep -v '^lib/core/theme/tokens/' \
    | grep -v '^lib/core/theme/app_theme.dart:' \
    || true)
if [ -n "$V4" ]; then
  echo "::error::Direct AppShadowTokens reads found. Use context.shadows instead."
  echo "$V4"
  EXIT_CODE=1
fi
```

Optionally delete or deprecate the `standard` alias once all call-sites are migrated so future contributors cannot reintroduce it.

### WR-02: `check_theme_purity.sh` relies on GNU-grep-only `--include` flag + BSD-incompatible `grep -v '^lib/...:'` anchoring

**File:** `tool/check_theme_purity.sh:29-34, 63-67, 91-95`

**Issue:** Two portability concerns:

1. `grep -rn ... --include='*.dart'` is GNU-grep syntax. On macOS default BSD grep the `--include` flag is silently ignored in some versions and supported in others — the Phase 37 workflow is likely fine in CI (Ubuntu runner) but local `bash tool/check_theme_purity.sh` runs on a developer's Mac may return incorrect subsets depending on the installed `grep`. Not a security issue, but a correctness risk if a developer uses the script as a pre-push gate and it misses violations.
2. The exemption filter `grep -v '^lib/main.dart:'` relies on the first grep printing paths as `lib/main.dart:...` with no leading `./`. The script is invoked from the repo root by the workflow, which makes this hold — but if a contributor ever runs it from a subdirectory the exemptions break silently (every line then starts with `../lib/...`). Fail-loud on CWD would be safer.

**Fix:** Two small hardenings at the top of the script:

```bash
set -euo pipefail

# Must run from repo root so path-prefix exemptions match
if [ ! -d "lib/core/theme/tokens" ]; then
  echo "ERROR: run from repo root (lib/core/theme/tokens not found)" >&2
  exit 2
fi

# Prefer ripgrep when available (GNU-compatible patterns, honors .gitignore)
GREP="grep"
if command -v rg >/dev/null 2>&1; then
  GREP="rg --no-heading --line-number --with-filename"
fi
```

Then replace `grep -rn ... --include='*.dart'` with a glob-safe equivalent, e.g. `grep -rn --include='*.dart'` when `$GREP=grep`, or `$GREP -t dart` when using ripgrep. A minimal fallback that works on BSD grep is:

```bash
find lib -type f -name '*.dart' -print0 | xargs -0 grep -nH 'AppColorTokens\.light\.'
```

## Info

### IN-01: `_SystemChromeThemeSync` schedules overlay style from `addPostFrameCallback` on every build

**File:** `lib/main.dart:213-232`

**Issue:** Every rebuild of `_SystemChromeThemeSync` schedules a `SystemChrome.setSystemUIOverlayStyle` callback via `addPostFrameCallback`. This is correct for "apply after first frame" but schedules redundant work on every `settingsProvider` emit — including unrelated settings fields via the broader `ref.watch(settingsProvider)` subscribers elsewhere. More importantly, there's a one-frame lag between a theme switch (e.g. Light → Dark) and the status/nav bar repainting: the first post-switch frame still shows the old overlay.

**Fix:** Minor — move the scheduling behind a diff check or use `SchedulerBinding.instance.addPostFrameCallback` only when `effective` actually changed. Or simpler: call `SystemChrome.setSystemUIOverlayStyle(style)` synchronously inside `build` (Flutter tolerates this for overlay style — unlike SystemChrome for platform UI mode) and skip the frame callback entirely. The one-frame flash on theme switch is cosmetic; not blocking.

### IN-02: `_AuthRetryScreen` uses `AppColorTokens.light` pre-hydration but is only wrapped in `AppTheme.lightTheme`

**File:** `lib/main.dart:114-168`

**Issue:** The retry screen is intentionally pinned to the light palette (justified by a comment and the purity script's `main.dart` exemption). That's fine. However, if a user with `AppThemeMode.dark` configured experiences an auth failure, they'll see a white scaffold flashed up before the retry handler succeeds and the real theme takes over. Since this is pre-hydration (settings haven't been read), the tradeoff is accepted — just noting it so nobody later tries to "fix" it by reading settings synchronously from SharedPreferences inside the retry screen.

**Fix:** No action needed. Consider documenting in `37-CONTEXT.md` so the intent is preserved through future refactors.

### IN-03: Redundant import path in `lib/main.dart`

**File:** `lib/main.dart:13`

**Issue:** `import '../../core/theme/tokens/color_tokens.dart';` — the `../../` prefix is wrong relative to `lib/main.dart` (the file is at `lib/main.dart`, not `lib/foo/bar/main.dart`). Dart's package resolution appears to accept it because `../../core/theme/tokens/color_tokens.dart` resolves to `/core/theme/tokens/color_tokens.dart` which outside `lib/` doesn't exist — so this must be resolving via the relative-import normalizer that Dart applies. Regardless, the idiomatic path is `'core/theme/tokens/color_tokens.dart'`.

**Fix:**

```dart
// Before
import '../../core/theme/tokens/color_tokens.dart';

// After
import 'core/theme/tokens/color_tokens.dart';
```

---

_Reviewed: 2026-04-18T12:05:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: quick_
