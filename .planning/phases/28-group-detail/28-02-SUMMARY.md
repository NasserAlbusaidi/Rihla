---
phase: 28-group-detail
plan: 02
subsystem: ui
tags: [flutter, riverpod, refresh-indicator, fade-in-list, tdd, group-detail, design-tokens]

# Dependency graph
requires:
  - phase: 28-01
    provides: Clean GroupDetailScreen structure with Consumer isolation and gradient CTA
provides:
  - RefreshIndicator wrapping GroupDetailScreen scroll content with 5-provider invalidation
  - FadeInList wrapping event cards for staggered entrance animation
  - Inline error state with ModuleHeader preserved, retry button re-fetches via ref.invalidate
  - GroupMemberBalanceCard with radiusLarge (16dp), cardSurface/selectionFill, successText/errorText
affects:
  - Phase 29 (invite code section — builds on stable GroupDetailScreen)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - RefreshIndicator with AlwaysScrollableScrollPhysics for content that fits viewport
    - FadeInList replacing bare Column for entrance animation (children as Padding-wrapped widgets)
    - Inline error state — preserve screen chrome (ModuleHeader) while showing error in content area
    - WCAG-safe color tokens for text: successText/errorText over display-only success/error

key-files:
  created: []
  modified:
    - lib/features/groups/screens/group_detail_screen.dart
    - lib/features/groups/widgets/group_member_balance_card.dart
    - test/features/group_detail_screen_test.dart
    - test/features/events/group_detail_events_test.dart
    - test/features/group_balance_card_test.dart

key-decisions:
  - "FadeInList wraps event cards in _buildEventsSection only — keeps stagger isolated to events, avoids animation replay on balance provider updates"
  - "AlwaysScrollableScrollPhysics required on SingleChildScrollView so RefreshIndicator activates even when content fits viewport"
  - "Inline error preserves ModuleHeader: Column(ModuleHeader, Expanded(Center(error+retry))) — not a full-screen replacement"
  - "successText/errorText used for balance text (WCAG 4.56:1 and 5.92:1) instead of success/error (display-only tokens)"

patterns-established:
  - "Inline error: Column(ModuleHeader, Expanded(Center(error message + retry))) keeps screen structure intact"
  - "Pull-to-refresh: invalidate 5 stream providers (group, events, members, activity, settlements) — NOT groupBalancesProvider (computed Provider.family)"

requirements-completed: [D-03, D-06, D-07, D-08, D-09, D-11, D-12, D-15]

# Metrics
duration: 11min
completed: 2026-04-02
---

# Phase 28 Plan 02: Group Detail Interactive Behaviors Summary

**GroupDetailScreen completed with pull-to-refresh, FadeInList staggered event entrance, inline error state with retry, and GroupMemberBalanceCard visual polish using design tokens**

## Performance

- **Duration:** ~11 min
- **Started:** 2026-04-02T08:13:19Z
- **Completed:** 2026-04-02T08:24:26Z
- **Tasks:** 2 (TDD: RED + GREEN)
- **Files modified:** 5

## Accomplishments

