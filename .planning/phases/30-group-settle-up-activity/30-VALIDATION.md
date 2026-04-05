---
phase: 30
slug: group-settle-up-activity
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-04
revised: 2026-04-04
---

# Phase 30 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (Flutter SDK built-in) |
| **Config file** | none — tests run via `flutter test` |
| **Quick run command** | `flutter test test/features/groups/ --no-pub` |
| **Full suite command** | `flutter test --no-pub` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/features/groups/ --no-pub`
- **After every plan wave:** Run `flutter test --no-pub`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 30-00-01 | 00 | 0 | D-01..D-06 (stubs) | widget | `flutter test test/features/groups/group_settle_up_screen_test.dart` | ✅ | ⬜ pending |
| 30-00-02 | 00 | 0 | D-07..D-14 (stubs) | widget+unit | `flutter test test/features/groups/group_activity_screen_test.dart test/unit/group_activity_service_test.dart` | ✅ | ⬜ pending |
| 30-01-01 | 01 | 1 | D-12 | widget | `flutter test test/features/groups/ --no-pub` | ✅ | ⬜ pending |
| 30-01-02 | 01 | 1 | D-14 | analyze | `flutter analyze lib/features/events/screens/create_event_screen.dart lib/features/groups/screens/join_group_screen.dart lib/features/groups/widgets/group_danger_section.dart lib/features/groups/widgets/group_members_section.dart --no-pub` | ✅ | ⬜ pending |
| 30-02-01 | 02 | 2 | D-04, D-05 | analyze | `flutter analyze lib/features/groups/widgets/group_settlement_tile.dart --no-pub` | ✅ | ⬜ pending |
| 30-02-02 | 02 | 2 | D-01, D-02, D-03, D-05, D-06 | analyze | `flutter analyze lib/features/groups/screens/group_settle_up_screen.dart --no-pub` | ✅ | ⬜ pending |
| 30-02-03 | 02 | 2 | D-01..D-06, D-12 | widget | `flutter test test/features/groups/group_settle_up_screen_test.dart --no-pub` | ✅ | ⬜ pending |
| 30-03-01 | 03 | 2 | D-07, D-08, D-09, D-10, D-11, D-15, D-16 | analyze | `flutter analyze lib/features/groups/screens/group_activity_screen.dart lib/features/groups/widgets/group_activity_tile.dart lib/features/groups/screens/group_detail_screen.dart --no-pub` | ✅ | ⬜ pending |
| 30-03-02 | 03 | 2 | D-07..D-11, D-15 | widget | `flutter test test/features/groups/group_activity_screen_test.dart --no-pub` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] Plan 00 creates skip-annotated test stubs in:
  - `test/features/groups/group_settle_up_screen_test.dart` — stubs: 4-tab AppTabBar renders; "You Owe" tab default; History tab shows settlement list; card-style tiles render; GroupStatsGrid subtitle tests (D-12)
  - `test/features/groups/group_activity_screen_test.dart` — stubs: date section headers appear; filter chips render; "All" filter shows all; type-specific filters work; infinite scroll (no Load more button)
  - `test/unit/group_activity_service_test.dart` — stubs: verify logGroupEvent for event_created, member_joined, member_left

*Wave 0 stubs use `skip` annotation — file passes but stubs are visible. Plans 02 and 03 unskip and flesh out stubs after implementation.*

*Existing infrastructure covers framework install — flutter_test is built-in.*

---

## D-15 Coverage

D-15 (CTA navigation) is verified in Plan 03 Task 1. The task reads GroupDetailScreen, verifies the three existing `context.push` calls for settle-up and activity routes remain intact, and adds `// D-15: CTA entry point — do not remove` comments. Acceptance criteria explicitly check for route strings in the file.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Balance sign visual correctness | D-12 | Requires visual confirmation that "You Owe" shows red/negative and "Owed to You" shows green/positive | 1. Create group with 2 members 2. Add expense where user A pays for user B 3. Check settle-up tabs for both users — signs should be opposite |
| Staggered entrance animations | Claude's discretion | Animation timing is visual | Open settle-up and activity screens, verify cards animate in with stagger |
| Infinite scroll UX | D-11 | Scroll behavior threshold is experiential | Scroll activity feed with 20+ items, verify auto-load triggers smoothly |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
