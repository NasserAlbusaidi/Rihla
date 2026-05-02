# Launch UX Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix 4 UX gaps before app launch — gate event creation to creator, fix bottom nav, skip EventCommandCenter hub, add event menu to Ledger.

**Architecture:** Pure UI layer changes across 3 files. No model, service, or router changes. All role checks use the existing `currentUserIdProvider` + `group.createdBy` pattern already used elsewhere in the codebase.

**Tech Stack:** Flutter, Riverpod 2.x, GoRouter, Iconsax icons

---

## Context

The app is Splitwise organized by groups and events. Two roles:
- **Creator** — creates events, removes members, manages group settings
- **Member** — adds expenses, settles up, views everything

All auth is anonymous Firebase. The current user's UID comes from `currentUserIdProvider` (defined in `lib/features/groups/providers/group_balance_provider.dart`). The group creator's UID is `group.createdBy` (a `String` field on the `Group` model).

**Run all tests with:** `flutter test`  
**Run a single test file:** `flutter test test/path/to/file.dart`  
**Analyze for type errors:** `flutter analyze`

---

## Task 1: Gate event creation FAB and empty state to creator only

**Files:**
- Modify: `lib/features/groups/screens/group_detail_screen.dart`
- Modify: `test/features/group_detail_screen_test.dart`

### Context

The FAB (floating action button) that navigates to `/group/$groupId/create-event` is currently shown to all members. It lives at the `Scaffold.floatingActionButton` in the `build()` method (~line 61). The group data is available via `groupAsync` which is `ref.watch(groupDetailProvider(groupId))`.

The current user UID is already used inside `_buildContent()` via `ref.watch(currentUserIdProvider)`. We need to also use it at the `Scaffold` level to conditionally show/hide the FAB.

The `_buildEventsSection` method also renders an empty state with a "Create Event" action button (~line 358) — this must also be gated.

**Pattern already used** in `group_settings_screen.dart`:
```dart
final isCreator = currentUserId == group.createdBy;
```

### Step 1: Write the failing tests

Add these two tests to `test/features/group_detail_screen_test.dart`.

First, read the existing test file to find the provider override helper and where to insert. Look for the section that builds the widget under test — it uses `ProviderScope` with overrides including `currentUserIdProvider`.

Add at the end of the existing test group (or in a new group `'FAB visibility'`):

```dart
testWidgets('creator sees FAB', (tester) async {
  // pump GroupDetailScreen with currentUid == group.createdBy
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // ... copy the minimal overrides from existing tests in this file ...
        currentUserIdProvider.overrideWithValue('uid-creator'),
        groupDetailProvider(_groupId).overrideWith((ref) =>
            Stream.value(_testGroup)),
        // add other required overrides: groupEventsProvider, groupMembersProvider,
        // groupBalancesProvider, groupActivityProvider, sharedPreferencesProvider
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: GroupDetailScreen(groupId: _groupId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(FloatingActionButton), findsOneWidget);
});

testWidgets('member does not see FAB', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('uid-member'), // NOT the creator
        groupDetailProvider(_groupId).overrideWith((ref) =>
            Stream.value(_testGroup)), // _testGroup.createdBy == 'uid-creator'
        // ... same other overrides ...
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: GroupDetailScreen(groupId: _groupId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(FloatingActionButton), findsNothing);
});
```

**Note:** Look at existing tests in the file to copy the exact override list — especially `sharedPreferencesProvider`, `groupEventsProvider`, `groupMembersProvider`, `groupBalancesProvider`, and `expenseProvider`. Don't guess; read the file first.

### Step 2: Run tests to verify they fail

```bash
flutter test test/features/group_detail_screen_test.dart
```

Expected: both new tests FAIL (FAB is currently always visible)

### Step 3: Implement the FAB gate

In `lib/features/groups/screens/group_detail_screen.dart`, find the `build()` method. The `groupAsync` is already watched there. Add a `currentUid` watch and compute `isCreator`:

```dart
@override
Widget build(BuildContext context) {
  final groupAsync = ref.watch(groupDetailProvider(groupId));
  final currentUid = ref.watch(currentUserIdProvider); // ADD THIS

  final isCreator = currentUid != null &&
      groupAsync.valueOrNull?.createdBy == currentUid; // ADD THIS

  return Scaffold(
    key: GroupKeys.detailScreen,
    backgroundColor: context.colors.scaffoldBackground,
    floatingActionButton: isCreator  // CHANGE: was unconditional
        ? Semantics(
            label: 'Create event',
            button: true,
            child: FloatingActionButton(
              onPressed: () {
                HapticService.lightClick();
                context.push('/group/$groupId/create-event');
              },
              backgroundColor: context.colors.primary,
              shape: const CircleBorder(),
              child: Icon(Iconsax.add, color: context.colors.textOnPrimary),
            ),
          )
        : null,  // CHANGE: null hides the FAB
    // ... rest unchanged
```

