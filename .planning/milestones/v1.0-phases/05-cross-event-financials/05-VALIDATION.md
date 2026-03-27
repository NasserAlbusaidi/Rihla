---
phase: 5
slug: cross-event-financials
status: approved
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-27
---

# Phase 5 -- Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (Flutter SDK built-in) + fake_cloud_firestore 4.1.0+1 + mocktail 1.0.4 |
| **Config file** | none -- standard Flutter test runner |
| **Quick run command** | `flutter test test/unit/` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/unit/`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-00-01 | 00 | 0 | FIN-02, FIN-05, FIN-06 | unit | `flutter test test/unit/group_balance_provider_test.dart` | W0 creates | pending |
| 05-00-02 | 00 | 0 | GRP-05 | unit | `flutter test test/unit/group_activity_service_test.dart` | W0 creates | pending |
| 05-00-03 | 00 | 0 | GRP-04 | widget | `flutter test test/features/group_detail_screen_test.dart` | W0 creates | pending |
| 05-00-04 | 00 | 0 | FIN-03 | widget | `flutter test test/features/group_balance_card_test.dart` | W0 creates | pending |
| 05-00-05 | 00 | 0 | FIN-04 | widget | `flutter test test/features/group_settle_up_screen_test.dart` | W0 creates | pending |
| 05-01-01 | 01 | 1 | FIN-05, FIN-04, GRP-05 | unit | `flutter test test/unit/group_settlement_service_test.dart test/unit/group_activity_service_test.dart` | W0 stubs | pending |
| 05-02-01 | 02 | 1 | FIN-01, FIN-07 | unit | `flutter test test/unit/balance_calculations_test.dart` | exists (extend) | pending |
| 05-03-01 | 03 | 2 | FIN-02, FIN-05, FIN-06 | unit | `flutter test test/unit/group_balance_provider_test.dart` | W0 stubs | pending |
| 05-04-01 | 04 | 3 | FIN-03, FIN-06 | widget | `flutter test test/features/group_balance_card_test.dart` | W0 stubs | pending |
| 05-05-01 | 05 | 4 | GRP-04, FIN-01, FIN-02, FIN-03 | widget | `flutter test test/features/group_detail_screen_test.dart` | W0 stubs | pending |
| 05-06-01 | 06 | 5 | FIN-04, FIN-07, GRP-05 | widget | `flutter test test/features/group_settle_up_screen_test.dart` | W0 stubs | pending |

*Status: pending -- green -- red -- flaky*

---

## Wave 0 Requirements

- [ ] `test/unit/group_balance_provider_test.dart` -- stubs for FIN-02, FIN-05, FIN-06 (use ProviderContainer + fake services)
- [ ] `test/unit/group_activity_service_test.dart` -- stubs for GRP-05 (use FakeFirebaseFirestore, mirror activity_service_test.dart)
- [ ] `test/unit/group_settlement_service_test.dart` -- stubs for FIN-04, FIN-05 (use FakeFirebaseFirestore)
- [ ] `test/features/group_detail_screen_test.dart` -- stubs for GRP-04 (widget test with overridden providers)
- [ ] `test/features/group_balance_card_test.dart` -- stubs for FIN-03 (expand/collapse interaction test)
- [ ] `test/features/group_settle_up_screen_test.dart` -- stubs for FIN-04 (widget test with mock groupBalancesProvider)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Balance toggle UX switches between per-event and group view | FIN-03 | Visual animation smoothness | Tap toggle, verify animated transition between views |
| Settle-up confirmation dialog flow | FIN-04 | Multi-step dialog interaction | Start settle-up, edit amount, confirm, verify balance updates |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 15s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved
