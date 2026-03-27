---
phase: 12
slug: expense-logistics-provider-rewiring
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-28
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter test (dart test runner) |
| **Config file** | `pubspec.yaml` (test dependencies: mocktail, fake_cloud_firestore, firebase_auth_mocks) |
| **Quick run command** | `flutter test test/unit/` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/unit/`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 12-01-01 | 01 | 1 | FIN-01 | widget | `flutter test test/features/ledger/payer_currency_rewiring_test.dart` | created by task | pending |
| 12-02-01 | 02 | 1 | EVT-08 | unit | `flutter test test/unit/sub_group_service_test.dart` | exists (extended by task) | pending |
| 12-02-02 | 02 | 1 | EVT-08 | widget | `flutter test test/features/logistics_screen_mutations_test.dart` | created by task | pending |

*Status: pending / green / red / flaky*

**Notes:**
- Plan 01 Task 1 creates `test/features/ledger/payer_currency_rewiring_test.dart` inline (TDD task — tests written before fixes).
- Plan 02 Task 1 extends existing `test/unit/sub_group_service_test.dart` with `updateSubGroup` tests.
- Plan 02 Task 2 creates `test/features/logistics_screen_mutations_test.dart` inline.
- No Wave 0 stubs required — each task creates its own test files as part of execution.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Payer dropdown renders in UI | FIN-01 | Widget rendering with real Riverpod scope | Build app, create expense as event creator, verify payer dropdown appears |
| Currency label shows event currency | FIN-01 | Visual verification of currency display | Create event with non-OMR currency, open expense form, verify currency label |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify commands
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] No Wave 0 stubs needed — tests created inline by tasks
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
