---
phase: 37-dark-theme-migration
verified: 2026-04-18T10:17:00Z
status: human_needed
score: 5/5 must-haves verified
overrides_applied: 0
re_verification:
  previous_verified: 2026-04-18T08:07:07Z
  previous_status: gaps_found
  previous_score: 4/5
  gaps_closed:
    - "Dark theme renders with the slate-based palette end-to-end (SC5) — shadow layer"
  gaps_remaining: []
  regressions: []
  closure_plan: 37-06 (5 commits: ae5e7b2, 61393fb, c7845c4, 51cd53b, 0b7f5d6)
gaps: []
deferred: []
human_verification:
  - test: "Launch app on a real Android device with `flutter run --dart-define-from-file=config.json`; cycle System → Light → Dark via Settings → Display → Theme."
    expected: "All cards/heroes render with richer black shadow tint in Dark (Color(0x59000000)), lighter slate tint in Light (Color(0x14111827)). System-chrome (status bar / navigation bar) icon brightness flips immediately without navigating away. Setting persists across app restart."
    why_human: "Visual delta between shadow tints (35% black vs 8% slate) and perceived elevation is inherently visual; golden baselines confirm pixel-level change but only humans can judge whether the dark shadow reads as 'rich, legible elevation' rather than 'muddy halo' on real OLED/LCD hardware."
  - test: "Walk through MANUAL-QA.md §2 (22-screen walkthrough) in Dark mode: Home → Group Detail → Event Command Center → Ledger → Add Expense → Settle Up → Gear → Logistics → Vault → Memories → Activity → Settings."
    expected: "Every elevated surface (hero cards, list rows, floating action buttons, dialogs, bottom sheets) shows the darker shadow tint in Dark mode. No card appears 'flat' or loses separation from the background. No residual light-theme artifact (pale borders, unexpected white fills) on any screen."
    why_human: "Requires eye-on-device judgment of perceived depth and background separation across 22 screens; the 10 golden screens (Home/Group/Event/Ledger/Gear/Logistics/Vault/Memories/Onboarding/Settings-profile/Add-expense/Group-settle-up) cover only ~half of the surface area listed in MANUAL-QA.md."
  - test: "Toggle between Light and Dark 5 times in rapid succession; observe for flicker, stale shadows, or content jump."
    expected: "Smooth cross-fade via MaterialApp themeMode; no layout shift, no single-frame flash of the wrong theme, no shadow ghosting."
    why_human: "Real-time theme animation quality can only be evaluated by watching the transition on-device at 60/120 Hz refresh."
---

# Phase 37: Dark Theme Migration Verification Report

