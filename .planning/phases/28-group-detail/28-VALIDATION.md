---
phase: 28
slug: group-detail
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-02
---

# Phase 28 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (built-in Flutter SDK) |
| **Config file** | none — flutter test auto-discovers |
| **Quick run command** | `flutter test test/features/group_detail_screen_test.dart test/features/events/group_detail_events_test.dart` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/features/group_detail_screen_test.dart test/features/events/group_detail_events_test.dart`
- **After every plan wave:** Run `flutter test test/features/`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 28-01-01 | 01 | 1 | D-05 invite code removal | widget | `flutter test test/features/group_detail_screen_test.dart` | ✅ (needs update) | ⬜ pending |
| 28-01-02 | 01 | 1 | D-13 header polish | widget | `flutter test test/features/group_detail_screen_test.dart` | ✅ | ⬜ pending |
| 28-01-03 | 01 | 1 | D-06 stats grid refresh | widget | `flutter test test/features/group_detail_screen_test.dart` | ✅ | ⬜ pending |
| 28-01-04 | 01 | 1 | D-08 FadeInList events | widget | `flutter test test/features/events/group_detail_events_test.dart` | ❌ W0 | ⬜ pending |
| 28-01-05 | 01 | 1 | D-09 member balance cards | widget | `flutter test test/features/group_detail_screen_test.dart` | ✅ | ⬜ pending |
| 28-01-06 | 01 | 1 | D-11 pull-to-refresh | widget | `flutter test test/features/group_detail_screen_test.dart` | ❌ W0 | ⬜ pending |
| 28-01-07 | 01 | 1 | D-12 inline error + retry | widget | `flutter test test/features/group_detail_screen_test.dart` | ❌ W0 | ⬜ pending |
| 28-01-08 | 01 | 1 | D-14 FAB token fix | widget | `flutter test test/features/group_detail_screen_test.dart` | ✅ | ⬜ pending |
| 28-01-09 | 01 | 1 | Provider rebuild isolation | widget | `flutter test test/features/group_detail_screen_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Update `test/features/group_detail_screen_test.dart` — remove `inviteCodeSection` present assertion, add `findsNothing` assertion
- [ ] Add `test/features/group_detail_screen_test.dart` — test for `RefreshIndicator` presence
- [ ] Add `test/features/group_detail_screen_test.dart` — test for inline error state with retry button
- [ ] Add `test/features/events/group_detail_events_test.dart` — test that `FadeInList` wraps event cards
- [ ] Add `test/features/group_detail_screen_test.dart` — test verifying `Consumer` widget isolates balance rebuilds (optional, hard to assert in widget test)

*Existing infrastructure covers stats grid, settle-up CTA conditional, section order, accordion expand/collapse.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Grain texture on ModuleHeader | D-13 | Visual shader effect cannot be asserted in widget tests | Verify grain texture visible on dark gradient header during manual QA |
| Stagger animation timing feels natural | D-08 | Animation timing is subjective UX | Run app, navigate to group detail, verify event cards animate in with staggered delay |
| Spacing/density feels balanced | D-03 | Visual density is subjective | Compare before/after screenshots of each section |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