- Pull-to-refresh (D-11): `RefreshIndicator` wraps `SingleChildScrollView` with `AlwaysScrollableScrollPhysics`. On pull, invalidates 5 Firestore-backed stream providers: `groupDetailProvider`, `groupEventsProvider`, `groupMembersProvider`, `groupActivityProvider`, `groupSettlementsProvider`. `groupBalancesProvider` not invalidated (computed Provider.family auto-recomputes).
- Staggered entrance (D-08): `FadeInList` replaces bare `Column` for event cards. Each card wrapped in `Padding(EdgeInsets.only(top: i > 0 ? 12 : 0))` so FadeInList receives individual widgets.
- Inline error state (D-12): Error handler uses `Column(ModuleHeader, Expanded(Center(error + retry)))` pattern — screen chrome preserved. Retry calls `ref.invalidate(groupDetailProvider(groupId))`.
- GroupMemberBalanceCard polish (D-09): `radiusLarge` (16dp) border radius on Container and InkWell. Background: `cardSurface` (#F8F9FA) collapsed, `selectionFill` (#E6F5F3) when expanded. Balance text: `successText` (#047857, WCAG 4.56:1) for positive, `errorText` (#B91C1C, WCAG 5.92:1) for negative, `textSecondary` for zero.
- 3 new widget tests added and passing: RefreshIndicator presence, inline error + retry, FadeInList presence.

## Task Commits

1. **Task 1: Write failing tests (RED)** - `93e49e5` (test)
2. **Task 2: Implement behaviors (GREEN)** - `9bba045` (feat)

## Files Created/Modified

- `lib/features/groups/screens/group_detail_screen.dart` — RefreshIndicator, FadeInList import, inline error state
- `lib/features/groups/widgets/group_member_balance_card.dart` — radiusLarge, selectionFill, successText/errorText
- `test/features/group_detail_screen_test.dart` — RefreshIndicator test + inline error test added
- `test/features/events/group_detail_events_test.dart` — FadeInList test added
- `test/features/group_balance_card_test.dart` — Updated color assertions to successText/errorText

## Decisions Made

- `FadeInList` placed in `_buildEventsSection` only (not in `_buildMembersBalancesSection`). This prevents animation replay when `groupBalancesProvider` updates push new balance data. Events section watches `groupEventsProvider` — the animation only fires when the events list itself changes.
- `AlwaysScrollableScrollPhysics` is mandatory. Without it, `RefreshIndicator` silently fails when all content fits within the viewport (common on large screens or with few events).
- Inline error keeps `ModuleHeader` visible. Full-screen replacement (`Center(child: Text(...))`) loses the screen identity — user can't tell which screen errored. Preserving the header with the group name (or "Group" fallback) maintains context.
- `successText`/`errorText` tokens instead of `success`/`error`. The comment in `color_tokens.dart` explicitly states: `success` is "Display only (badges, icons). For text use successText." Using the wrong tokens would fail WCAG AA.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated group_balance_card_test assertions to match new WCAG-safe colors**
- **Found during:** Task 2 (GREEN run)
- **Issue:** `group_balance_card_test.dart` was asserting `AppColorTokens.light.success.value` and `AppColorTokens.light.error.value`. After implementing D-09's requirement to use `successText`/`errorText` for balance text, these assertions failed.
- **Fix:** Updated test assertions to check `successText.value` and `errorText.value`
- **Files modified:** test/features/group_balance_card_test.dart
- **Committed in:** 9bba045 (Task 2 commit)

**2. [Rule 3 - Blocking Issue] Git stash pop reverted implementation files mid-execution**
- **Found during:** Task 2 verification
- **Issue:** Used `git stash` to verify pre-existing test failures; `git stash pop` failed due to macOS file conflict and partially reverted `group_detail_screen.dart` and `group_member_balance_card.dart` to pre-edit state.
- **Fix:** Re-applied all implementation changes from scratch after detecting the revert
- **No additional commit needed** — revert detected before committing, fix merged into Task 2 commit

---

**Total deviations:** 2 (1 test assertion update, 1 environment issue)

## Pre-existing Issues (Out of Scope)

Logged to `deferred-items.md` in phase directory:
1. `test/features/ledger_test.dart` — Compilation error: `event` named param removed in prior refactor
2. `test/features/group_settle_up_screen_test.dart` — Compilation error: `group` named param removed
3. `test/features/groups/group_screens_test.dart` — Invite code test (Plan 01 removed invite code section; test not updated in Plan 01 scope)

None of these failures are caused by Plan 02 changes. Verified by `git diff HEAD~1` showing no modifications to these files.

## Known Stubs

None — all changes are concrete implementations. No placeholder text or wired-but-empty data flows.

## Next Phase Readiness

- GroupDetailScreen is complete for Phase 28 requirements
- All D-0x requirements implemented across Plans 01 and 02
- Phase 29 can add invite code section to GroupSettings without conflicts

---
*Phase: 28-group-detail*
*Completed: 2026-04-02*
