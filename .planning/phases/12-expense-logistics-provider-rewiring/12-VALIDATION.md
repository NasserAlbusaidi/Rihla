---
phase: 12
slug: expense-logistics-provider-rewiring
status: draft
nyquist_compliant: false
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
| 12-01-01 | 01 | 1 | FIN-01 | unit | `flutter test test/unit/currency_derivation_test.dart` | ❌ W0 | ⬜ pending |
| 12-01-02 | 01 | 1 | FIN-01 | unit | `flutter test test/unit/payer_override_test.dart` | ❌ W0 | ⬜ pending |
| 12-02-01 | 02 | 1 | EVT-08 | unit | `flutter test test/unit/logistics_wiring_test.dart` | ❌ W0 | ⬜ pending |
| 12-02-02 | 02 | 1 | EVT-08 | unit | `flutter test test/unit/sub_group_service_test.dart` | ❌ W0 | ⬜ pending |
| 12-03-01 | 03 | 2 | FIN-01 | unit | `flutter test test/unit/` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/unit/currency_derivation_test.dart` — stubs for FIN-01 currency fix
- [ ] `test/unit/payer_override_test.dart` — stubs for FIN-01 isLeader derivation
- [ ] `test/unit/logistics_wiring_test.dart` — stubs for EVT-08 logistics stub wiring
- [ ] `test/unit/sub_group_service_test.dart` — stubs for EVT-08 updateSubGroup method

*Existing test infrastructure covers framework needs — no new dependencies required.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Payer dropdown renders in UI | FIN-01 | Widget rendering with real Riverpod scope | Build app, create expense as event creator, verify payer dropdown appears |
| Currency label shows event currency | FIN-01 | Visual verification of currency display | Create event with non-OMR currency, open expense form, verify currency label |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
