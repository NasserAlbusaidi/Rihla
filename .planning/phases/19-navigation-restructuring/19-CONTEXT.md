# Phase 19: Navigation Restructuring - Context

**Gathered:** 2026-03-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace all imperative `Navigator.push` / `AppPageRoute` calls with declarative GoRouter subroutes so every event-level screen has a deep-linkable URL. Migrate screen constructors from full objects to string IDs with provider lookup. Delete dead navigation utilities. Update CLAUDE.md routing documentation.

This phase does NOT wire bottom nav tabs to real screens, redesign any screen visually, or add new screens. It restructures navigation only.

</domain>

<decisions>
## Implementation Decisions

### Route URL Structure
- **D-01:** Fully nested route tree — `/group/:gid/event/:eid/ledger` mirrors the data hierarchy. Every level is self-describing in the URL. Back button walks up naturally.
- **D-02:** Complete route tree:
  ```
  / (splash → redirect)
  /onboarding
  /home (BottomNavShell)
  /settings
  /create-group
  /join-group
  /group/:gid
    /settings (exists)
    /settle-up
    /create-event
    /create-event/:type
    /event/:eid (CommandCenter)
      /ledger
        /add
        /edit/:expId
      /gear
      /logistics
      /vault
      /memories
        /:memId
      /activity
  ```

### Transition Animations
- **D-03:** Preserve slide-right (`SlideTransition` with `Offset(1, 0) → Offset.zero`, `Curves.easeOutCubic`) for ALL screens via `CustomTransitionPage`. Zero visual regression for users. No direction-aware or modal transitions — that's Phase 22 territory.

### Bottom Navigation
- **D-04:** Keep all placeholder tabs (Activity, Chats, Profile show "Coming soon"). Phase 19 scope is routing only — no tab wiring.

### CommandCenter Migration
- **D-05:** CommandCenter becomes a GoRouter subroute at `/group/:gid/event/:eid`. Module screens are nested subroutes under it. Full deep linking from home to any module.

### Event Creation Flow
- **D-06:** Event creation screens become GoRouter routes: `/group/:gid/create-event` (EventTypePicker), `/group/:gid/create-event/:type` (CreateEventScreen). On success, `context.go('/group/:gid/event/:newId')` replaces the creation route with the new event's CommandCenter.

### Form Screens
- **D-07:** All form screens become GoRouter routes: `/group/:gid/event/:eid/ledger/add` (AddExpenseScreen), `/group/:gid/event/:eid/ledger/edit/:expId` (EditExpenseSheet), `/group/:gid/settle-up` (GroupSettleUpScreen). No modals — consistent with the fully-nested decision.

### Parameter Passing
- **D-08:** Path params + provider lookup. Screens receive `groupId`/`eventId` as strings from GoRouter path parameters. Data is fetched via `ref.watch(groupProvider(groupId))` inside the screen. No `state.extra` — deep links must work without pre-loaded objects.

### Dead Code Cleanup
- **D-09:** Delete `lib/core/utils/page_transitions.dart` and `test/unit/page_transitions_test.dart` in this phase. After all `Navigator.push` calls are replaced, `AppPageRoute` and `AppBottomSheetRoute` have zero consumers.

### Memory Detail Navigation
- **D-10:** Memory detail viewer becomes `/group/:gid/event/:eid/memories/:memId`. Consistent with fully-nested pattern. Individual photos/videos are deep-linkable.

### Error/404 Handling
- **D-11:** In-screen error state, not redirect. If a deep link references a deleted event or inaccessible group, the target screen renders normally but shows "This event no longer exists" (or similar) with a "Go Home" button. Same pattern as Phase 18's error state. No custom 404 screen.

