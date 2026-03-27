---
phase: 6
slug: testing-and-coverage
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-27
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (Flutter 3.41.5 SDK) |
| **Config file** | None — standard `flutter test` discovery |
| **Quick run command** | `flutter test test/unit/balance_calculations_test.dart` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test`
- **After every plan wave:** Run `flutter test --coverage`
- **Before `/gsd:verify-work`:** Full suite must be green, filtered coverage >= 80%
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 1 | TST-01 | unit | `flutter test test/unit/balance_calculations_test.dart` | ✅ needs expansion | ⬜ pending |
| 06-01-02 | 01 | 1 | TST-01 | unit | `flutter test test/unit/settlement_optimization_test.dart` | ✅ needs expansion | ⬜ pending |
| 06-01-03 | 01 | 1 | TST-01 | unit | `flutter test test/unit/money_serializer_test.dart` | ✅ verify coverage | ⬜ pending |
| 06-01-04 | 01 | 1 | TST-01 | unit | `flutter test test/unit/firebase_model_roundtrip_test.dart` | ❌ W0 | ⬜ pending |
| 06-01-05 | 01 | 1 | TST-01 | unit | `flutter test test/unit/formatters_test.dart` | ✅ verify coverage | ⬜ pending |
| 06-02-01 | 02 | 2 | TST-02 | widget | `flutter test test/features/groups/group_screens_test.dart` | ✅ needs expansion | ⬜ pending |
| 06-02-02 | 02 | 2 | TST-02 | widget | `flutter test test/features/events/create_event_test.dart` | ✅ needs expansion | ⬜ pending |
| 06-02-03 | 02 | 2 | TST-02 | widget | `flutter test test/features/home/home_screen_groups_test.dart` | ✅ verify coverage | ⬜ pending |
| 06-02-04 | 02 | 2 | TST-02 | widget | `flutter test test/features/groups/group_settle_up_screen_test.dart` | ✅ needs expansion | ⬜ pending |
| 06-02-05 | 02 | 2 | TST-02 | widget | `flutter test test/features/ledger_test.dart` | ✅ needs expansion | ⬜ pending |
| 06-02-06 | 02 | 2 | TST-02 | widget | `flutter test test/features/events/event_command_center_test.dart` | ✅ needs expansion | ⬜ pending |
| 06-03-01 | 03 | 3 | TST-06 | integration | `flutter test test/integration/offline_scenario_test.dart` | ❌ W0 | ⬜ pending |
| 06-04-01 | 04 | 3 | TST-05 | coverage | `flutter test --coverage` | ❌ CI step | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Fix `test/features/command_center_test.dart` — delete or redirect (imports deleted widget)
- [ ] Fix `test/unit/group_service_test.dart` — override Firebase-touching providers with mocks
- [ ] Fix `test/features/events/group_detail_events_test.dart` — diagnose 4 failures, fix assertions
- [ ] Fix `test/unit/group_join_test.dart` — override Firebase provider
- [ ] Create `test/integration/offline_scenario_test.dart` — stub for 3 offline scenarios per D-12
- [ ] Create `test/unit/firebase_model_roundtrip_test.dart` — stub for all model toFirestore/fromFirestore (D-04)
- [ ] Add CI coverage step to `.github/workflows/release_android.yml` (D-14, D-17)
- [ ] Verify `lcov` installable in CI runner

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| CI coverage comment appears on PR | TST-05 | Requires actual GitHub PR context | Push branch, open PR, verify lcov-reporter-action posts coverage comment |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
