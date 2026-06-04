import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Helper to build a minimal [Event] for testing.
Event _makeEvent({
  required String id,
  required String groupId,
  List<String>? participantIds,
  Map<String, String>? participantNames,
}) {
  return Event(
    id: id,
    name: 'Event $id',
    type: EventType.trip,
    groupId: groupId,
    createdBy: 'creator',
    participantIds: participantIds ?? [],
    participantNames: participantNames ?? {},
    modules: const EventModules(),
    createdAt: DateTime(2025, 1, 1),
  );
}

/// Helper to build a minimal [GroupMember] for testing.
GroupMember _makeMember({
  required String userId,
  required String groupId,
  String? displayName,
}) {
  return GroupMember(
    id: 'member-$userId',
    groupId: groupId,
    userId: userId,
    displayName: displayName ?? 'User $userId',
    role: 'MEMBER',
    joinedAt: DateTime(2025, 1, 1),
  );
}

/// Helper to build a minimal [Expense] for testing.
Expense _makeExpense({
  required String id,
  required String payerParticipantId,
  required Decimal amount,
  String tripId = 'event-a',
}) {
  return Expense(
    id: id,
    tripId: tripId,
    payerParticipantId: payerParticipantId,
    amount: amount,
    scope: ExpenseScope.global,
    createdAt: DateTime(2025, 1, 1),
  );
}

/// Helper to build a minimal [Settlement] for testing.
Settlement _makeSettlement({
  required String id,
  required String payerParticipantId,
  required String recipientParticipantId,
  required Decimal amount,
  String scope = 'group',
  String tripId = 'group-1',
}) {
  return Settlement(
    id: id,
    tripId: tripId,
    payerParticipantId: payerParticipantId,
    recipientParticipantId: recipientParticipantId,
    amount: amount,
    settledAt: DateTime(2025, 1, 2),
    scope: scope,
  );
}

