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
  Decimal get owedToUser => _only?.owedToUser ?? Decimal.zero;
  Decimal get userOwes => _only?.userOwes ?? Decimal.zero;
}

// ---------------------------------------------------------------------------
// #104 — one-shot home balance aggregation
//
// The home dashboard must read per-event expenses/settlements via one-shot
// `.get()` (getExpenses/getSettlements), NOT via live `.snapshots()` listeners
// (watchExpenses/watchSettlements). These counting fakes let us assert exactly
// that: the one-shot path uses getX and holds ZERO live leaf listeners, while
// the live `crossGroupBalanceProvider` (kept for in-group screens) still opens
// them — proving the regression assertion discriminates.
// ---------------------------------------------------------------------------

class _CountingExpenseService extends ExpenseService {
  _CountingExpenseService(this._seed)
      : super.withFirestore(FakeFirebaseFirestore());
  final Map<String, List<Expense>> _seed;
  int getCount = 0;
  int activeWatchListeners = 0;

  @override
  Future<List<Expense>> getExpenses(String groupId, String eventId) async {
    getCount++;
    return _seed[eventId] ?? const <Expense>[];
  }

  @override
  Stream<List<Expense>> watchExpenses(String groupId, String eventId) {
    late final StreamController<List<Expense>> ctrl;
    ctrl = StreamController<List<Expense>>(
      onListen: () {
        activeWatchListeners++;
        ctrl.add(_seed[eventId] ?? const <Expense>[]);
      },
      onCancel: () {
        activeWatchListeners--;
        ctrl.close();
      },
    );
    return ctrl.stream;
  }
}

class _CountingSettlementService extends SettlementService {
  _CountingSettlementService([this._seed = const {}])
      : super.withFirestore(FakeFirebaseFirestore());
  final Map<String, List<Settlement>> _seed;
  int getCount = 0;
  int activeWatchListeners = 0;

  @override
  Future<List<Settlement>> getSettlements(String groupId, String eventId) async {
    getCount++;
    return _seed[eventId] ?? const <Settlement>[];
  }

  @override
  Stream<List<Settlement>> watchSettlements(String groupId, String eventId) {
    late final StreamController<List<Settlement>> ctrl;
    ctrl = StreamController<List<Settlement>>(
      onListen: () {
        activeWatchListeners++;
        ctrl.add(_seed[eventId] ?? const <Settlement>[]);
      },
      onCancel: () {
        activeWatchListeners--;
        ctrl.close();
      },
    );
    return ctrl.stream;
  }
}

Group _makeGroup(String id) => Group(
      id: id,
      name: 'Group $id',
      inviteCode: 'AAAAAA',
      createdBy: 'uid-a',
      memberIds: const ['uid-a', 'uid-b'],
      createdAt: DateTime(2025, 1, 1),
    );

