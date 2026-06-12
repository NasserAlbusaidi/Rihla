import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/services/expense_service.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';

/// #261: single-currency adapter — see cross_group_balance_test.dart. `.single`
/// throws if a test ever holds >1 currency, so it can never silently re-sum.
extension _SingleCurrencyAccess on CrossGroupBalance {
  CurrencyBalance? get _only => byCurrency.isEmpty ? null : byCurrency.single;
  Decimal get net => _only?.net ?? Decimal.zero;
  Decimal get userOwes => _only?.userOwes ?? Decimal.zero;
}

// ---------------------------------------------------------------------------
// #244 — home once-path graceful partial.
//
// groupBalancesOnceProvider must DROP an event whose one-shot money read throws
// (permission-denied / uncached-while-offline), record it in failedEventIds,
// and compute the balance from the survivors — mirroring the live error-skip in
// groupBalancesProvider but surfacing the drop. crossGroupHomeBalanceProvider
// ORs that into a `partial` flag. A COARSE list read (events/members/group
// settlements) still rejects the whole group (loud-safe → error card).
//
// Before this fix, ANY per-event read throw rejected the once-future → the home
// hero showed a full error card (loud-safe but blunt). These tests pin the new
// graceful behavior.
// ---------------------------------------------------------------------------

class _PartialExpenseService extends ExpenseService {
  _PartialExpenseService(this._seed, this._failFor)
      : super.withFirestore(FakeFirebaseFirestore());
  final Map<String, List<Expense>> _seed;
  final Set<String> _failFor;

  @override
  Future<List<Expense>> getExpenses(String groupId, String eventId) async {
    if (_failFor.contains(eventId)) {
      throw Exception('simulated expense read failure: $eventId');
    }
    return _seed[eventId] ?? const <Expense>[];
  }
}

class _PartialSettlementService extends SettlementService {
  _PartialSettlementService([
    this._seed = const {},
    this._failFor = const {},
  ]) : super.withFirestore(FakeFirebaseFirestore());
  final Map<String, List<Settlement>> _seed;
  final Set<String> _failFor;

  @override
  Future<List<Settlement>> getSettlements(
      String groupId, String eventId) async {
    if (_failFor.contains(eventId)) {
      throw Exception('simulated settlement read failure: $eventId');
    }
    return _seed[eventId] ?? const <Settlement>[];
  }
}

Group _group(String id) => Group(
      id: id,
      name: 'Group $id',
      inviteCode: 'AAAAAA',
      createdBy: 'uid-a',
      memberIds: const ['uid-a', 'uid-b'],
      createdAt: DateTime(2025, 1, 1),
    );

Event _event(String id, String groupId) => Event(
      id: id,
      name: 'Event $id',
      type: EventType.trip,
      groupId: groupId,
      createdBy: 'uid-a',
      participantIds: const ['uid-a', 'uid-b'],
      participantNames: const {'uid-a': 'A', 'uid-b': 'B'},
      modules: const EventModules(),
      createdAt: DateTime(2025, 1, 1),
    );

GroupMember _member(String uid, String groupId) => GroupMember(
      id: 'member-$uid',
      groupId: groupId,
      userId: uid,
      displayName: uid == 'uid-a' ? 'A' : 'B',
      role: 'MEMBER',
      joinedAt: DateTime(2025, 1, 1),
    );

// uid-b pays [amount] on an equal global split between uid-a and uid-b, so uid-a
// owes amount/2 (net = -amount/2).
Expense _expense(String id, Decimal amount, String eventId) => Expense(
      id: id,
      tripId: eventId,
      payerParticipantId: 'uid-b',
      amount: amount,
      scope: ExpenseScope.global,
      createdAt: DateTime(2025, 1, 1),
    );

Decimal _netOf(GroupBalances b, String uid) => b.balances['OMR']!
    .firstWhere((x) => x.participantId == uid)
    .netBalance;


/// #366: the cross-group fold is now a sync Provider over the facade (no
/// `.future`). Settle the async source chain, then read the resolved value.
Future<CrossGroupBalanceOnce> readCrossSettled(
  ProviderContainer container,
) async {
  // Pin the provider chain — without a listener the autoDispose once-path
  // sources dispose between microtasks and the fold never leaves loading.
  final sub = container.listen(crossGroupHomeBalanceProvider, (_, _) {});
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  final value = container.read(crossGroupHomeBalanceProvider).requireValue;
  sub.close();
  return value;
}

