# Phase 19: Navigation Restructuring - Research

**Researched:** 2026-03-30
**Domain:** GoRouter nested routes, Flutter declarative navigation, screen constructor migration
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

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
- **D-03:** Preserve slide-right (`SlideTransition` with `Offset(1, 0) → Offset.zero`, `Curves.easeOutCubic`) for ALL screens via `CustomTransitionPage`. Zero visual regression. No direction-aware or modal transitions — that is Phase 22 territory.
- **D-04:** Keep all placeholder tabs (Activity, Chats, Profile show "Coming soon"). Phase 19 scope is routing only — no tab wiring.
- **D-05:** CommandCenter becomes a GoRouter subroute at `/group/:gid/event/:eid`. Module screens are nested subroutes under it. Full deep linking from home to any module.
- **D-06:** Event creation screens become GoRouter routes: `/group/:gid/create-event` (EventTypePicker), `/group/:gid/create-event/:type` (CreateEventScreen). On success, `context.go('/group/:gid/event/:newId')` replaces the creation route with the new event's CommandCenter.
- **D-07:** All form screens become GoRouter routes: `/group/:gid/event/:eid/ledger/add` (AddExpenseScreen), `/group/:gid/event/:eid/ledger/edit/:expId` (EditExpenseSheet), `/group/:gid/settle-up` (GroupSettleUpScreen). No modals — consistent with the fully-nested decision.
- **D-08:** Path params + provider lookup. Screens receive `groupId`/`eventId` as strings from GoRouter path parameters. Data is fetched via `ref.watch(groupProvider(groupId))` inside the screen. No `state.extra` — deep links must work without pre-loaded objects.
- **D-09:** Delete `lib/core/utils/page_transitions.dart` and `test/unit/page_transitions_test.dart` in this phase after all Navigator.push calls are replaced.
- **D-10:** Memory detail viewer becomes `/group/:gid/event/:eid/memories/:memId`. Consistent with fully-nested pattern.
- **D-11:** In-screen error state, not redirect. If a deep link references a deleted event or inaccessible group, the target screen renders normally but shows "This event no longer exists" with a "Go Home" button.
- **D-12:** Update CLAUDE.md navigation flow section with plain text route tree. No mermaid diagrams. Updated in the same commit as routing code changes.
- **D-13:** Real GoRouter with test routes. Create a `testRouter` helper that registers all routes. Tests use `MaterialApp.router(routerConfig: testRouter())`. Navigation verified by finding the target screen type. No MockGoRouter.
- **D-14:** Big bang — change all screen constructors from full objects to string IDs in this phase. Every screen that takes a `Group`/`Event` object switches to `groupId`/`eventId`. Clean break, no transitional dual constructors.
- **D-15:** Event-level activity becomes `/group/:gid/event/:eid/activity` — a module route sibling to `/ledger`, `/gear`, etc.

### Claude's Discretion
- Route transition timing (duration, curve fine-tuning) — keep current values unless they feel wrong
- GoRouter `redirect` logic for auth/onboarding — extend existing pattern as needed
- Order of migration (which files first) — planner decides based on dependencies

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| NAV-03 | All event-level screens are accessible via GoRouter subroutes, replacing Navigator.push with context.push | Route tree design (D-01/D-02), constructor migration pattern (D-08/D-14), test infrastructure (D-13) all documented below |

</phase_requirements>

---

## Summary

Phase 19 migrates all imperative `Navigator.push`/`AppPageRoute` calls to GoRouter declarative subroutes. The project already runs GoRouter 13.2.5 (`go_router: ^13.2.0`) with a working pattern for nested routes — `GroupSettingsScreen` is already a nested subroute under `/group/:gid` using `routes:` inside `GoRoute`. Phase 19 extends this exact pattern downward into event-level and module-level routes.

