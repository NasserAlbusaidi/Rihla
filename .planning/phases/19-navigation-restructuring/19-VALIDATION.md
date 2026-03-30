---
phase: 19
slug: navigation-restructuring
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-30
---

# Phase 19 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (built-in), Flutter 3.41.5 |
| **Config file** | None — `flutter test` at project root |
| **Quick run command** | `flutter test test/features/ test/unit/ -x slow` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~60 seconds (full suite) |

---

## Sampling Rate

- **After every task commit:** Run `flutter analyze && flutter test test/unit/`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 19-01-01 | 01 | 1 | NAV-03 | widget/integration | `flutter test test/features/events/event_command_center_test.dart` | ✅ (needs update) | ⬜ pending |
| 19-01-02 | 01 | 1 | NAV-03 | widget | `flutter test test/features/events/event_module_list_test.dart` | ✅ (needs update) | ⬜ pending |
| 19-01-03 | 01 | 1 | NAV-03 | widget | `flutter test test/features/group_detail_screen_test.dart` | ✅ (needs update) | ⬜ pending |
| 19-01-04 | 01 | 1 | NAV-03 | widget | `flutter test test/features/events/` | ✅ (needs update) | ⬜ pending |
| 19-01-05 | 01 | 1 | NAV-03 | static | `flutter analyze` | N/A | ⬜ pending |
| 19-01-06 | 01 | 1 | NAV-03 | manual | manual inspection | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/helpers/test_router.dart` — shared `testRouter()` helper for navigation tests (D-13)
- [ ] `test/features/events/event_command_center_test.dart` — update provider overrides for D-14 constructor migration
- [ ] `test/features/events/event_module_list_test.dart` — same as above
- [ ] `test/features/group_detail_screen_test.dart` — wrap in `testRouter`, add route stubs

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Hardware back button navigates correctly at every depth | NAV-03 | Physical device interaction required | Navigate Home → Group → Event → Module, press back at each level, verify correct parent screen appears |
| CLAUDE.md navigation section updated | NAV-03 | Documentation review | Read CLAUDE.md, verify route tree matches actual GoRouter configuration |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
