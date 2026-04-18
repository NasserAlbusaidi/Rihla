---
phase: 37
slug: dark-theme-migration
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-04-17
---

# Phase 37 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (SDK) + mocktail ^1.0 |
| **Config file** | `pubspec.yaml` (dev_dependencies) |
| **Quick run command** | `flutter test test/unit/dark_theme_contrast_test.dart` |
| **Full suite command** | `flutter test` |
| **Goldens command** | `flutter test test/goldens/` |
| **CI guard command** | `bash tool/check_theme_purity.sh` |
| **Estimated runtime** | quick ~5s · goldens ~45s · full ~90s |

---

## Sampling Rate

- **After every task commit:** Run `flutter analyze` + targeted unit/widget test for the touched file (or `flutter test test/unit/dark_theme_contrast_test.dart` if no targeted test exists)
- **After every plan wave:** Run `flutter test` (full suite)
- **After Wave 5 task that adds CI guard:** Run `bash tool/check_theme_purity.sh` and confirm exit 0
- **After Wave 5 golden test task:** Run `flutter test test/goldens/` (regenerate baseline once, then assert no diff)
- **Before `/gsd-verify-work`:** Full suite + CI guard must be green
- **Max feedback latency:** 90 seconds (full suite)

---

## Per-Task Verification Map

> Filled by gsd-planner during PLAN.md generation. Each task in each plan must have a row here OR be backed by a Wave 0 stub.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 37-01-* | 01 | 1 | DARK-02 | — | MaterialApp wires darkTheme; SystemChrome theme-aware; AppThemeMode.toMaterialThemeMode() round-trips | unit | `flutter test test/unit/theme_wiring_test.dart test/unit/settings_theme_mode_test.dart` | ❌ W0 (created by Plan 01 Task 37-01-01) | ⬜ pending |
| 37-02-01..02 | 02 | 2 | DARK-01, DARK-03, DARK-04 | — | shared widgets + error_widgets + router shells read via context.colors | analyze | `flutter analyze && flutter test test/unit/` | N/A — shared smoke covered by 37-02-03 | ⬜ pending |
| 37-02-03 | 02 | 2 | DARK-01, DARK-03 | — | shared widgets render in both themes without throwing | widget | `flutter test test/features/shared_widgets/shared_widgets_theme_test.dart` | ❌ W0 (created by Plan 02 Task 37-02-03) | ⬜ pending |
| 37-03a-* | 03a | 3 | DARK-01, DARK-03, DARK-04 | — | auth/onboarding/settings/home migrate to context.colors (color-only; no behavior change) | analyze | `flutter analyze && flutter test test/unit/` per task; `flutter test` after plan completes | N/A — UI-level verification deferred to Plan 05 golden screenshots + Plan 02's shared_widgets_theme_test.dart (see note ¹) | ⬜ pending |
| 37-03b-* | 03b | 3 | DARK-01, DARK-03, DARK-04 | — | groups feature migrates to context.colors (color-only; no behavior change) | analyze | `flutter analyze && flutter test test/unit/` per task; `flutter test` after plan completes | N/A — UI-level verification deferred to Plan 05 goldens (see note ¹) | ⬜ pending |
| 37-03c-* | 03c | 3 | DARK-01, DARK-03, DARK-04 | — | events/ledger migrate to context.colors (color-only; no behavior change; BalanceCalculator untouched) | analyze | `flutter analyze && flutter test test/unit/` per task; `flutter test` after plan completes | N/A — UI-level verification deferred to Plan 05 goldens (see note ¹) | ⬜ pending |
| 37-03d-* | 03d | 3 | DARK-01, DARK-03, DARK-04 | — | gear/logistics/vault/memories/activity migrate to context.colors (color-only; no behavior change) | analyze | `flutter analyze && flutter test test/unit/` per task; `flutter test` after plan completes | N/A — UI-level verification deferred to Plan 05 goldens (see note ¹) | ⬜ pending |
| 37-04-* | 04 | 4 | DARK-04, DARK-05 | — | gradient/avatar/category tokens resolve in both themes; literal elimination via token promotion | unit | `flutter test test/unit/token_promotions_test.dart` | ❌ W0 (created by Plan 04 Task 37-04-01) | ⬜ pending |
| 37-05-* | 05 | 5 | DARK-02, DARK-03, DARK-05 | — | Settings theme picker persists; goldens present in both themes; CI guard rejects violations; contrast test asserts WCAG AA | unit + widget + integration | `flutter test test/features/settings/theme_picker_test.dart && flutter test test/goldens/ && bash tool/check_theme_purity.sh && flutter test test/unit/dark_theme_contrast_test.dart` | ❌ W0 (expanded from Plan 01 stub) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**¹ Note on Wave 3 UI-level verification:** Wave 3 plans (03a, 03b, 03c, 03d) migrate color references only — no behavioral changes. Dedicated per-feature theme smoke tests under `test/features/{feature}/` are NOT required because:
1. Plan 02's `shared_widgets_theme_test.dart` covers the shared components used across all features (ModuleHeader, AppTabBar, OfflineBanner, EmptyStateView, LoadingButton, InitialsCircle, etc.) in both light + dark.
2. Plan 05's 10 golden screenshot tests exercise the full rendered feature screens (home, group_detail, group_settle_up, ledger, add_expense, gear, logistics, settings/profile, memories, onboarding) in both themes end-to-end.
3. Sampling: `flutter analyze` + `flutter test test/unit/` after every task (≤10s feedback); `flutter test` full suite (~90s) after each Wave 3 plan completes.