The core technical work is two-fold: (1) expanding `app_router.dart` to declare ~14 new `GoRoute` entries in a deeply-nested tree, and (2) refactoring 9 screen constructors from full `Event`/`Group` objects to `groupId`/`eventId` string params with provider lookup inside the screen. Both providers needed for lookup (`groupDetailProvider`, `eventDetailProvider`) already exist as `StreamProvider.family` — no new Firestore code is required.

The main risk is the big-bang constructor migration (D-14). Every screen, its test file, and every call site that currently passes a `Group`/`Event` object must be updated atomically. A second risk is `GroupSettleUpScreen`'s optional `preSelectedMemberId` parameter — this was passed as a constructor argument and must become a GoRouter query parameter.

**Primary recommendation:** Migrate files in dependency order: router expansion first, then module screens (no callers), then EventCommandCenter and EventModuleList, then GroupDetailScreen, then CreateEventScreen. Delete `page_transitions.dart` last after all callers are gone.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `go_router` | 13.2.5 (installed) | Declarative URL routing | Already in use; nested `routes:` pattern proven with `/group/:gid/settings` |
| `flutter_riverpod` | 2.4.9 (installed) | Provider-based state mgmt | `groupDetailProvider` and `eventDetailProvider` are the lookup backbone for D-08 |

### No New Dependencies

This phase adds zero new packages. All required capabilities exist:
- `GoRoute` with nested `routes:` — already used for `/group/:gid/settings`
- `CustomTransitionPage` with `SlideTransition` — already used for every existing route
- `state.pathParameters['key']` — already used in `GroupDetailScreen` and `GroupSettingsScreen`
- `context.push(path)` — already used in `home_screen.dart` for group navigation

### Current Router State (Baseline)

The existing `app_router.dart` has 6 top-level routes and 1 existing nested subroute:

```
/ (splash)
/onboarding
/home
/create-group
/join-group
/settings
/group/:id
  /settings  ← only existing nested route (GroupSettingsScreen)
```

**Version verification:** GoRouter 13.2.5 confirmed in `pubspec.lock`.

---

## Architecture Patterns

### Recommended Project Structure

No new files/folders needed. All changes are to:
```
lib/core/router/
└── app_router.dart          ← expanded with ~14 new GoRoute entries + new AppRoutes constants

lib/features/events/screens/
├── event_command_center.dart  ← constructor: Event+Group → groupId+eventId
├── event_type_picker_screen.dart ← already takes groupId; 1 Navigator.push → context.push
└── create_event_screen.dart  ← Navigator.pop/pop/push → context.go

lib/features/events/widgets/
└── event_module_list.dart    ← constructor: Event+Group → groupId+eventId; 5 pushes → context.push

lib/features/groups/screens/
├── group_detail_screen.dart   ← 7 Navigator.push → context.push; also remove Group obj params
├── group_settle_up_screen.dart ← constructor: groupId+Group+preSelectedMemberId → groupId+preSelectedMemberId?
└── group_activity_screen.dart ← already takes groupId only; no change needed

lib/features/ledger/screens/
├── ledger_screen.dart        ← constructor: Event+Group → groupId+eventId; 2 pushes → context.push
├── add_expense_screen.dart   ← already takes groupId+eventId only; no change needed
└── edit_expense_sheet.dart   ← verify constructor signature

lib/features/gear/screens/
└── gear_screen.dart          ← constructor: Event+Group → groupId+eventId

lib/features/logistics/screens/
└── logistics_screen.dart     ← constructor: Event+Group → groupId+eventId

lib/features/vault/screens/
└── vault_screen.dart         ← constructor: Event+Group → groupId+eventId

lib/features/memories/screens/
└── memories_screen.dart      ← constructor: Event+Group → groupId+eventId; FullScreenPhoto stays as Navigator push (overlay)

lib/core/utils/
└── page_transitions.dart     ← DELETE

test/unit/
└── page_transitions_test.dart ← DELETE
```

### Pattern 1: Nested GoRoute Declaration

