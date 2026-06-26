import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/utils/write_ack.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/services/event_service.dart';
import 'package:safar/features/events/widgets/event_danger_section.dart';
import 'package:safar/features/events/widgets/event_info_section.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockEventService extends Mock implements EventService {}

class _MockGroupActivityService extends Mock implements GroupActivityService {}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2026, 1, 1));
  });

  testWidgets(
    '#667: offline event settings save releases spinner and marks queued',
    (tester) async {
      final service = _MockEventService();
      final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
        ..setOffline();
      late ProviderContainer container;

      when(
        () => service.updateEvent(
          groupId: 'group-1',
          eventId: 'event-1',
          name: 'Updated Event',
          startDate: null,
          endDate: null,
          description: null,
        ),
      ).thenAnswer((_) => Completer<void>().future);

      await tester.pumpWidget(
        _wrapInfoSection(
          eventService: service,
          connectivity: connectivity,
          onContainer: (c) => container = c,
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'Updated Event');
      await tester.tap(find.byKey(EventKeys.saveChangesButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        find.text('Event updated — will sync when online.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Save Changes'), findsOneWidget);
      expect(container.read(connectivityProvider), ConnectivityStatus.syncing);
      verify(
        () => service.updateEvent(
          groupId: 'group-1',
          eventId: 'event-1',
          name: 'Updated Event',
          startDate: null,
          endDate: null,
          description: null,
        ),
      ).called(1);
    },
  );

  testWidgets(
    '#682: stale-probe online Save surfaces queued "will sync" feedback '
    'after the ack timeout',
    (tester) async {
      final service = _MockEventService();
      // Stale probe: the connectivity provider still reads `online` (it lags
      // real connectivity up to 60s, #633) while the device is actually
      // offline, so `skipWait` is false and the write is awaited to timeout.
      final connectivity = ConnectivityNotifier(startPeriodicChecks: false);
      late ProviderContainer container;

      when(
        () => service.updateEvent(
          groupId: 'group-1',
          eventId: 'event-1',
          name: 'Updated Event',
          startDate: null,
          endDate: null,
          description: null,
        ),
      ).thenAnswer((_) => Completer<void>().future); // never acks (offline)

      await tester.pumpWidget(
        _wrapInfoSection(
          eventService: service,
          connectivity: connectivity,
          onContainer: (c) => container = c,
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'Updated Event');
      await tester.tap(find.byKey(EventKeys.saveChangesButton));
      await tester.pump();

      // Within the timeout: spinner up, no confirmation yet.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Advance past kWriteAckTimeout → awaitServerAck resolves to queued.
      await tester.pump(kWriteAckTimeout + const Duration(milliseconds: 200));

      expect(
        find.text('Event updated — will sync when online.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Save Changes'), findsOneWidget);
      expect(container.read(connectivityProvider), ConnectivityStatus.syncing);
    },
  );

  testWidgets('#667: offline event delete routes back and marks queued', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'settings_device_name': 'Test User',
    });
    final prefs = await SharedPreferences.getInstance();
    final service = _MockEventService();
    final activityService = _MockGroupActivityService();
    final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
      ..setOffline();
    late ProviderContainer container;

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
    when(
      () => service.deleteEvent(groupId: 'group-1', eventId: 'event-1'),
    ).thenAnswer((_) => Completer<void>().future);

    await tester.pumpWidget(
      _wrapDangerSection(
        prefs: prefs,
        eventService: service,
        activityService: activityService,
        connectivity: connectivity,
        onContainer: (c) => container = c,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(EventKeys.deleteEventTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(EventKeys.deleteEventConfirmButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Group:group-1'), findsOneWidget);
    expect(container.read(connectivityProvider), ConnectivityStatus.syncing);
    verify(
      () => service.deleteEvent(groupId: 'group-1', eventId: 'event-1'),
    ).called(1);
  });
}

Widget _wrapInfoSection({
  required EventService eventService,
  required ConnectivityNotifier connectivity,
  required void Function(ProviderContainer) onContainer,
}) {
  return ProviderScope(
    overrides: [
      eventServiceProvider.overrideWithValue(eventService),
      connectivityProvider.overrideWith((ref) => connectivity),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onContainer(ProviderScope.containerOf(context));
          });
          return Scaffold(body: EventInfoSection(event: _event()));
        },
      ),
    ),
  );
}

Widget _wrapDangerSection({
  required SharedPreferences prefs,
  required EventService eventService,
  required GroupActivityService activityService,
  required ConnectivityNotifier connectivity,
  required void Function(ProviderContainer) onContainer,
}) {
  final event = _event();
  final router = GoRouter(
    initialLocation: '/danger',
    routes: [
      GoRoute(
        path: '/danger',
        builder: (_, _) => Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onContainer(ProviderScope.containerOf(context));
            });
            return Scaffold(
              body: EventDangerSection(
                groupId: event.groupId,
                eventId: event.id,
                event: event,
                isAdmin: true,
              ),
            );
          },
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
      connectivityProvider.overrideWith((ref) => connectivity),
      currentUserIdProvider.overrideWithValue('uid-creator'),
      eventExpensesProvider((
        groupId: event.groupId,
        eventId: event.id,
      )).overrideWith((ref) => Stream.value(const [])),
      eventSettlementsProvider((
        groupId: event.groupId,
        eventId: event.id,
      )).overrideWith((ref) => Stream.value(const [])),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

Event _event() {
  return Event(
    id: 'event-1',
    name: 'Original Event',
    type: EventType.trip,
    groupId: 'group-1',
    createdBy: 'uid-creator',
    participantIds: const ['uid-creator'],
    participantNames: const {'uid-creator': 'Creator'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 6, 24),
  );
}
