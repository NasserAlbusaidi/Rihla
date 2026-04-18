---
phase: 37-dark-theme-migration
plan: 01
subsystem: theme-foundation
tags: [theme, dark-mode, foundation, wave-0, wave-1]
requires:
  - AppColorTokens.dark (landed Apr 16)
  - AppTheme.darkTheme scaffold (landed Apr 16)
  - settingsProvider + AppThemeMode enum (pre-existing)
provides:
  - AppTheme.darkTheme registers AppColorTokens.dark + AppShadowTokens.dark
  - AppThemeModeX.toMaterialThemeMode() extension (lib/core/models/app_settings_model.dart)
  - AppShadowTokens.light + .dark instances (standard retained as alias)
  - _SystemChromeThemeSync widget (main.dart) — OS overlay tracks theme
  - Wave 0 test scaffolding: theme_wiring_test, dark_theme_contrast_test stub, settings_theme_mode_test
  - VALIDATION.md wave_0_complete flag set true
affects:
  - All downstream Wave 2-5 plans — Wave 0 tests now exist and pass
  - Widget bodySmall/labelSmall color silently corrected from textMuted to textSecondary in dark mode
tech-stack:
  added: []
  patterns:
    - "ThemeExtension-based token registration (AppColorTokens + AppSpacingTokens + AppShadowTokens on both themes)"
    - "settingsProvider.select((s) => s.themeMode) — single source of truth for theme mode"
    - "MediaQuery.platformBrightnessOf + WidgetsBinding.instance.addPostFrameCallback for SystemChrome sync"
    - "design-token-justified comment convention for intentional hex literals"
key-files:
  created:
    - test/unit/theme_wiring_test.dart
    - test/unit/dark_theme_contrast_test.dart
    - test/unit/settings_theme_mode_test.dart
  modified:
    - lib/core/theme/app_theme.dart
    - lib/core/theme/tokens/shadow_tokens.dart
    - lib/core/models/app_settings_model.dart
    - lib/main.dart
    - .planning/phases/37-dark-theme-migration/37-VALIDATION.md
decisions:
  - "Reused settingsProvider.themeMode as single source of truth (no parallel themeModeProvider) — honors D-07a/D-08a per research correction #1"
  - "Added AppShadowTokens.dark as distinct instance from .standard/.light so lightTheme and darkTheme resolve different shadow extensions"
  - "Kept _AuthRetryScreen hardcoded to AppColorTokens.light with justification comment — theme hydration has not happened when the retry screen paints (auth bootstrap failure path)"
  - "Kept warm input label/hint literals (#2C1A0E, #A89888) with design-token-justified comments — token promotion deferred to Wave 4 to avoid conflicting with that wave's scope"
  - "SystemChrome handled via new _SystemChromeThemeSync widget (option b in RESEARCH), preserving the initial main() bootstrap overlay call as a first-paint light default"
  - "main.dart bootstrap SystemChrome overlay retains light literal (no justification) — it runs before Riverpod hydrates and is subsequently overridden by the widget-level sync on first frame"
metrics:
  tasks_completed: 4
  tasks_planned: 4
  files_created: 3
  files_modified: 5
  commits: 4
  duration_minutes: ~20
  tests_added: 14
  tests_passing: 986 (3 skipped, 0 failed across full suite)
completed: 2026-04-18
---

# Phase 37 Plan 01: Dark Theme Foundation Summary

Hardened `AppTheme.darkTheme` into a complete brightness-aware theme (registers correct color/spacing/shadow extensions; text theme now resolves brightness via a unified `tokens` variable; five hardcoded `Color(0xFF...)` bugs fixed). Added a `_SystemChromeThemeSync` widget so the OS status-bar and navigation-bar colors follow the active theme (including resolving `ThemeMode.system` against the platform brightness at runtime). Landed Wave 0 test scaffolding so all downstream waves have a stable foundation to build on.

## What Got Built

### Theme Infrastructure