GoRouter 13.x supports infinitely nested routes via the `routes:` property. Path segments are relative — a child route `path: 'ledger'` under a parent at `/group/:gid/event/:eid` produces the full URL `/group/:gid/event/:eid/ledger`. Path parameters from all ancestor segments are available in `state.pathParameters`.

```dart
// Source: existing app_router.dart + GoRouter 13.x API
GoRoute(
  path: '/group/:gid',
  pageBuilder: (context, state) => CustomTransitionPage(
    key: state.pageKey,
    child: GroupDetailScreen(groupId: state.pathParameters['gid']!),
    transitionsBuilder: _slideRight,
  ),
  routes: [
    GoRoute(
      path: 'settings',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        // Both 'gid' and any child params available here
        child: GroupSettingsScreen(groupId: state.pathParameters['gid']!),
        transitionsBuilder: _slideRight,
      ),
    ),
    GoRoute(
      path: 'event/:eid',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: EventCommandCenter(
          groupId: state.pathParameters['gid']!,
          eventId: state.pathParameters['eid']!,
        ),
        transitionsBuilder: _slideRight,
      ),
      routes: [
        GoRoute(
          path: 'ledger',
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: LedgerScreen(
              groupId: state.pathParameters['gid']!,
              eventId: state.pathParameters['eid']!,
            ),
            transitionsBuilder: _slideRight,
          ),
          routes: [
            GoRoute(
              path: 'add',
              pageBuilder: (context, state) => CustomTransitionPage(
                key: state.pageKey,
                child: AddExpenseScreen(
                  groupId: state.pathParameters['gid']!,
                  eventId: state.pathParameters['eid']!,
                ),
                transitionsBuilder: _slideRight,
              ),
            ),
            GoRoute(
              path: 'edit/:expId',
              pageBuilder: (context, state) => CustomTransitionPage(
                key: state.pageKey,
                child: EditExpenseSheet(
                  groupId: state.pathParameters['gid']!,
                  eventId: state.pathParameters['eid']!,
                  expenseId: state.pathParameters['expId']!,
                ),
                transitionsBuilder: _slideRight,
              ),
            ),
          ],
        ),
        // ... gear, logistics, vault, memories, activity routes
      ],
    ),
  ],
),
```

**Confidence:** HIGH — this is the exact same pattern already used for `/group/:gid/settings` in `app_router.dart`.

### Pattern 2: Screen Constructor Migration (D-14)

Before:
```dart
class LedgerScreen extends ConsumerStatefulWidget {
  final Event event;
  final Group group;
  const LedgerScreen({super.key, required this.event, required this.group});
}
```

After:
```dart
class LedgerScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String eventId;
  const LedgerScreen({super.key, required this.groupId, required this.eventId});
}
```

Inside the screen body, replace `widget.event` accesses with provider lookups:
```dart
// In build():
final eventAsync = ref.watch(eventDetailProvider((groupId: widget.groupId, eventId: widget.eventId)));
final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
```

Handle null case per D-11:
```dart
eventAsync.when(
  data: (event) {
    if (event == null) {
      return _buildNotFound(context); // "This event no longer exists" + Go Home
    }
    return _buildContent(context, event, group);
  },
  loading: () => const Center(child: CircularProgressIndicator()),
  error: (e, _) => _buildError(context),
)
```

**Confidence:** HIGH — `eventDetailProvider` and `groupDetailProvider` are `StreamProvider.family` with the correct key types already.

### Pattern 3: context.push for Navigation

Replace every `Navigator.of(context).push(AppPageRoute(...))` with `context.push(path)`:

```dart
// Before (GroupDetailScreen → EventCommandCenter):
Navigator.of(context).push(
  AppPageRoute(builder: (_) => EventCommandCenter(event: events[i], group: group)),
);

// After:
context.push('/group/$groupId/event/${events[i].id}');
```

For event creation success (D-06), replace the `pop/pop/push` sequence:
```dart
// Before:
Navigator.of(context)
  ..pop()
  ..pop();
Navigator.of(context).push(AppPageRoute(builder: (_) => EventCommandCenter(...)));

// After (replaces entire creation stack with the new event's hub):
context.go('/group/$groupId/event/$newEventId');
```

