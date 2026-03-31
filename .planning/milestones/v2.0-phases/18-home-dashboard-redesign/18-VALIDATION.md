---
phase: 18
slug: home-dashboard-redesign
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-29
---

# Phase 18 -- Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (built-in) + mocktail |
| **Config file** | `pubspec.yaml` (test dependencies already configured) |
| **Quick run command** | `flutter test test/features/home/` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/features/home/`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 18-01-01 | 01 | 1 | NAV-01, NAV-02 | unit | `flutter test test/unit/color_tokens_test.dart` | Created inline (TDD task) | pending |
| 18-01-02 | 01 | 1 | NAV-02 | unit | `flutter test test/unit/cross_group_balance_test.dart test/unit/dashboard_providers_test.dart` | Created inline (TDD task) | pending |
| 18-02-01 | 02 | 2 | NAV-01, NAV-02 | widget | `flutter test test/features/home/balance_hero_card_test.dart` | Created inline (TDD task) | pending |
| 18-02-02 | 02 | 2 | NAV-01, NAV-06 | widget | `flutter test test/features/home/widgets_test.dart` | Created inline (TDD task) | pending |
| 18-03-01 | 03 | 3 | NAV-01, NAV-02, NAV-04, NAV-06 | integration | `flutter test test/features/home/home_screen_dashboard_test.dart` | Created first in Task 1 (TDD RED) | pending |
| 18-03-02 | 03 | 3 | NAV-04 | unit | `flutter analyze lib/features/groups/widgets/group_card.dart` | N/A (modification) | pending |
| 18-03-03 | 03 | 3 | NAV-01, NAV-02, NAV-04, NAV-06 | integration | `flutter test test/features/home/ && flutter analyze` | Tests exist from Task 1 | pending |
| 18-03-04 | 03 | 3 | All | manual | Visual verification on device | N/A (checkpoint) | pending |

*Status: pending / green / red / flaky*

---

## Nyquist Compliance Rationale

All three plans satisfy the Nyquist rule (every task has automated verification):

- **Plan 01 (Wave 1):** Both tasks are `tdd="true"`. Task 1 creates `test/unit/color_tokens_test.dart` inline before implementation. Task 2 creates `test/unit/cross_group_balance_test.dart` and `test/unit/dashboard_providers_test.dart` inline before implementation. No separate Wave 0 needed -- TDD tasks create their own test files as part of the RED phase.

- **Plan 02 (Wave 2):** Both tasks are `tdd="true"`. Task 1 creates `test/features/home/balance_hero_card_test.dart` inline. Task 2 creates `test/features/home/widgets_test.dart` inline. Same rationale -- TDD tasks write tests first.

- **Plan 03 (Wave 3):** Restructured so Task 1 writes all integration tests FIRST (TDD RED phase) before Tasks 2-3 implement production code. Task 1 creates `test/features/home/home_screen_dashboard_test.dart` and updates `test/features/home/home_screen_groups_test.dart`. Tasks 2-3 are the GREEN phase -- implementation that makes those tests pass. Task 4 is a human-verify checkpoint.

No Wave 0 stubs are needed because TDD tasks create their own test files as their first action.

---

## Wave 0 Requirements

None needed. All plans use inline TDD (`tdd="true"` tasks) which create test files as part of their RED phase. Plan 03 was restructured so that Task 1 (test writing) executes before Tasks 2-3 (implementation), eliminating the original dependency gap where implementation ran before tests existed.

*Existing test infrastructure (mocktail, provider overrides) covers framework needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 60fps scroll performance | NAV-04 (SC4) | Requires physical device + DevTools Performance view | Run on mid-range Android, scroll group list, check no frame > 16ms |
| Visual color-coding accuracy | NAV-01 (SC1) | Widget tests can check semantics but not visual rendering | Verify green/red/gray balance colors render correctly on device |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or TDD inline test creation
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 not needed -- TDD tasks create tests inline; Plan 03 restructured for tests-first
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** ready
