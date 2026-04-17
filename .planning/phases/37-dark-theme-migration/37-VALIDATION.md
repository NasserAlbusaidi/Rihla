---
phase: 37
slug: dark-theme-migration
status: draft
nyquist_compliant: false
wave_0_complete: false
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
| 37-01-* | 01 | 1 | DARK-01 | — | MaterialApp wires darkTheme; SystemChrome theme-aware | unit | `flutter test test/unit/theme_wiring_test.dart` | ❌ W0 | ⬜ pending |
| 37-02-* | 02 | 2 | DARK-01 | — | shared widgets render in both themes without throwing | widget | `flutter test test/features/shared_widgets/` | ❌ W0 | ⬜ pending |
| 37-03a-* | 03a | 3 | DARK-01, DARK-03 | — | auth/onboarding/settings/home features render in both themes | widget | `flutter test test/features/{auth,onboarding,settings,home}/` | ⚠️ partial | ⬜ pending |
| 37-03b-* | 03b | 3 | DARK-01, DARK-03 | — | groups feature renders in both themes | widget | `flutter test test/features/groups/` | ⚠️ partial | ⬜ pending |
| 37-03c-* | 03c | 3 | DARK-01, DARK-03 | — | events/ledger features render in both themes | widget | `flutter test test/features/{events,ledger}/` | ⚠️ partial | ⬜ pending |
| 37-03d-* | 03d | 3 | DARK-01, DARK-03 | — | gear/logistics/vault/memories/activity features render in both themes | widget | `flutter test test/features/{gear,logistics,vault,memories,activity}/` | ⚠️ partial | ⬜ pending |
| 37-04-* | 04 | 4 | DARK-04 | — | gradient/avatar/category tokens resolve in both themes; spacing tokens applied on touched files | unit | `flutter test test/unit/token_promotions_test.dart` | ❌ W0 | ⬜ pending |
| 37-05-* | 05 | 5 | DARK-02, DARK-05 | — | Settings theme picker persists; goldens unchanged on light, present on dark; CI guard rejects violations | unit + widget + integration | `flutter test test/features/settings/theme_picker_test.dart && flutter test test/goldens/ && bash tool/check_theme_purity.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

> **Note:** The planner expands `*` to per-task IDs (e.g., `37-01-01`, `37-01-02`) in PLAN.md frontmatter. This table is the contract — each task PLAN.md must point back to a row here.

---

## Wave 0 Requirements

Test files that must exist (or be stubbed by the first task touching the area) before downstream tasks can verify:

- [ ] `test/unit/theme_wiring_test.dart` — asserts `AppTheme.darkTheme.brightness == Brightness.dark`, `AppTheme.lightTheme.brightness == Brightness.light`, both wire `AppColorTokens` correctly into `extensions`. **Created in Plan 01.**
- [ ] `test/unit/dark_theme_contrast_test.dart` — walks every documented `(text, background)` pair in `AppColorTokens.dark` and asserts WCAG AA (4.5:1 normal, 3:1 large/UI). Reuses contrast helper from `test/unit/design_tokens_test.dart:16-37`. **Created in Plan 01.**
- [ ] `test/unit/token_promotions_test.dart` — asserts `AppGroupAvatarColors.lightSlots.length == 5 && darkSlots.length == 5`, `AppGradients.terracotta.colors.length == 2`, etc. **Created in Plan 04.**
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
- [ ] Wave 0 covers all MISSING references (theme_wiring, dark_theme_contrast, token_promotions, theme_picker, goldens, check_theme_purity)
- [ ] No watch-mode flags (`--watch` forbidden in any plan command)
- [ ] Feedback latency < 90s
- [ ] `nyquist_compliant: true` set in frontmatter once planner expands per-task IDs

**Approval:** pending
