---
phase: 3
slug: events
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-26
---

# Phase 3 -- Validation Strategy

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
| 03-00-01 | 00 | 1 | EVT-02 | unit | `flutter test test/unit/event_model_test.dart` | created in 03-00 T1 | pending |
| 03-00-02 | 00 | 1 | EVT-03, EVT-05 | unit (stubs) | `flutter test test/unit/event_service_test.dart` | W0 stub in 03-00 T2 | pending |
| 03-01-01 | 01 | 2 | EVT-01 | unit | `flutter test test/unit/event_service_test.dart` | replaces stubs from W0 | pending |
| 03-01-02 | 01 | 2 | EVT-04 | analyze | `flutter analyze lib/features/events/providers/` | created in 03-01 T1 | pending |
| 03-01-03 | 01 | 2 | EVT-06 | grep+analyze | `grep -c 'match /events' security/firestore.rules && flutter analyze lib/features/home/` | created in 03-01 T2 | pending |
| 03-02-01 | 02 | 3 | EVT-02, EVT-05 | widget | `flutter test test/features/events/create_event_test.dart` | W0 stub in 03-00 T2, replaced in 03-02 T2 | pending |
| 03-03-01 | 03 | 3 | EVT-07 | widget | `flutter test test/features/events/group_detail_events_test.dart` | W0 stub in 03-00 T2, replaced in 03-03 T2 | pending |
| 03-04-01 | 04 | 4 | EVT-03, EVT-08 | widget | `flutter test test/features/events/event_command_center_test.dart` | W0 stub in 03-00 T2, replaced in 03-04 T2 | pending |
| 03-04-02 | 04 | 4 | EVT-08 | manual | End-to-end flow on device (checkpoint:human-verify) | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Plan 03-00 Task 2 creates all Wave 0 test stub files:

- [ ] `test/unit/event_model_test.dart` -- real tests for Event model (created in 03-00 Task 1, not a stub)
- [ ] `test/unit/event_service_test.dart` -- stubs for EventService (7 skipped tests, awaiting Plan 03-01)
- [ ] `test/features/events/create_event_test.dart` -- stubs for EventTypePickerScreen + CreateEventScreen (6 skipped tests, awaiting Plan 03-02)
- [ ] `test/features/events/group_detail_events_test.dart` -- stubs for GroupDetailScreen events section (6 skipped tests, awaiting Plans 03-03 and 03-04)
- [ ] `test/features/events/event_command_center_test.dart` -- stubs for EventCommandCenter (5 skipped tests, awaiting Plan 03-04)

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