void main() {
  const gid = 'g1';
  const d = Decimal.fromInt;

  group('groupBalancesOnceProvider per-event tolerance (#244)', () {
    // g1 has e1 (uid-a owes 10) and e2 (uid-a owes 30).
    ProviderContainer makeContainer({
      Set<String> failExpenses = const {},
      Set<String> failSettlements = const {},
      Stream<List<GroupMember>>? membersStream,
      Stream<List<Event>>? eventsStream,
    }) {
      final expFake = _PartialExpenseService(
        {
          'e1': [_expense('x1', d(20), 'e1')],
          'e2': [_expense('x2', d(60), 'e2')],
        },
        failExpenses,
      );
      final setFake = _PartialSettlementService(const {}, failSettlements);
      return ProviderContainer(
        overrides: [
          expenseServiceProvider.overrideWithValue(expFake),
          settlementServiceProvider.overrideWithValue(setFake),
          currentUserIdProvider.overrideWith((_) => 'uid-a'),
          userGroupsProvider.overrideWith((_) => Stream.value([_group(gid)])),
          groupEventsProvider(gid).overrideWith(
            (_) => eventsStream ??
                Stream.value([_event('e1', gid), _event('e2', gid)]),
          ),
          groupMembersProvider(gid).overrideWith(
            (_) =>
                membersStream ??
                Stream.value([_member('uid-a', gid), _member('uid-b', gid)]),
          ),
          groupSettlementsProvider(gid).overrideWith((_) => Stream.value([])),
        ],
      );
    }

    test('expense read throws for one event → dropped, flagged, balance from '
        'survivor', () async {
      final container = makeContainer(failExpenses: {'e2'});
      addTearDown(container.dispose);
      container.listen(groupBalancesOnceProvider(gid), (_, _) {},
          fireImmediately: true);

      final result =
          await container.read(groupBalancesOnceProvider(gid).future);

      expect(result.failedEventIds, {'e2'});
      expect(_netOf(result.balances, 'uid-a'), d(-10),
          reason: 'e2 dropped → only e1 (owes 10) counts');
    });

    test('settlement read throws (expenses fine) → event still flagged (OR) and '
        'its expense is NOT half-counted', () async {
      final container = makeContainer(failSettlements: {'e2'});
      addTearDown(container.dispose);
      container.listen(groupBalancesOnceProvider(gid), (_, _) {},
          fireImmediately: true);

      final result =
          await container.read(groupBalancesOnceProvider(gid).future);

      expect(result.failedEventIds, {'e2'},
          reason: 'a failed settlement read flags the event (OR with expenses)');
      expect(_netOf(result.balances, 'uid-a'), d(-10),
          reason: 'e2 expense must NOT be counted when its settlement read '
              'failed — whole event drops, no half-count');
    });

    test('all reads succeed → empty failed set (regression fence)', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      container.listen(groupBalancesOnceProvider(gid), (_, _) {},
          fireImmediately: true);

      final result =
          await container.read(groupBalancesOnceProvider(gid).future);

      expect(result.failedEventIds, isEmpty);
      expect(_netOf(result.balances, 'uid-a'), d(-40),
          reason: 'e1 (10) + e2 (30) both counted');
    });

    test('COARSE: a members list read error rejects the whole group '
        '(loud-safe, NOT a silent 0-event drop)', () async {
      final container = makeContainer(
        membersStream: Stream.error(Exception('members denied')),
      );
      addTearDown(container.dispose);
      container.listen(groupBalancesOnceProvider(gid), (_, _) {},
          fireImmediately: true);

      await expectLater(
        container.read(groupBalancesOnceProvider(gid).future),
        throwsA(isA<Exception>()),
        reason: 'a coarse list-read failure must hard-fail the group, not '
            'silently return a 0-balance partial',
      );
    });

    test('COARSE: an events list read error rejects the whole group', () async {
      final container = makeContainer(
        eventsStream: Stream.error(Exception('events denied')),
      );
      addTearDown(container.dispose);
      container.listen(groupBalancesOnceProvider(gid), (_, _) {},
          fireImmediately: true);

      await expectLater(
        container.read(groupBalancesOnceProvider(gid).future),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('crossGroupHomeBalanceProvider partial flag (#244)', () {
    test('group with a failed event → partial true, net = surviving sum',
        () async {
      final expFake = _PartialExpenseService(
        {
          'e1': [_expense('x1', d(20), 'e1')],
          'e2': [_expense('x2', d(60), 'e2')],
        },
        {'e2'},
      );
      final container = ProviderContainer(
        overrides: [
          expenseServiceProvider.overrideWithValue(expFake),
          settlementServiceProvider
              .overrideWithValue(_PartialSettlementService()),
          currentUserIdProvider.overrideWith((_) => 'uid-a'),
          userGroupsProvider.overrideWith((_) => Stream.value([_group(gid)])),
          groupEventsProvider(gid).overrideWith(
            (_) => Stream.value([_event('e1', gid), _event('e2', gid)]),
          ),
          groupMembersProvider(gid).overrideWith(
            (_) =>
                Stream.value([_member('uid-a', gid), _member('uid-b', gid)]),
          ),
          groupSettlementsProvider(gid).overrideWith((_) => Stream.value([])),
        ],
      );
      addTearDown(container.dispose);
      container.listen(crossGroupHomeBalanceProvider, (_, _) {},
          fireImmediately: true);

      final result = await readCrossSettled(container);

      expect(result.partial, isTrue);
      expect(result.balance.net, d(-10), reason: 'only e1 (owes 10) survives');
      expect(result.balance.userOwes, d(10));
    });

    test('all reads succeed → partial false', () async {
      final expFake = _PartialExpenseService(
        {
          'e1': [_expense('x1', d(20), 'e1')],
          'e2': [_expense('x2', d(60), 'e2')],
        },
        const {},
      );
      final container = ProviderContainer(
        overrides: [
          expenseServiceProvider.overrideWithValue(expFake),
          settlementServiceProvider
              .overrideWithValue(_PartialSettlementService()),
          currentUserIdProvider.overrideWith((_) => 'uid-a'),
          userGroupsProvider.overrideWith((_) => Stream.value([_group(gid)])),
          groupEventsProvider(gid).overrideWith(
            (_) => Stream.value([_event('e1', gid), _event('e2', gid)]),
          ),
          groupMembersProvider(gid).overrideWith(
            (_) =>
                Stream.value([_member('uid-a', gid), _member('uid-b', gid)]),
          ),
          groupSettlementsProvider(gid).overrideWith((_) => Stream.value([])),
        ],
      );
      addTearDown(container.dispose);
      container.listen(crossGroupHomeBalanceProvider, (_, _) {},
          fireImmediately: true);

      final result = await readCrossSettled(container);

      expect(result.partial, isFalse);
      expect(result.balance.net, d(-40));
    });

    test('multi-group: one group all-ok, another drops an event → partial true, '
        'net folds both groups (surviving events)', () async {
      // g1=[e1] (uid-a owes 10); g2=[e2 (owes 30), e3 (owes 50, FAILS)].
      final expFake = _PartialExpenseService(
        {
          'e1': [_expense('x1', d(20), 'e1')],
          'e2': [_expense('x2', d(60), 'e2')],
          'e3': [_expense('x3', d(100), 'e3')],
        },
        {'e3'},
      );
      final container = ProviderContainer(
        overrides: [
          expenseServiceProvider.overrideWithValue(expFake),
          settlementServiceProvider
              .overrideWithValue(_PartialSettlementService()),
          currentUserIdProvider.overrideWith((_) => 'uid-a'),
          userGroupsProvider
              .overrideWith((_) => Stream.value([_group('g1'), _group('g2')])),
          groupEventsProvider('g1')
              .overrideWith((_) => Stream.value([_event('e1', 'g1')])),
          groupEventsProvider('g2').overrideWith(
            (_) => Stream.value([_event('e2', 'g2'), _event('e3', 'g2')]),
          ),
          groupMembersProvider('g1').overrideWith(
            (_) =>
                Stream.value([_member('uid-a', 'g1'), _member('uid-b', 'g1')]),
          ),
          groupMembersProvider('g2').overrideWith(
            (_) =>
                Stream.value([_member('uid-a', 'g2'), _member('uid-b', 'g2')]),
          ),
          groupSettlementsProvider('g1').overrideWith((_) => Stream.value([])),
          groupSettlementsProvider('g2').overrideWith((_) => Stream.value([])),
        ],
      );
      addTearDown(container.dispose);
      container.listen(crossGroupHomeBalanceProvider, (_, _) {},
          fireImmediately: true);

      final result = await readCrossSettled(container);

      expect(result.partial, isTrue, reason: 'g2 dropped e3');
      // g1: -10, g2: -30 (e2 only, e3 dropped). Total -40.
      expect(result.balance.net, d(-40));
      expect(result.balance.userOwes, d(40));
    });
  });
}
