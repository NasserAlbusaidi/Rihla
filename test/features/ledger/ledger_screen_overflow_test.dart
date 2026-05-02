import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/ledger_screen.dart';

void main() {
  const groupId = 'g1';
  const eventId = 'e1';
  const eventRef = (groupId: groupId, eventId: eventId);

  final event = Event(
    id: eventId,
    groupId: groupId,
    name: 'Beach Trip',
    type: EventType.trip,
    createdBy: 'uid-creator',
    participantIds: const ['uid-creator'],
    participantNames: const {'uid-creator': 'Alice'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 1, 10),
  );

  Widget buildLedger() {
    final router = GoRouter(
      initialLocation: '/group/$groupId/event/$eventId/ledger',
      routes: [
        GoRoute(
          path: '/group/:gid',
          builder: (context, state) => const Scaffold(body: Text('Group')),
          routes: [
            GoRoute(
              path: 'event/:eid',
              builder: (context, state) => const Scaffold(body: Text('Event')),
              routes: [
                GoRoute(
                  path: 'ledger',
                  builder: (context, state) => LedgerScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                ),
                GoRoute(
                  path: 'activity',
                  builder: (context, state) =>
                      const Scaffold(body: Text('Activity route')),
                ),
                GoRoute(
                  path: 'settings',
                  builder: (context, state) =>
                      const Scaffold(body: Text('Settings route')),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        eventDetailProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(event)),
        eventExpensesProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(const <Expense>[])),
        eventSettlementsProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(const <Settlement>[])),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    );
  }

  group('LedgerScreen overflow menu', () {
    testWidgets('overflow menu button is visible', (tester) async {
      await tester.pumpWidget(buildLedger());
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('overflow menu has Event activity and Event settings items', (
      tester,
    ) async {
      await tester.pumpWidget(buildLedger());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Event activity'), findsOneWidget);
      expect(find.text('Event settings'), findsOneWidget);
    });

    testWidgets('Event activity item navigates to event activity route', (
      tester,
    ) async {
      await tester.pumpWidget(buildLedger());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Event activity'));
      await tester.pumpAndSettle();

      expect(find.text('Activity route'), findsOneWidget);
    });

    testWidgets('Event settings item navigates to event settings route', (
      tester,
    ) async {
      await tester.pumpWidget(buildLedger());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Event settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings route'), findsOneWidget);
    });
  });
}