**Confidence:** HIGH — `context.go` replaces current history, `context.push` adds to it. For event creation, `go` is correct because we do not want back navigation to re-enter the creation flow.

### Pattern 4: GroupSettleUpScreen Query Parameter

`GroupSettleUpScreen` currently takes `Group group` (full object) and optional `String? preSelectedMemberId`. After D-14 migration:

```dart
class GroupSettleUpScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String? preSelectedMemberId; // remains optional
  const GroupSettleUpScreen({
    super.key,
    required this.groupId,
    this.preSelectedMemberId,
  });
}
```

In the router, use `state.uri.queryParameters`:
```dart
GoRoute(
  path: 'settle-up',
  pageBuilder: (context, state) => CustomTransitionPage(
    key: state.pageKey,
    child: GroupSettleUpScreen(
      groupId: state.pathParameters['gid']!,
      preSelectedMemberId: state.uri.queryParameters['memberId'],
    ),
    transitionsBuilder: _slideRight,
  ),
),
```

Navigate with optional query param:
```dart
// Without pre-selection (hero card, D-22 entry 1):
context.push('/group/$groupId/settle-up');

// With pre-selection (member card settle-up tap, D-22 entry 2):
context.push('/group/$groupId/settle-up?memberId=$participantId');
```

**Confidence:** HIGH — `state.uri.queryParameters` is standard GoRouter 13.x API.

### Pattern 5: FullScreenPhoto Stays as Navigator.push

`MemoriesScreen._showFullScreen()` uses a `PageRouteBuilder` with `opaque: false` and `barrierColor: Colors.black87` to create a full-screen overlay that is transparent behind the photo. This is NOT a navigation destination — it is an in-screen overlay lightbox. D-10 says the memory detail viewer at `/memories/:memId` is a GoRouter route. These are two different things:

- `/memories/:memId` — the per-memory detail route (deep-linkable, standard slide transition)
- `FullScreenPhoto` overlay — modal-style photo viewer launched from within `MemoriesScreen`, stays as `Navigator.push` with `PageRouteBuilder`

The `FullScreenPhoto` overlay should NOT be converted to GoRouter. Converting it would break the transparent-background overlay effect, since GoRouter always produces opaque pages.

**Confidence:** HIGH — `opaque: false` is incompatible with GoRouter's `CustomTransitionPage` (which defaults `opaque: true`).

### Pattern 6: Shared Transition Builder

Extract the repeated `SlideTransition` builder to a helper to avoid repeating it across ~14 routes:

```dart
// Add to app_router.dart as a module-level function
Widget _slideRightTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  );
}
```

This matches `AppPageRoute.buildTransitions` exactly — same offset, same curve, same result — satisfying D-03 with no visual regression.

### Pattern 7: AppRoutes Constants

Add new static constants to `AppRoutes` for all new paths:

```dart
class AppRoutes {
  // existing...
  static const String groupSettleUp = '/group/:gid/settle-up';
  static const String createEvent = '/group/:gid/create-event';
  static const String createEventTyped = '/group/:gid/create-event/:type';
  static const String eventHub = '/group/:gid/event/:eid';
  static const String eventLedger = '/group/:gid/event/:eid/ledger';
  static const String eventLedgerAdd = '/group/:gid/event/:eid/ledger/add';
  static const String eventLedgerEdit = '/group/:gid/event/:eid/ledger/edit/:expId';
  static const String eventGear = '/group/:gid/event/:eid/gear';
  static const String eventLogistics = '/group/:gid/event/:eid/logistics';
  static const String eventVault = '/group/:gid/event/:eid/vault';
  static const String eventMemories = '/group/:gid/event/:eid/memories';
  static const String eventMemoryDetail = '/group/:gid/event/:eid/memories/:memId';
  static const String eventActivity = '/group/:gid/event/:eid/activity';
}
```

