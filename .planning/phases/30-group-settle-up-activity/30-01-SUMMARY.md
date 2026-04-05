---
phase: 30-group-settle-up-activity
plan: 01
subsystem: ui
tags: [flutter, riverpod, balance, activity-log, firestore]

requires:
  - phase: 29-group-management
    provides: GroupDangerSection, GroupMembersSection, GroupSettingsScreen with leave/remove flows

provides:
  - GroupStatsGrid YOUR BALANCE tile with directional subtitle (You owe / Owed to you / Settled)
  - logGroupEvent call sites for event_created, member_joined, member_left (leave), member_left (remove)
  - Phase 30 test keys in GroupKeys for Plans 02 and 03

affects:
  - 30-02 (settle-up redesign uses GroupKeys.settleUpTabBar etc.)
  - 30-03 (activity redesign uses GroupKeys.activityFilter* keys)

tech-stack:
  added: []
  patterns:
    - "Activity logging: fire-and-forget try/catch wrapper around logGroupEvent call sites"
    - "Balance direction: switch expression on compareTo(Decimal.zero) → subtitle string"

key-files:
  created: []
  modified:
    - lib/features/groups/widgets/group_stats_grid.dart
    - lib/features/groups/keys/group_keys.dart
    - lib/features/events/screens/create_event_screen.dart
    - lib/features/groups/screens/join_group_screen.dart
    - lib/features/groups/widgets/group_danger_section.dart
    - lib/features/groups/widgets/group_members_section.dart

key-decisions:
  - "Activity logging wrapped in try/catch (not just fire-and-forget unawaited) at call sites — ensures logging failure never crashes creation/join/leave/remove flows even if FirebaseConfig throws"
  - "Direction label (subtitle) added to _StatCard as optional param — only YOUR BALANCE passes it; all other stat cards remain unchanged"
  - "event_deleted skipped — no UI call site exists yet; will be added when deletion UI is built in Phase 31+"

patterns-established:
  - "Activity call site pattern: try { FirebaseConfig.currentUser access + logGroupEvent } catch (_) {}"

requirements-completed: []

duration: 6min
completed: 2026-04-05
---

# Phase 30 Plan 01: Foundation Fixes Summary

**Balance direction label (You owe/Owed to you/Settled) on GroupStatsGrid YOUR BALANCE tile, plus 4 new logGroupEvent call sites for event_created, member_joined, and member_left (leave + remove paths)**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-04-05T08:02:52Z
- **Completed:** 2026-04-05T08:08:51Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Fixed D-12: YOUR BALANCE stat now shows explicit directional text alongside the absolute amount and color
- Fixed D-14: activity feed now logs 4 previously-missing action types (event_created, member_joined, member_left x2)
- Added Phase 30 test keys to GroupKeys (settleUpTabBar, settleUpHistoryTab, activityFilterAll, activityFilterSettlements, activityFilterEvents, activityFilterMembers + 4 more)

## Task Commits

1. **Task 1: Fix balance sign display + direction label (D-12)** - `eef11c7` (fix)
2. **Task 2: Add missing activity logging calls + Phase 30 test keys (D-14)** - `c6c6dde` (feat)

## Files Created/Modified

- `lib/features/groups/widgets/group_stats_grid.dart` — Added `balanceSubtitle` switch expression and optional `subtitle` param to `_StatCard`
- `lib/features/groups/keys/group_keys.dart` — Added 10 Phase 30 test keys for Plans 02 and 03
- `lib/features/events/screens/create_event_screen.dart` — Added `event_created` logGroupEvent after successful event creation; imported `group_balance_provider.dart`
- `lib/features/groups/screens/join_group_screen.dart` — Added `member_joined` logGroupEvent after successful group join; imported `firebase_config.dart` and `group_balance_provider.dart`
- `lib/features/groups/widgets/group_danger_section.dart` — Added `member_left` logGroupEvent before leaveGroup call in `_executeLeave`; imported `firebase_config.dart` and `group_balance_provider.dart`
- `lib/features/groups/widgets/group_members_section.dart` — Added `member_left` logGroupEvent before removeMember call in `_handleRemove`; imported `firebase_config.dart`

## Decisions Made

- Activity logging wrapped in `try/catch` (not just `unawaited`) at each call site. `FirebaseConfig.currentUser` can throw in test environments; the catch ensures logging failure never crashes the creation/join/leave/remove flow. This is consistent with the existing pattern in `group_settle_up_screen.dart` lines 697-701.
- `event_deleted` skipped per plan spec — no UI call site exists today; added when event deletion UI ships.
- Direction subtitle uses the same `valueColor` as the balance amount for visual consistency (not a separate muted color).

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

- Flutter test runner crashed with `Bad state: No element` on first attempt using `--no-pub` flag. Ran without the flag successfully. Pre-existing flutter tools bug unrelated to this plan's changes.
- Worktree was on an old branch (`c06e4c3`) predating groups/events features. Reset to main HEAD (`0c5f1f4`) before starting work.

## Known Stubs

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plan 02 (settle-up redesign) can use all `GroupKeys.settleUpTab*` keys
- Plan 03 (activity redesign) can use all `GroupKeys.activityFilter*` keys
- GroupStatsGrid direction label provides correct visual context for users navigating to settle-up

## Self-Check: PASSED

- FOUND: group_stats_grid.dart
- FOUND: group_keys.dart
- FOUND: create_event_screen.dart
- FOUND: join_group_screen.dart
- FOUND: group_danger_section.dart
- FOUND: group_members_section.dart
- FOUND: commit eef11c7
- FOUND: commit c6c6dde
- FOUND: commit 2eef636

---
*Phase: 30-group-settle-up-activity*
*Completed: 2026-04-05*
