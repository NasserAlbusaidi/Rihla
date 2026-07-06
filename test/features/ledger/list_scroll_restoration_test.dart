import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/activity/screens/activity_feed_screen.dart';
import 'package:safar/features/activity/services/activity_service.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/ledger_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #362: scroll position on the activity-feed + ledger scrollables must survive
/// an Android process kill. We simulate that with [WidgetTester.restartAndRestore]
/// and assert the offset is restored. Restoration is a no-op unless (a) the
/// scrollable carries a stable `restorationId` and (b) it sits under an active
/// restoration scope — here supplied by `MaterialApp.router(restorationScopeId:)`.
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

  double scrollOffset(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

  group('activity feed scroll restoration', () {
    Future<void> seed(FakeFirebaseFirestore db, int n) async {
      for (var i = 0; i < n; i++) {
        final ts = DateTime.utc(2026, 2, 1).add(Duration(seconds: n - i));
        await db
            .collection('groups')
            .doc(groupId)
            .collection('events')
            .doc(eventId)
            .collection('activity_logs')
            .doc('a${i.toString().padLeft(4, '0')}')
            .set({
              'id': 'a$i',
              'eventId': eventId,
              'category': 'MONEY',
              'eventType': 'CREATE',
              'logText': 'paid for item $i',
              'actorId': 'u1',
              'actorName': 'Actor $i',
              'metadata': <String, dynamic>{},
              'createdAt': ts.toIso8601String(),
            });
      }
    }

    Widget buildRoute(List<Override> overrides) {
      final router = GoRouter(
        restorationScopeId: 'router',
        initialLocation: '/group/$groupId/event/$eventId/activity',
        routes: [
          GoRoute(
            path: '/group/:gid',
            builder: (c, s) => const Scaffold(body: Text('Group')),
            routes: [
              GoRoute(
                path: 'event/:eid',
                builder: (c, s) => const Scaffold(body: Text('Event')),
                routes: [
                  GoRoute(
                    path: 'activity',
                    builder: (c, s) => Scaffold(
                      body: ActivityFeedScreen(
                        groupId: s.pathParameters['gid']!,
                        eventId: s.pathParameters['eid']!,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      return ProviderScope(
        overrides: [
          eventDetailProvider(
            eventRef,
          ).overrideWith((ref) => Stream<Event?>.value(event)),
          ...overrides,
        ],
        child: MaterialApp.router(
          restorationScopeId: 'app',
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
    }

    testWidgets('restores scroll offset after a simulated process kill', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await seed(db, 40); // one page (<50) -> no infinite footer spinner
      await tester.pumpWidget(
        buildRoute([
          activityServiceProvider.overrideWithValue(
            ActivityService.withFirestore(db),
          ),
        ]),
      );
      await tester.pump(const Duration(seconds: 1));

      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -600));
      await tester.pump();
      final before = scrollOffset(tester);
      expect(before, greaterThan(0));

      await tester.restartAndRestore();
      await tester.pump(const Duration(seconds: 1));

      expect(scrollOffset(tester), moreOrLessEquals(before, epsilon: 1.0));
    });
  });

  group('ledger scroll restoration', () {
    Widget buildLedger(List<Expense> expenses) {
      final groupMembers = [
        for (final uid in event.participantIds)
          GroupMember(
            id: uid,
            groupId: groupId,
            userId: uid,
            displayName: event.participantNames[uid] ?? uid,
            role: uid == event.createdBy ? 'CREATOR' : 'MEMBER',
            joinedAt: event.createdAt,
          ),
      ];
      final router = GoRouter(
        restorationScopeId: 'router',
        initialLocation: '/group/$groupId/event/$eventId/ledger',
        routes: [
          GoRoute(
            path: '/group/:gid',
            builder: (context, state) => const Scaffold(body: Text('Group')),
            routes: [
              GoRoute(
                path: 'event/:eid',
                builder: (context, state) =>
                    const Scaffold(body: Text('Event')),
                routes: [
                  GoRoute(
                    path: 'ledger',
                    builder: (context, state) => Scaffold(
                      body: LedgerScreen(
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
      addTearDown(router.dispose);
      return ProviderScope(
        overrides: [
          groupDetailProvider(groupId).overrideWith(
            (ref) => Stream.value(
              Group(
                id: groupId,
                name: 'Trip',
                inviteCode: 'ABC123',
                createdBy: 'creator',
                memberIds: const [],
                currency: 'OMR',
                createdAt: DateTime(2026),
              ),
            ),
          ),
          currentUserIdProvider.overrideWithValue('uid-creator'),
          eventDetailProvider(
            eventRef,
          ).overrideWith((ref) => Stream.value(event)),
          eventExpensesProvider(
            eventRef,
          ).overrideWith((ref) => Stream.value(expenses)),
          eventSettlementsProvider(
            eventRef,
          ).overrideWith((ref) => Stream.value(const <Settlement>[])),
          groupMembersProvider(
            groupId,
          ).overrideWith((ref) => Stream.value(groupMembers)),
        ],
        child: MaterialApp.router(
          restorationScopeId: 'app',
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
    }

    testWidgets('restores scroll offset after a simulated process kill', (
      tester,
    ) async {
      final expenses = [
        for (var i = 0; i < 30; i++)
          Expense(
            id: 'expense-$i',
            tripId: eventId,
            payerParticipantId: 'uid-creator',
            amount: Decimal.parse('3.000'),
            description: 'Item $i',
            scope: ExpenseScope.global,
            createdAt: DateTime(2026, 1, 10).subtract(Duration(days: i)),
          ),
      ];
      await tester.pumpWidget(buildLedger(expenses));
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -600));
      await tester.pump();
      final before = scrollOffset(tester);
      expect(before, greaterThan(0));

      await tester.restartAndRestore();
      await tester.pumpAndSettle();

      expect(scrollOffset(tester), moreOrLessEquals(before, epsilon: 1.0));
    });
  });
}