**Phase Goal:** Dark Theme Migration — Widget migration to `context.colors`, theme toggle, textMuted contrast (#17, #29, #31, #32)
**Verified:** 2026-04-18T10:17:00Z
**Status:** human_needed
**Re-verification:** Yes — after Plan 37-06 gap closure (previous status `gaps_found` at 4/5)

## Re-verification Summary

| Item | Previous | Current |
|------|----------|---------|
| Status | gaps_found | **human_needed** |
| Score | 4/5 | **5/5** |
| Open gaps | 1 (SC5 — elevation layer not theme-aware) | **0** |
| Regressions introduced | — | **0** (1088/3/0 preserved) |

Plan 37-06 closed the single remaining gap from the prior verification by (a) migrating 37 call sites across 32 feature/settings files from `AppShadowTokens.standard.*` to `context.shadows.*`, (b) fixing the golden harness to resolve shadows through a `Builder` + `context.shadows.raised`, (c) deleting the `AppShadowTokens.standard = light` alias in `shadow_tokens.dart`, (d) adding Check 4 to `tool/check_theme_purity.sh`, and (e) regenerating the 10 dark golden baselines. All four "missing" deliverables from gaps[0].missing independently reverified in this run.

The phase is now structurally complete. Status is **human_needed** (not `passed`) because elevation/shadow tint is an inherently visual outcome that golden baselines confirm at the pixel level but only on-device viewing in Dark mode can validate as "rich, legible depth" across all 22 screens listed in MANUAL-QA.md.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Zero direct `AppColorTokens.light.*` references in rendered widget code (enforced by lint or CI check) | ✓ VERIFIED | `grep -rn "AppColorTokens\.light\." lib/ \| grep -v "lib/core/theme/tokens/" \| grep -v "lib/core/theme/app_theme.dart" \| grep -v "lib/main.dart"` = 0. `bash tool/check_theme_purity.sh` exits 0 on all 4 checks. |
| 2 | Settings exposes a theme toggle (System / Light / Dark) persisted via SharedPreferences | ✓ VERIFIED | `ProfileDisplaySection` opens `ThemePickerSheet.show(context)`; sheet writes via `settingsProvider.notifier.setThemeMode(v)`; `theme_picker_test` (3 tests) asserts round-trip; `MaterialApp.router` consumes `settings.themeMode.toMaterialThemeMode()` in main.dart:184-185. |
| 3 | textMuted no longer used for functional text; contrast audit passes WCAG AA on all text/background pairs in both themes | ✓ VERIFIED | `test/unit/dark_theme_contrast_test.dart` — 11 WCAG assertions pass; `tool/check_theme_purity.sh` Check 3 enforces `// textMuted-decorative-justified:` justification window. |
| 4 | Spacing tokens adopted where semantically meaningful; remaining `Color(0xFF…)` hardcoded literals justified inline or removed | ✓ VERIFIED | Avatar slots + 4 gradient pairs + category colors promoted to tokens in Plan 04; Check 2 enforces 5-line `// design-token-justified:` window for any remaining literal. |
| 5 | Screenshot diffs show light theme unchanged and dark theme renders with the slate-based palette end-to-end | ✓ VERIFIED | **GAP CLOSED.** 0 `AppShadowTokens.standard.*` reads anywhere in `lib/` or `test/`. Alias deleted from `shadow_tokens.dart`. Harness reads via `context.shadows.raised` inside a Builder at lines 150 and 208. 10 dark golden PNGs regenerated with visible byte-delta (+363 to +687 bytes per file, consistent with `Color(0x59000000)` shadow tint replacing `Color(0x14111827)`). 10 light baselines byte-identical (no regression). `flutter test test/goldens/` passes 10/10 without `--update-goldens`. |

**Score:** 5/5 truths verified

### Deliverable Closure — Previous `gaps[0].missing`

Each item from the prior VERIFICATION.md re-checked against current repo state.

| # | Missing deliverable | Current state | Status |
|---|---------------------|---------------|--------|
| 1 | Replace every `AppShadowTokens.standard.raised\|floating` read in `lib/features/` with `context.shadows.*` (32 files, 37 sites) | `grep -rn 'AppShadowTokens\.standard\.' lib/features/` = **0**; `grep -rn 'context\.shadows\.' lib/features/` = **49** (37 new + 12 pre-existing from Wave 2) | ✓ CLOSED |
| 2 | Fix `golden_harness.dart` lines 149/205 to read `context.shadows.raised` via a Builder | Harness now has `Builder(builder: (context) => ...)` at lines 144 and 203, each containing `boxShadow: context.shadows.raised` at lines 150 and 208 | ✓ CLOSED |
| 3 | Deprecate the `AppShadowTokens.standard` alias OR document remaining uses with `// design-token-justified:` + extend purity script with Check 4 | Default branch taken: alias deleted (not present in shadow_tokens.dart). Doc comment at line 7-8 now points consumers to `context.shadows.*`. Check 4 added to `tool/check_theme_purity.sh` (no-justification-window — any occurrence is a pure regression signal). | ✓ CLOSED |
| 4 | Regenerate 10 dark-theme golden baselines after the harness fix | Commit `0b7f5d6` regenerated all 10 `*_dark.png` files with byte-size delta ranging +363 to +687 bytes. Light baselines unchanged (byte-identical). `flutter test test/goldens/` → 10 pass without `--update-goldens`. | ✓ CLOSED |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/core/theme/tokens/shadow_tokens.dart` | No `standard` alias; `.light` + `.dark` only | ✓ VERIFIED | `grep -n 'standard' shadow_tokens.dart` → 0 matches. `.light` at line 26, `.dark` at line 57. Doc comment at 7-8 steers consumers. |
| `tool/check_theme_purity.sh` | 4-check guard; Check 4 added | ✓ VERIFIED | `grep -c 'Check 4'` = 2 (header + echo label). Script runs 4 checks sequentially, outputs `Theme purity check PASS` on clean repo, exit code 0. Still executable (mode `-rwxr-xr-x@`). |
| `test/goldens/golden_harness.dart` | Builder wrapping + `context.shadows.raised` | ✓ VERIFIED | `Builder(` at lines 144, 203. `context.shadows.raised` at lines 150, 208. No `AppShadowTokens.standard.*` anywhere in file. |
| `test/goldens/goldens/*_dark.png` | 10 regenerated baselines | ✓ VERIFIED | 10 files under `test/goldens/goldens/*_dark.png`. Commit `0b7f5d6` touched all 10 with Bin size delta. |
| 32 feature/settings source files | Migrated to `context.shadows.*` | ✓ VERIFIED | All 32 files in 37-06-SUMMARY's `files_modified` list show `context.shadows.raised\|floating` and zero `AppShadowTokens.standard`. Spot-checks: `balance_hero_card.dart` lines 64,122 ✓; `add_expense_screen.dart` lines 374,394,475,528 ✓. |
| `lib/core/theme/app_theme.dart` | Light ThemeData registers `AppShadowTokens.light` explicitly (no alias) | ✓ VERIFIED | Executor auto-fixed a Rule-3 blocker — light ThemeData line 181 now uses `.light` instead of `.standard`. Behaviour identical. |
| `test/unit/design_tokens_test.dart` | 5 `.standard` refs swapped to `.light` | ✓ VERIFIED | Behavior identical (alias was `= light`), deletion would have compile-failed otherwise. Full suite remains 1088/3/0 — test body still valid. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| 32 feature/settings widgets | `Theme.of(context).extension<AppShadowTokens>()` | `context.shadows.raised \| .floating` | ✓ WIRED | 49 call sites across `lib/features/` now read via the theme-aware extension; dark ThemeData registers `AppShadowTokens.dark`, so these reads resolve differently between themes. |
| `golden_harness.dart` card builders | `context.shadows.raised` | `Builder(builder: (context) => ...)` | ✓ WIRED | Builder confines the shadow read to a theme-scoped BuildContext — defensive against future refactors inserting a Theme override. |
| `tool/check_theme_purity.sh` Check 4 | `AppShadowTokens.standard` regression guard | `grep -rn 'AppShadowTokens\.standard\.' lib/ --include='*.dart' \| grep -v '^lib/core/theme/tokens/'` | ✓ WIRED | Inserted before final exit block. Exits 1 with `::error::` annotation on any match. Negative-test verified in Task 4. |
| `.github/workflows/release_android.yml:49` | `tool/check_theme_purity.sh` | `run: bash tool/check_theme_purity.sh` | ✓ WIRED | CI workflow was wired in Plan 37-05; Check 4 runs automatically on every release build. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| Any feature hero card | `context.shadows.raised` | `Theme.of(context).extension<AppShadowTokens>()` via `domain_aliases.dart:29` | Yes — resolves to `.light` or `.dark` based on `Theme.of(context).brightness` | ✓ FLOWING |
| Golden harness hero card | `context.shadows.raised` (via Builder) | Same extension, but now under a Builder-created context | Yes — golden output captures the tint for current theme | ✓ FLOWING |
| Prior "masked alias" state | `AppShadowTokens.standard.raised` | DELETED (compile-error path if reintroduced) | N/A | ✓ REMOVED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Purity script 4/4 PASS | `bash tool/check_theme_purity.sh` | Outputs all 4 check labels + `Theme purity check PASS`, exit 0 | ✓ PASS |
| Zero shadow-alias reads in features | `grep -rn 'AppShadowTokens\.standard\.' lib/features/ --include='*.dart' \| wc -l` | 0 | ✓ PASS |
| Zero shadow-alias refs repo-wide | `grep -rn 'AppShadowTokens\.standard' lib/ test/ --include='*.dart'` | (no output — 0 matches) | ✓ PASS |
| Harness uses `context.shadows.raised` | `grep -n 'context\.shadows\.' test/goldens/golden_harness.dart` | 2 hits (lines 150, 208) | ✓ PASS |
| Harness wraps in Builder | `grep -n 'Builder(' test/goldens/golden_harness.dart` | 2 hits (lines 144, 203) | ✓ PASS |
| Alias line deleted | `grep -n 'static final AppShadowTokens standard' lib/core/theme/tokens/shadow_tokens.dart` | (no output — 0 matches) | ✓ PASS |
| 10 dark baselines exist | `ls test/goldens/goldens/*_dark.png \| wc -l` | 10 | ✓ PASS |
| 10 dark baselines regenerated by commit `0b7f5d6` | `git log --stat 0b7f5d6` | 10 `Bin N -> M bytes` entries, all growing by +363…+687 bytes | ✓ PASS |
| Full test suite green | `flutter test` | `+1088 ~3: All tests passed!` | ✓ PASS |
| Flutter analyze 0 errors | `flutter analyze` | `348 issues found.` — 0 errors, all info-level, baseline-matching | ✓ PASS |
| Check 4 wired into CI | `grep -c 'Check 4' tool/check_theme_purity.sh` | 2 | ✓ PASS |
| Golden re-run passes without regen flag | `flutter test test/goldens/` | 10 pass (per executor); 10 golden tests all green in full-suite run at lines 1074-1082 | ✓ PASS |

### Requirements Coverage

**Note on REQUIREMENTS.md:** The current `.planning/REQUIREMENTS.md` is scoped to v2.2 (Profile Page) and does not contain explicit `DARK-01..DARK-05` entries. The DARK-* requirement IDs are carried in the ROADMAP Phase 37 summary (lines 100-109) and every plan's frontmatter. Treating the ROADMAP entries as the authoritative source since REQUIREMENTS.md is stale relative to v2.4.

| Requirement | Source Plan(s) | Description (from ROADMAP + plan context) | Status | Evidence |
|-------------|----------------|-------------------------------------------|--------|----------|
| DARK-01 | 37-02, 37-03a, 37-03b, 37-03c, 37-03d, 37-06 | Every widget reads colors via `context.colors` | ✓ SATISFIED | Check 1 passes; 0 unjustified `AppColorTokens.light.*` reads. Plan 37-06 extends coverage to shadows via `context.shadows.*`. |
| DARK-02 | 37-01, 37-02, 37-03a-d, 37-04, 37-05 | Dark theme toggle persisted in Settings | ✓ SATISFIED | `ThemePickerSheet` → `settingsProvider.setThemeMode` → `SharedPreferences`; `theme_picker_test` asserts round-trip. |
| DARK-03 | 37-02, 37-03a-d, 37-05 | textMuted removed from functional roles; WCAG AA pass | ✓ SATISFIED | 11 contrast assertions in `dark_theme_contrast_test`; Check 3 enforces `// textMuted-decorative-justified:` window. |
| DARK-04 | 37-02, 37-03a-d, 37-04 | `AppSpacingTokens.standard` actively used | ✓ SATISFIED | ~107+ opportunistic adoptions across waves; ThemePickerSheet and new profile sections use `context.spacing.*`. |
| DARK-05 | 37-04, 37-05 | Hardcoded `Color(0xFF…)` literals eliminated or justified | ✓ SATISFIED | Avatar slots / gradient pairs / category colors promoted; Check 2 enforces 5-line justification window for remainders. |

No orphan requirement IDs — every ID from every plan frontmatter is satisfied. Plan 37-06 re-declared `requirements: [DARK-01]` because the shadow sweep extends the same `context.*` token contract to elevation.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | No new anti-patterns. Prior `AppShadowTokens.standard` alias warning is ELIMINATED — alias deleted, Check 4 guards against regression. |

### Human Verification Required

Three items requiring on-device validation. All three are about visual/motion quality that the automated golden + contrast checks bound but cannot fully ratify:

#### 1. Theme toggle on real device

**Test:** Launch app on Android device via `flutter run --dart-define-from-file=config.json`. Cycle System → Light → Dark via Settings → Display → Theme.
**Expected:** All cards/heroes render with richer black shadow tint in Dark (`Color(0x59000000)`, 35% black) vs lighter slate tint in Light (`Color(0x14111827)`, 8% slate). System-chrome status bar / navigation bar icon brightness flips immediately. Setting persists across app restart.
**Why human:** Perceived elevation is inherently visual; goldens confirm pixel-level change, but only humans can judge whether the dark shadow reads as "rich legible depth" vs "muddy halo" on OLED/LCD hardware.

#### 2. MANUAL-QA.md 22-screen walkthrough in Dark

**Test:** Walk through every screen listed in `.planning/phases/37-dark-theme-migration/MANUAL-QA.md` §2 in Dark mode: Home, Group Detail, Event Command Center, Ledger, Add Expense, Settle Up, Gear, Logistics, Vault, Memories, Activity, Settings, and 10 more sub-screens.
**Expected:** Every elevated surface shows the darker shadow tint. No card appears flat. No residual light-theme artifact (pale borders, unexpected white fills) on any screen.
**Why human:** The 10 golden screens cover only a subset of MANUAL-QA.md's 22-screen inventory; remaining surfaces need eye-on-device verification.

#### 3. Theme-toggle motion quality

**Test:** Toggle between Light and Dark 5 times in rapid succession.
**Expected:** Smooth cross-fade; no flicker, no single-frame flash of wrong theme, no shadow ghosting.
**Why human:** Real-time theme-change animation on 60/120 Hz displays cannot be evaluated programmatically.

### Gaps Summary

None. All 5 success criteria are now structurally verified. The phase is mechanically complete — all mandatory deliverables, CI guards, test suites, and golden baselines are in place. The three outstanding human-verification items above are visual/motion-quality checks that belong in MANUAL-QA.md's on-device sign-off step, not in the automated verification layer.

If all three human items pass on-device, Phase 37 is fully closed and can be marked complete on the ROADMAP. If any human item reveals a visual regression (e.g., a screen where shadows look wrong), a small Plan 37-07 follow-up would be justified — but based on the golden-suite green + Check 4 CI guard + 1088/3/0 test pass, no further structural gap is expected.

---

_Re-verified: 2026-04-18T10:17:00Z_
_Verifier: Claude (gsd-verifier)_
_Gap-closure plan: 37-06 (5 commits: ae5e7b2, 61393fb, c7845c4, 51cd53b, 0b7f5d6)_