### Step 4: Gate the empty state "Create Event" button

Inside `_buildEventsSection`, find the `EmptyStateView` (roughly line 352-360). It currently always shows `actionLabel: 'Create Event'` and `onAction`. Gate it:

```dart
// BEFORE:
return EmptyStateView(
  key: GroupKeys.noEventsEmpty,
  icon: Iconsax.calendar_add,
  title: 'No events yet',
  message: 'Create your first event to start planning together.',
  actionLabel: 'Create Event',
  onAction: () => context.push('/group/$groupId/create-event'),
);

// AFTER:
return EmptyStateView(
  key: GroupKeys.noEventsEmpty,
  icon: Iconsax.calendar_add,
  title: 'No events yet',
  message: isCreator
      ? 'Create your first event to start planning together.'
      : 'Waiting for the group creator to add the first event.',
  actionLabel: isCreator ? 'Create Event' : null,
  onAction: isCreator
      ? () => context.push('/group/$groupId/create-event')
      : null,
);
```

**Note:** `EmptyStateView` accepts nullable `actionLabel` and `onAction` — check `lib/shared/widgets/empty_state_view.dart` to confirm the signature accepts nulls before writing this.

The `isCreator` value from `build()` is not directly available inside `_buildEventsSection` — you'll need to pass it as a parameter:

```dart
// Change signature:
Widget _buildEventsSection(BuildContext context, Group group, {required bool isCreator})

// Update call site in _buildContent:
_buildEventsSection(context, group, isCreator: isCreator),
```

### Step 5: Run tests to verify they pass

```bash
flutter test test/features/group_detail_screen_test.dart
```

Expected: all tests PASS including the two new ones

### Step 6: Commit

```bash
git add lib/features/groups/screens/group_detail_screen.dart \
        test/features/group_detail_screen_test.dart
git commit -m "feat: gate event creation FAB and empty state to creator only"
```

---

## Task 2: Fix bottom nav — remove Chats, wire Activity

**Files:**
- Modify: `lib/features/home/widgets/bottom_nav_shell.dart`
- Modify: `test/features/home/home_screen_groups_test.dart` (update tab count assertions if any)

### Context

`BottomNavShell` in `lib/features/home/widgets/bottom_nav_shell.dart` currently has 4 tabs:
- 0: Groups (real content)
- 1: Activity (placeholder)
- 2: Chats (placeholder) ← REMOVE
- 3: Profile (real ProfileScreen) ← becomes index 2

Import needed: `CrossGroupActivityScreen` from `lib/features/home/screens/cross_group_activity_screen.dart`

### Step 1: Write the failing test

Add to `test/features/home/home_screen_groups_test.dart` (or a new file `test/features/home/bottom_nav_test.dart`):

```dart
testWidgets('bottom nav has 3 tabs: Groups, Activity, Profile', (tester) async {
  // pump BottomNavShell with minimal child
  await tester.pumpWidget(
    ProviderScope(
      overrides: [/* sharedPreferencesProvider override */],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: BottomNavShell(child: const SizedBox()),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // 3 tabs total
  expect(find.byType(BottomNavigationBarItem), findsNWidgets(3));
  
  // Correct labels
  expect(find.text('Groups'), findsOneWidget);
  expect(find.text('Activity'), findsOneWidget);
  expect(find.text('Profile'), findsOneWidget);
  
  // Chats is gone
  expect(find.text('Chats'), findsNothing);
});

testWidgets('Activity tab shows CrossGroupActivityScreen', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [/* sharedPreferencesProvider + crossGroupBalanceProvider overrides */],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: BottomNavShell(child: const SizedBox()),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Tap Activity tab (index 1)
  await tester.tap(find.text('Activity'));
  await tester.pumpAndSettle();

  // CrossGroupActivityScreen renders (find its key or a distinctive widget)
  expect(find.byType(CrossGroupActivityScreen), findsOneWidget);
});
```

### Step 2: Run tests to verify they fail

```bash
flutter test test/features/home/
```

Expected: new tests FAIL (4 tabs, Activity shows placeholder)