### CLAUDE.md Documentation
- **D-12:** Update CLAUDE.md navigation flow section with a plain text route tree showing the full GoRouter hierarchy. Same format as the D-02 tree above. No mermaid diagrams. Updated in the same commit as the routing code changes (per success criterion #4).

### Test Migration
- **D-13:** Real GoRouter with test routes. Create a `testRouter` helper that registers all routes. Tests use `MaterialApp.router(routerConfig: testRouter())`. Navigation verified by finding the target screen type. No MockGoRouter.

### Screen Constructor Refactoring
- **D-14:** Big bang — change all screen constructors from full objects to string IDs in this phase. Every screen that takes a `Group`/`Event` object switches to `groupId`/`eventId`. Clean break, no transitional dual constructors.

### Activity Module Route
- **D-15:** Event-level activity becomes `/group/:gid/event/:eid/activity` — a module route sibling to `/ledger`, `/gear`, etc. Consistent treatment as a full module screen.

### Claude's Discretion
- Route transition timing (duration, curve fine-tuning) — keep current values unless they feel wrong
- GoRouter `redirect` logic for auth/onboarding — extend existing pattern as needed
- Order of migration (which files first) — planner decides based on dependencies

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Routing Architecture
- `lib/core/router/app_router.dart` — Current GoRouter configuration (6 routes, splash redirect logic)
- `lib/core/utils/page_transitions.dart` — AppPageRoute/AppBottomSheetRoute classes (to be deleted)

### Navigation Call Sites (19 total)
- `lib/features/groups/screens/group_detail_screen.dart` — 7 Navigator.push calls (events, settle up, settings, command center)
- `lib/features/events/widgets/event_module_list.dart` — 5 Navigator.push calls (one per module: ledger, gear, logistics, vault, memories)
- `lib/features/events/screens/event_command_center.dart` — 2 Navigator.push calls (event type picker, module list)
- `lib/features/ledger/screens/ledger_screen.dart` — 2 Navigator.push calls (add expense, edit expense)
- `lib/features/events/screens/event_type_picker_screen.dart` — 1 Navigator.push call (create event)
- `lib/features/events/screens/create_event_screen.dart` — 1 Navigator.push call (command center on success)
- `lib/features/memories/screens/memories_screen.dart` — 1 Navigator.push call (memory detail viewer)

### Phase 18 Integration Points
- `lib/features/home/widgets/bottom_nav_shell.dart` — BottomNavShell with 4 tabs (Groups real, 3 placeholder)
- `lib/features/home/screens/home_screen.dart` — Already uses `context.push('/group/${group.id}')` for GroupCard navigation

### Prior Phase Context
- `.planning/phases/18-home-dashboard-redesign/18-CONTEXT.md` — Dashboard decisions (bottom nav, group card navigation)
- `.planning/phases/16-stitch-workflow-design-reference/16-CONTEXT.md` — Bottom nav locked to Groups/Activity/Chats/Profile

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CustomTransitionPage` pattern already used for all 6 existing GoRouter routes — reuse same `SlideTransition` builder for new subroutes
- `testRouter` pattern needed — Phase 18 tests already use `GoRouter` with test routes in `home_screen_groups_test.dart` and `home_screen_dashboard_test.dart`
- `EventRef` typedef `({String groupId, String eventId})` already exists for event scoping — screens can derive this from their string params

### Established Patterns
- GoRouter routes use `CustomTransitionPage` with `SlideTransition` or `FadeTransition` (see `app_router.dart`)
- Screen constructors currently take full domain objects (`Group group, Event event`) — will switch to string IDs
- Riverpod providers use `.family` with string ID or `EventRef` record — compatible with path-param-only screens

### Integration Points
- `app_router.dart` — All new subroutes nest under existing `/group/:gid` route
- `BottomNavShell` — HomeScreen is wrapped; new routes are children pushed on top of the shell
- `AppRoutes` class — Add new static constants for all new route paths
- Existing `context.push` calls in `home_screen.dart` — Already using GoRouter pattern

</code_context>

<specifics>
## Specific Ideas

No specific requirements — standard GoRouter migration following the decisions above.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 19-navigation-restructuring*
*Context gathered: 2026-03-30*
