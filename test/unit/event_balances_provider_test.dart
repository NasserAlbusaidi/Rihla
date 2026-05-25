import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

const _groupId = 'group-1';
const _eventId = 'event-1';

Event _event({
  required List<String> participantIds,
  required Map<String, String> participantNames,
}) {
  return Event(
    id: _eventId,
    name: 'Trip',
    type: EventType.trip,
    groupId: _groupId,
    createdBy: 'alice',
    participantIds: participantIds,
    participantNames: participantNames,
    modules: const EventModules(),
    createdAt: DateTime(2026, 5, 25),
  );
}

GroupMember _member(String uid, String name, {bool isTombstone = false}) {
  return GroupMember(
    id: uid,
    groupId: _groupId,
    userId: uid,
    displayName: name,
    role: 'MEMBER',
    isTombstone: isTombstone,
    joinedAt: DateTime(2026, 5, 25),
  );
}

Expense _expense({
  required String id,
  required String payer,
  required String amount,
  ExpenseScope scope = ExpenseScope.global,
}) {
  return Expense(
    id: id,
    tripId: _eventId,
    payerParticipantId: payer,
    amount: Decimal.parse(amount),
    scope: scope,
    createdAt: DateTime(2026, 5, 25, 10),
  );
}

Settlement _settlement({
  required String id,
  required String payer,
  required String recipient,
  required String amount,
  String? payerName,
  String? recipientName,
}) {
  return Settlement(
    id: id,
    tripId: _eventId,
    payerParticipantId: payer,
    recipientParticipantId: recipient,
    amount: Decimal.parse(amount),
    payerName: payerName,
    recipientName: recipientName,
    settledAt: DateTime(2026, 5, 25, 11),
    scope: 'event',
  );
}

ProviderContainer _container({
  required Event event,
  required List<GroupMember> members,
  List<Expense> expenses = const [],
  List<Settlement> settlements = const [],
}) {
  const ref = (groupId: _groupId, eventId: _eventId);
  return ProviderContainer(
    overrides: [
      groupMembersProvider(_groupId).overrideWith((_) => Stream.value(members)),
      eventExpensesProvider(ref).overrideWith((_) => Stream.value(expenses)),
      eventSettlementsProvider(
        ref,
      ).overrideWith((_) => Stream.value(settlements)),
    ],
  );
}

Future<void> _pump(ProviderContainer container, Event event) async {
  container.listen(
    eventBalancesProvider((eventRef: (groupId: _groupId, eventId: _eventId), event: event)),
    (_, _) {},
    fireImmediately: true,
  );
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'former-member payer settling to current recipient preserves sum-to-zero',
    () async {
      // The headline Fix [3] bug: former payer's contribution was dropped
      // (paidMap.containsKey guard at expense_provider.dart:286), recipient
      // adjustment still applied → sum off by settlement amount.
      final event = _event(
        participantIds: const ['alice', 'bob'],
        participantNames: const {'alice': 'Alice', 'bob': 'Bob'},
      );
      final container = _container(
        event: event,
        members: [
          _member('alice', 'Alice'),
          _member('bob', 'Bob'),
          _member('charlie', 'Charlie', isTombstone: true),
        ],
        expenses: [
          _expense(id: 'x1', payer: 'alice', amount: '30.000'),
        ],
        settlements: [
          _settlement(
            id: 's1',
            payer: 'charlie',
            recipient: 'alice',
            amount: '5.000',
            payerName: 'Charlie',
            recipientName: 'Alice',
          ),
        ],
      );
      addTearDown(container.dispose);

      await _pump(container, event);

      final balances = container
          .read(eventBalancesProvider((
            eventRef: (groupId: _groupId, eventId: _eventId),
            event: event,
          )))
          .valueOrNull;
      expect(balances, isNotNull);

      final sum = balances!.fold(
        Decimal.zero,
        (acc, b) => acc + b.netBalance,
      );
      expect(sum, Decimal.zero, reason: 'per-event sum(netBalance) must be 0');

      final byUid = {for (final b in balances) b.participantId: b};
      expect(
        byUid.keys.toSet(),
        {'alice', 'bob', 'charlie'},
        reason: 'former actor (charlie) must appear in the balance set',
      );
      expect(byUid['charlie']!.totalPaid, Decimal.parse('5.000'));
      expect(
        byUid['charlie']!.displayName,
        'Charlie (former member)',
        reason: 'tombstoned member is formatted with former suffix',
      );
    },
  );

  test(
    'pure-orphan payer name from settlement is preserved (not replaced with "Former member")',
    () async {
      // Round-1 [P1] #3 regression: without fallback-name plumb-through, the
      // resolver would emit "Former member (former member)" — which would
      // then persist into new settlements via the SettleUp userRawNames map.
      final event = _event(
        participantIds: const ['alice'],
        participantNames: const {'alice': 'Alice'},
      );
      final container = _container(
        event: event,
        members: [_member('alice', 'Alice')],
        settlements: [
          _settlement(
            id: 's1',
            payer: 'ghost',
            recipient: 'alice',
            amount: '7.000',
            payerName: 'Ghost',
            recipientName: 'Alice',
          ),
        ],
      );
      addTearDown(container.dispose);

      await _pump(container, event);

      final balances = container
          .read(eventBalancesProvider((
            eventRef: (groupId: _groupId, eventId: _eventId),
            event: event,
          )))
          .valueOrNull!;
      final byUid = {for (final b in balances) b.participantId: b};
      expect(byUid['ghost']!.displayName, 'Ghost (former member)');
    },
  );
}