> **Note:** The planner expands `*` to per-task IDs (e.g., `37-01-01`, `37-01-02`) in PLAN.md frontmatter. This table is the contract — each task PLAN.md must point back to a row here.

---

## Wave 0 Requirements

Test files that must exist (or be stubbed by the first task touching the area) before downstream tasks can verify:

- [ ] `test/unit/theme_wiring_test.dart` — asserts `AppTheme.darkTheme.brightness == Brightness.dark`, `AppTheme.lightTheme.brightness == Brightness.light`, both wire `AppColorTokens` correctly into `extensions`. **Created in Plan 01.**
- [ ] `test/unit/dark_theme_contrast_test.dart` — walks every documented `(text, background)` pair in `AppColorTokens.dark` and asserts WCAG AA (4.5:1 normal, 3:1 large/UI). Asserts `textSecondary` on `scaffoldBackground` in BOTH themes ≥ 4.5:1. Reuses contrast helper from `test/unit/design_tokens_test.dart:16-37`. **Stub in Plan 01; expanded in Plan 05.**
- [ ] `test/unit/settings_theme_mode_test.dart` — asserts `AppThemeMode.{light,dark,system}.toMaterialThemeMode()` mapping and SharedPreferences round-trip via SettingsService. **Created in Plan 01.**
- [ ] `test/features/shared_widgets/shared_widgets_theme_test.dart` — smoke test that every shared widget renders in light + dark without throwing. **Created in Plan 02 Task 37-02-03.**
- [ ] `test/unit/token_promotions_test.dart` — asserts `AppGroupAvatarColors.lightSlots.length == 5 && darkSlots.length == 5`, `AppGradients.terracotta.{light,dark}.colors.length == 2`, etc. **Created in Plan 04.**
- [ ] `test/features/settings/theme_picker_test.dart` — widget test for the bottom sheet (System/Light/Dark radio + persistence). **Created in Plan 05.**
- [ ] `test/goldens/` directory with 20 baselines (10 screens × 2 themes). **Created in Plan 05 via `flutter test --update-goldens` after assertions pass.**
- [ ] `tool/check_theme_purity.sh` — bash CI guard. Exits 0 on clean repo, exits 1 with file:line listing on violations. **Created in Plan 05.**

> **No new test framework needed** — `flutter_test` already in use. `mocktail` already in dev_dependencies.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual confirmation that dark theme reads as slate (not "darker beige") | DARK-05 | Subjective aesthetic — automated contrast can't catch hue drift | After Wave 5: open `test/goldens/home_dark.png`, confirm cool slate tonality vs. warm CONTEXT specifics line 178 |
| Theme switch UX feels native (instant, no white flash) | DARK-02 | Perceptual — automated tests can't measure flash | Run app on device, toggle between System→Light→Dark via Settings, confirm no perceptible flash |
| Per-screen QA walkthrough (`MANUAL-QA.md` per D-19) | DARK-01..DARK-05 | Catch any layout artifact missed by goldens (e.g., off-screen overflow only visible on real device) | Author `.planning/phases/37-dark-theme-migration/MANUAL-QA.md` in Plan 05; Nasser runs before merge |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (theme_wiring, dark_theme_contrast, settings_theme_mode, shared_widgets_theme, token_promotions, theme_picker, goldens, check_theme_purity)
- [ ] Wave 3 UI-level coverage via Plan 02 shared smoke + Plan 05 goldens (no per-feature theme test files required — see note ¹)
- [ ] No watch-mode flags (`--watch` forbidden in any plan command)
- [ ] Feedback latency < 90s
- [ ] `wave_0_complete: true` set after Plan 01 Task 37-01-04 completes (stub files landed)
- [ ] `nyquist_compliant: true` set after Plan 05 Task 37-05-06 completes

**Approval:** pending