### Step 3: Implement the changes

In `lib/features/home/widgets/bottom_nav_shell.dart`:

1. Add import at the top:
```dart
import '../screens/cross_group_activity_screen.dart';
```

2. In `_buildBody()`, change the `tabs` list from:
```dart
final tabs = [
  widget.child,           // 0: Groups
  const _PlaceholderTab(), // 1: Activity  
  const _PlaceholderTab(), // 2: Chats
  const ProfileScreen(),   // 3: Profile
];
```
to:
```dart
final tabs = [
  widget.child,                      // 0: Groups
  const CrossGroupActivityScreen(),  // 1: Activity (wired)
  const ProfileScreen(),             // 2: Profile
];
```

3. In `_buildNavBar()`, change the `items` list from 4 items to 3:
```dart
items: const [
  BottomNavigationBarItem(
    icon: Icon(Iconsax.people, key: HomeKeys.bottomNavGroups),
    label: 'Groups',
  ),
  BottomNavigationBarItem(
    icon: Icon(Iconsax.activity, key: HomeKeys.bottomNavActivity),
    label: 'Activity',
  ),
  BottomNavigationBarItem(
    icon: Icon(Iconsax.profile_circle, key: HomeKeys.bottomNavProfile),
    label: 'Profile',
  ),
],
```

Remove the Chats `BottomNavigationBarItem` entirely.

**Note:** `HomeKeys.bottomNavChats` will now be unused. Delete it from `lib/features/home/keys/home_keys.dart` if it exists there, or leave it — `flutter analyze` will catch unused keys.

### Step 4: Run tests

```bash
flutter test test/features/home/
flutter analyze
```

Expected: all PASS, no analysis errors. Fix any unused key warnings.

### Step 5: Commit

```bash
git add lib/features/home/widgets/bottom_nav_shell.dart \
        lib/features/home/keys/home_keys.dart \
        test/features/home/
git commit -m "feat: replace 4-tab nav with 3-tab nav, wire Activity to CrossGroupActivityScreen"
```

---

## Task 3: Event card navigates directly to Ledger

**Files:**
- Modify: `lib/features/groups/screens/group_detail_screen.dart`
- Modify: `test/features/group_detail_screen_test.dart`

### Context

In `_buildEventsSection`, the `EventCard` `onTap` currently navigates to:
```
/group/$groupId/event/${events[i].id}
```
which lands on `EventCommandCenter`. After Phase 39, EventCommandCenter has only one module (Ledger) making it a pointless hop.

Change to:
```
/group/$groupId/event/${events[i].id}/ledger
```

EventCommandCenter stays in the router — just unreachable from normal navigation.

### Step 1: Write the failing test

Add to `test/features/group_detail_screen_test.dart`:

```dart
testWidgets('tapping event card navigates to ledger route', (tester) async {
  final navigatedRoutes = <String>[];

  // Use a GoRouter that records pushes
  final router = GoRouter(
    initialLocation: '/group/group-1',
    routes: [
      GoRoute(
        path: '/group/:gid',
        builder: (context, state) => ProviderScope(
          overrides: [/* same overrides as creator tests */],
          child: GroupDetailScreen(groupId: state.pathParameters['gid']!),
        ),
        routes: [
          GoRoute(
            path: 'event/:eid/ledger',
            builder: (context, state) {
              navigatedRoutes.add('/group/${state.pathParameters['gid']}'
                  '/event/${state.pathParameters['eid']}/ledger');
              return const Scaffold(body: Text('Ledger'));
            },
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    MaterialApp.router(routerConfig: router),
  );
  await tester.pumpAndSettle();

  // Tap the first event card
  await tester.tap(find.byType(EventCard).first);
  await tester.pumpAndSettle();

  expect(navigatedRoutes, contains(contains('/ledger')));
});
```

**Note:** This test uses a real GoRouter to verify the route. If the existing test patterns in the file use a simpler approach (just checking navigation callbacks), match that pattern instead — the important thing is verifying the route ends in `/ledger`, not `/event/:eid`.

### Step 2: Run the test to verify it fails

```bash
flutter test test/features/group_detail_screen_test.dart
```

Expected: FAIL (currently navigates to `/event/:eid`, not `/ledger`)

### Step 3: Implement the change

In `lib/features/groups/screens/group_detail_screen.dart`, in `_buildEventsSection`, find the `EventCard` `onTap`:

