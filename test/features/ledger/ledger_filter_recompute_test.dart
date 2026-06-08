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
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/ledger_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #106 — a category-chip tap must NOT re-enter [BalanceCalculator.calculateBalances]
/// (the filter-independent balance/name work is hoisted into a memoized provider),
/// and the refactor must not regress former-member rendering.
void main() {
  const groupId = 'g1';
  const eventId = 'e1';
  const eventRef = (groupId: groupId, eventId: eventId);

  GroupMember member(String uid, String name, {bool tombstone = false}) =>
      GroupMember(
        id: uid,
        groupId: groupId,
        userId: uid,
        displayName: name,
        role: 'MEMBER',
        isTombstone: tombstone,
        joinedAt: DateTime(2026, 1, 10),
      );

  Expense expense({
    required String id,
    required String payer,
    required String category,
    required String amount,
  }) =>
      Expense(
        id: id,
        tripId: eventId,
        payerParticipantId: payer,
        amount: Decimal.parse(amount),
        description: category,
        categoryName: category,
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 1, 11),
        createdBy: payer,
        currency: 'OMR',
      );

  Future<void> pumpLedger(
    WidgetTester tester, {
    required Event event,
    required List<Expense> expenses,
    required List<GroupMember> members,
    String currentUser = 'uid-sara',
  }) async {
    final router = GoRouter(
      initialLocation: '/group/$groupId/event/$eventId/ledger',
      routes: [
        GoRoute(
          path: '/group/:gid/event/:eid/ledger',
          builder: (context, state) => LedgerScreen(
            groupId: state.pathParameters['gid']!,
            eventId: state.pathParameters['eid']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
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
          currentUserIdProvider.overrideWithValue(currentUser),
          eventDetailProvider(eventRef).overrideWith((ref) => Stream.value(event)),
          eventExpensesProvider(eventRef).overrideWith((ref) => Stream.value(expenses)),
          eventSettlementsProvider(eventRef)
              .overrideWith((ref) => Stream.value(const <Settlement>[])),
          groupMembersProvider(groupId).overrideWith((ref) => Stream.value(members)),
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
  }

  final twoCategoryEvent = Event(
    id: eventId,
    groupId: groupId,
    name: 'Beach Trip',
    type: EventType.trip,
    createdBy: 'uid-sara',
    participantIds: const ['uid-sara', 'uid-bob'],
    participantNames: const {'uid-sara': 'Sara', 'uid-bob': 'Bob'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 1, 10),
  );

  testWidgets(
    'category-chip tap does not re-enter calculateBalances and still filters',
    (tester) async {
      await pumpLedger(
        tester,
        event: twoCategoryEvent,
        expenses: [
          expense(id: 'x-food', payer: 'uid-sara', category: 'Dinner', amount: '30.000'),
          expense(id: 'x-transit', payer: 'uid-bob', category: 'Taxi', amount: '12.000'),
        ],
        members: [member('uid-sara', 'Sara'), member('uid-bob', 'Bob')],
      );

      // Both categories visible under the default "All" filter.
      expect(find.byKey(LedgerKeys.expenseCard('x-food')), findsOneWidget);
      expect(find.byKey(LedgerKeys.expenseCard('x-transit')), findsOneWidget);

      // Measure ONLY the work the tap itself triggers.
      BalanceCalculator.debugCalculateBalancesCount = 0;
      await tester.tap(find.text('Food'));
      await tester.pump();

      // The filter changed (Transit row gone, Food row stays) ...
      expect(find.byKey(LedgerKeys.expenseCard('x-transit')), findsNothing);
      expect(find.byKey(LedgerKeys.expenseCard('x-food')), findsOneWidget);
      // ... but the balance pass was NOT re-run. (RED on pre-#106 main.)
      expect(BalanceCalculator.debugCalculateBalancesCount, 0);
    },
  );

  testWidgets('a departed payer still renders with the (former member) suffix',
      (tester) async {
    await pumpLedger(
      tester,
      event: twoCategoryEvent,
      expenses: [
        expense(id: 'x-omar', payer: 'uid-omar', category: 'Dinner', amount: '20.000'),
      ],
      members: [
        member('uid-sara', 'Sara'),
        member('uid-bob', 'Bob'),
        member('uid-omar', 'Omar', tombstone: true),
      ],
    );

    expect(
      find.textContaining('Omar (former member)', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets(
    'settlement row shows the resolved party name, not the raw persisted payerName',
    (tester) async {
      // P1#1 guard: the provider stores the RESOLVED label for a settlement
      // whose payer is a known participant; the widget post-pass must NOT leak
      // the raw persisted payerName. (LedgerDayCard's LedgerSettleRow and the
      // search sheet consume the identical post-passed map.)
      await pumpLedger(
        tester,
        event: twoCategoryEvent,
        currentUser: 'uid-bob',
        expenses: [
          expense(id: 'x-food', payer: 'uid-sara', category: 'Dinner', amount: '30.000'),
        ],
        members: [member('uid-sara', 'Sara'), member('uid-bob', 'Bob')],
      );
      // Re-pump with a settlement whose persisted payerName is deliberately wrong.
      // (The pump helper seeds settlements as empty; rebuild with one here.)
      final settlement = Settlement(
        id: 's1',
        tripId: eventId,
        payerParticipantId: 'uid-sara',
        payerName: 'WRONG_RAW',
        recipientParticipantId: 'uid-bob',
        recipientName: 'Bob',
        amount: Decimal.parse('5.000'),
        settledAt: DateTime(2026, 1, 13),
      );
      await tester.pumpWidget(
        ProviderScope(
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
            currentUserIdProvider.overrideWithValue('uid-bob'),
            eventDetailProvider(eventRef)
                .overrideWith((ref) => Stream.value(twoCategoryEvent)),
            eventExpensesProvider(eventRef).overrideWith(
              (ref) => Stream.value([
                expense(id: 'x-food', payer: 'uid-sara', category: 'Dinner', amount: '30.000'),
              ]),
            ),
            eventSettlementsProvider(eventRef)
                .overrideWith((ref) => Stream.value([settlement])),
            groupMembersProvider(groupId).overrideWith(
              (ref) => Stream.value([member('uid-sara', 'Sara'), member('uid-bob', 'Bob')]),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: GoRouter(
              initialLocation: '/group/$groupId/event/$eventId/ledger',
              routes: [
                GoRoute(
                  path: '/group/:gid/event/:eid/ledger',
                  builder: (context, state) => LedgerScreen(
                    groupId: state.pathParameters['gid']!,
                    eventId: state.pathParameters['eid']!,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Sara', findRichText: true), findsWidgets);
      expect(find.textContaining('WRONG_RAW', findRichText: true), findsNothing);
    },
  );
}
