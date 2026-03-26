---
phase: 3
slug: events
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-26
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test + fake_cloud_firestore 4.1.0+1 + mocktail 1.0.4 |
| **Config file** | `pubspec.yaml` (dev_dependencies) |
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
| 03-01-01 | 01 | 1 | EVT-01 | unit | `flutter test test/unit/event_model_test.dart` | ❌ W0 | ⬜ pending |
| 03-01-02 | 01 | 1 | EVT-02 | unit | `flutter test test/unit/event_type_test.dart` | ❌ W0 | ⬜ pending |
| 03-02-01 | 02 | 1 | EVT-03 | unit | `flutter test test/unit/event_service_test.dart` | ❌ W0 | ⬜ pending |
| 03-02-02 | 02 | 1 | EVT-04 | unit | `flutter test test/unit/event_modules_test.dart` | ❌ W0 | ⬜ pending |
| 03-03-01 | 03 | 2 | EVT-05 | unit | `flutter test test/unit/gear_seeding_test.dart` | ❌ W0 | ⬜ pending |
| 03-03-02 | 03 | 2 | EVT-06 | widget | `flutter test test/features/events/` | ❌ W0 | ⬜ pending |
| 03-04-01 | 04 | 2 | EVT-07 | widget | `flutter test test/features/events/event_timeline_test.dart` | ❌ W0 | ⬜ pending |
| 03-04-02 | 04 | 2 | EVT-08 | integration | `flutter test test/integration/` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/unit/event_model_test.dart` — stubs for EVT-01 (event data model)
- [ ] `test/unit/event_type_test.dart` — stubs for EVT-02 (event type + module mapping)
- [ ] `test/unit/event_service_test.dart` — stubs for EVT-03 (Firestore CRUD)
- [ ] `test/unit/event_modules_test.dart` — stubs for EVT-04 (module visibility per type)
- [ ] `test/unit/gear_seeding_test.dart` — stubs for EVT-05 (preset gear items)
- [ ] `test/features/events/` — directory for widget tests

*Existing test infrastructure (flutter_test, mocktail) covers framework needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Pull-to-refresh reloads from Firestore | EVT-08 / Phase 2 gap #8 | Requires real Firestore server round-trip | 1. Open home screen 2. Pull down to refresh 3. Verify spinner shows 4. Verify data reloads |
| Slide transitions between screens | UI-SPEC | Animation timing requires visual inspection | 1. Navigate to event type picker 2. Verify slide-right transition 3. Navigate to event hub 4. Verify ModuleHeader animation |

*All other behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
