import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/providers/group_spending_summary_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/utils/group_spending_summary.dart';

Event _makeEvent({
  required String id,
  required String groupId,
  List<String> participantIds = const ['uid-1', 'uid-2'],
}) {
  return Event(
    id: id,
    name: 'Event $id',
    type: EventType.trip,
    groupId: groupId,
    createdBy: 'creator',
    participantIds: participantIds,
    participantNames: {for (final uid in participantIds) uid: 'User $uid'},
    modules: const EventModules(),
    createdAt: DateTime(2025, 1, 1),
  );
}

Expense _makeExpense({
  required String id,
  required String tripId,
  required String amount,
  String payer = 'uid-1',
  String? categoryId,
}) {
  return Expense(
    id: id,
    tripId: tripId,
    payerParticipantId: payer,
    amount: Decimal.parse(amount),
    scope: ExpenseScope.global,
    createdAt: DateTime(2025, 1, 1),
    categoryId: categoryId,
  );
}

Future<void> _pump(ProviderContainer container, String groupId) async {
  container.listen(
    groupSpendingSummaryProvider(groupId),
    (_, _) {},
    fireImmediately: true,
  );
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  const groupId = 'group-1';

  group('groupSpendingSummaryProvider', () {
    test('wires per-event expenses + balances into the pure aggregator',
        () async {
      final eventA = _makeEvent(id: 'event-a', groupId: groupId);
      final eventB = _makeEvent(id: 'event-b', groupId: groupId);
      final expensesA = [
        _makeExpense(
          id: 'x1',
          tripId: 'event-a',
          amount: '10',
          categoryId: 'food',
        ),
      ];
      final expensesB = [
        _makeExpense(
          id: 'x2',
          tripId: 'event-b',
          amount: '30',
          payer: 'uid-2',
          categoryId: 'fuel',
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(groupId)
              .overrideWith((_) => Stream.value([eventA, eventB])),
          groupMembersProvider(groupId).overrideWith((_) => Stream.value([])),
          groupSettlementsProvider(groupId)
              .overrideWith((_) => Stream.value([])),
          eventExpensesProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith((_) => Stream.value(expensesA)),
          eventExpensesProvider((groupId: groupId, eventId: 'event-b'))
              .overrideWith((_) => Stream.value(expensesB)),
          eventSettlementsProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith((_) => Stream.value(const <Settlement>[])),
          eventSettlementsProvider((groupId: groupId, eventId: 'event-b'))
              .overrideWith((_) => Stream.value(const <Settlement>[])),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final summary = container.read(groupSpendingSummaryProvider(groupId));

      expect(summary.totalSpentByCurrency, {'OMR': Decimal.parse('40')});
      expect(summary.eventTotalsByCurrency['OMR'], [
        (eventId: 'event-b', total: Decimal.parse('30')),
        (eventId: 'event-a', total: Decimal.parse('10')),
      ]);

      // Same inputs through the pure fn agree with the balances the live
      // provider computed (wiring correctness, not new arithmetic).
      final balances =
          container.read(groupBalancesProvider(groupId)).requireValue;
      final direct = computeGroupSpendingSummary(
        expensesByEvent: {'event-a': expensesA, 'event-b': expensesB},
        balances: balances.balances,
      );
      expect(
        summary.topPayerByCurrency['OMR'],
        direct.topPayerByCurrency['OMR'],
      );
      expect(summary.topPayerByCurrency['OMR']?.participantId, 'uid-2');
    });

    test('event with errored settlements stream is OR-skipped like balances',
        () async {
      final eventA = _makeEvent(id: 'event-a', groupId: groupId);
      final eventB = _makeEvent(id: 'event-b', groupId: groupId);
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(groupId)
              .overrideWith((_) => Stream.value([eventA, eventB])),
          groupMembersProvider(groupId).overrideWith((_) => Stream.value([])),
          groupSettlementsProvider(groupId)
              .overrideWith((_) => Stream.value([])),
          eventExpensesProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith(
            (_) => Stream.value([
              _makeExpense(id: 'x1', tripId: 'event-a', amount: '10'),
            ]),
          ),
          eventExpensesProvider((groupId: groupId, eventId: 'event-b'))
              .overrideWith(
            (_) => Stream.value([
              _makeExpense(id: 'x2', tripId: 'event-b', amount: '99'),
            ]),
          ),
          eventSettlementsProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith((_) => Stream.value(const <Settlement>[])),
          eventSettlementsProvider((groupId: groupId, eventId: 'event-b'))
              .overrideWith(
            (_) => Stream<List<Settlement>>.error(Exception('denied')),
          ),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final summary = container.read(groupSpendingSummaryProvider(groupId));

      // event-b's money never enters any slice — mirrors the balance
      // provider's OR-skip so summary and balances share one event universe.
      expect(summary.totalSpentByCurrency, {'OMR': Decimal.parse('10')});
      expect(summary.eventTotalsByCurrency['OMR'], [
        (eventId: 'event-a', total: Decimal.parse('10')),
      ]);
    });

    test('balances still loading -> spend slices computed, superlatives empty',
        () async {
      final eventA = _makeEvent(id: 'event-a', groupId: groupId);
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(groupId)
              .overrideWith((_) => Stream.value([eventA])),
          // Never emits: groupBalancesProvider stays AsyncLoading.
          groupMembersProvider(groupId)
              .overrideWith((_) => const Stream.empty()),
          groupSettlementsProvider(groupId)
              .overrideWith((_) => Stream.value([])),
          eventExpensesProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith(
            (_) => Stream.value([
              _makeExpense(id: 'x1', tripId: 'event-a', amount: '10'),
            ]),
          ),
          eventSettlementsProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith((_) => Stream.value(const <Settlement>[])),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final summary = container.read(groupSpendingSummaryProvider(groupId));

      expect(summary.totalSpentByCurrency, {'OMR': Decimal.parse('10')});
      expect(summary.topPayerByCurrency, isEmpty);
      expect(summary.topConsumerByCurrency, isEmpty);
    });
  });
}
