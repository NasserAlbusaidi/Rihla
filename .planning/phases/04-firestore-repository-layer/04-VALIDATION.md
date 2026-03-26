---
phase: 4
slug: firestore-repository-layer
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-26
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Flutter Test (built-in) + fake_cloud_firestore 4.1.0+1 |
| **Config file** | None — standard `flutter test` discovery |
| **Quick run command** | `flutter test test/unit/ --no-pub` |
| **Full suite command** | `flutter test --no-pub` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/unit/ --no-pub`
- **After every plan wave:** Run `flutter test --no-pub`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | MIG-01 | unit | `flutter test test/unit/expense_service_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 | 1 | MIG-01 | unit | `flutter test test/unit/settlement_service_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 04-01-03 | 01 | 1 | MIG-01 | unit | `flutter test test/unit/gear_service_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 04-01-04 | 01 | 1 | MIG-01 | unit | `flutter test test/unit/sub_group_service_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 04-01-05 | 01 | 1 | MIG-01 | unit | `flutter test test/unit/activity_service_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 04-02-01 | 02 | 1 | MIG-02 | unit | `flutter test test/unit/expense_service_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 04-03-01 | 03 | 2 | MIG-03 | unit | grep -rn 'SyncService' lib/ (expect 0 results) | Exists (delete) | ⬜ pending |
| 04-04-01 | 04 | 2 | MIG-04 | unit | `flutter test test/unit/balance_calculations_test.dart --no-pub` | ✅ Exists | ⬜ pending |
| 04-05-01 | 05 | 1 | MIG-05 | unit | `flutter test test/unit/firestore_repository_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 04-05-02 | 05 | 2 | MIG-05 | grep | grep -rn 'FirebaseFirestore.instance' lib/ (expect 0 outside FirestoreRepository) | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/unit/expense_service_test.dart` — stubs for MIG-01, MIG-02 (expenses)
- [ ] `test/unit/settlement_service_test.dart` — stubs for MIG-01, MIG-02 (settlements)
- [ ] `test/unit/gear_service_test.dart` — stubs for MIG-01 (gear)
- [ ] `test/unit/sub_group_service_test.dart` — stubs for MIG-01 (sub-groups)
- [ ] `test/unit/activity_service_test.dart` — stubs for MIG-01 (activity)
- [ ] `test/unit/firestore_repository_test.dart` — stubs for MIG-05 base class contract
- [ ] `test/unit/balance_cache_repository_test.dart` — stubs for MIG-04 narrow SQLite interface
- [ ] `test/unit/lazy_migration_service_test.dart` — stubs for D-18 lazy migration
- [ ] `test/unit/connectivity_provider_test.dart` — stubs for ConnectivityNotifier Firestore ping

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Offline write queues locally and syncs on reconnect | MIG-01 | Requires airplane mode toggle on real device | 1. Enable airplane mode 2. Add expense 3. Disable airplane mode 4. Verify expense in Firestore console |
| Cross-device real-time propagation | MIG-02 | Requires two physical devices | 1. Open app on device A and B 2. Add expense on A 3. Verify appears on B within seconds |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