/// Wait for [groupBalancesProvider] to settle to AsyncData by listening to it
/// and pumping the async queue until it resolves.
///
/// [groupBalancesProvider] is a [Provider.family] that watches several
/// [StreamProvider.family] providers in a cascade: it first watches events,
/// then for each event watches expense and settlement stream providers.
/// Each layer needs one pump round:
///   Round 1: groupEventsProvider delivers events list
///   Round 2: per-event expense/settlement providers deliver data
///   Round 3: final Provider.family re-evaluation with complete data
///
/// We use `Future.delayed(Duration.zero)` which yields to the event loop
/// (unlike `Future.microtask` which only yields to the microtask queue).
Future<void> _pumpUntilData(ProviderContainer container, String groupId) async {
  // Subscribe to trigger initialization of the provider graph
  container.listen(
    groupBalancesProvider(groupId),
    (_, _) {},
    fireImmediately: true,
  );
  // Yield to event loop multiple times for cascading stream deliveries
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  // ---------------------------------------------------------------------------
  // groupBalancesProvider tests
  // ---------------------------------------------------------------------------

  group('groupBalancesProvider', () {
    const groupId = 'group-1';

    test(
      'aggregates expenses from 2 events and returns combined balances',
      () async {
        // uid-1 paid 10 OMR for event-a, uid-2 paid 20 OMR for event-b.
        // Each event has 2 participants (global scope = split evenly).
        final eventA = _makeEvent(
          id: 'event-a',
          groupId: groupId,
          participantIds: ['uid-1', 'uid-2'],
          participantNames: {'uid-1': 'Alice', 'uid-2': 'Bob'},
        );
        final eventB = _makeEvent(
          id: 'event-b',
          groupId: groupId,
          participantIds: ['uid-1', 'uid-2'],
          participantNames: {'uid-1': 'Alice', 'uid-2': 'Bob'},
        );

        // uid-1 paid 10 OMR in event-a; uid-2 paid 20 OMR in event-b.
        final expensesA = [
          _makeExpense(
            id: 'exp-1',
            payerParticipantId: 'uid-1',
            amount: Decimal.parse('10.000'),
            tripId: 'event-a',
          ),
        ];
        final expensesB = [
          _makeExpense(
            id: 'exp-2',
            payerParticipantId: 'uid-2',
            amount: Decimal.parse('20.000'),
            tripId: 'event-b',
          ),
        ];

        final members = [
          _makeMember(userId: 'uid-1', groupId: groupId, displayName: 'Alice'),
          _makeMember(userId: 'uid-2', groupId: groupId, displayName: 'Bob'),
        ];

        final container = ProviderContainer(
          overrides: [
            groupEventsProvider(
              groupId,
            ).overrideWith((_) => Stream.value([eventA, eventB])),
            groupMembersProvider(
              groupId,
            ).overrideWith((_) => Stream.value(members)),
            eventExpensesProvider((
              groupId: groupId,
              eventId: 'event-a',
            )).overrideWith((_) => Stream.value(expensesA)),
            eventExpensesProvider((
              groupId: groupId,
              eventId: 'event-b',
            )).overrideWith((_) => Stream.value(expensesB)),
            eventSettlementsProvider((
              groupId: groupId,
              eventId: 'event-a',
            )).overrideWith((_) => Stream.value([])),
            eventSettlementsProvider((
              groupId: groupId,
              eventId: 'event-b',
            )).overrideWith((_) => Stream.value([])),
            groupSettlementsProvider(
              groupId,
            ).overrideWith((_) => Stream.value([])),
          ],
        );
        addTearDown(container.dispose);

        await _pumpUntilData(container, groupId);

        final result = container.read(groupBalancesProvider(groupId));

        expect(result, isA<AsyncData<GroupBalances>>());
        final data = result.valueOrNull!;

        // totalSpent = 10 + 20 = 30 OMR
        expect(data.totalSpent, equals(Decimal.parse('30.000')));
        expect(data.eventCount, equals(2));
        expect(data.balances, hasLength(2));
        expect(data.memberNames, containsPair('uid-1', 'Alice'));
        expect(data.memberNames, containsPair('uid-2', 'Bob'));
      },
    );

    test('includes group-level settlements in balance calculation', () async {
      // uid-1 paid 20 OMR in event-a (split with uid-2 = 10 each).
      // uid-2 owes uid-1 10 OMR. After group settlement of 10 OMR
      // from uid-2 -> uid-1, both nets reach zero.
      final event = _makeEvent(
        id: 'event-a',
        groupId: groupId,
        participantIds: ['uid-1', 'uid-2'],
        participantNames: {'uid-1': 'Alice', 'uid-2': 'Bob'},
      );

      final expenses = [
        _makeExpense(
          id: 'exp-1',
          payerParticipantId: 'uid-1',
          amount: Decimal.parse('20.000'),
          tripId: 'event-a',
        ),
      ];

      // uid-2 pays uid-1 to settle the 10 OMR debt.
      final groupSettlement = _makeSettlement(
        id: 'settle-1',
        payerParticipantId: 'uid-2',
        recipientParticipantId: 'uid-1',
        amount: Decimal.parse('10.000'),
        scope: 'group',
      );

      final members = [
        _makeMember(userId: 'uid-1', groupId: groupId, displayName: 'Alice'),
        _makeMember(userId: 'uid-2', groupId: groupId, displayName: 'Bob'),
      ];

      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([event])),
          groupMembersProvider(
            groupId,
          ).overrideWith((_) => Stream.value(members)),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value(expenses)),
          eventSettlementsProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value([])),
          groupSettlementsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([groupSettlement])),
        ],
      );
      addTearDown(container.dispose);

      await _pumpUntilData(container, groupId);

      final result = container.read(groupBalancesProvider(groupId));

      expect(result, isA<AsyncData<GroupBalances>>());
      final data = result.valueOrNull!;

      final uid1Balance = data.balances.firstWhere(
        (b) => b.participantId == 'uid-1',
      );
      final uid2Balance = data.balances.firstWhere(
        (b) => b.participantId == 'uid-2',
      );

      // BalanceCalculator:
      // uid-1: paid=20, owed=10, settlementAdj=-10 (received 10), net=(20-10)-10=0
      // uid-2: paid=0,  owed=10, settlementAdj=+10 (paid 10),    net=(0+10)-10=0
      expect(uid1Balance.netBalance, equals(Decimal.zero));
      expect(uid2Balance.netBalance, equals(Decimal.zero));
    });

    test(
      'perEventBreakdown contains correct net balance for uid-1 in event-a',
      () async {
        // uid-1 paid 10 OMR in event-a (2 participants: uid-1, uid-2).
        // Each owes 5; uid-1 paid 10 -> uid-1 net = 10 - 5 = +5.
        final event = _makeEvent(
          id: 'event-a',
          groupId: groupId,
          participantIds: ['uid-1', 'uid-2'],
          participantNames: {'uid-1': 'Alice', 'uid-2': 'Bob'},
        );

        final expenses = [
          _makeExpense(
            id: 'exp-1',
            payerParticipantId: 'uid-1',
            amount: Decimal.parse('10.000'),
            tripId: 'event-a',
          ),
        ];

        final members = [
          _makeMember(userId: 'uid-1', groupId: groupId, displayName: 'Alice'),
          _makeMember(userId: 'uid-2', groupId: groupId, displayName: 'Bob'),
        ];

        final container = ProviderContainer(
          overrides: [
            groupEventsProvider(
              groupId,
            ).overrideWith((_) => Stream.value([event])),
            groupMembersProvider(
              groupId,
            ).overrideWith((_) => Stream.value(members)),
            eventExpensesProvider((
              groupId: groupId,
              eventId: 'event-a',
            )).overrideWith((_) => Stream.value(expenses)),
            eventSettlementsProvider((
              groupId: groupId,
              eventId: 'event-a',
            )).overrideWith((_) => Stream.value([])),
            groupSettlementsProvider(
              groupId,
            ).overrideWith((_) => Stream.value([])),
          ],
        );
        addTearDown(container.dispose);

        await _pumpUntilData(container, groupId);

        final result = container.read(groupBalancesProvider(groupId));

        expect(result, isA<AsyncData<GroupBalances>>());
        final data = result.valueOrNull!;

        // uid-1 net in event-a = paid 10 - owed 5 = +5
        expect(data.perEventBreakdown, contains('uid-1'));
        expect(data.perEventBreakdown['uid-1'], contains('event-a'));
        expect(
          data.perEventBreakdown['uid-1']!['event-a'],
          equals(Decimal.parse('5.000')),
        );
      },
    );

    test('returns AsyncValue.loading when events stream has no value yet', () {
      // A stream that never emits — groupBalancesProvider must return loading.
      final controller = StreamController<List<Event>>.broadcast();

      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(groupId).overrideWith((_) => controller.stream),
          groupMembersProvider(groupId).overrideWith((_) => Stream.value([])),
          groupSettlementsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([])),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(controller.close);

      final result = container.read(groupBalancesProvider(groupId));
      // Synchronous read before stream emits — must be loading
      expect(result, isA<AsyncLoading<GroupBalances>>());
    });

    test('totalSpent sums all expenses across all events', () async {
      final eventA = _makeEvent(
        id: 'event-a',
        groupId: groupId,
        participantIds: ['uid-1'],
        participantNames: {'uid-1': 'Alice'},
      );
      final eventB = _makeEvent(
        id: 'event-b',
        groupId: groupId,
        participantIds: ['uid-1'],
        participantNames: {'uid-1': 'Alice'},
      );

      // 15.000 + 25.500 = 40.500 in event-a
      // 9.500 in event-b
      // total = 50.000
      final expensesA = [
        _makeExpense(
          id: 'exp-1',
          payerParticipantId: 'uid-1',
          amount: Decimal.parse('15.000'),
          tripId: 'event-a',
        ),
        _makeExpense(
          id: 'exp-2',
          payerParticipantId: 'uid-1',
          amount: Decimal.parse('25.500'),
          tripId: 'event-a',
        ),
      ];
      final expensesB = [
        _makeExpense(
          id: 'exp-3',
          payerParticipantId: 'uid-1',
          amount: Decimal.parse('9.500'),
          tripId: 'event-b',
        ),
      ];

      final members = [
        _makeMember(userId: 'uid-1', groupId: groupId, displayName: 'Alice'),
      ];

      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA, eventB])),
          groupMembersProvider(
            groupId,
          ).overrideWith((_) => Stream.value(members)),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value(expensesA)),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-b',
          )).overrideWith((_) => Stream.value(expensesB)),
          eventSettlementsProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value([])),
          eventSettlementsProvider((
            groupId: groupId,
            eventId: 'event-b',
          )).overrideWith((_) => Stream.value([])),
          groupSettlementsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([])),
        ],
      );
      addTearDown(container.dispose);

      await _pumpUntilData(container, groupId);

      final result = container.read(groupBalancesProvider(groupId));

      expect(result, isA<AsyncData<GroupBalances>>());
      final data = result.valueOrNull!;
      // totalSpent = 15.000 + 25.500 + 9.500 = 50.000
      expect(data.totalSpent, equals(Decimal.parse('50.000')));
    });
  });

  // ---------------------------------------------------------------------------
  // groupSettlementsProvider tests
  // ---------------------------------------------------------------------------

  group('groupSettlementsProvider', () {
    const groupId = 'group-1';

    test('returns stream of settlements from GroupSettlementService', () async {
      final settlement = _makeSettlement(
        id: 's1',
        payerParticipantId: 'uid-1',
        recipientParticipantId: 'uid-2',
        amount: Decimal.parse('5.000'),
      );

      // Override the entire provider — bypasses service initialization.
      final container = ProviderContainer(
        overrides: [
          groupSettlementsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([settlement])),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        groupSettlementsProvider(groupId).future,
      );
      expect(result, hasLength(1));
      expect(result.first.id, equals('s1'));
    });
  });

  // ---------------------------------------------------------------------------
  // groupActivityProvider tests
  // ---------------------------------------------------------------------------

  group('groupActivityProvider', () {
    const groupId = 'group-1';

    test(
      'returns stream of recent activity from GroupActivityService',
      () async {
        // Override the entire provider — bypasses service initialization.
        final container = ProviderContainer(
          overrides: [
            groupActivityProvider(
              groupId,
            ).overrideWith((_) => Stream.value(<GroupActivityLog>[])),
          ],
        );
        addTearDown(container.dispose);

        final result = await container.read(
          groupActivityProvider(groupId).future,
        );
        expect(result, isEmpty);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // perEventBreakdown participant-set invariant (#112)
  //
  // The breakdown is participantIds-only; the aggregate folds in former
  // financial actors. After dedup'ing the breakdown's data source onto the
  // pre-built maps, this distinction must still hold. This test fails if the
  // breakdown is ever re-sourced from the formerActors-inclusive set.
  // ---------------------------------------------------------------------------
  group('groupBalancesProvider perEventBreakdown vs aggregate (#112)', () {
    const groupId = 'group-1';

    test(
      'former-member payer appears in aggregate but NOT in per-event breakdown',
      () async {
        // event-a: clean expense paid by a CURRENT member (deterministic).
        // event-b: expense paid by uid-former, who is NOT a group member and
        // NOT in event-b.participantIds — so they are a "former financial
        // actor" folded into the aggregate, but excluded from the breakdown.
        final eventA = _makeEvent(
          id: 'event-a',
          groupId: groupId,
          participantIds: ['uid-1', 'uid-2'],
          participantNames: {'uid-1': 'Alice', 'uid-2': 'Bob'},
        );
        final eventB = _makeEvent(
          id: 'event-b',
          groupId: groupId,
          participantIds: ['uid-1', 'uid-2'],
          participantNames: {'uid-1': 'Alice', 'uid-2': 'Bob'},
        );

        final expensesA = [
          _makeExpense(
            id: 'exp-a',
            payerParticipantId: 'uid-1',
            amount: Decimal.parse('20.000'),
            tripId: 'event-a',
          ),
        ];
        final expensesB = [
          _makeExpense(
            id: 'exp-b',
            payerParticipantId: 'uid-former',
            amount: Decimal.parse('30.000'),
            tripId: 'event-b',
          ),
        ];

        // uid-former is intentionally absent from members (the
        // difference(liveMemberIds) former-actor path, since _makeMember has
        // no tombstone flag).
        final members = [
          _makeMember(userId: 'uid-1', groupId: groupId, displayName: 'Alice'),
          _makeMember(userId: 'uid-2', groupId: groupId, displayName: 'Bob'),
        ];

        final container = ProviderContainer(
          overrides: [
            groupEventsProvider(
              groupId,
            ).overrideWith((_) => Stream.value([eventA, eventB])),
            groupMembersProvider(
              groupId,
            ).overrideWith((_) => Stream.value(members)),
            eventExpensesProvider((
              groupId: groupId,
              eventId: 'event-a',
            )).overrideWith((_) => Stream.value(expensesA)),
            eventExpensesProvider((
              groupId: groupId,
              eventId: 'event-b',
            )).overrideWith((_) => Stream.value(expensesB)),
            eventSettlementsProvider((
              groupId: groupId,
              eventId: 'event-a',
            )).overrideWith((_) => Stream.value([])),
            eventSettlementsProvider((
              groupId: groupId,
              eventId: 'event-b',
            )).overrideWith((_) => Stream.value([])),
            groupSettlementsProvider(
              groupId,
            ).overrideWith((_) => Stream.value([])),
          ],
        );
        addTearDown(container.dispose);

        await _pumpUntilData(container, groupId);
        final data = container
            .read(groupBalancesProvider(groupId))
            .valueOrNull!;

        // Aggregate INCLUDES the former actor (event-b split 3 ways: paid 30,
        // owes 10 => net +20).
        final former = data.balances
            .where((b) => b.participantId == 'uid-former')
            .toList();
        expect(former, hasLength(1));
        expect(former.single.netBalance, equals(Decimal.parse('20.000')));

        // Breakdown EXCLUDES the former actor entirely (participantIds-only).
        expect(data.perEventBreakdown.containsKey('uid-former'), isFalse);

        // A current participant's breakdown is unaffected (event-a: 20 split
        // 2 ways, uid-1 paid => net +10).
        expect(
          data.perEventBreakdown['uid-1']?['event-a'],
          equals(Decimal.parse('10.000')),
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // groupFailedEventIdsProvider tests (#244)
  // ---------------------------------------------------------------------------

  group('groupFailedEventIdsProvider (#244)', () {
    const groupId = 'group-1';

    final eventA = _makeEvent(
      id: 'event-a',
      groupId: groupId,
      participantIds: ['uid-1', 'uid-2'],
    );
    final eventB = _makeEvent(
      id: 'event-b',
      groupId: groupId,
      participantIds: ['uid-1', 'uid-2'],
    );

    Future<Set<String>> readFailed(ProviderContainer container) async {
      container.listen(
        groupFailedEventIdsProvider(groupId),
        (_, _) {},
        fireImmediately: true,
      );
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return container.read(groupFailedEventIdsProvider(groupId));
    }

    test('flags the event whose expense read errors, not the healthy one',
        () async {
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA, eventB])),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value(<Expense>[])),
          eventSettlementsProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value(<Settlement>[])),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-b',
          )).overrideWith(
            (_) => Stream<List<Expense>>.error(Exception('permission-denied')),
          ),
          eventSettlementsProvider((
            groupId: groupId,
            eventId: 'event-b',
          )).overrideWith((_) => Stream.value(<Settlement>[])),
        ],
      );
      addTearDown(container.dispose);

      expect(await readFailed(container), {'event-b'});
    });

    test('flags the event whose SETTLEMENT read errors (expenses fine)',
        () async {
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA])),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value(<Expense>[])),
          eventSettlementsProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith(
            (_) => Stream<List<Settlement>>.error(Exception('denied')),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await readFailed(container), {'event-a'});
    });

    test('all reads succeed -> empty set (regression fence)', () async {
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA, eventB])),
          for (final id in const ['event-a', 'event-b']) ...[
            eventExpensesProvider((
              groupId: groupId,
              eventId: id,
            )).overrideWith((_) => Stream.value(<Expense>[])),
            eventSettlementsProvider((
              groupId: groupId,
              eventId: id,
            )).overrideWith((_) => Stream.value(<Settlement>[])),
          ],
        ],
      );
      addTearDown(container.dispose);

      expect(await readFailed(container), isEmpty);
    });

    test('a still-loading event is NOT flagged (loading != partial)', () async {
      final pending = StreamController<List<Expense>>();
      addTearDown(pending.close);
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value([eventA])),
          eventExpensesProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => pending.stream),
          eventSettlementsProvider((
            groupId: groupId,
            eventId: 'event-a',
          )).overrideWith((_) => Stream.value(<Settlement>[])),
        ],
      );
      addTearDown(container.dispose);

      expect(await readFailed(container), isEmpty);
    });
  });
}
