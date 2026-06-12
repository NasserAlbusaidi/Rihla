import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

const _groupId = 'group-1';

Event _event(
  String id, {
  required List<String> participantIds,
  required Map<String, String> participantNames,
}) {
  return Event(
    id: id,
    name: 'Event $id',
    type: EventType.trip,
    groupId: _groupId,
    createdBy: 'alice',
    participantIds: participantIds,
    participantNames: participantNames,
    modules: const EventModules(),
    createdAt: DateTime(2026, 5, 17),
  );
}

GroupMember _member(String uid, String name) {
  return GroupMember(
    id: uid,
    groupId: _groupId,
    userId: uid,
    displayName: name,
    role: 'MEMBER',
    joinedAt: DateTime(2026, 5, 17),
  );
}

Expense _expense(String id, String eventId, String payer, String amount) {
  return Expense(
    id: id,
    tripId: eventId,
    payerParticipantId: payer,
    amount: Decimal.parse(amount),
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 5, 17),
  );
}

Settlement _settlement(
  String id,
  String eventId, {
  required String payer,
  required String recipient,
  required String amount,
}) {
  return Settlement(
    id: id,
    tripId: eventId,
    payerParticipantId: payer,
    recipientParticipantId: recipient,
    amount: Decimal.parse(amount),
    settledAt: DateTime(2026, 5, 18),
    scope: 'event',
  );
}

Future<void> _pumpUntilData(ProviderContainer container) async {
  container.listen(
    groupBalancesProvider(_groupId),
    (_, _) {},
    fireImmediately: true,
  );
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderContainer _container({
  required List<Event> events,
  required List<GroupMember> members,
  required Map<String, List<Expense>> expensesByEvent,
  required Map<String, List<Settlement>> settlementsByEvent,
  List<Settlement> groupSettlements = const [],
}) {
  return ProviderContainer(
    overrides: [
      groupEventsProvider(_groupId).overrideWith((_) => Stream.value(events)),
      groupMembersProvider(_groupId).overrideWith((_) => Stream.value(members)),
      for (final event in events) ...[
        eventExpensesProvider((
          groupId: _groupId,
          eventId: event.id,
        )).overrideWith((_) => Stream.value(expensesByEvent[event.id] ?? [])),
        eventSettlementsProvider(
          (groupId: _groupId, eventId: event.id),
        ).overrideWith((_) => Stream.value(settlementsByEvent[event.id] ?? [])),
      ],
      groupSettlementsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(groupSettlements)),
    ],
  );
}

void main() {
  test(
    'adds an orphan financial actor without charging them for other events',
    () async {
      final eventA = _event(
        'event-a',
        participantIds: const ['alice', 'bob', 'orphan'],
        participantNames: const {
          'alice': 'Alice',
          'bob': 'Bob',
          'orphan': 'Aisha',
        },
      );
      final eventB = _event(
        'event-b',
        participantIds: const ['alice', 'bob'],
        participantNames: const {'alice': 'Alice', 'bob': 'Bob'},
      );
      final container = _container(
        events: [eventA, eventB],
        members: [_member('alice', 'Alice'), _member('bob', 'Bob')],
        expensesByEvent: {
          'event-a': [_expense('a-1', 'event-a', 'orphan', '30.000')],
          'event-b': [_expense('b-1', 'event-b', 'bob', '30.000')],
        },
        settlementsByEvent: const {},
      );
      addTearDown(container.dispose);

      await _pumpUntilData(container);

      final data = container.read(groupBalancesProvider(_groupId)).valueOrNull!;
      final byUid = {for (final b in data.balances['OMR']!) b.participantId: b};

      expect(data.memberNames['orphan'], 'Aisha (former member)');
      expect(data.memberRawNames['orphan'], 'Aisha');
      expect(byUid['orphan']!.totalOwed, Decimal.parse('10.000'));
      expect(byUid['orphan']!.netBalance, Decimal.parse('20.000'));
      expect(byUid['alice']!.netBalance, Decimal.parse('-25.000'));
      expect(byUid['bob']!.netBalance, Decimal.parse('5.000'));
    },
  );

  test(
    'preserves event-scoped settlement adjustments in aggregate net',
    () async {
      final eventA = _event(
        'event-a',
        participantIds: const ['alice', 'bob'],
        participantNames: const {'alice': 'Alice', 'bob': 'Bob'},
      );
      final container = _container(
        events: [eventA],
        members: [_member('alice', 'Alice'), _member('bob', 'Bob')],
        expensesByEvent: {
          'event-a': [_expense('a-1', 'event-a', 'bob', '20.000')],
        },
        settlementsByEvent: {
          'event-a': [
            _settlement(
              's-1',
              'event-a',
              payer: 'alice',
              recipient: 'bob',
              amount: '10.000',
            ),
          ],
        },
      );
      addTearDown(container.dispose);

      await _pumpUntilData(container);

      final data = container.read(groupBalancesProvider(_groupId)).valueOrNull!;
      final byUid = {for (final b in data.balances['OMR']!) b.participantId: b};

      expect(byUid['alice']!.netBalance, Decimal.zero);
      expect(byUid['bob']!.netBalance, Decimal.zero);
    },
  );
}
