import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/app_messenger.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/create_event_screen.dart';
import 'package:safar/features/events/services/event_service.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/empty_state_view.dart';
import 'package:safar/shared/widgets/offline_banner.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';

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

/// Throwaway Event for stubs whose ack errors before the event is read.
final _anyEvent = Event(
  id: 'event-x',
  name: 'Beach Day',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'uid-creator',
  participantIds: const ['uid-creator', 'uid-member'],
  participantNames: const {'uid-creator': 'Alice', 'uid-member': 'Bob'},
  modules: const EventModules(),
  createdAt: DateTime(2026, 6, 1),
);

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
  String? currentUserId = 'uid-creator',
  ConnectivityStatus connectivity = ConnectivityStatus.online,
  EventType initialType = EventType.trip,
}) {
  final router = GoRouter(
    initialLocation: '/create',
    routes: [
      GoRoute(
        path: '/create',
        builder: (_, _) => CreateEventScreen(
          groupId: 'group-1',
          initialEventType: initialType,
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
      // The create path reads connectivityProvider (#516). Use a timer-free
      // notifier (startPeriodicChecks:false) or pumpAndSettle hangs on the
      // 60s periodic timer (the documented ConnectivityNotifier trap).
      connectivityProvider.overrideWith((ref) {
        final notifier = ConnectivityNotifier(startPeriodicChecks: false);
        if (connectivity == ConnectivityStatus.offline) notifier.setOffline();
        if (connectivity == ConnectivityStatus.syncing) notifier.setSyncing();
        return notifier;
      }),
    ],
    // The queued "will sync" feedback is shown via the global appMessengerKey
    // because context.go tears down the local ScaffoldMessenger (#516).
    child: MaterialApp.router(
      scaffoldMessengerKey: appMessengerKey,
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
    SharedPreferences.setMockInitialValues({
      'settings_device_name': 'Test User',
    });
    prefs = await SharedPreferences.getInstance();
  });

  // -------------------------------------------------------------------------
  // CreateEventScreen async states (#488)
  // -------------------------------------------------------------------------

  group('CreateEventScreen async states (#488)', () {
    Widget wrapWithMembers(Stream<List<GroupMember>> members) => ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        groupMembersProvider('group-1').overrideWith((ref) => members),
        groupDetailProvider(
          'group-1',
        ).overrideWith((ref) => Stream.value(_testGroup)),
        eventLoadingProvider.overrideWith((ref) => false),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CreateEventScreen(
          groupId: 'group-1',
          initialEventType: EventType.trip,
        ),
      ),
    );

    testWidgets('loading shows a skeleton, not a bare spinner (#488)', (
      tester,
    ) async {
      // A never-completing members stream keeps the screen in loading.
      await tester.pumpWidget(
        wrapWithMembers(Completer<List<GroupMember>>().future.asStream()),
      );
      await tester.pump(); // one frame; skeleton shimmer never settles

      expect(find.byType(SkeletonLoader), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('member-load error shows an EmptyStateView with retry (#488)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithMembers(Stream.error(Exception('network'))),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EmptyStateView), findsOneWidget);
      expect(find.text("Couldn't load members"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
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
            initialEventType: EventType.trip,
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

    testWidgets(
      'header reads "New event"; the type chip-row shows the type (#489)',
      (tester) async {
        await tester.pumpWidget(
          _wrapCreate(
            const CreateEventScreen(
              groupId: 'group-1',
              initialEventType: EventType.camping,
            ),
            prefs,
          ),
        );
        await tester.pumpAndSettle();

        // The header is the generic "New event"; the type lives in the chip-row.
        expect(find.text('New event'), findsOneWidget);
        // The Camping chip renders its label exactly once (no static badge now).
        expect(find.text('Camping'), findsOneWidget);
        // Custom is not creatable — no Custom chip.
        expect(find.byKey(EventKeys.eventTypeCard('Custom')), findsNothing);
      },
    );

    testWidgets(
      'renders 4 selectable chips (Custom dropped), Trip selected by default (#489)',
      (tester) async {
        await tester.pumpWidget(
          _wrapCreate(
            const CreateEventScreen(
              groupId: 'group-1',
              initialEventType: EventType.trip,
            ),
            prefs,
          ),
        );
        await tester.pumpAndSettle();

        for (final label in const [
          'Trip',
          'Camping',
          'Travel',
          'Night/Day Out',
        ]) {
          expect(
            find.byKey(EventKeys.eventTypeCard(label)),
            findsOneWidget,
            reason: 'Expected a $label chip',
          );
        }
        expect(find.byKey(EventKeys.eventTypeCard('Custom')), findsNothing);

        // Trip is the selected chip by default; Camping is not (WYSIWYG).
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.selected ?? false) &&
                w.properties.label == 'Trip',
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.selected ?? false) &&
                w.properties.label == 'Camping',
          ),
          findsNothing,
        );
      },
    );

    testWidgets('selecting the Camping chip creates a camping event (#489)', (
      tester,
    ) async {
      final eventService = _MockEventService();
      final activityService = _MockGroupActivityService();
      final createdEvent = Event(
        id: 'event-created',
        name: 'Beach Day',
        type: EventType.camping,
        groupId: 'group-1',
        createdBy: 'uid-creator',
        participantIds: const ['uid-creator', 'uid-member'],
        participantNames: const {'uid-creator': 'Alice', 'uid-member': 'Bob'},
        modules: const EventModules(),
        createdAt: DateTime(2026, 6, 1),
      );
      when(
        () => eventService.stageEvent(
          groupId: 'group-1',
          name: 'Beach Day',
          type: EventType.camping,
          participantIds: const ['uid-creator', 'uid-member'],
          participantNames: const {'uid-creator': 'Alice', 'uid-member': 'Bob'},
          createdBy: 'uid-creator',
          startDate: null,
          endDate: null,
          modules: null,
        ),
      ).thenReturn((event: createdEvent, ack: Future<void>.value()));
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

      // Switch the type to Camping via the chip-row.
      await tester.tap(find.byKey(EventKeys.eventTypeCard('Camping')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Beach Day');
      await tester.ensureVisible(find.byKey(EventKeys.createEventButton));
      await tester.tap(find.byKey(EventKeys.createEventButton));
      await tester.pumpAndSettle();

      verify(
        () => eventService.stageEvent(
          groupId: 'group-1',
          name: 'Beach Day',
          type: EventType.camping,
          participantIds: const ['uid-creator', 'uid-member'],
          participantNames: const {'uid-creator': 'Alice', 'uid-member': 'Bob'},
          createdBy: 'uid-creator',
          startDate: null,
          endDate: null,
          modules: null,
        ),
      ).called(1);
      expect(find.text('EventHub:event-created'), findsOneWidget);
    });

    testWidgets(
      'a custom deep-link coerces to Trip — creating yields a trip event (#489)',
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
          () => eventService.stageEvent(
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
        ).thenReturn((event: createdEvent, ack: Future<void>.value()));
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
            initialType: EventType.custom,
          ),
        );
        await tester.pumpAndSettle();

        // No Custom chip exists; the custom seed was coerced to Trip.
        expect(find.byKey(EventKeys.eventTypeCard('Custom')), findsNothing);

        await tester.enterText(find.byType(TextFormField), 'Beach Day');
        await tester.ensureVisible(find.byKey(EventKeys.createEventButton));
        await tester.tap(find.byKey(EventKeys.createEventButton));
        await tester.pumpAndSettle();

        // Coercion is proven by the OUTBOUND type: trip (NOT custom) — the only
        // signal that distinguishes a coerced-Trip from a default-Trip.
        verify(
          () => eventService.stageEvent(
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
      },
    );

    testWidgets('does NOT show module toggles for non-Custom types', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapCreate(
          const CreateEventScreen(
            groupId: 'group-1',
            initialEventType: EventType.trip,
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
            initialEventType: EventType.trip,
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
            initialEventType: EventType.trip,
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
            initialEventType: EventType.trip,
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
            initialEventType: EventType.trip,
          ),
          prefs,
        ),
      );
      await tester.pumpAndSettle();

      // First deselect Alice to ensure not all are selected
      await tester.ensureVisible(find.text('Alice'));
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
            initialEventType: EventType.trip,
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
            initialEventType: EventType.trip,
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
          () => eventService.stageEvent(
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
        ).thenReturn((event: createdEvent, ack: Future<void>.value()));
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
          () => eventService.stageEvent(
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
            actorName: 'Test User',
            description: 'created Beach Day',
            metadata: {'eventId': 'event-created', 'eventName': 'Beach Day'},
          ),
        ).called(1);
        expect(find.text('EventHub:event-created'), findsOneWidget);
      },
    );

    testWidgets(
      'offline submit releases the spinner, shows will-sync, and routes to the hub (#516)',
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

        // Offline: the SDK applies the write to cache and returns the staged
        // Event immediately, but the server ack never arrives until reconnect.
        when(
          () => eventService.stageEvent(
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
        ).thenReturn((event: createdEvent, ack: Completer<void>().future));
        // Pre-fix the screen awaits createEvent, whose raw write never acks
        // offline — the RED fails here (spinner hangs, no navigation).
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
        ).thenAnswer((_) => Completer<Event>().future);
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
            connectivity: ConnectivityStatus.offline,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField), 'Beach Day');
        await tester.ensureVisible(find.byKey(EventKeys.createEventButton));
        await tester.tap(find.byKey(EventKeys.createEventButton));
        await tester.pumpAndSettle();

        // Spinner released + routed to the event hub without waiting on the ack.
        expect(find.text('EventHub:event-created'), findsOneWidget);

        // Connectivity flipped to "syncing" (Saved — will sync).
        final container = ProviderScope.containerOf(
          tester.element(find.text('EventHub:event-created')),
        );
        expect(container.read(connectivityProvider), ConnectivityStatus.syncing);

        // The will-sync feedback survived the navigation (global messenger).
        expect(
          find.text('Event saved — will sync when online.'),
          findsOneWidget,
        );

        // The queued event was logged optimistically.
        verify(
          () => activityService.logGroupEvent(
            groupId: 'group-1',
            type: 'event_created',
            actorId: 'uid-creator',
            actorName: 'Test User',
            description: 'created Beach Day',
            metadata: {'eventId': 'event-created', 'eventName': 'Beach Day'},
          ),
        ).called(1);
      },
    );

    testWidgets('submit without an authenticated uid does not write', (
      tester,
    ) async {
      final eventService = _MockEventService();
      final activityService = _MockGroupActivityService();

      await tester.pumpWidget(
        _wrapCreateRouted(
          prefs: prefs,
          eventService: eventService,
          activityService: activityService,
          currentUserId: null,
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
      verifyZeroInteractions(eventService);
      verifyZeroInteractions(activityService);
    });

    testWidgets(
      '#533 OfflineBanner is visible when composing the form offline',
      (tester) async {
        final eventService = _MockEventService();
        final activityService = _MockGroupActivityService();

        await tester.pumpWidget(
          _wrapCreateRouted(
            prefs: prefs,
            eventService: eventService,
            activityService: activityService,
            connectivity: ConnectivityStatus.offline,
          ),
        );
        // _wrapCreateRouted uses ConnectivityNotifier(startPeriodicChecks:false)
        // so pumpAndSettle is safe — there is no long-running periodic timer.
        await tester.pumpAndSettle();

        // Pre-fix: no OfflineBanner in the Scaffold body → findsNothing → RED.
        // Post-fix: the banner is mounted and the offline connectivity makes it
        // render the strip → findsOneWidget → GREEN.
        expect(find.byType(OfflineBanner), findsOneWidget);
      },
    );

    testWidgets('submit failure shows create-event error snack bar', (
      tester,
    ) async {
      final eventService = _MockEventService();
      final activityService = _MockGroupActivityService();
      when(
        () => eventService.stageEvent(
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
      ).thenAnswer(
        (_) =>
            (event: _anyEvent, ack: Future<void>.error(StateError('network down'))),
      );

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
