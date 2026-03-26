---
phase: 03-events
plan: 03
subsystem: ui
tags: [flutter, events, event-card, group-detail, riverpod, firestore, financial]

# Dependency graph
requires:
  - phase: 03-events-01
    provides: groupEventsProvider stream, tripExpensesProvider, Event model with bridgeTripId
  - phase: 03-events-02
    provides: EventTypePickerScreen (FAB target), CreateEventScreen

provides:
  - EventCard widget with live financial total from bridge trip expenses
  - Updated GroupDetailScreen with live events section, count chip, FAB, empty state
  - GroupDetailScreen FAB navigates to EventTypePickerScreen
  - group_detail_events_test.dart with 8 real widget tests (1 skipped for Plan 03-04)

affects:
  - 03-events-04 (EventCommandCenter — EventCard onTap TODO)
  - test/features/groups/group_screens_test.dart (updated stale tests)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "EventCard watches tripExpensesProvider(event.bridgeTripId) for live financial total"
    - "Past event dimming via Opacity(0.6) wrapping the entire card"
    - "_PressableCard StatefulWidget with AnimatedScale 0.98 on press, 80ms easeInOut"
    - "GroupDetailScreen _buildEventsSection accepts (BuildContext, WidgetRef, Group)"
    - "groupEventsProvider override in widget tests prevents real Firestore connection"
    - "tripExpensesProvider override in widget tests prevents SQLite initialization"

key-files:
  created:
    - lib/features/events/widgets/event_card.dart
  modified:
    - lib/features/groups/screens/group_detail_screen.dart
    - test/features/events/group_detail_events_test.dart
    - test/features/groups/group_screens_test.dart

key-decisions:
  - "EventCard is a ConsumerWidget to watch tripExpensesProvider for live total — StatelessWidget was not sufficient"
  - "_PressableCard uses AnimatedScale widget (stateful) rather than AnimationController for simpler press feedback"
  - "GroupDetailScreen FAB always visible (even during loading) — creating events is always valid"

requirements-completed: [EVT-07]

# Metrics
duration: 6min
completed: 2026-03-26
---

# Phase 3 Plan 03: EventCard and GroupDetailScreen Events Section Summary

**EventCard widget displaying live financial total from bridge expenses, updated GroupDetailScreen with real events section and FAB navigating to EventTypePickerScreen**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-26T10:15:55Z
- **Completed:** 2026-03-26T10:21:57Z
- **Tasks:** 2
- **Files modified:** 4 (1 created)

## Accomplishments

- EventCard ConsumerWidget displays event type icon, name with type badge, date range (en-dash), participant count (middle dot separator), and live financial total from `tripExpensesProvider(event.bridgeTripId)`
- Past events wrapped in `Opacity(0.6)` per D-26 — card remains tappable
- Press animation via `_PressableCard` scales to 0.98 on tap-down, 80ms easeInOut
- Semantics wrapper with `button: true` for accessibility
- GroupDetailScreen updated: `_buildEventsSection(context, ref, group)` watches `groupEventsProvider`
- Events section header shows count chip when events exist (`'${events.length}'`)
- Empty state matches Copywriting Contract: 'No events yet' / 'Tap the + button to create the first event for this group.'
- FAB with `Semantics(label: 'Create event')` navigates to `EventTypePickerScreen(groupId: groupId)`
- 8 real widget tests replacing all skip markers (1 correctly skipped for Plan 03-04)
- Fixed stale test in group_screens_test.dart: updated empty state message + added `groupEventsProvider` override

## Task Commits

Each task was committed atomically:

1. **Task 1: EventCard widget** - `fb071ed` (feat)
2. **Task 2: GroupDetailScreen + tests** - `a99892f` (feat)

**Plan metadata:** pending (docs commit)

## Files Created/Modified

- `lib/features/events/widgets/event_card.dart` — EventCard ConsumerWidget with live expense total, past-event dimming, press animation, accessibility
- `lib/features/groups/screens/group_detail_screen.dart` — Events section with live provider, count chip, FAB, Copywriting Contract empty state
- `test/features/events/group_detail_events_test.dart` — 8 passing tests (events visible, empty state, count chip, opacity dimming, FAB visible, financial total, zero total)
- `test/features/groups/group_screens_test.dart` — Fixed: added groupEventsProvider override, updated stale empty state message

## Decisions Made

- EventCard is a `ConsumerWidget` (not `StatelessWidget`) because it needs `ref.watch(tripExpensesProvider)` for live financial totals. Making it a ConsumerWidget is the minimal change for reactivity.
- `_PressableCard` uses `AnimatedScale` widget with `setState` toggling a boolean, rather than a raw `AnimationController`. Simpler and avoids mixin boilerplate.
- FAB placed unconditionally on `Scaffold.floatingActionButton` (not conditional on data loaded) — creating events is always valid from GroupDetailScreen regardless of loading state.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Stale test message in group_screens_test.dart**
- **Found during:** Task 2 verification (running existing tests)
- **Issue:** `group_screens_test.dart` expected old empty state message `'Create an event to get started — events will appear here.'` — but Plan 03-03 changes the Copywriting Contract message to `'Tap the + button to create the first event for this group.'`. The test also had no `groupEventsProvider` override, causing it to attempt a real Firestore connection.
- **Fix:** Added `groupEventsProvider('group-1').overrideWith((ref) => Stream.value(const []))` to the `_wrap` helper and updated the expected message text.
- **Files modified:** test/features/groups/group_screens_test.dart
- **Verification:** All 10 tests in group_screens_test.dart pass
- **Committed in:** a99892f (Task 2 commit)

**2. [Rule 3 - Blocking] create_event_screen.dart did not exist**
- **Found during:** Task 2 (GroupDetailScreen imports EventTypePickerScreen, which imports create_event_screen.dart)
- **Issue:** EventTypePickerScreen imports `create_event_screen.dart` which did not exist — would have caused compile error. Plan 03-02's parallel agent had already created the full implementation by the time this was discovered (commit 9c881ad). No action needed — the file was already complete when checked.
- **Resolution:** Full CreateEventScreen from Plan 03-02 agent already in place.

---

**Total deviations:** 2 auto-fixed (1 Rule 1 bug, 1 Rule 3 blocking — resolved by parallel agent)
**Impact on plan:** Both handled without scope creep.

## Known Stubs

- `EventCard.onTap` in GroupDetailScreen has a TODO comment for Plan 03-04: EventCommandCenter navigation. The tap is non-functional but the card renders and is accessible. This is intentional — Plan 03-04 will implement navigation.

## Self-Check: PASSED

- lib/features/events/widgets/event_card.dart: FOUND
- lib/features/groups/screens/group_detail_screen.dart: FOUND (modified)
- test/features/events/group_detail_events_test.dart: FOUND (8 tests passing)
- test/features/groups/group_screens_test.dart: FOUND (10 tests passing)
- commit fb071ed (Task 1): FOUND
- commit a99892f (Task 2): FOUND

---
*Phase: 03-events*
*Completed: 2026-03-26*
