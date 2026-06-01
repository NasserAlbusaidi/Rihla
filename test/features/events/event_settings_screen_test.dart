// test/features/events/event_settings_screen_test.dart
//
// ECC-02 tests for EventSettingsScreen (Phase 31 Plan 02).
// These tests verify the GREEN phase — EventSettingsScreen is now implemented.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/event_settings_screen.dart';
import 'package:safar/features/events/services/event_service.dart';
import 'package:safar/features/events/widgets/event_danger_section.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockEventService extends Mock implements EventService {}

class _RecordingGroupActivityService extends GroupActivityService {
  _RecordingGroupActivityService({this.throwOnLog = false})
    : super.withFirestore(FakeFirebaseFirestore());

  final bool throwOnLog;
  final calls =
      <
        ({
          String groupId,
          String type,
          String actorId,
          String actorName,
          String description,
          Map<String, dynamic>? metadata,
        })
      >[];

  @override
  void logGroupEvent({
    required String groupId,
    required String type,
    required String actorId,
    required String actorName,
    required String description,
    Map<String, dynamic>? metadata,
  }) {
    if (throwOnLog) {
      throw StateError('log failed');
    }
    calls.add((
      groupId: groupId,
      type: type,
      actorId: actorId,
      actorName: actorName,
      description: description,
      metadata: metadata,
    ));
  }
}

// ---------------------------------------------------------------------------
// Stub helpers
// ---------------------------------------------------------------------------

Event _makeEvent({
  String id = 'evt-1',
  String name = 'Summer Trip',
  EventType type = EventType.trip,
  DateTime? startDate,
  DateTime? endDate,
  String createdBy = 'uid-creator',
  String? description,
}) {
  return Event(
    id: id,
    name: name,
    type: type,
    groupId: 'group-1',
    createdBy: createdBy,
    participantIds: const ['uid-creator'],
    participantNames: const {'uid-creator': 'Alice'},
    modules: EventModules.forType(type),
    startDate: startDate,
    endDate: endDate,
    createdAt: DateTime(2026, 3, 1),
    description: description,
  );
}

Group _makeGroup({
  String id = 'group-1',
  String createdBy = 'uid-group-other',
}) {
  return Group(
    id: id,
    name: 'Trip Squad',
    inviteCode: 'ABCDEF',
    createdBy: createdBy,
    memberIds: const ['uid-group-other', 'uid-creator'],
    createdAt: DateTime(2026, 1, 1),
  );
}

Expense _makeExpense({String id = 'expense-1', String eventId = 'evt-1'}) {
  return Expense(
    id: id,
    tripId: eventId,
    payerParticipantId: 'uid-creator',
    amount: Decimal.fromInt(10),
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 3, 2),
  );
}