Event _makeEvent(String id, String groupId) => Event(
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

GroupMember _makeMember(String uid, String groupId) => GroupMember(
      id: 'member-$uid',
      groupId: groupId,
      userId: uid,
      displayName: uid == 'uid-a' ? 'A' : 'B',
      role: 'MEMBER',
      joinedAt: DateTime(2025, 1, 1),
    );

Expense _makeExpense(String id, String payer, Decimal amount, String eventId) =>
    Expense(
      id: id,
      tripId: eventId,
      payerParticipantId: payer,
      amount: amount,
      scope: ExpenseScope.global,
      createdAt: DateTime(2025, 1, 1),
    );

Settlement _makeGroupSettlement(String payer, String recipient, Decimal amount) =>
    Settlement(
      id: 'gs-1',
      tripId: 'group-1',
      payerParticipantId: payer,
      recipientParticipantId: recipient,
      amount: amount,
      settledAt: DateTime(2025, 1, 2),
      scope: 'group',
    );


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
  const eid = 'e1';

  /// Overrides that route both the one-shot and the live providers through the
  /// counting fakes and the in-memory list streams. [groupSettlements] feeds the
  /// LIVE `groupSettlementsProvider` (group settlements stay live by design).
  List<Override> buildOverrides({
    required _CountingExpenseService expFake,
    required _CountingSettlementService setFake,
    List<Settlement> groupSettlements = const [],
  }) =>
      [
        expenseServiceProvider.overrideWithValue(expFake),
        settlementServiceProvider.overrideWithValue(setFake),
        currentUserIdProvider.overrideWith((_) => 'uid-a'),
        userGroupsProvider.overrideWith((_) => Stream.value([_makeGroup(gid)])),
        groupEventsProvider(gid)
            .overrideWith((_) => Stream.value([_makeEvent(eid, gid)])),
        groupMembersProvider(gid).overrideWith(
          (_) => Stream.value([_makeMember('uid-a', gid), _makeMember('uid-b', gid)]),
        ),
        groupSettlementsProvider(gid)
            .overrideWith((_) => Stream.value(groupSettlements)),
      ];

  group('#104 one-shot home balance', () {
    test(
      'the cross-group home fold uses one-shot reads and holds ZERO live '
      'leaf listeners (the leak fix)',
      () async {
        // uid-b pays 20, equal 2-way split → uid-a owes 10, uid-b owed 10.
        final expFake = _CountingExpenseService({
          eid: [_makeExpense('x1', 'uid-b', Decimal.fromInt(20), eid)],
        });
        final setFake = _CountingSettlementService();
        final container = ProviderContainer(
          overrides: buildOverrides(expFake: expFake, setFake: setFake),
        );
        addTearDown(container.dispose);

        final result = await readCrossSettled(container);

        // One-shot reads were used (one event → one get of each).
        expect(expFake.getCount, 1, reason: 'getExpenses must be one-shot');
        expect(setFake.getCount, 1, reason: 'getSettlements must be one-shot');
        // The whole point of #104: NO permanent leaf listeners from the home path.
        expect(expFake.activeWatchListeners, 0,
            reason: 'no live expense listener may survive the one-shot path');
        expect(setFake.activeWatchListeners, 0,
            reason: 'no live settlement listener may survive the one-shot path');

        // uid-a is owed nothing, owes 10.
        expect(result.balance.net, Decimal.fromInt(-10));
        expect(result.balance.owedToUser, Decimal.zero);
        expect(result.balance.userOwes, Decimal.fromInt(10));
        expect(result.balance.groupCount, 1);
        expect(result.partial, isFalse,
            reason: 'all reads succeeded → not partial');
      },
    );

    test(
      'CONTRAST: the live crossGroupBalanceProvider DOES open leaf listeners '
      '(proves the regression assertion discriminates)',
      () async {
        final expFake = _CountingExpenseService({
          eid: [_makeExpense('x1', 'uid-b', Decimal.fromInt(20), eid)],
        });
        final setFake = _CountingSettlementService();
        final container = ProviderContainer(
          overrides: buildOverrides(expFake: expFake, setFake: setFake),
        );
        addTearDown(container.dispose);

        // Keep the live provider subscribed (mirrors the always-mounted home).
        container.listen(crossGroupBalanceProvider, (_, _) {},
            fireImmediately: true);
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        // The live path opens (and holds) per-event snapshot listeners — the
        // exact leak #104 is about. getExpenses is NOT used by the live path.
        expect(expFake.activeWatchListeners, greaterThan(0));
        expect(expFake.getCount, 0);
      },
    );

    test(
      'settlement sign-flip (orthogonal axis): a group settlement flips uid-a '
      'from owes to owed on the one-shot path',
      () async {
        // Same expense (uid-a owes 10), plus a group settlement: uid-a pays
        // uid-b 25 → uid-a net -10 + 25 = +15 (flips negative → positive).
        final expFake = _CountingExpenseService({
          eid: [_makeExpense('x1', 'uid-b', Decimal.fromInt(20), eid)],
        });
        final setFake = _CountingSettlementService();
        final container = ProviderContainer(
          overrides: buildOverrides(
            expFake: expFake,
            setFake: setFake,
            groupSettlements: [
              _makeGroupSettlement('uid-a', 'uid-b', Decimal.fromInt(25)),
            ],
          ),
        );
        addTearDown(container.dispose);

        final result = await readCrossSettled(container);

        expect(result.balance.net, Decimal.fromInt(15));
        expect(result.balance.owedToUser, Decimal.fromInt(15));
        expect(result.balance.userOwes, Decimal.zero);
        // Group settlement was surfaced via the LIVE groupSettlementsProvider,
        // not a per-event one-shot read.
        expect(expFake.activeWatchListeners, 0);
      },
    );

    test('ledgerRevisionProvider bump recomputes the one-shot aggregate', () async {
      var expenses = <Expense>[
        _makeExpense('x1', 'uid-b', Decimal.fromInt(20), eid),
      ];
      // A fake whose getExpenses reads a mutable list, so a "write" + bump
      // surfaces the new amount on recompute.
      final expFake = _MutableExpenseService(() => expenses);
      final setFake = _CountingSettlementService();
      final container = ProviderContainer(
        overrides: [
          expenseServiceProvider.overrideWithValue(expFake),
          settlementServiceProvider.overrideWithValue(setFake),
          currentUserIdProvider.overrideWith((_) => 'uid-a'),
          userGroupsProvider.overrideWith((_) => Stream.value([_makeGroup(gid)])),
          groupEventsProvider(gid)
              .overrideWith((_) => Stream.value([_makeEvent(eid, gid)])),
          groupMembersProvider(gid).overrideWith(
            (_) => Stream.value(
                [_makeMember('uid-a', gid), _makeMember('uid-b', gid)]),
          ),
          groupSettlementsProvider(gid).overrideWith((_) => Stream.value([])),
        ],
      );
      addTearDown(container.dispose);
      container.listen(crossGroupHomeBalanceProvider, (_, _) {},
          fireImmediately: true);

      final before = await readCrossSettled(container);
      expect(before.balance.net, Decimal.fromInt(-10));

      // Simulate a new expense write + the liveness bump.
      expenses = [
        _makeExpense('x1', 'uid-b', Decimal.fromInt(20), eid),
        _makeExpense('x2', 'uid-b', Decimal.fromInt(40), eid), // uid-a +owes 20
      ];
      container.read(ledgerRevisionProvider.notifier).state++;

      final after = await readCrossSettled(container);
      expect(after.balance.net, Decimal.fromInt(-30),
          reason: 'bump must force a fresh one-shot read');
    });

    test(
      'list-liveness: a new event on the LIVE groupEventsProvider refreshes the '
      'one-shot aggregate WITHOUT a revision bump (Gate P2-2)',
      () async {
        final eventsCtrl = StreamController<List<Event>>.broadcast();
        final expFake = _CountingExpenseService({
          'e1': [_makeExpense('x1', 'uid-b', Decimal.fromInt(20), 'e1')],
          'e2': [_makeExpense('x2', 'uid-b', Decimal.fromInt(60), 'e2')],
        });
        final setFake = _CountingSettlementService();
        final container = ProviderContainer(
          overrides: [
            expenseServiceProvider.overrideWithValue(expFake),
            settlementServiceProvider.overrideWithValue(setFake),
            currentUserIdProvider.overrideWith((_) => 'uid-a'),
            userGroupsProvider.overrideWith((_) => Stream.value([_makeGroup(gid)])),
            groupEventsProvider(gid).overrideWith((_) => eventsCtrl.stream),
            groupMembersProvider(gid).overrideWith(
              (_) => Stream.value(
                  [_makeMember('uid-a', gid), _makeMember('uid-b', gid)]),
            ),
            groupSettlementsProvider(gid).overrideWith((_) => Stream.value([])),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(eventsCtrl.close);
        container.listen(groupBalancesOnceProvider(gid), (_, _) {},
            fireImmediately: true);

        Future<GroupBalances> settle() async {
          for (var i = 0; i < 12; i++) {
            await Future<void>.delayed(Duration.zero);
          }
          return container
              .read(groupBalancesOnceProvider(gid))
              .requireValue
              .balances;
        }

        Decimal netA(GroupBalances b) => b.balances['OMR']!
            .firstWhere((x) => x.participantId == 'uid-a')
            .netBalance;

        eventsCtrl.add([_makeEvent('e1', gid)]);
        expect(netA(await settle()), Decimal.fromInt(-10)); // owes 10 on e1 only

        // A NEW event appears on the live list — NO ledgerRevision bump.
        eventsCtrl.add([_makeEvent('e1', gid), _makeEvent('e2', gid)]);
        expect(
          netA(await settle()),
          Decimal.fromInt(-40),
          reason: 'live event-list change must refresh the one-shot aggregate '
              'without a revision bump',
        );
      },
    );
  });
}

class _MutableExpenseService extends ExpenseService {
  _MutableExpenseService(this._read)
      : super.withFirestore(FakeFirebaseFirestore());
  final List<Expense> Function() _read;

  @override
  Future<List<Expense>> getExpenses(String groupId, String eventId) async =>
      _read();
}