- **`AppShadowTokens.dark`** added — separate instance from `.light` / `.standard` (kept as alias). Gives dark theme a distinct shadow set (pure black base at higher opacity — 0.35/0.50 versus light's 0.04/0.07).
- **`AppThemeModeX.toMaterialThemeMode()`** — extension on `AppThemeMode` enum in `lib/core/models/app_settings_model.dart`. `AppSettings.theme` getter delegates to this, so the enum → `ThemeMode` mapping lives in one place. `main.dart` uses `settings.themeMode.toMaterialThemeMode()` on `MaterialApp.router(themeMode:)` — traceable via grep.
- **`AppTheme._buildTextTheme(Brightness)`** rewritten around a single `final tokens = brightness == Brightness.dark ? AppColorTokens.dark : AppColorTokens.light;` resolution. Every text role sources its color from `tokens.textPrimary`/`tokens.textSecondary`. No more silent light/dark split in `bodySmall`/`labelSmall`.
- **`AppTheme.darkTheme.extensions`** now includes `AppShadowTokens.dark` (Task 1 minimal change for the theme-wiring test; rest of darkTheme already registered `AppColorTokens.dark` + `AppSpacingTokens.standard`).

### Bug Fixes (app_theme.dart)

| # | Line (before) | Before | After |
|---|---|---|---|
| 1 | 23 | `onSecondary: const Color(0xFFFFFFFF)` | `AppColorTokens.light.textOnPrimary` |
| 2 | 25 | `onError: const Color(0xFFFFFFFF)` | `AppColorTokens.light.textOnPrimary` |
| 3 | 115 | `labelStyle color: const Color(0xFF2C1A0E)` | Same literal + `// design-token-justified:` comment |
| 4 | 121 | `hintStyle color: const Color(0xFFA89888)` | Same literal + `// design-token-justified:` comment |
| 5 | 380/398 | `bodySmall/labelSmall color: AppColorTokens.light.textMuted` | `tokens.textSecondary` — now honors B4 (functional text must meet WCAG AA) and flips correctly between brightnesses |

`grep -c "const Color(0xFF" lib/core/theme/app_theme.dart` = 2 (both with justification). `grep -c "AppColorTokens.light.textMuted" lib/core/theme/app_theme.dart` = 0.

### main.dart Theme-Aware Overlay

Added a `_SystemChromeThemeSync` `ConsumerWidget` inside `SafarApp.build`, wrapping `MaterialApp.router`. On each build it:

1. Watches `settingsProvider.select((s) => s.themeMode)`.
2. Resolves the effective brightness (`AppThemeMode.system` falls back to `MediaQuery.platformBrightnessOf(context)`).
3. Schedules a post-frame `SystemChrome.setSystemUIOverlayStyle` with brightness-appropriate status-bar and navigation-bar colors.

Both the dark and light `AppColorTokens.scaffoldBackground` references in this widget carry `// design-token-justified:` comments so the Plan 05 CI guard won't require a `main.dart` exemption.

The initial `main()` overlay call (pre-hydration) retains its original light palette — runs before Riverpod is ready and is immediately overridden by the widget on first frame.

### Auth Retry Justification

`_AuthRetryScreen.build` still hardcodes `const colors = AppColorTokens.light;` — unavoidable because this screen paints on Firebase anonymous-auth failure, which happens before `settingsProvider` hydrates. Added the canonical comment:

```
// design-token-justified: auth retry renders before settingsProvider hydration; light palette is the only safe default.
```

### Wave 0 Test Scaffolding

Three new test files, all passing:

| File | Tests | What it asserts |
|---|---|---|
| `test/unit/theme_wiring_test.dart` | 4 | `lightTheme`/`darkTheme` have correct brightness; register `AppColorTokens.{light,dark}`; register `AppSpacingTokens.standard`; shadow extensions are distinct instances |
| `test/unit/dark_theme_contrast_test.dart` | 1 (stub) | Smoke check — `AppColorTokens.dark.scaffoldBackground` + `.textPrimary` are non-null. Plan 05 expands with WCAG AA pair assertions. |
| `test/unit/settings_theme_mode_test.dart` | 9 | `AppThemeMode.{light,dark,system}.toMaterialThemeMode()` round-trips; `AppSettings.theme` getter parity with the extension; `SettingsService.saveThemeMode/loadSettings` round-trip across SharedPreferences; default when unset is `system` |

`theme_wiring_test` uses `testWidgets` + a `_suppressFontErrors` helper that drops google_fonts' "asset not bundled" async errors (mirrors the pattern from the existing `design_tokens_test.dart` `testWidgets('AppTheme.lightTheme registers all three extensions', ...)` test). `settings_theme_mode_test` uses `SharedPreferences.setMockInitialValues({})` in `setUp`.

### VALIDATION.md Flag

Flipped `wave_0_complete: false → true`. This unblocks the Wave 2-5 plans which check this flag before executing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Task 1 test expected distinct shadow extensions but darkTheme registered `AppShadowTokens.standard`**

- **Found during:** Task 37-01-01 (tests failing on the "distinct shadow instances" assertion).
- **Issue:** The plan's Task 1 test requires `identical(lightTheme.extension<AppShadowTokens>(), darkTheme.extension<AppShadowTokens>()) == false`, but `app_theme.dart` registered `AppShadowTokens.standard` on BOTH themes.
- **Fix:** Added `AppShadowTokens.dark` as a distinct static final, kept `.standard` as an alias for `.light`, and updated `AppTheme.darkTheme.extensions` to register `AppShadowTokens.dark`. Minimal change — only touched what Task 1's acceptance criteria required. Task 2's remaining darkTheme work proceeded on top.
- **Files modified:** `lib/core/theme/tokens/shadow_tokens.dart`, `lib/core/theme/app_theme.dart`
- **Commit:** 895c4cb

**2. [Rule 3 — Blocker] google_fonts async errors leaked test failures**

- **Found during:** Task 37-01-01 (running `theme_wiring_test.dart`).
- **Issue:** `GoogleFonts.getFont(...)` inside `AppTheme.{light,dark}Theme` attempts to load the asset manifest even with `allowRuntimeFetching = false`, then reports "font not in bundled assets" via `FlutterError.reportError` on an async microtask. This marked the tests as failed AFTER the body's assertions had passed.
- **Fix:** Switched test from `test(...)` → `testWidgets(...)` (so the harness drives an event loop that predictably absorbs the async error), and wrapped each test body in a `_suppressFontErrors` helper that filters the specific google_fonts exception text. Mirrors the pattern already used in `test/unit/design_tokens_test.dart`.
- **Files modified:** `test/unit/theme_wiring_test.dart`
- **Commit:** 895c4cb

### Explicit reuse (no deviation)

- **`settingsProvider` reused** — did NOT create a parallel `themeModeProvider`. This honors research correction #1 / decisions D-07a / D-08a. The `AppThemeModeX.toMaterialThemeMode()` extension is the only new piece of state machinery; it sits on top of the existing enum.
- **`_AuthRetryScreen` left hardcoded to light** per RESEARCH Open Question 2 resolution.
- **Warm input label/hint literals (#2C1A0E, #A89888)** kept with justification comments per RESEARCH Open Question 3 option (b); token promotion (textOnWarm / hintOnWarm) deferred to Wave 4.

## Authentication Gates

None encountered — this plan touches only local code, test files, and a frontmatter flag.

## Verification Results

- `flutter analyze` — clean (273 pre-existing info-level lints unchanged; no warnings/errors introduced).
- `flutter test test/unit/theme_wiring_test.dart test/unit/dark_theme_contrast_test.dart test/unit/settings_theme_mode_test.dart test/unit/design_tokens_test.dart` — 50 tests pass, 0 fail.
- `flutter test` (full suite) — **986 tests pass, 3 skipped, 0 fail**.
- `grep -c "const Color(0xFF" lib/core/theme/app_theme.dart` = 2 (both with justification).
- `grep -c "AppColorTokens.light.textMuted" lib/core/theme/app_theme.dart` = 0.
- `grep -c "darkTheme: AppTheme.darkTheme" lib/main.dart` = 1.
- `grep -c "themeMode: settings.themeMode.toMaterialThemeMode" lib/main.dart` = 1.
- `grep -B1 "const colors = AppColorTokens.light" lib/main.dart | grep -c "design-token-justified"` = 1.
- `grep -B1 "AppColorTokens.dark.scaffoldBackground" lib/main.dart | grep -c "design-token-justified"` = 1.
- `grep -B1 "AppColorTokens.light.scaffoldBackground" lib/main.dart | grep -c "design-token-justified"` = 1 (on the `_SystemChromeThemeSync` widget reference; the initial bootstrap reference retains no comment per plan guidance).

## Commits

| Hash | Scope | Message |
|---|---|---|
| 895c4cb | test | wave 0 scaffolding — theme_wiring, contrast stub, settings_theme_mode |
| 620be76 | fix | resolve 5 hardcoded Color(0xFF) bugs in app_theme.dart |
| c80372e | feat | make main.dart SystemChrome overlay theme-aware |
| 7b5bdc3 | docs | justify _AuthRetryScreen light palette + flip wave_0_complete |

## Known Stubs

- `test/unit/dark_theme_contrast_test.dart` is intentionally a STUB — only asserts non-null. Plan 05 expands this with WCAG AA pair assertions using the helpers from `test/unit/design_tokens_test.dart:16-37`. Documented in the plan itself (Task 37-01-01 behavior block).

## Threat Flags

None. This plan modified an enum→`ThemeMode` mapping extension, theme factory internals, test scaffolding, and the `SystemChrome` overlay wrapper. No network endpoints, no auth boundaries, no storage keys added (the existing `settings_theme` SharedPreferences key was already in place).

## Self-Check: PASSED

- Files created exist on disk: `test/unit/theme_wiring_test.dart` FOUND, `test/unit/dark_theme_contrast_test.dart` FOUND, `test/unit/settings_theme_mode_test.dart` FOUND.
- Commits exist in `git log --all`: 895c4cb FOUND, 620be76 FOUND, c80372e FOUND, 7b5bdc3 FOUND.
- Final-metadata commit pending (orchestrator will capture).
