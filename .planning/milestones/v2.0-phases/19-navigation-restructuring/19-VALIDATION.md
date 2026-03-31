---
phase: 19
slug: navigation-restructuring
status: draft
nyquist_compliant: true
wave_0_complete: true
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
| 19-01-01 | 01 | 1 | NAV-03 | static | `flutter analyze lib/core/router/app_router.dart lib/features/home/screens/home_screen.dart lib/features/groups/screens/join_group_screen.dart lib/features/groups/screens/create_group_screen.dart` | N/A | pending |
| 19-01-02 | 01 | 1 | NAV-03 | static + widget | `flutter analyze lib/shared/widgets/module_header.dart test/helpers/test_router.dart` | test_router.dart created in this task | pending |
| 19-02-01 | 02 | 2 | NAV-03 | static | `flutter analyze lib/features/events/screens/event_command_center.dart lib/features/events/widgets/event_module_list.dart lib/features/ledger/screens/ledger_screen.dart lib/features/ledger/screens/settle_up_screen.dart` | N/A | pending |
| 19-02-02 | 02 | 2 | NAV-03 | static | `flutter analyze lib/features/gear/screens/gear_screen.dart lib/features/logistics/screens/logistics_screen.dart lib/features/vault/screens/vault_screen.dart lib/features/memories/screens/memories_screen.dart lib/features/groups/screens/group_settle_up_screen.dart` | N/A | pending |
| 19-02-03 | 02 | 2 | NAV-03 | static | `flutter analyze lib/features/groups/screens/group_detail_screen.dart lib/features/events/screens/event_type_picker_screen.dart lib/features/events/screens/create_event_screen.dart lib/core/router/app_router.dart` | N/A | pending |
| 19-03-01 | 03 | 3 | NAV-03 | static + widget | `flutter analyze lib/features/ledger/screens/ lib/core/router/app_router.dart && flutter test test/helpers/navigation_test.dart` | navigation_test.dart created in this task | pending |
| 19-03-02 | 03 | 3 | NAV-03 | widget | `flutter test test/features/events/ test/features/groups/ test/features/ledger/ test/helpers/navigation_test.dart` | All exist (need update) | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

Wave 0 is satisfied by Plan 01 Task 2 which creates `test/helpers/test_router.dart` before Plans 02 and 03 execute. Since Plans 02 and 03 depend sequentially on Plan 01 (via `depends_on: [19-01]` and `depends_on: [19-02]`), the testRouter helper is guaranteed to exist when subsequent plans need it.

- [x] `test/helpers/test_router.dart` — created in Plan 01 Task 2 (Wave 1), available for Plan 02 (Wave 2) and Plan 03 (Wave 3)

---

## Back Navigation Coverage (ROADMAP Success Criterion 2)

| Route Depth | Pop Target | Test File | Test Name |
|-------------|-----------|-----------|-----------|
| /group/:gid/event/:eid/ledger | EventHub | test/helpers/navigation_test.dart | pop from ledger returns to EventHub |
| /group/:gid/event/:eid | GroupDetail | test/helpers/navigation_test.dart | pop from EventHub returns to GroupDetail |
| /group/:gid/event/:eid/gear | EventHub | test/helpers/navigation_test.dart | pop from gear returns to EventHub |
| /group/:gid/event/:eid/ledger/add | Ledger | test/helpers/navigation_test.dart | pop from add expense returns to ledger |
| /group/:gid/event/:eid/ledger/settle-up | Ledger | test/helpers/navigation_test.dart | pop from event settle-up returns to ledger |

Created in Plan 03 Task 1 — provides automated coverage for hardware back button behavior.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| CLAUDE.md navigation section updated | NAV-03 | Documentation review | Read CLAUDE.md, verify route tree matches actual GoRouter configuration |

Note: Hardware back button testing was previously manual-only but is now covered by automated widget tests in `test/helpers/navigation_test.dart` (5 pop-navigation tests using `testRouter`).

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** ready
