import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/event_type_config.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/create_event_screen.dart';
import 'package:safar/features/events/screens/event_type_picker_screen.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Stub group used across tests.
final _testGroup = Group(
  id: 'group-1',
  name: 'Adventure Crew',
  inviteCode: 'ABC123',
  createdBy: 'uid-creator',
  memberIds: const ['uid-creator', 'uid-member'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

/// Stub members for participant picker tests.
final _testMembers = [
  GroupMember(
    id: 'mem-1',
    groupId: 'group-1',
    userId: 'uid-creator',
    displayName: 'Alice',
    role: 'CREATOR',
    joinedAt: DateTime(2026, 1, 1),
  ),
  GroupMember(
    id: 'mem-2',
    groupId: 'group-1',
    userId: 'uid-member',
    displayName: 'Bob',
    role: 'MEMBER',
    joinedAt: DateTime(2026, 1, 2),
  ),
];

/// Wraps a widget in ProviderScope + MaterialApp with standard test overrides.
Widget _wrapPicker(Widget child, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: MaterialApp(home: child),
  );
}

Widget _wrapCreate(Widget child, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      groupMembersProvider('group-1').overrideWith(
        (ref) => Stream.value(_testMembers),
      ),
      groupDetailProvider('group-1').overrideWith(
        (ref) => Stream.value(_testGroup),
      ),
      eventLoadingProvider.overrideWith((ref) => false),
    ],
    child: MaterialApp(home: child),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'device_name': 'Test User'});
    prefs = await SharedPreferences.getInstance();
  });

  // -------------------------------------------------------------------------
  // EventTypePickerScreen
  // -------------------------------------------------------------------------

  group('EventTypePickerScreen', () {
    testWidgets('displays all 5 event type cards', (tester) async {
      await tester.pumpWidget(
        _wrapPicker(
          const EventTypePickerScreen(groupId: 'group-1'),
          prefs,
        ),
      );
      await tester.pumpAndSettle();

      // Verify all 5 type labels appear
      for (final config in EventTypeConfig.allTypes) {
        expect(find.text(config.label), findsOneWidget,
            reason: 'Expected type label "${config.label}" to appear');
      }
    });

    testWidgets('shows AppBar title "Choose Event Type"', (tester) async {
      await tester.pumpWidget(
        _wrapPicker(
          const EventTypePickerScreen(groupId: 'group-1'),
          prefs,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(EventKeys.eventTypePickerTitle), findsOneWidget);
    });

    testWidgets('shows 5 type descriptions', (tester) async {
      await tester.pumpWidget(
        _wrapPicker(
          const EventTypePickerScreen(groupId: 'group-1'),
          prefs,
        ),
      );
      await tester.pumpAndSettle();

      for (final config in EventTypeConfig.allTypes) {
        expect(find.text(config.description), findsOneWidget,
            reason: 'Expected description for ${config.label}');
      }
    });

    testWidgets('tapping type card navigates to CreateEventScreen',
        (tester) async {
      // EventTypePickerScreen uses context.push so we need MaterialApp.router
      final router = GoRouter(
        initialLocation: '/group/group-1/create-event',
        routes: [
          GoRoute(
            path: '/group/:gid',
            builder: (_, state) => Scaffold(
              body: Text('GroupDetail:${state.pathParameters['gid']}'),
            ),
            routes: [
              GoRoute(
                path: 'create-event',
                builder: (_, state) => const EventTypePickerScreen(groupId: 'group-1'),
              ),
              GoRoute(
                path: 'create-event/:type',
                builder: (_, state) => CreateEventScreen(
                  groupId: 'group-1',
                  eventType: EventType.fromString(
                    state.pathParameters['type'] ?? 'custom',
                  ),
                ),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupMembersProvider('group-1').overrideWith(
              (ref) => Stream.value(_testMembers),
            ),
            groupDetailProvider('group-1').overrideWith(
              (ref) => Stream.value(_testGroup),
            ),
            eventLoadingProvider.overrideWith((ref) => false),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the first card (Trip)
      await tester.tap(find.byKey(EventKeys.eventTypeCard('Trip')));
      await tester.pumpAndSettle();

      // Should now see the CreateEventScreen AppBar
      expect(find.text('New Trip Event'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // CreateEventScreen
  // -------------------------------------------------------------------------

  group('CreateEventScreen', () {
    testWidgets('pre-checks all group members in participant picker',
        (tester) async {
      await tester.pumpWidget(
        _wrapCreate(
          const CreateEventScreen(
            groupId: 'group-1',
            eventType: EventType.trip,
          ),
          prefs,
        ),
      );
      await tester.pumpAndSettle();

      // Both member names should appear
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      // Both checkboxes should be checked
      final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      for (final checkbox in checkboxes) {
        expect(checkbox.value, isTrue,
            reason: 'All participants should be pre-checked by default');
      }
    });

    testWidgets('shows AppBar title with event type name', (tester) async {
      await tester.pumpWidget(
        _wrapCreate(
          const CreateEventScreen(
            groupId: 'group-1',
            eventType: EventType.camping,
          ),
          prefs,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Camping Event'), findsOneWidget);
    });

    testWidgets('shows module toggles for Custom type', (tester) async {
      await tester.pumpWidget(
        _wrapCreate(
          const CreateEventScreen(
            groupId: 'group-1',
            eventType: EventType.custom,
          ),
          prefs,
        ),
      );
      await tester.pumpAndSettle();

      // "Modules" section label should appear for Custom type
      expect(find.byKey(EventKeys.modulesSection), findsOneWidget);

      // All 5 module toggle rows should appear
      expect(find.byKey(EventKeys.moduleLedgerToggle), findsOneWidget);
      expect(find.byKey(EventKeys.moduleGearToggle), findsOneWidget);
      expect(find.byKey(EventKeys.moduleLogisticsToggle), findsOneWidget);
      expect(find.byKey(EventKeys.moduleVaultToggle), findsOneWidget);
      expect(find.byKey(EventKeys.moduleMemoriesToggle), findsOneWidget);

      // Switch widgets should be present
      expect(find.byType(Switch), findsWidgets);
    });

    testWidgets(
        'Ledger toggle is enabled (onChanged is not null) for Custom type',
        (tester) async {
      await tester.pumpWidget(
        _wrapCreate(
          const CreateEventScreen(
            groupId: 'group-1',
            eventType: EventType.custom,
          ),
          prefs,
        ),
      );
      await tester.pumpAndSettle();

      // Find all Switch widgets — Ledger is the first one
      final switches = tester.widgetList<Switch>(find.byType(Switch));
      expect(switches.isNotEmpty, isTrue);

      // All switches should have non-null onChanged (all toggleable per D-14)
      for (final sw in switches) {
        expect(sw.onChanged, isNotNull,
            reason:
                'Module toggles including Ledger must be enabled for Custom type');
      }
    });

    testWidgets('does NOT show module toggles for non-Custom types',
        (tester) async {
      await tester.pumpWidget(
        _wrapCreate(
          const CreateEventScreen(
            groupId: 'group-1',
            eventType: EventType.trip,
          ),
          prefs,
        ),
      );
      await tester.pumpAndSettle();

      // "Modules" section label should NOT appear for Trip type
      expect(find.byKey(EventKeys.modulesSection), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('validates event name is required', (tester) async {
      await tester.pumpWidget(
        _wrapCreate(
          const CreateEventScreen(
            groupId: 'group-1',
            eventType: EventType.trip,
          ),
          prefs,
        ),
      );
      await tester.pumpAndSettle();

      // Tap submit without entering a name
      await tester.tap(find.byKey(EventKeys.createEventButton));
      await tester.pumpAndSettle();

      // Validator error message should appear
      expect(find.text("Event name can't be empty."), findsOneWidget);
    });

    testWidgets('shows event name field with correct hint text', (tester) async {
      await tester.pumpWidget(
        _wrapCreate(
          const CreateEventScreen(
            groupId: 'group-1',
            eventType: EventType.trip,
          ),
          prefs,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('e.g. Summer camping trip'), findsOneWidget);
    });
  });
}
