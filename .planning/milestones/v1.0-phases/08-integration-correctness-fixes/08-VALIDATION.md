---
phase: 8
slug: integration-correctness-fixes
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-27
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (built-in with Flutter SDK) |
| **Config file** | none — standard `flutter test` discovery |
| **Quick run command** | `flutter test test/unit/ test/features/groups/` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/unit/ test/features/groups/`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01 | 01 | 1 | D-05, D-06 | unit | `flutter test test/unit/balance_cache_repository_test.dart` | ✅ | ⬜ pending |
| 02-01 | 02 | 1 | EVT-08, D-10 | unit | `flutter test test/unit/provider_swap_test.dart` | ❌ W0 | ⬜ pending |
| 02-02 | 02 | 1 | EVT-08 | unit | `flutter test test/unit/` | ✅ | ⬜ pending |
| 03-01 | 03 | 2 | FIN-04, D-01, D-04 | unit | `flutter test test/unit/formatters_test.dart` | ✅ (extend) | ⬜ pending |
| 03-02 | 03 | 2 | FIN-04, D-09 | widget | `flutter test test/features/groups/group_settle_up_screen_test.dart` | ✅ (extend) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/unit/provider_swap_test.dart` — stubs for EVT-08 / Fix #1: provider swap returns non-empty participants for Firestore-only event
- [ ] `test/unit/formatters_test.dart` — extend with `formatShortMonthDay` test cases
- [ ] `test/features/groups/group_settle_up_screen_test.dart` — extend with two new test cases: happy path (event name + date) and fallback (event type)

*Existing `balance_cache_repository_test.dart` already covers Fix #3 behavior — no gap there.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
