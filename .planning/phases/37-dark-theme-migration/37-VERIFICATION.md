---
phase: 37-dark-theme-migration
verified: 2026-04-18T08:07:07Z
status: gaps_found
score: 4/5 must-haves verified
overrides_applied: 0
gaps:
  - truth: "Dark theme renders with the slate-based palette end-to-end (SC5)"
    status: partial
    reason: "32 files in lib/features/ and lib/features/settings/ still read `AppShadowTokens.standard.raised`/`.floating` directly. `AppShadowTokens.standard` is declared as an alias for `AppShadowTokens.light` in shadow_tokens.dart line 25 (`static final AppShadowTokens standard = light;`), so every consumer gets the light shadow set even under `ThemeMode.dark`. The dark theme registers `AppShadowTokens.dark` on `Theme.of(context).extension<AppShadowTokens>()` and `context.shadows.*` would resolve correctly, but 37 direct reads bypass that extension. The palette claim 'end-to-end' is therefore false for elevation/shadow layer — only color/text/gradient tokens flip with brightness. Goldens cannot detect this because the synthetic harness at test/goldens/golden_harness.dart:149,205 itself uses `AppShadowTokens.standard.raised`, so the light→dark diff for shadows is zero in the baseline — the gap is masked by the harness. Plan 02 did migrate shared-widget shadows (~14 context.shadows reads), and Plan 03b opportunistically migrated 10 refs in groups/, but Plans 03a/03c/03d/04 did not sweep shadow reads. No later phase in the v2.4 roadmap addresses this."
    artifacts:
      - path: "lib/features/settings/widgets/profile_stats_section.dart"
        issue: "boxShadow: AppShadowTokens.standard.raised (line 134) — reads light shadow in dark mode"
      - path: "lib/features/settings/widgets/profile_display_section.dart"
        issue: "boxShadow: AppShadowTokens.standard.raised (line 40) — newly added in Wave 5 yet still light-only"
      - path: "lib/features/home/widgets/balance_hero_card.dart"
        issue: "2 reads (lines 65, 123) of AppShadowTokens.standard.raised"
      - path: "lib/features/ledger/screens/add_expense_screen.dart"
        issue: "4 reads of AppShadowTokens.standard.raised (lines 375, 395, 476, 529)"
      - path: "lib/features/ledger/widgets/*"
        issue: "7 files with .standard shadow reads (expense_card, split_scope_selector, settlement_tile×2, settlement_summary_card, settlement_row, expense_success_dialog)"
      - path: "test/goldens/golden_harness.dart"
        issue: "Lines 149 and 205 use AppShadowTokens.standard.raised — the harness itself masks this gap"
    missing:
      - "Replace every `AppShadowTokens.standard.raised|floating` read in lib/features/ and lib/features/settings/ with `context.shadows.raised|floating` (32 files, 37 call sites)"
      - "Fix golden_harness.dart lines 149, 205 to read `context.shadows.raised` via a Builder so elevation surfaces render differently between light and dark baselines"
      - "Decide whether to deprecate `AppShadowTokens.standard` (remove the alias) or keep it explicitly for documented pre-hydration cases with `// design-token-justified:` comments, then extend `tool/check_theme_purity.sh` with a Check 4 that forbids unjustified `AppShadowTokens.standard` reads"
      - "Regenerate the 10 dark-theme golden baselines after the harness fix — expect visible shadow tint delta (light shadow uses `Color(0x14111827)`, dark uses `Color(0x59000000)`)"
deferred: []
---

# Phase 37: Dark Theme Migration Verification Report