For type-safe navigation, use helper functions rather than string interpolation at call sites:
```dart
// These do NOT live in AppRoutes (they are runtime helpers, not compile-time constants)
String groupEventPath(String gid, String eid) => '/group/$gid/event/$eid';
String groupLedgerPath(String gid, String eid) => '/group/$gid/event/$eid/ledger';
```

### Pattern 8: Test Router Helper (D-13)

The Phase 18 tests established the `GoRouter` + `MaterialApp.router` pattern. Phase 19 must extend it:

```dart
// In a shared test helper file: test/helpers/test_router.dart
GoRouter testRouter({
  String initialLocation = '/home',
  List<RouteBase> extraRoutes = const [],
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('Home'))),
      GoRoute(path: '/group/:gid', builder: (ctx, state) =>
          Scaffold(body: Text('Group:${state.pathParameters['gid']}'))),
      GoRoute(path: '/group/:gid/event/:eid', builder: (ctx, state) =>
          Scaffold(body: Text('Event:${state.pathParameters['eid']}'))),
      GoRoute(path: '/group/:gid/event/:eid/ledger', builder: (ctx, state) =>
          Scaffold(body: Text('Ledger'))),
      // ... add routes as needed per test file
      ...extraRoutes,
    ],
  );
}
```

Tests that need to verify navigation (e.g., tapping an event card pushes to `/group/:gid/event/:eid`) can use `find.text('Event:evt-1')` to confirm arrival at the route stub.

### Anti-Patterns to Avoid

- **Passing objects via `state.extra`:** D-08 explicitly prohibits this. Deep links arriving without prior navigation state would receive null `extra` and crash.
- **Creating transitional dual constructors:** D-14 says clean break. No `LedgerScreen.fromObject(...)` shims.
- **Making FullScreenPhoto a GoRouter route:** It uses `opaque: false` — GoRouter pages are always opaque. The overlay must remain as `Navigator.push` with `PageRouteBuilder`.
- **Using `context.go` instead of `context.push` for module navigation:** `go` replaces the stack. Users tapping the back button would jump to home instead of the event hub.
- **Forgetting to handle null event/group in screen body:** D-11 says render an error state, not redirect. A screen that calls `.event!` will throw on a stale deep link.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Path parameter inheritance in nested routes | Manual parameter threading | GoRouter `state.pathParameters` | All ancestor path params are automatically merged into the map for child routes |
| Query parameters | Custom URL parsing | `state.uri.queryParameters['key']` | GoRouter parses the full URI; `state.uri` is always populated |
| Transition animation | New animation class | `CustomTransitionPage` with `_slideRightTransition` helper | Identical to current `AppPageRoute` behavior |
| Screen not-found state | Custom 404 screen | In-screen null check + "Go Home" button | Per D-11; avoids adding a new route and is consistent with Phase 18 error pattern |

---

## Runtime State Inventory

This is a pure code refactoring phase — no data migration, no Firestore schema changes, no stored route state. Skip.

---

## Common Pitfalls

### Pitfall 1: Parent Path Parameter Names Must Be Consistent

**What goes wrong:** If the parent route uses `:id` (current `/group/:id`) but child routes reference `state.pathParameters['gid']`, the parameter will be null.

**Why it happens:** GoRouter uses the parameter name as defined in the nearest ancestor that declares it. The current `groupDetail` route uses `path: AppRoutes.groupDetail` which is `/group/:id`. Every child route added under it must use `state.pathParameters['id']`, NOT `state.pathParameters['gid']`.

**How to avoid:** Either rename the parent's `:id` to `:gid` (rename the path constant and all existing references — about 5 call sites) OR keep `:id` and use `state.pathParameters['id']` consistently in all child routes. The D-02 route tree shows `:gid` as the parameter name, so the rename is the correct path.

**Warning signs:** `state.pathParameters['gid']` returns null at runtime; `!` operator throws; screen shows an error state unexpectedly.

