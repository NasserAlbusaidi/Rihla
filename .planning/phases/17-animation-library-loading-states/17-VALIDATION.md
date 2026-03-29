---
phase: 17
slug: animation-library-loading-states
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-29
---

# Phase 17 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (SDK-bundled) |
| **Config file** | none — uses flutter test runner |
| **Quick run command** | `flutter test test/unit/skeleton_loader_test.dart test/unit/tap_bounce_test.dart test/unit/fade_in_list_test.dart test/unit/staggered_grid_test.dart` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/unit/skeleton_loader_test.dart test/unit/tap_bounce_test.dart test/unit/fade_in_list_test.dart test/unit/staggered_grid_test.dart`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 17-01-01 | 01 | 1 | NAV-05 | unit/widget | `flutter test test/unit/skeleton_loader_test.dart` | :x: W0 | :white_large_square: pending |
| 17-01-02 | 01 | 1 | PLSH-03 | unit/widget | `flutter test test/unit/tap_bounce_test.dart` | :x: W0 | :white_large_square: pending |
| 17-01-03 | 01 | 1 | PLSH-03 | unit/widget | `flutter test test/unit/fade_in_list_test.dart` | :x: W0 | :white_large_square: pending |
| 17-01-04 | 01 | 1 | PLSH-03 | unit/widget | `flutter test test/unit/staggered_grid_test.dart` | :x: W0 | :white_large_square: pending |

*Status: :white_large_square: pending · :white_check_mark: green · :x: red · :warning: flaky*

---

## Wave 0 Requirements

- [ ] `test/unit/skeleton_loader_test.dart` — stubs for NAV-05 skeleton rendering
- [ ] `test/unit/tap_bounce_test.dart` — stubs for PLSH-03 tap bounce and dispose
- [ ] `test/unit/fade_in_list_test.dart` — stubs for PLSH-03 staggered list
- [ ] `test/unit/staggered_grid_test.dart` — stubs for PLSH-03 staggered grid

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Shimmer warm-neutral tone matches earthy palette | NAV-05 | Visual perception — automated tests verify colors but not perceived warmth | Render skeleton on device, compare shimmer base/highlight against AppColors.surfaceLight and AppColors.surface |
| Animation feels "crisp & confident" (D-03) | PLSH-03 | Subjective motion personality | Play fade-in list, tap bounce, staggered grid on device — motion should feel calm, assured, no drama |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