```dart
// BEFORE (~line 375):
onTap: () => context.push(
  '/group/$groupId/event/${events[i].id}',
),

// AFTER:
onTap: () => context.push(
  '/group/$groupId/event/${events[i].id}/ledger',
),
```

### Step 4: Run tests

```bash
flutter test test/features/group_detail_screen_test.dart
flutter test test/features/events/
```

Expected: all PASS

### Step 5: Commit

```bash
git add lib/features/groups/screens/group_detail_screen.dart \
        test/features/group_detail_screen_test.dart
git commit -m "feat: event card navigates directly to ledger, skip EventCommandCenter"
```

---

## Task 4: Add event settings + activity overflow menu to Ledger header

**Files:**
- Modify: `lib/features/ledger/screens/ledger_screen.dart`
- Modify: `test/features/ledger/` (new test file or extend existing)

### Context

Since EventCommandCenter is now bypassed, users have no path to event settings or event activity. The `ModuleHeader` widget accepts an `actions` parameter (`List<Widget>?`). Add a `PopupMenuButton` there with two items:
- "Event activity" → `context.push('/group/$groupId/event/$eventId/activity')`
- "Event settings" → `context.push('/group/$groupId/event/$eventId/settings')`

`LedgerScreen` already receives `groupId` and `eventId` as constructor params.

**ModuleHeader signature** (from `lib/shared/widgets/module_header.dart`):
```dart
ModuleHeader({
  required String title,
  List<Widget>? actions,
})
```

### Step 1: Write the failing test

Create `test/features/ledger/ledger_screen_overflow_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/screens/ledger_screen.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
// add other imports as needed

void main() {
  group('LedgerScreen overflow menu', () {
    Widget buildLedger({List<Override> extraOverrides = const []}) {
      return ProviderScope(
        overrides: [
          // Override eventDetailProvider to return a minimal event
          // Override expenseStreamProvider to return empty list
          // Override settlementStreamProvider to return empty list
          // Override sharedPreferencesProvider
          ...extraOverrides,
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: LedgerScreen(groupId: 'g1', eventId: 'e1'),
        ),
      );
    }

    testWidgets('overflow menu button is visible', (tester) async {
      await tester.pumpWidget(buildLedger());
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuButton), findsOneWidget);
    });

    testWidgets('overflow menu has Event activity and Event settings items',
        (tester) async {
      await tester.pumpWidget(buildLedger());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton));
      await tester.pumpAndSettle();

      expect(find.text('Event activity'), findsOneWidget);
      expect(find.text('Event settings'), findsOneWidget);
    });
  });
}
```

**Note:** Look at `test/features/events/event_settings_screen_test.dart` for the exact provider overrides needed to pump `LedgerScreen`. Match those patterns.

### Step 2: Run the test to verify it fails

```bash
flutter test test/features/ledger/ledger_screen_overflow_test.dart
```

Expected: FAIL (no PopupMenuButton exists yet)

### Step 3: Implement the overflow menu

In `lib/features/ledger/screens/ledger_screen.dart`, find where `ModuleHeader` is constructed. It will look something like:

```dart
ModuleHeader(title: event.name)
```

Change it to:

```dart
ModuleHeader(
  title: event.name,
  actions: [
    PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'activity') {
          context.push('/group/$groupId/event/$eventId/activity');
        } else if (value == 'settings') {
          context.push('/group/$groupId/event/$eventId/settings');
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'activity',
          child: Text('Event activity'),
        ),
        PopupMenuItem(
          value: 'settings',
          child: Text('Event settings'),
        ),
      ],
    ),
  ],
)
```

**Note:** `LedgerScreen` is a `ConsumerWidget` — `context` is available in `build(BuildContext context, WidgetRef ref)`. The `groupId` and `eventId` are instance fields on the widget.

### Step 4: Run tests

```bash
flutter test test/features/ledger/
flutter analyze
```

Expected: all PASS, no analysis errors

### Step 5: Commit

```bash
git add lib/features/ledger/screens/ledger_screen.dart \
        test/features/ledger/ledger_screen_overflow_test.dart
git commit -m "feat: add event settings and activity overflow menu to ledger header"
```

---

## Final Verification

Run the full test suite and analyzer:

```bash
flutter test
flutter analyze
```

Expected: all tests pass, no analysis errors.

If any golden tests fail (they compare pixel-perfect screenshots), regenerate them:

```bash
flutter test --update-goldens test/goldens/
```

Then commit the updated goldens:

```bash
git add test/goldens/
git commit -m "chore: update golden snapshots for launch UX fixes"
```