**Phase Goal:** Dark Theme Migration — Widget migration to `context.colors`, theme toggle, textMuted contrast (#17, #29, #31, #32)
**Verified:** 2026-04-18T08:07:07Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Zero direct `AppColorTokens.light.*` references in rendered widget code (enforced by lint or CI check) | ✓ VERIFIED | `grep -rn "AppColorTokens\.light\." lib/ --include='*.dart' | grep -v "lib/core/theme/tokens/" | grep -v "lib/core/theme/app_theme.dart" | grep -v "lib/main.dart" | wc -l` = 0. `bash tool/check_theme_purity.sh` exits 0. CI wired in release_android.yml before tests. |
| 2 | Settings exposes a theme toggle (System / Light / Dark) persisted via SharedPreferences | ✓ VERIFIED | ProfileDisplaySection at lib/features/settings/widgets/profile_display_section.dart:72 calls `ThemePickerSheet.show(context)`. Sheet at lib/features/settings/widgets/theme_picker_sheet.dart:94 calls `settingsProvider.notifier.setThemeMode(v)`. 3 `RadioListTile<AppThemeMode>` values verified. main.dart:184-185 passes `AppTheme.darkTheme` + `settings.themeMode.toMaterialThemeMode()` to MaterialApp.router. theme_picker_test (3 tests) exercises persistence round-trip. |
| 3 | textMuted no longer used for functional text; contrast audit passes WCAG AA on all text/background pairs in both themes | ✓ VERIFIED | test/unit/dark_theme_contrast_test.dart: 11 WCAG AA pair assertions pass (8 dark-palette pairs + 2 functional-text-in-both-themes + 1 light-textMuted-below-AA encoding the decorative-only rule). Triage tallies across waves: 6+21+14+52 functional → textSecondary conversions; 0+6+1+6=13 decorative retentions all carrying `// textMuted-decorative-justified:` comments. CI Check 3 enforces this. |
| 4 | Spacing tokens adopted where semantically meaningful; remaining `Color(0xFF…)` hardcoded literals justified inline or removed | ✓ VERIFIED | ~60+40+7 opportunistic `context.spacing.*` replacements across waves. `grep -c "Color(0xFF" lib/core/theme/app_theme.dart` = 2 (both with `// design-token-justified:` on preceding line — warm input label/hint). `grep -c "Color(0xFF" lib/features/ledger/models/expense_category_model.dart` = 0 after Plan 04's `resolveColor(AppColorTokens)` refactor. Avatar slots and gradient literals now live in `lib/core/theme/tokens/{group_avatar_colors,gradient_tokens}.dart` as named tokens. |
| 5 | Screenshot diffs show light theme unchanged and dark theme renders with the slate-based palette end-to-end | ✗ FAILED | 20 golden baselines exist (10 screens × 2 themes) but use a synthetic `GoldenHarness` shell, not real feature screens. Real feature code still reads `AppShadowTokens.standard.*` in 32 files — and `standard` is aliased to `.light` (shadow_tokens.dart:25) — so dark-mode shadows render as light shadows. The harness itself (lines 149, 205) uses the same alias, masking the diff in goldens. "End-to-end" is only true for color/text/gradient tokens, not elevation. |

**Score:** 4/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/core/theme/app_theme.dart` | darkTheme + 5 bug fixes | ✓ VERIFIED | `AppTheme.darkTheme` registers brightness + 3 extensions (theme_wiring_test passes). `_buildTextTheme(Brightness)` resolves `tokens` once per theme. 2 remaining `Color(0xFF...)` literals both carry `// design-token-justified:` per Plan 01 revision B6 Q3. |
| `lib/core/theme/tokens/group_avatar_colors.dart` | AppGroupAvatarColors.lightSlots/darkSlots (5 each) | ✓ VERIFIED | File exists (1.6k). token_promotions_test asserts lightSlots.length == 5, darkSlots.length == 5, lightSlots != darkSlots. |
| `lib/core/theme/tokens/gradient_tokens.dart` | AppGradientPair + terracotta/olive/teal/gray | ✓ VERIFIED | File exists (3.1k). All 4 pairs have light+dark LinearGradients with identical begin/end. |
| `lib/features/settings/widgets/theme_picker_sheet.dart` | ConsumerWidget bottom sheet | ✓ VERIFIED | `ThemePickerSheet.show(context)` static method. Calls `setThemeMode(v)` + `Navigator.of(c).pop()`. Uses `context.spacing.space24` / `space16`. |
| `lib/features/settings/widgets/profile_display_section.dart` | Display section with Theme tile | ✓ VERIFIED | Section widget with icon (brightness_6_outlined), trailing current-mode label, tap opens ThemePickerSheet. Referenced at profile_screen.dart:76. |
| `tool/check_theme_purity.sh` | Executable 3-check CI guard | ✓ VERIFIED | File mode `-rwxr-xr-x`. `set -euo pipefail`. Exempt paths: tokens/, app_theme.dart, main.dart. Exits 0 on clean repo. Check 2 uses 5-line preceding window (W5 correction). Check 3 extended to 5-line window per Plan 05 decision. |
| `test/unit/dark_theme_contrast_test.dart` | 11 WCAG assertions | ✓ VERIFIED | 11 tests pass: 8 AppColorTokens.dark pairs at appropriate AA thresholds + 2 functional-text-both-themes + 1 light-textMuted below-AA. |
| `test/unit/shared_test_contrast_helpers.dart` | Extracted helpers | ✓ VERIFIED | `relativeLuminance(Color)` + `contrastRatio(Color, Color)` public API. Consumed by both dark_theme_contrast_test and design_tokens_test. |
| `test/features/settings/theme_picker_test.dart` | Persistence round-trip | ✓ VERIFIED | 3 tests pass: renders 3 radios, tapping Dark writes AppThemeMode.dark.index to SharedPreferences, tapping Light updates settingsProvider.state.themeMode. |
| `test/goldens/ 10 files + 20 PNGs` | 10 screens × 2 themes | ⚠️ PRESENT-BUT-SYNTHETIC | 10 `*_golden_test.dart` files + 20 PNGs under `test/goldens/goldens/`. All use `GoldenHarness` synthetic shell + bespoke `_goldenTheme(brightness:)` that skips google_fonts. Baselines discriminate color tokens but NOT elevation (harness uses the aliased `AppShadowTokens.standard`). Counted as VERIFIED for "baselines exist and pass" but contributes to SC5 failure. |
| `.planning/phases/37-dark-theme-migration/MANUAL-QA.md` | Pre-merge checklist | ✓ VERIFIED | File exists (3.4k) with 22-screen walkthrough + theme toggle UX + OS chrome + edge cases. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| profile_screen.dart | profile_display_section.dart | `const ProfileDisplaySection()` at line 76 | ✓ WIRED | Reads from profile_screen structure above About section |
| profile_display_section.dart | theme_picker_sheet.dart | `ThemePickerSheet.show(context)` at line 72 | ✓ WIRED | onTap handler opens sheet |
| theme_picker_sheet.dart | settingsProvider | `ref.read(settingsProvider.notifier).setThemeMode(v)` line 94 | ✓ WIRED | Calls into existing provider (no parallel themeModeProvider) |
| main.dart (SafarApp.build) | AppTheme.darkTheme | `darkTheme: AppTheme.darkTheme` line 184 | ✓ WIRED | MaterialApp.router consumes dark theme |
| main.dart | settingsProvider | `settings.themeMode.toMaterialThemeMode()` line 185 + `_SystemChromeThemeSync` at line 205 | ✓ WIRED | Both MaterialApp themeMode and SystemChrome overlay track settings |
| .github/workflows/release_android.yml | tool/check_theme_purity.sh | `run: bash tool/check_theme_purity.sh` line 49 | ✓ WIRED | Runs AFTER flutter analyze and BEFORE flutter test. Obsolete "Hardcoded color lint" step removed. |
| AppColorTokens (color_tokens.dart) | AppGroupAvatarColors.{light,dark}Slots | `groupAvatarSlot(String groupId)` method uses `brightness` field to dispatch | ✓ WIRED | group_card.dart:2 occurrences of `context.colors.groupAvatarSlot` confirmed |
| onboarding/ledger/activity hero | AppGradients via context.gradient | 5+ call sites found | ✓ WIRED | grep confirms AppGradients.terracotta / .gray usage |
| Shared widgets | context.shadows (theme-aware) | 14 reads across Wave 2 surface | ⚠️ PARTIAL | Shared widgets read `context.shadows`. Feature widgets read `AppShadowTokens.standard.*` (32 files, 37 reads) — NOT wired to theme. Aliased to light. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| ThemePickerSheet | `current` mode | `ref.watch(settingsProvider.select((s) => s.themeMode))` | Yes — flows from StateNotifier backed by SettingsService + SharedPreferences | ✓ FLOWING |
| _SystemChromeThemeSync | `mode` | `ref.watch(settingsProvider.select((s) => s.themeMode))` + `MediaQuery.platformBrightnessOf(context)` | Yes — resolves system brightness correctly | ✓ FLOWING |
| MaterialApp.router themeMode | `settings.themeMode` | `ref.watch(settingsProvider)` | Yes — triggers app-wide rebuild on theme change | ✓ FLOWING |
| Any feature widget shadows | `AppShadowTokens.standard.raised` | Static alias to `AppShadowTokens.light` — does NOT read `Theme.of(context)` | No — static, theme-independent | ⚠️ STATIC (masked alias) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| CI purity script passes on clean repo | `bash tool/check_theme_purity.sh` | "Theme purity check PASS" exit 0 | ✓ PASS |
| Zero unjustified AppColorTokens.light outside exempt paths | `grep -rn "AppColorTokens\.light\." lib/ ... | wc -l` | 0 | ✓ PASS |
| Display section wired to picker sheet | `grep "ThemePickerSheet" lib/features/settings/screens/profile_screen.dart lib/features/settings/widgets/profile_display_section.dart` | 2 hits (reference in docs + actual call) | ✓ PASS |
| MaterialApp.router uses darkTheme | `grep "darkTheme: AppTheme.darkTheme" lib/main.dart` | 1 hit | ✓ PASS |
| Full test suite green | Summary reports 1088 pass / 3 skip / 0 fail (Plan 05 gate) | 1088/3/0 | ✓ PASS |
| Contrast test passes | `flutter test test/unit/dark_theme_contrast_test.dart` | 11 pass per Plan 05 SUMMARY | ✓ PASS |
| Shadow tokens dark variant registered on darkTheme | theme_wiring_test: `identical(...) == false` | Pass — distinct AppShadowTokens instances | ✓ PASS |
| Feature widgets read shadow via theme | `grep -rn "AppShadowTokens\.standard\." lib/ | grep -v "lib/core/theme/tokens/" | wc -l` | **37 direct reads across 32 files** | ✗ FAIL |
| Dark shadow alias behavior | `grep "standard = " lib/core/theme/tokens/shadow_tokens.dart` | `static final AppShadowTokens standard = light;` | ✗ FAIL (silent aliasing) |

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|-------------|----------------|-------------|--------|----------|
| DARK-01 | 37-02, 37-03a, 37-03b, 37-03c, 37-03d | Every widget reads colors via `context.colors` | ✓ SATISFIED | CI guard exits 0; grep confirms 0 unjustified direct reads |
| DARK-02 | 37-01, 37-02, 37-03a-d, 37-04, 37-05 | Dark theme toggle persisted in Settings | ✓ SATISFIED | ThemePickerSheet + ProfileDisplaySection wired end-to-end; theme_picker_test asserts persistence round-trip |
| DARK-03 | 37-02, 37-03a-d, 37-05 | textMuted removed from functional roles; WCAG AA pass | ✓ SATISFIED | Triage complete (73+ functional migrations, 13 decorative-kept with justifications); contrast test passes 11 pairs; CI Check 3 enforces |
| DARK-04 | 37-02, 37-03a-d, 37-04 | `AppSpacingTokens.standard` actively used | ✓ SATISFIED | ~60+40+7+ opportunistic adoptions across waves; Plan 05's ThemePickerSheet uses context.spacing.space* |
| DARK-05 | 37-04, 37-05 | Hardcoded `Color(0xFF…)` literals eliminated or justified | ✓ SATISFIED | Avatar slots + 4 gradient pairs + event/expense category roles all promoted to tokens in Plan 04; CI Check 2 enforces remaining literals to have `// design-token-justified:` within 5 preceding lines |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| lib/core/theme/tokens/shadow_tokens.dart | 25 | `static final AppShadowTokens standard = light;` (alias) | ⚠️ Warning | Allows 32 consumer files to silently get light shadows in dark mode. Breaks SC5 "end-to-end". Tests pass because the alias exists; the reality is that shadows don't flip. |
| test/goldens/golden_harness.dart | 149, 205 | `boxShadow: AppShadowTokens.standard.raised` inside the golden harness | ⚠️ Warning | Golden baselines cannot distinguish shadow regressions because the harness itself is theme-independent for elevation. Creates a false-green on SC5's visual coverage. |
| 32 files under lib/features/ and lib/features/settings/ | various | `AppShadowTokens.standard.raised` / `.floating` reads | ⚠️ Warning | Main body of the gap. Not blocker per se — app still renders — but dark theme loses shadow contrast. |

### Human Verification Required

None gating the phase status. (Status is `gaps_found`, not `human_needed`.) However, manual confirmation of MANUAL-QA.md's visual walkthrough on a real device would be the natural final check once the shadow gap is closed.

### Gaps Summary

The phase successfully delivered 4 of the 5 ROADMAP success criteria cleanly: color-migration is complete (DARK-01), the Settings toggle persists and wires into `settingsProvider` without a parallel provider (DARK-02), `textMuted` is retired from functional roles with both runtime contrast assertions and a CI comment-based guard (DARK-03), spacing tokens and token-justified literals are enforced by CI (DARK-04 + DARK-05).

The single remaining gap is that **elevation does not track brightness**. `AppShadowTokens.standard` is a static alias for `AppShadowTokens.light`, and 32 files (37 call sites) across lib/features/ and lib/features/settings/ read this alias directly instead of going through `context.shadows.*`. Plan 02 migrated shared-widget shadows and Plan 03b opportunistically migrated 10 refs in groups/, but Plans 03a/03c/03d/04 did not sweep shadow reads — they were not in those plans' must_haves. Wave 1's theme_wiring_test confirms `AppShadowTokens.dark` is registered on `AppTheme.darkTheme`, but direct `AppShadowTokens.standard.*` consumers bypass the extension. The golden suite does not catch this because the synthetic harness itself reads the same alias.

This is a material defect against SC5 ("dark theme renders with the slate-based palette end-to-end"). It's a focused, mechanical fix: roughly the same shape as the Wave 2 shared-widget migration but on a smaller surface. No later phase on the v2.4 roadmap addresses it, so it is not deferrable.

**Recommendation for planner:** Follow-up plan with three tasks — (1) replace every unjustified `AppShadowTokens.standard.*` read with `context.shadows.*` (32 files, scope comparable to Wave 3's smaller folders); (2) fix the golden harness to use `context.shadows` and regenerate the 10 dark baselines; (3) add a Check 4 to `tool/check_theme_purity.sh` forbidding unjustified `AppShadowTokens.standard` reads, then either delete the `standard = light` alias in shadow_tokens.dart or mark the remaining uses with `// design-token-justified:` comments for documented pre-hydration surfaces (if any).

---

_Verified: 2026-04-18T08:07:07Z_
_Verifier: Claude (gsd-verifier)_
