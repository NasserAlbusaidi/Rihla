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

Event _event(String id) => Event(
  id: id,
  name: 'Event $id',
  type: EventType.trip,
  groupId: _groupId,
  createdBy: 'alice',
  participantIds: const ['alice', 'bob'],
  participantNames: const {'alice': 'Alice', 'bob': 'Bob'},
  modules: const EventModules(),
  createdAt: DateTime(2026, 7, 1),
);

GroupMember _member(String uid, String name) => GroupMember(
  id: uid,
  groupId: _groupId,
  userId: uid,
  displayName: name,
  role: 'MEMBER',
  joinedAt: DateTime(2026, 7, 1),
);

Expense _expense(String id, String eventId, String amount) => Expense(
  id: id,
  tripId: eventId,
  payerParticipantId: 'alice',
  amount: Decimal.parse(amount),
  scope: ExpenseScope.global,
  createdAt: DateTime(2026, 7, 1),
);

Future<void> _drainMicrotasks() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    '#1106: an event whose expense stream has no first snapshot is converging; '
    'display still proceeds-on-partial (#244 pinned)',
    () async {
      final pendingExpenses = StreamController<List<Expense>>();
      addTearDown(pendingExpenses.close);
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            _groupId,
          ).overrideWith((_) => Stream.value([_event('e1'), _event('e2')])),
          groupMembersProvider(_groupId).overrideWith(
            (_) => Stream.value([
              _member('alice', 'Alice'),
              _member('bob', 'Bob'),
            ]),
          ),
          groupSettlementsProvider(
            _groupId,
          ).overrideWith((_) => Stream.value(const <Settlement>[])),
          eventExpensesProvider((
            groupId: _groupId,
            eventId: 'e1',
          )).overrideWith((_) => Stream.value([_expense('x1', 'e1', '20.000')])),
          eventSettlementsProvider((
            groupId: _groupId,
            eventId: 'e1',
          )).overrideWith((_) => Stream.value(const <Settlement>[])),
          eventExpensesProvider((
            groupId: _groupId,
            eventId: 'e2',
          )).overrideWith((_) => pendingExpenses.stream),
          eventSettlementsProvider((
            groupId: _groupId,
            eventId: 'e2',
          )).overrideWith((_) => Stream.value(const <Settlement>[])),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        groupConvergingEventIdsProvider(_groupId),
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        groupBalancesProvider(_groupId),
        (_, _) {},
        fireImmediately: true,
      );
      await _drainMicrotasks();

      // e2's expense stream has not delivered a first snapshot → converging.
      expect(container.read(groupConvergingEventIdsProvider(_groupId)), {'e2'});
      // #244 display invariant PINNED: the balance provider still returns DATA
      // computed from e1 alone (proceed-on-partial is deliberately kept).
      final balances = container.read(groupBalancesProvider(_groupId));
      expect(balances.hasValue, isTrue);
      expect(
        balances.requireValue.balances['OMR']!
            .firstWhere((b) => b.participantId == 'bob')
            .netBalance,
        Decimal.parse('-10.000'),
      );

      // First snapshot arrives → the window closes.
      pendingExpenses.add(const <Expense>[]);
      await _drainMicrotasks();
      expect(
        container.read(groupConvergingEventIdsProvider(_groupId)),
        isEmpty,
      );
    },
  );

  test('#1106: a hard-errored stream is failed, NOT converging (orthogonal '
      'to groupFailedEventIdsProvider)', () async {
    final container = ProviderContainer(
      overrides: [
        groupEventsProvider(
          _groupId,
        ).overrideWith((_) => Stream.value([_event('e1')])),
        groupMembersProvider(_groupId).overrideWith(
          (_) =>
              Stream.value([_member('alice', 'Alice'), _member('bob', 'Bob')]),
        ),
        groupSettlementsProvider(
          _groupId,
        ).overrideWith((_) => Stream.value(const <Settlement>[])),
        eventExpensesProvider((groupId: _groupId, eventId: 'e1')).overrideWith(
          (_) => Stream<List<Expense>>.error(Exception('permission-denied')),
        ),
        eventSettlementsProvider((
          groupId: _groupId,
          eventId: 'e1',
        )).overrideWith((_) => Stream.value(const <Settlement>[])),
      ],
    );
    addTearDown(container.dispose);
    container.listen(
      groupConvergingEventIdsProvider(_groupId),
      (_, _) {},
      fireImmediately: true,
    );
    container.listen(
      groupFailedEventIdsProvider(_groupId),
      (_, _) {},
      fireImmediately: true,
    );
    await _drainMicrotasks();

    expect(container.read(groupConvergingEventIdsProvider(_groupId)), isEmpty);
    expect(container.read(groupFailedEventIdsProvider(_groupId)), {'e1'});
  });

  test('#1106: a pending SETTLEMENT stream alone marks the event converging '
      '(OR semantics)', () async {
    final pendingSettlements = StreamController<List<Settlement>>();
    addTearDown(pendingSettlements.close);
    final container = ProviderContainer(
      overrides: [
        groupEventsProvider(
          _groupId,
        ).overrideWith((_) => Stream.value([_event('e1')])),
        groupMembersProvider(_groupId).overrideWith(
          (_) =>
              Stream.value([_member('alice', 'Alice'), _member('bob', 'Bob')]),
        ),
        groupSettlementsProvider(
          _groupId,
        ).overrideWith((_) => Stream.value(const <Settlement>[])),
        eventExpensesProvider((
          groupId: _groupId,
          eventId: 'e1',
        )).overrideWith((_) => Stream.value(const <Expense>[])),
        eventSettlementsProvider((
          groupId: _groupId,
          eventId: 'e1',
        )).overrideWith((_) => pendingSettlements.stream),
      ],
    );
    addTearDown(container.dispose);
    container.listen(
      groupConvergingEventIdsProvider(_groupId),
      (_, _) {},
      fireImmediately: true,
    );
    await _drainMicrotasks();

    expect(container.read(groupConvergingEventIdsProvider(_groupId)), {'e1'});
  });
}