**Files affected by rename:** `AppRoutes.groupDetail`, `app_router.dart` (parent route path + `GroupDetailScreen` instantiation), `home_screen.dart` (`context.push('/group/${group.id}')`), `join_group_screen.dart`, `create_group_screen.dart`.

### Pitfall 2: context.go vs context.push for Event Creation

**What goes wrong:** Using `context.push` for the creation success navigation adds the creation screens to history. Pressing back from `EventCommandCenter` returns to `CreateEventScreen` — the event already exists and the form is stale.

**Why it happens:** `context.push` always adds to the history stack. `context.go` replaces history with a new location.

**How to avoid:** For `CreateEventScreen._submitForm`, after creating the event, call `context.go('/group/$groupId/event/$newEventId')`. This clears the creation flow and puts only the new event hub in the stack above the group detail screen.

### Pitfall 3: EditExpenseSheet Uses showModalBottomSheet, Not Navigation

**What goes wrong:** `ledger_screen.dart._editExpense` currently calls `showModalBottomSheet(...)` for `EditExpenseSheet`. D-07 says it should become `/group/:gid/event/:eid/ledger/edit/:expId`. Changing `showModalBottomSheet` to `context.push` changes the UX (no longer a bottom sheet, now a full-screen slide). This may be intentional (D-07 says "No modals") but could feel jarring to users.

**Why it happens:** The existing `EditExpenseSheet` is named "Sheet" because it was designed as a bottom sheet. If converted to a full-page route, the `ModuleHeader` pattern should be applied to it like other screens.

**How to avoid:** Be explicit in the plan that `EditExpenseSheet` becomes a full-page route (consistent with D-07 "No modals"). Rename it `EditExpenseScreen` to avoid confusion. Ensure the screen has a proper header/back button — it currently relies on the modal's drag-to-dismiss for navigation.

### Pitfall 4: GoRouter Adds Back Navigation From Within the Router Subtree Only

**What goes wrong:** BottomNavShell uses `IndexedStack` outside GoRouter. When GoRouter navigates to `/group/:gid/event/:eid`, the back button removes that route and returns to `/group/:gid`. This is correct. But the hardware back button behavior depends entirely on GoRouter's history — not the IndexedStack state.

**Why it happens:** The BottomNavShell is rendered as the child of the `/home` GoRoute. GoRouter manages the pages list for its Navigator. IndexedStack within the home screen manages tab state only, not navigation pages.

**How to avoid:** No change needed — this behavior is already correct in Phase 18 and remains correct in Phase 19.

### Pitfall 5: Screen Tests That Use MaterialApp (Not MaterialApp.router) Will Break

**What goes wrong:** `event_command_center_test.dart` currently wraps the widget in `MaterialApp(home: EventCommandCenter(...))`. After D-14, `EventCommandCenter` takes `groupId`/`eventId` strings instead of full objects. The tests need provider overrides to supply the group and event data. More critically, if the screen calls `context.push(...)` internally (e.g., on FAB tap), the `MaterialApp` (not `MaterialApp.router`) test will throw a `GoRouterMissingException`.

**Why it happens:** `context.push` requires GoRouter in the widget tree. `MaterialApp` does not provide it.

**How to avoid:** Per D-13, all navigation tests must use `MaterialApp.router(routerConfig: testRouter(...))`. Tests that only verify rendering (not navigation) can still use `MaterialApp` if no `context.push` is triggered. Add provider overrides for `groupDetailProvider` and `eventDetailProvider` in every test helper.

### Pitfall 6: GroupSettleUpScreen Takes Group Object (Not Just groupId)

**What goes wrong:** `GroupSettleUpScreen` currently takes `final Group group` as a required param (not just `groupId`). If only `groupId` is added to the router and the screen still reads `widget.group.currency` directly, the app will crash.

**Why it happens:** The screen uses `group.currency` for display and `group.id` for the settlement service call. These must migrate to provider lookup.

