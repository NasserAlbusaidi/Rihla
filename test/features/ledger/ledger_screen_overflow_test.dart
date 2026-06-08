import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/ledger_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

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

  Widget buildLedger({
    Event? eventOverride,
    List<Expense> expenses = const <Expense>[],
    String? currentUserId = 'uid-creator',
  }) {
    final effectiveEvent = eventOverride ?? event;
    final groupMembers = [
      for (final uid in effectiveEvent.participantIds)
        GroupMember(
          id: uid,
          groupId: groupId,
          userId: uid,
          displayName: effectiveEvent.participantNames[uid] ?? uid,
          role: uid == effectiveEvent.createdBy ? 'CREATOR' : 'MEMBER',
          joinedAt: effectiveEvent.createdAt,
        ),
    ];
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
                  routes: [
                    GoRoute(
                      path: 'add',
                      builder: (context, state) =>
                          const Scaffold(body: Text('Add expense route')),
                    ),
                    GoRoute(
                      path: 'edit/:expId',
                      builder: (context, state) => Scaffold(
                        body: Text(
                          'Edit expense route:${state.pathParameters['expId']}',
                        ),
                      ),
                    ),
                    GoRoute(
                      path: 'settle-up',
                      builder: (context, state) =>
                          const Scaffold(body: Text('Settle up route')),
                    ),
                  ],
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
        currentUserIdProvider.overrideWithValue(currentUserId),
        eventDetailProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(effectiveEvent)),
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
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  group('LedgerScreen header actions', () {
    testWidgets('settings and search buttons are visible', (tester) async {
      await tester.pumpWidget(buildLedger());
      await tester.pumpAndSettle();

      expect(find.byTooltip('Search expenses'), findsOneWidget);
      expect(find.byTooltip('Event settings'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });

    testWidgets('direct entry back button returns to event route', (
      tester,
    ) async {
      await tester.pumpWidget(buildLedger());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Event'), findsOneWidget);
    });

    testWidgets('search button opens the ledger search sheet', (tester) async {
      await tester.pumpWidget(buildLedger());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search expenses'));
      await tester.pumpAndSettle();

      expect(find.byKey(LedgerKeys.searchField), findsOneWidget);
      expect(find.text('Search expenses'), findsWidgets);
    });

    testWidgets('settings button navigates to event settings route', (
      tester,
    ) async {
      await tester.pumpWidget(buildLedger());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Event settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings route'), findsOneWidget);
    });

    testWidgets('add expense CTA navigates to add expense route', (
      tester,
    ) async {
      await tester.pumpWidget(buildLedger());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();

      expect(find.text('Add expense route'), findsOneWidget);
    });

    testWidgets('settle up CTA navigates to settle-up route', (tester) async {
      // V5R disables Settle up when balance is zero (nothing to settle).
      // Seed a 2-person event with an unsettled expense so it stays tappable.
      final twoMemberEvent = event.copyWith(
        participantIds: const ['uid-creator', 'uid-other'],
        participantNames: const {'uid-creator': 'Alice', 'uid-other': 'Bob'},
      );
      final expenses = [
        Expense(
          id: 'expense-1',
          tripId: eventId,
          payerParticipantId: 'uid-creator',
          amount: Decimal.parse('3.000'),
          description: 'Coffee',
          scope: ExpenseScope.global,
          createdAt: DateTime(2026, 1, 10),
        ),
      ];
      await tester.pumpWidget(
        buildLedger(eventOverride: twoMemberEvent, expenses: expenses),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settle up'));
      await tester.pumpAndSettle();

      expect(find.text('Settle up route'), findsOneWidget);
    });

    testWidgets('expense row tap navigates to edit expense route', (
      tester,
    ) async {
      final expenses = [
        Expense(
          id: 'expense-1',
          tripId: eventId,
          payerParticipantId: 'uid-creator',
          amount: Decimal.parse('3.000'),
          description: 'Coffee',
          scope: ExpenseScope.global,
          createdAt: DateTime(2026, 1, 10),
        ),
      ];

      await tester.pumpWidget(buildLedger(expenses: expenses));
      await tester.pumpAndSettle();

      final row = find.byKey(LedgerKeys.expenseCard('expense-1'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.text('Edit expense route:expense-1'), findsOneWidget);
    });

    testWidgets('search result tap navigates to edit expense route', (
      tester,
    ) async {
      final expenses = [
        Expense(
          id: 'expense-1',
          tripId: eventId,
          payerParticipantId: 'uid-creator',
          amount: Decimal.parse('3.000'),
          description: 'Coffee',
          categoryName: 'Food',
          scope: ExpenseScope.global,
          createdAt: DateTime(2026, 1, 10),
        ),
      ];

      await tester.pumpWidget(buildLedger(expenses: expenses));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search expenses'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(LedgerKeys.searchField), 'Coffee');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coffee').last);
      await tester.pumpAndSettle();

      expect(find.text('Edit expense route:expense-1'), findsOneWidget);
    });

    testWidgets('uses the signed-in member for the event balance', (
      tester,
    ) async {
      final twoMemberEvent = event.copyWith(
        participantIds: const ['uid-payer', 'uid-debtor'],
        participantNames: const {'uid-payer': 'Mona', 'uid-debtor': 'Nasser'},
      );
      final expenses = [
        Expense(
          id: 'expense-1',
          tripId: eventId,
          payerParticipantId: 'uid-payer',
          amount: Decimal.parse('3.000'),
          description: 'Coffee',
          scope: ExpenseScope.global,
          createdAt: DateTime(2026, 1, 10),
        ),
      ];

      await tester.pumpWidget(
        buildLedger(
          eventOverride: twoMemberEvent,
          expenses: expenses,
          currentUserId: 'uid-debtor',
        ),
      );
      await tester.pumpAndSettle();

      // V5R hero prose: "You owe −OMR 1.500 to 1 person." rendered as
      // Text.rich with an inline WidgetSpan for the money, so assert the
      // prose halves via findRichText.
      expect(
        find.textContaining('You owe', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('to 1 person', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Mona paid · split 2 ways'), findsOneWidget);
    });
  });
}
