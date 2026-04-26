// test/features/events/event_settings_screen_test.dart
//
// ECC-02 tests for EventSettingsScreen (Phase 31 Plan 02).
// These tests verify the GREEN phase — EventSettingsScreen is now implemented.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/event_settings_screen.dart';
import 'package:safar/features/events/services/event_service.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockEventService extends Mock implements EventService {}

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

Widget _wrapSettings({
  required Event event,
  String currentUserId = 'uid-creator',
  List<Override> extraOverrides = const [],
}) {
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
        builder: (_, __) => const Scaffold(body: Text('GroupDetail')),
        routes: [
          GoRoute(
            path: 'event/:eid',
            builder: (_, __) => const Scaffold(body: Text('EventHub')),
            routes: [
              GoRoute(
                path: 'settings',
                builder: (_, state) => ProviderScope(
                  overrides: [
                    eventDetailProvider(eventRef).overrideWith(
                      (ref) => Stream.value(event),
                    ),
                    eventServiceProvider.overrideWithValue(mockService),
                    currentUserIdProvider.overrideWithValue(currentUserId),
                    eventExpensesProvider(eventRef).overrideWith(
                      (ref) => Stream.value(const []),
                    ),
                    eventSettlementsProvider(eventRef).overrideWith(
                      (ref) => Stream.value(const <Settlement>[]),
                    ),
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

  return MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime.now());
  });

  group('ECC-02: EventSettingsScreen', () {
    testWidgets('renders event name in text field', (tester) async {
      final event = _makeEvent(name: 'Beach Getaway');
      await tester.pumpWidget(_wrapSettings(event: event));
      await tester.pumpAndSettle();

      expect(find.text('Beach Getaway'), findsOneWidget);
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
          _wrapSettings(event: event, currentUserId: 'uid-creator'));
      await tester.pumpAndSettle();

      expect(find.text('Delete event'), findsOneWidget);
    });

    testWidgets('delete event tile is hidden for non-creator', (tester) async {
      final event = _makeEvent(createdBy: 'uid-creator');
      await tester.pumpWidget(
          _wrapSettings(event: event, currentUserId: 'uid-other'));
      await tester.pumpAndSettle();

      expect(find.text('Delete event'), findsNothing);
    });

    testWidgets('delete tile tap shows confirmation dialog', (tester) async {
      final event = _makeEvent(createdBy: 'uid-creator');
      await tester.pumpWidget(
          _wrapSettings(event: event, currentUserId: 'uid-creator'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete event'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this event?'), findsOneWidget);
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
            builder: (_, __) => const Scaffold(body: Text('GroupDetail')),
            routes: [
              GoRoute(
                path: 'event/:eid',
                builder: (_, __) => const Scaffold(body: Text('EventHub')),
                routes: [
                  GoRoute(
                    path: 'settings',
                    builder: (_, state) => ProviderScope(
                      overrides: [
                        eventDetailProvider(eventRef).overrideWith(
                          (ref) => Stream.value(event),
                        ),
                        eventServiceProvider.overrideWithValue(mockService),
                        currentUserIdProvider.overrideWithValue('uid-creator'),
                        eventExpensesProvider(eventRef).overrideWith(
                          (ref) => Stream.value(const []),
                        ),
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

      await tester.pumpWidget(MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router));
      await tester.pumpAndSettle();

      // Change name
      await tester.enterText(find.byType(TextField).first, 'New Name');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(find.text('Event updated'), findsOneWidget);
    });
  });
}