Widget _wrapSettings({
  required Event event,
  String currentUserId = 'uid-creator',
  Group? group,
  Stream<Event?>? eventStream,
  Stream<Group?>? groupStream,
  List<Override> extraOverrides = const [],
}) {
  final eventRef = (groupId: event.groupId, eventId: event.id);
  final resolvedGroup = group ?? _makeGroup(id: event.groupId);
  final mockService = _MockEventService();

  when(
    () => mockService.updateEvent(
      groupId: any(named: 'groupId'),
      eventId: any(named: 'eventId'),
      name: any(named: 'name'),
      startDate: any(named: 'startDate'),
      endDate: any(named: 'endDate'),
      description: any(named: 'description'),
    ),
  ).thenAnswer((_) async {});

  when(
    () => mockService.deleteEvent(
      groupId: any(named: 'groupId'),
      eventId: any(named: 'eventId'),
    ),
  ).thenAnswer((_) async {});

  final router = GoRouter(
    initialLocation: '/group/${event.groupId}/event/${event.id}/settings',
    routes: [
      GoRoute(
        path: '/group/:gid',
        builder: (_, _) => const Scaffold(body: Text('GroupDetail')),
        routes: [
          GoRoute(
            path: 'event/:eid',
            builder: (_, _) => const Scaffold(body: Text('EventHub')),
            routes: [
              GoRoute(
                path: 'settings',
                builder: (_, state) => ProviderScope(
                  overrides: [
                    eventDetailProvider(
                      eventRef,
                    ).overrideWith((ref) => eventStream ?? Stream.value(event)),
                    groupDetailProvider(event.groupId).overrideWith(
                      (ref) => groupStream ?? Stream.value(resolvedGroup),
                    ),
                    eventServiceProvider.overrideWithValue(mockService),
                    currentUserIdProvider.overrideWithValue(currentUserId),
                    eventExpensesProvider(
                      eventRef,
                    ).overrideWith((ref) => Stream.value(const [])),
                    eventSettlementsProvider(
                      eventRef,
                    ).overrideWith((ref) => Stream.value(const <Settlement>[])),
                    ...extraOverrides,
                  ],
                  child: EventSettingsScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  return MaterialApp.router(
    theme: AppTheme.lightTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
  );
}

Widget _wrapDangerSection({
  required SharedPreferences prefs,
  required Event event,
  required EventService eventService,
  required GroupActivityService activityService,
  bool isAdmin = true,
  List<Expense> expenses = const [],
  List<Settlement> settlements = const [],
}) {
  final eventRef = (groupId: event.groupId, eventId: event.id);
  final router = GoRouter(
    initialLocation: '/danger',
    routes: [
      GoRoute(
        path: '/danger',
        builder: (_, _) => Scaffold(
          body: EventDangerSection(
            groupId: event.groupId,
            eventId: event.id,
            event: event,
            isAdmin: isAdmin,
          ),
        ),
      ),
      GoRoute(
        path: '/group/:gid',
        builder: (_, state) =>
            Scaffold(body: Text('Group:${state.pathParameters['gid']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      eventServiceProvider.overrideWithValue(eventService),
      groupActivityServiceProvider.overrideWithValue(activityService),
      eventExpensesProvider(
        eventRef,
      ).overrideWith((ref) => Stream.value(expenses)),
      eventSettlementsProvider(
        eventRef,
      ).overrideWith((ref) => Stream.value(settlements)),
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
    setupFirebaseCoreMocks();
    try {
      await Firebase.initializeApp();
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }
    SharedPreferences.setMockInitialValues({
      'settings_device_name': 'Test User',
    });
    prefs = await SharedPreferences.getInstance();
    registerFallbackValue(DateTime.now());
  });

  group('ECC-02: EventSettingsScreen', () {
    testWidgets('renders event name in text field', (tester) async {
      final event = _makeEvent(name: 'Beach Getaway');
      await tester.pumpWidget(_wrapSettings(event: event));
      await tester.pumpAndSettle();

      expect(find.text('Beach Getaway'), findsOneWidget);
    });

    testWidgets('direct route back button returns to event hub', (
      tester,
    ) async {
      final event = _makeEvent();
      await tester.pumpWidget(_wrapSettings(event: event));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(EventKeys.settingsBackButton));
      await tester.pumpAndSettle();

      expect(find.text('EventHub'), findsOneWidget);
    });

    testWidgets('shows loading skeleton while event stream is pending', (
      tester,
    ) async {
      final event = _makeEvent();
      final controller = StreamController<Event?>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _wrapSettings(event: event, eventStream: controller.stream),
      );
      await tester.pump();

      expect(find.byKey(EventKeys.settingsBackButton), findsOneWidget);
      expect(find.text('Event Settings'), findsNothing);
    });

    testWidgets('shows retry state when event is missing', (tester) async {
      final event = _makeEvent();

      await tester.pumpWidget(
        _wrapSettings(event: event, eventStream: Stream<Event?>.value(null)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load settings'), findsOneWidget);
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('error state retry invalidates event details provider', (
      tester,
    ) async {
      final event = _makeEvent();

      await tester.pumpWidget(
        _wrapSettings(
          event: event,
          eventStream: Stream<Event?>.error(StateError('load failed')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load settings'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Could not load settings'), findsOneWidget);
    });

    testWidgets('Save Changes button is present', (tester) async {
      final event = _makeEvent();
      await tester.pumpWidget(_wrapSettings(event: event));
      await tester.pumpAndSettle();

      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('delete event tile is visible for creator', (tester) async {
      final event = _makeEvent(createdBy: 'uid-creator');
      await tester.pumpWidget(
        _wrapSettings(event: event, currentUserId: 'uid-creator'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete event'), findsOneWidget);
    });

    testWidgets('delete event tile is hidden for non-creator', (tester) async {
      final event = _makeEvent(createdBy: 'uid-creator');
      await tester.pumpWidget(
        _wrapSettings(event: event, currentUserId: 'uid-other'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete event'), findsNothing);
    });

    testWidgets(
      'delete event tile is visible for group creator (not event creator)',
      (tester) async {
        final event = _makeEvent(createdBy: 'uid-event-creator');
        await tester.pumpWidget(
          _wrapSettings(
            event: event,
            currentUserId: 'uid-group-creator',
            group: _makeGroup(
              id: event.groupId,
              createdBy: 'uid-group-creator',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Delete event'), findsOneWidget);
      },
    );

    testWidgets('delete tile tap shows confirmation dialog', (tester) async {
      final event = _makeEvent(createdBy: 'uid-creator');
      await tester.pumpWidget(
        _wrapSettings(event: event, currentUserId: 'uid-creator'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete event'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this event?'), findsOneWidget);
    });

    testWidgets('danger section renders nothing for non-admin', (tester) async {
      final event = _makeEvent();
      final service = _MockEventService();
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(
        _wrapDangerSection(
          prefs: prefs,
          event: event,
          eventService: service,
          activityService: activityService,
          isAdmin: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(EventKeys.dangerSection), findsNothing);
      expect(find.byKey(EventKeys.deleteEventTile), findsNothing);
      expect(activityService.calls, isEmpty);
    });

    testWidgets('unsettled event shows warning and cancellable dialog body', (
      tester,
    ) async {
      final event = _makeEvent();
      final service = _MockEventService();
      final activityService = _RecordingGroupActivityService();

      await tester.pumpWidget(
        _wrapDangerSection(
          prefs: prefs,
          event: event,
          eventService: service,
          activityService: activityService,
          expenses: [_makeExpense(eventId: event.id)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('This event has unsettled balances.'), findsOneWidget);

      await tester.tap(find.byKey(EventKeys.deleteEventTile));
      await tester.pumpAndSettle();

      expect(find.byKey(EventKeys.deleteEventDialog), findsOneWidget);
      expect(find.textContaining('proceed anyway'), findsOneWidget);

      await tester.tap(find.text('Keep event'));
      await tester.pumpAndSettle();

      expect(find.byKey(EventKeys.deleteEventDialog), findsNothing);
      verifyNever(
        () => service.deleteEvent(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
        ),
      );
    });

    testWidgets('confirming delete logs activity, deletes, and routes back', (
      tester,
    ) async {
      final event = _makeEvent();
      final service = _MockEventService();
      final activityService = _RecordingGroupActivityService();
      when(
        () => service.deleteEvent(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
        ),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(
        _wrapDangerSection(
          prefs: prefs,
          event: event,
          eventService: service,
          activityService: activityService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(EventKeys.deleteEventTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(EventKeys.deleteEventConfirmButton));
      await tester.pumpAndSettle();

      verify(
        () => service.deleteEvent(groupId: event.groupId, eventId: event.id),
      ).called(1);
      expect(find.text('Group:${event.groupId}'), findsOneWidget);
      expect(activityService.calls.single.groupId, event.groupId);
      expect(activityService.calls.single.type, 'event_deleted');
      expect(activityService.calls.single.actorName, 'Test User');
      expect(activityService.calls.single.metadata, {
        'eventId': event.id,
        'eventName': event.name,
      });
    });

    testWidgets('activity logging failure does not block delete routing', (
      tester,
    ) async {
      final event = _makeEvent();
      final service = _MockEventService();
      final activityService = _RecordingGroupActivityService(throwOnLog: true);
      when(
        () => service.deleteEvent(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
        ),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(
        _wrapDangerSection(
          prefs: prefs,
          event: event,
          eventService: service,
          activityService: activityService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(EventKeys.deleteEventTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(EventKeys.deleteEventConfirmButton));
      await tester.pumpAndSettle();

      verify(
        () => service.deleteEvent(groupId: event.groupId, eventId: event.id),
      ).called(1);
      expect(find.text('Group:${event.groupId}'), findsOneWidget);
    });

    testWidgets('delete failure shows snackbar and stays on danger section', (
      tester,
    ) async {
      final event = _makeEvent();
      final service = _MockEventService();
      final activityService = _RecordingGroupActivityService();
      when(
        () => service.deleteEvent(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
        ),
      ).thenThrow(StateError('boom'));

      await tester.pumpWidget(
        _wrapDangerSection(
          prefs: prefs,
          event: event,
          eventService: service,
          activityService: activityService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(EventKeys.deleteEventTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(EventKeys.deleteEventConfirmButton));
      await tester.pumpAndSettle();

      verify(
        () => service.deleteEvent(groupId: event.groupId, eventId: event.id),
      ).called(1);
      expect(
        find.text('Failed to delete event: Bad state: boom'),
        findsOneWidget,
      );
      expect(find.byKey(EventKeys.dangerSection), findsOneWidget);
    });

    testWidgets('Save Changes button calls updateEvent on tap', (tester) async {
      final event = _makeEvent(name: 'Original Name');
      final eventRef = (groupId: event.groupId, eventId: event.id);
      final mockService = _MockEventService();

      when(
        () => mockService.updateEvent(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
          name: any(named: 'name'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          description: any(named: 'description'),
        ),
      ).thenAnswer((_) async {});

      final router = GoRouter(
        initialLocation: '/group/${event.groupId}/event/${event.id}/settings',
        routes: [
          GoRoute(
            path: '/group/:gid',
            builder: (_, _) => const Scaffold(body: Text('GroupDetail')),
            routes: [
              GoRoute(
                path: 'event/:eid',
                builder: (_, _) => const Scaffold(body: Text('EventHub')),
                routes: [
                  GoRoute(
                    path: 'settings',
                    builder: (_, state) => ProviderScope(
                      overrides: [
                        eventDetailProvider(
                          eventRef,
                        ).overrideWith((ref) => Stream.value(event)),
                        groupDetailProvider(event.groupId).overrideWith(
                          (ref) => Stream.value(_makeGroup(id: event.groupId)),
                        ),
                        eventServiceProvider.overrideWithValue(mockService),
                        currentUserIdProvider.overrideWithValue('uid-creator'),
                        eventExpensesProvider(
                          eventRef,
                        ).overrideWith((ref) => Stream.value(const [])),
                        eventSettlementsProvider(eventRef).overrideWith(
                          (ref) => Stream.value(const <Settlement>[]),
                        ),
                      ],
                      child: EventSettingsScreen(
                        groupId: state.pathParameters['gid']!,
                        eventId: state.pathParameters['eid']!,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      // Change name
      await tester.enterText(find.byType(TextField).first, 'New Name');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('Event updated'), findsOneWidget);
    });
  });
}