**How to avoid:** As part of D-14, `GroupSettleUpScreen` receives `groupId` and uses `ref.watch(groupDetailProvider(groupId))` for all group data. The `preSelectedMemberId` parameter migrates to a query param read via `state.uri.queryParameters['memberId']`.

---

## Code Examples

### Verified Pattern: Existing Nested Route in app_router.dart

```dart
// Source: lib/core/router/app_router.dart (lines 126-170)
GoRoute(
  path: AppRoutes.groupDetail,        // '/group/:id'
  pageBuilder: (context, state) => CustomTransitionPage(
    key: state.pageKey,
    child: GroupDetailScreen(groupId: state.pathParameters['id']!),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      );
    },
  ),
  routes: [
    GoRoute(
      path: 'settings',   // resolves to /group/:id/settings
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: GroupSettingsScreen(groupId: state.pathParameters['id']!),
        transitionsBuilder: /* same SlideTransition */ ...,
      ),
    ),
  ],
),
```

### Verified Pattern: Existing context.push in home_screen.dart

```dart
// Source: lib/features/home/screens/home_screen.dart (lines 163-166)
onTap: () => context.push('/group/${group.id}'),
```

### Verified Pattern: Test Router Pattern from Phase 18

```dart
// Source: test/features/home/home_screen_groups_test.dart (lines 67-94)
Widget _buildTestApp(Widget widget, {List<Override> overrides = const []}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (ctx, state) => widget),
      GoRoute(path: '/create-group', builder: (ctx, state) =>
          const Scaffold(body: Text('CreateGroupScreen'))),
      GoRoute(path: '/group/:id', builder: (ctx, state) =>
          Scaffold(body: Text('GroupDetail:${state.pathParameters['id']}'))),
    ],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}
```

### Verified Pattern: eventDetailProvider Lookup

