import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/event_type_config.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/create_event_screen.dart';
import 'package:safar/features/events/screens/event_type_picker_screen.dart';
import 'package:safar/features/events/services/event_service.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockEventService extends Mock implements EventService {}

class _MockGroupActivityService extends Mock implements GroupActivityService {}

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
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

Widget _wrapCreate(Widget child, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      groupMembersProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testMembers)),
      groupDetailProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testGroup)),
      eventLoadingProvider.overrideWith((ref) => false),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

Widget _wrapCreateRouted({
  required SharedPreferences prefs,
  required EventService eventService,
  required GroupActivityService activityService,
  String currentUserId = 'uid-creator',
}) {
  final router = GoRouter(
    initialLocation: '/create',
    routes: [
      GoRoute(
        path: '/create',
        builder: (_, _) => const CreateEventScreen(
          groupId: 'group-1',
          eventType: EventType.trip,
        ),
      ),
      GoRoute(
        path: '/group/:gid/event/:eid',
        builder: (_, state) =>
            Scaffold(body: Text('EventHub:${state.pathParameters['eid']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue(currentUserId),
      eventServiceProvider.overrideWithValue(eventService),
      groupActivityServiceProvider.overrideWithValue(activityService),
      groupMembersProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testMembers)),
      groupDetailProvider(
        'group-1',
      ).overrideWith((ref) => Stream.value(_testGroup)),
      eventLoadingProvider.overrideWith((ref) => false),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
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
        _wrapPicker(const EventTypePickerScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      // Verify all 5 type labels appear
      for (final config in EventTypeConfig.allTypes) {
        expect(
          find.text(config.label),
          findsOneWidget,
          reason: 'Expected type label "${config.label}" to appear',
        );
      }
    });

    testWidgets('shows top bar title "New event"', (tester) async {
      await tester.pumpWidget(
        _wrapPicker(const EventTypePickerScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      expect(find.text('New event'), findsOneWidget);
    });

    testWidgets('shows 5 type descriptions', (tester) async {
      await tester.pumpWidget(
        _wrapPicker(const EventTypePickerScreen(groupId: 'group-1'), prefs),
      );
      await tester.pumpAndSettle();

      for (final config in EventTypeConfig.allTypes) {
        expect(
          find.text(config.description),
          findsOneWidget,
          reason: 'Expected description for ${config.label}',
        );
      }
    });

    testWidgets('tapping type card navigates to CreateEventScreen', (
      tester,
    ) async {
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
                builder: (_, state) =>
                    const EventTypePickerScreen(groupId: 'group-1'),
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
            groupMembersProvider(
              'group-1',
            ).overrideWith((ref) => Stream.value(_testMembers)),
            groupDetailProvider(
              'group-1',
            ).overrideWith((ref) => Stream.value(_testGroup)),
            eventLoadingProvider.overrideWith((ref) => false),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select the first card (Trip), then continue.
      await tester.tap(find.byKey(EventKeys.eventTypeCard('Trip')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(EventKeys.createEventButton));
      await tester.tap(find.byKey(EventKeys.createEventButton));
      await tester.pumpAndSettle();

      // AppBar title is gone after Plan 02; event type appears in ModuleHeader
      // title AND in the badge — both are correct, so findsAtLeastNWidgets(1).
      expect(find.text('New Trip Event'), findsNothing);
      expect(find.text('Trip'), findsAtLeastNWidgets(1));
    });
  });

  // -------------------------------------------------------------------------
  // CreateEventScreen
  // -------------------------------------------------------------------------

  group('CreateEventScreen', () {
    testWidgets('pre-checks all group members in participant picker', (
      tester,
    ) async {
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
        expect(
          checkbox.value,
          isTrue,
          reason: 'All participants should be pre-checked by default',
        );
      }
    });

    testWidgets('shows event type badge with type label, no AppBar title', (
      tester,
    ) async {
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

      // After Plan 02: AppBar title is gone; type label shows in ModuleHeader
      // title AND in the event type badge — both correct, so findsAtLeastNWidgets(1).
      expect(find.text('New Camping Event'), findsNothing);
      expect(find.text('Camping'), findsAtLeastNWidgets(1));
    });

    testWidgets('does NOT show module toggles for non-Custom types', (
      tester,
    ) async {
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

      // The module toggle should NOT appear for Trip type
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

      // Scroll to and tap submit without entering a name
      await tester.ensureVisible(find.byKey(EventKeys.createEventButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(EventKeys.createEventButton));
      await tester.pumpAndSettle();

      // Validator error message should appear
      expect(find.text("Name can't be empty."), findsOneWidget);
    });

    testWidgets('shows event name field with correct hint text', (
      tester,
    ) async {
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

    testWidgets('shows Select All checkbox in participants card', (
      tester,
    ) async {
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
      expect(find.byKey(EventKeys.selectAllButton), findsOneWidget);
    });

    testWidgets('Select All selects all participants when tapped', (
      tester,
    ) async {
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

      // First deselect Alice to ensure not all are selected
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      // Tap Select All
      await tester.tap(find.byKey(EventKeys.selectAllButton));
      await tester.pumpAndSettle();

      // All checkboxes (excluding the Select All checkbox itself) should be true
      final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      for (final cb in checkboxes) {
        expect(
          cb.value,
          isTrue,
          reason: 'All participants should be selected after Select All',
        );
      }
    });

    testWidgets('Select All deselects all when all participants are selected', (
      tester,
    ) async {
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
      // All participants pre-checked — tap Select All to deselect
      await tester.tap(find.byKey(EventKeys.selectAllButton));
      await tester.pumpAndSettle();
      // Find the participant-only checkboxes: exclude the Select All checkbox
      // by targeting only the ones inside _ParticipantRow (find by type Checkbox)
      // The Select All Checkbox will also show value==false — all should be false
      final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      for (final cb in checkboxes) {
        expect(
          cb.value,
          isFalse,
          reason:
              'All participants should be deselected after Select All toggle',
        );
      }
    });

    testWidgets('submit with no participants shows validation snack bar', (
      tester,
    ) async {
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

      await tester.enterText(find.byType(TextFormField), 'Beach Day');
      await tester.tap(find.byKey(EventKeys.selectAllButton));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(EventKeys.createEventButton));
      await tester.tap(find.byKey(EventKeys.createEventButton));
      await tester.pump();

      expect(find.text('Select at least one participant.'), findsOneWidget);
    });

    testWidgets(
      'valid submit creates event with current uid and routes to hub',
      (tester) async {
        final eventService = _MockEventService();
        final activityService = _MockGroupActivityService();
        final createdEvent = Event(
          id: 'event-created',
          name: 'Beach Day',
          type: EventType.trip,
          groupId: 'group-1',
          createdBy: 'uid-creator',
          participantIds: const ['uid-creator', 'uid-member'],
          participantNames: const {'uid-creator': 'Alice', 'uid-member': 'Bob'},
          modules: const EventModules(),
          createdAt: DateTime(2026, 6, 1),
        );

        when(
          () => eventService.createEvent(
            groupId: 'group-1',
            name: 'Beach Day',
            type: EventType.trip,
            participantIds: const ['uid-creator', 'uid-member'],
            participantNames: const {
              'uid-creator': 'Alice',
              'uid-member': 'Bob',
            },
            createdBy: 'uid-creator',
            startDate: null,
            endDate: null,
            modules: null,
          ),
        ).thenAnswer((_) async => createdEvent);
        when(
          () => activityService.logGroupEvent(
            groupId: any(named: 'groupId'),
            type: any(named: 'type'),
            actorId: any(named: 'actorId'),
            actorName: any(named: 'actorName'),
            description: any(named: 'description'),
            metadata: any(named: 'metadata'),
          ),
        ).thenReturn(null);

        await tester.pumpWidget(
          _wrapCreateRouted(
            prefs: prefs,
            eventService: eventService,
            activityService: activityService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField), 'Beach Day');
        await tester.ensureVisible(find.byKey(EventKeys.createEventButton));
        await tester.tap(find.byKey(EventKeys.createEventButton));
        await tester.pumpAndSettle();

        verify(
          () => eventService.createEvent(
            groupId: 'group-1',
            name: 'Beach Day',
            type: EventType.trip,
            participantIds: const ['uid-creator', 'uid-member'],
            participantNames: const {
              'uid-creator': 'Alice',
              'uid-member': 'Bob',
            },
            createdBy: 'uid-creator',
            startDate: null,
            endDate: null,
            modules: null,
          ),
        ).called(1);
        verify(
          () => activityService.logGroupEvent(
            groupId: 'group-1',
            type: 'event_created',
            actorId: 'uid-creator',
            actorName: 'Someone',
            description: 'created Beach Day',
            metadata: {'eventId': 'event-created', 'eventName': 'Beach Day'},
          ),
        ).called(1);
        expect(find.text('EventHub:event-created'), findsOneWidget);
      },
    );

    testWidgets('submit failure shows create-event error snack bar', (
      tester,
    ) async {
      final eventService = _MockEventService();
      final activityService = _MockGroupActivityService();
      when(
        () => eventService.createEvent(
          groupId: 'group-1',
          name: 'Beach Day',
          type: EventType.trip,
          participantIds: const ['uid-creator', 'uid-member'],
          participantNames: const {'uid-creator': 'Alice', 'uid-member': 'Bob'},
          createdBy: 'uid-creator',
          startDate: null,
          endDate: null,
          modules: null,
        ),
      ).thenThrow(StateError('network down'));

      await tester.pumpWidget(
        _wrapCreateRouted(
          prefs: prefs,
          eventService: eventService,
          activityService: activityService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Beach Day');
      await tester.ensureVisible(find.byKey(EventKeys.createEventButton));
      await tester.tap(find.byKey(EventKeys.createEventButton));
      await tester.pump();

      expect(
        find.text(
          "Couldn't create event. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      verifyNever(
        () => activityService.logGroupEvent(
          groupId: any(named: 'groupId'),
          type: any(named: 'type'),
          actorId: any(named: 'actorId'),
          actorName: any(named: 'actorName'),
          description: any(named: 'description'),
          metadata: any(named: 'metadata'),
        ),
      );
    });
  });
}
