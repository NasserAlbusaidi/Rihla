---
phase: 30
slug: group-settle-up-activity
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-04
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
| 30-01-01 | 01 | 1 | D-01, D-02 | widget | `flutter test test/features/groups/group_settle_up_screen_test.dart` | ✅ | ⬜ pending |
| 30-01-02 | 01 | 1 | D-03 | widget | `flutter test test/features/groups/group_settle_up_screen_test.dart` | ✅ | ⬜ pending |
| 30-01-03 | 01 | 1 | D-04, D-05 | widget | `flutter test test/features/groups/group_settle_up_screen_test.dart` | ✅ | ⬜ pending |
| 30-02-01 | 02 | 1 | D-07, D-08 | widget | `flutter test test/features/groups/group_activity_screen_test.dart` | ✅ | ⬜ pending |
| 30-02-02 | 02 | 1 | D-09, D-10 | widget | `flutter test test/features/groups/group_activity_screen_test.dart` | ✅ | ⬜ pending |
| 30-02-03 | 02 | 1 | D-11 | widget | `flutter test test/features/groups/group_activity_screen_test.dart` | ✅ | ⬜ pending |
| 30-03-01 | 03 | 2 | D-12 | widget | `flutter test test/features/groups/group_settle_up_screen_test.dart` | ✅ | ⬜ pending |
| 30-03-02 | 03 | 2 | D-14 | unit | `flutter test test/unit/group_activity_service_test.dart` | ❌ W0 | ⬜ pending |
| 30-04-01 | 04 | 2 | D-15, D-16 | widget | `flutter test test/features/groups/group_detail_screen_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/features/groups/group_settle_up_screen_test.dart` — add stubs: 4-tab AppTabBar renders; "You Owe" tab default; History tab shows settlement list; card-style tiles render
- [ ] `test/features/groups/group_activity_screen_test.dart` — add stubs: date section headers appear; filter chips render; "All" filter shows all; type-specific filters work; infinite scroll triggers
- [ ] `test/unit/group_activity_service_test.dart` — create: verify logGroupEvent called for event_created, event_deleted, member_joined, member_left

*Existing infrastructure covers framework install — flutter_test is built-in.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Balance sign visual correctness | D-12 | Requires visual confirmation that "You Owe" shows red/negative and "Owed to You" shows green/positive | 1. Create group with 2 members 2. Add expense where user A pays for user B 3. Check settle-up tabs for both users — signs should be opposite |
| Staggered entrance animations | Claude's discretion | Animation timing is visual | Open settle-up and activity screens, verify cards animate in with stagger |
| Infinite scroll UX | D-11 | Scroll behavior threshold is experiential | Scroll activity feed with 20+ items, verify auto-load triggers smoothly |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