```dart
// Source: lib/features/events/providers/event_provider.dart (lines 79-91)
final eventDetailProvider =
    StreamProvider.family<Event?, ({String groupId, String eventId})>(
      (ref, params) {
        return FirebaseConfig.firestore
          .collection('groups').doc(params.groupId)
          .collection('events').doc(params.eventId)
          .snapshots()
          .map((doc) => doc.exists ? Event.fromDoc(doc) : null);
      });

// Usage in screen after constructor migration:
final eventAsync = ref.watch(
  eventDetailProvider((groupId: widget.groupId, eventId: widget.eventId)),
);
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `Navigator.push(AppPageRoute(...))` | `context.push('/path')` | Phase 19 | Deep links, back button correctness, URL reflects app state |
| Screen constructors take full objects | Constructors take string IDs | Phase 19 | Provider lookup inside screen; no state.extra needed |
| `AppPageRoute` / `AppBottomSheetRoute` | `CustomTransitionPage` | Phase 19 | Same transitions, declarative routing |
| `page_transitions.dart` | Deleted | Phase 19 | Dead code eliminated |

**Deprecated/outdated after Phase 19:**
- `AppPageRoute`: fully replaced by GoRouter `CustomTransitionPage`. Zero consumers after migration.
- `AppBottomSheetRoute`: not actually used by any call site (all current calls use `AppPageRoute`). Already dead code — confirmed by grep.

---

## Open Questions

1. **EditExpenseSheet widget name/structure after modal-to-route conversion**
   - What we know: D-07 says it becomes a GoRouter route. The widget is currently named "Sheet" and designed as a bottom sheet (no AppBar, relies on modal dismiss).
   - What's unclear: Does the screen need to be rebuilt with a `ModuleHeader` / `AppBar` for the back button? Or does it receive a system back button from GoRouter?
   - Recommendation: GoRouter routes get the system back button automatically via `WillPopScope`/`NavigatorObserver`. However, the screen should be given a `ModuleHeader` for visual consistency with other screens. Rename to `EditExpenseScreen` in this phase.

2. **GroupActivityScreen route vs existing app usage**
   - What we know: D-15 creates `/group/:gid/event/:eid/activity`. There is also a `GroupActivityScreen(groupId: groupId)` that shows group-level activity (not event-level). Currently reached by `Navigator.push` from the "See all activity" button in `GroupDetailScreen`.
   - What's unclear: Should the group-level activity screen become `/group/:gid/activity`? It is not listed in D-02's route tree.
   - Recommendation: Add `/group/:gid/activity` to the router to replace the `Navigator.push` from `GroupDetailScreen._buildActivitySection`. The planner should address this in the task breakdown.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is a pure code/routing refactoring. No external tools, databases, or services beyond the existing Flutter + GoRouter SDK.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (built-in), Flutter 3.41.5 |
| Config file | None — `flutter test` at project root |
| Quick run command | `flutter test test/features/ test/unit/ -x slow` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| NAV-03 | EventCommandCenter reachable via GoRouter URL without Navigator.push | widget/integration | `flutter test test/features/events/event_command_center_test.dart` | ✅ (needs update) |
| NAV-03 | Module screens (Ledger, Gear, etc.) reachable via GoRouter subroutes | widget | `flutter test test/features/events/event_module_list_test.dart` | ✅ (needs update) |
| NAV-03 | GroupDetailScreen routes to event via context.push | widget | `flutter test test/features/group_detail_screen_test.dart` | ✅ (needs update) |
| NAV-03 | Hardware back button works correctly through nested routes | widget | `flutter test test/features/events/` | ✅ (needs update) |
| NAV-03 | AppPageRoute/page_transitions.dart deleted, no compilation errors | static | `flutter analyze` | N/A |
| NAV-03 | CLAUDE.md navigation section updated | manual | manual inspection | N/A |

### Sampling Rate

- **Per task commit:** `flutter analyze && flutter test test/unit/` (fast — unit tests only, ~30s)
- **Per wave merge:** `flutter test` (full suite, ~743 tests)
- **Phase gate:** Full suite green + `flutter analyze` clean before marking complete

### Wave 0 Gaps

- [ ] `test/helpers/test_router.dart` — shared `testRouter()` helper for navigation tests (D-13). All existing test files that will exercise navigation need this.
- [ ] `test/features/events/event_command_center_test.dart` — update provider overrides to use `groupDetailProvider`/`eventDetailProvider` after D-14 constructor migration
- [ ] `test/features/events/event_module_list_test.dart` — same as above
- [ ] `test/features/group_detail_screen_test.dart` — wrap in `testRouter`, add `/group/:gid/event/:eid` route stub to verify navigation

---

## Sources

### Primary (HIGH confidence)
- `lib/core/router/app_router.dart` — baseline GoRouter configuration, existing nested route pattern (`/group/:id/settings`), `CustomTransitionPage` usage
- `lib/core/utils/page_transitions.dart` — `AppPageRoute` implementation (identical transition to what GoRouter will produce)
- GoRouter 13.2.5 in `pubspec.lock` — installed version confirmed

### Secondary (MEDIUM confidence)
- [go_router pub.dev](https://pub.dev/packages/go_router) — version 17.1.0 current stable; project stays on 13.2.5 per CLAUDE.md (separate upgrade milestone)
- [Flutter Navigation GoRouter Go vs Push](https://codewithandrea.com/articles/flutter-navigation-gorouter-go-vs-push/) — `context.go` vs `context.push` semantics verified
- [GoRouter nested routes example](https://dev.to/7twilight/mastering-nested-navigation-in-flutter-with-gorouter-and-a-bottom-nav-bar-555l) — GoRouter nested subroutes pattern

### Tertiary (LOW confidence)
- None — all critical patterns verified against live codebase code.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — GoRouter 13.2.5 installed, verified in lockfile
- Architecture: HIGH — nested route pattern already proven in codebase with `/group/:id/settings`
- Pitfalls: HIGH — all derived from direct reading of the actual affected source files
- Constructor migration scope: HIGH — all 9 affected screen constructors read and documented

**Research date:** 2026-03-30
**Valid until:** 2026-05-01 (GoRouter stable; Flutter/Riverpod not changing in this window)
