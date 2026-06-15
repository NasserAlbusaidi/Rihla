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
import 'package:safar/features/settings/providers/profile_stats_provider.dart';

// ---------------------------------------------------------------------------
// #517 — the Profile tab must not reopen the #104 O(G×E) live-listener leak.
//
// `profileStatsProvider` is read by the always-mounted Profile tab
// (BottomNavShell keeps tabs alive forever). It must read per-event
// expenses/settlements via one-shot `.get()` (getExpenses/getSettlements) by
// routing through `groupBalancesOnceProvider`, NOT via the live
// `groupBalancesProvider` which holds a `.snapshots()` listener per event of
// every group for the whole session. These counting fakes assert exactly that:
// the one-shot path holds ZERO live leaf listeners while still computing the
// correct per-currency `totalSpent`. Mirrors home_balance_once_104_test.dart.
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

Group _makeGroup(String id, {String currency = 'OMR'}) => Group(
      id: id,
      name: 'Group $id',
      inviteCode: 'AAAAAA',
      createdBy: 'uid-a',
      memberIds: const ['uid-a', 'uid-b'],
      currency: currency,
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

Expense _makeExpense(
  String id,
  String payer,
  Decimal amount,
  String eventId, {
  String currency = 'OMR',
}) =>
    Expense(
      id: id,
      tripId: eventId,
      payerParticipantId: payer,
      amount: amount,
      currency: currency,
      scope: ExpenseScope.global,
      createdAt: DateTime(2025, 1, 1),
    );

/// Pin the provider chain and drain microtasks so the autoDispose once-path
/// future resolves (without a listener it disposes between microtasks).
Future<ProfileStats> _readStatsSettled(ProviderContainer container) async {
  final sub = container.listen(profileStatsProvider, (_, _) {});
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  final value = container.read(profileStatsProvider).requireValue;
  sub.close();
  return value;
}

void main() {
  const gid = 'g1';
  const eid = 'e1';

  List<Override> buildOverrides({
    required _CountingExpenseService expFake,
    required _CountingSettlementService setFake,
    String currency = 'OMR',
  }) =>
      [
        expenseServiceProvider.overrideWithValue(expFake),
        settlementServiceProvider.overrideWithValue(setFake),
        userGroupsProvider
            .overrideWith((_) => Stream.value([_makeGroup(gid, currency: currency)])),
        groupEventsProvider(gid)
            .overrideWith((_) => Stream.value([_makeEvent(eid, gid)])),
        groupMembersProvider(gid).overrideWith(
          (_) =>
              Stream.value([_makeMember('uid-a', gid), _makeMember('uid-b', gid)]),
        ),
        groupSettlementsProvider(gid).overrideWith((_) => Stream.value([])),
      ];

  group('#517 profile stats listener leak', () {
    test(
      'profileStatsProvider uses one-shot reads and holds ZERO live leaf '
      'listeners (the leak fix)',
      () async {
        // uid-b pays 20 → group gross spend = 20 OMR.
        final expFake = _CountingExpenseService({
          eid: [_makeExpense('x1', 'uid-b', Decimal.fromInt(20), eid)],
        });
        final setFake = _CountingSettlementService();
        final container = ProviderContainer(
          overrides: buildOverrides(expFake: expFake, setFake: setFake),
        );
        addTearDown(container.dispose);

        final stats = await _readStatsSettled(container);

        // One-shot reads were used (one event → one get of each).
        expect(expFake.getCount, greaterThan(0),
            reason: 'getExpenses must be the one-shot read path');
        expect(setFake.getCount, greaterThan(0),
            reason: 'getSettlements must be the one-shot read path');
        // The whole point of #517/#104: NO permanent leaf listeners survive.
        expect(expFake.activeWatchListeners, 0,
            reason: 'no live expense listener may survive the Profile path');
        expect(setFake.activeWatchListeners, 0,
            reason: 'no live settlement listener may survive the Profile path');

        // Money axis: gross spend is correct on the one-shot path.
        expect(stats.groupCount, 1);
        expect(stats.eventCount, 1);
        expect(
          stats.spentByCurrency,
          equals([(currency: 'OMR', amount: Decimal.fromInt(20))]),
        );
      },
    );

    test(
      'CONTRAST: the live groupBalancesProvider DOES open leaf listeners '
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

        container.listen(groupBalancesProvider(gid), (_, _) {},
            fireImmediately: true);
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        // The live path opens (and holds) per-event snapshot listeners — the
        // exact leak. getExpenses is NOT used by the live path.
        expect(expFake.activeWatchListeners, greaterThan(0));
        expect(expFake.getCount, 0);
      },
    );

    test(
      'money axis: a USD group buckets its gross spend under USD, never summed '
      'into OMR',
      () async {
        final expFake = _CountingExpenseService({
          eid: [
            _makeExpense('x1', 'uid-b', Decimal.parse('20.00'), eid,
                currency: 'USD'),
          ],
        });
        final setFake = _CountingSettlementService();
        final container = ProviderContainer(
          overrides:
              buildOverrides(expFake: expFake, setFake: setFake, currency: 'USD'),
        );
        addTearDown(container.dispose);

        final stats = await _readStatsSettled(container);

        expect(expFake.activeWatchListeners, 0);
        expect(
          stats.spentByCurrency,
          equals([(currency: 'USD', amount: Decimal.parse('20.00'))]),
        );
      },
    );

    test(
      'no false-zero flicker: while a balance is still loading and no spend is '
      'known yet, the stats stay LOADING (skeleton), not data with an empty '
      'spend that renders a hard 0.000 (Gate P2)',
      () async {
        // events resolve immediately; balances never complete.
        final container = ProviderContainer(
          overrides: [
            userGroupsProvider
                .overrideWith((_) => Stream.value([_makeGroup(gid)])),
            groupEventsProvider(gid).overrideWith(
              (_) => Stream.value([_makeEvent(eid, gid), _makeEvent('e2', gid)]),
            ),
            groupBalancesOnceProvider(gid).overrideWith(
              (ref) => Completer<GroupBalancesOnce>().future, // never completes
            ),
          ],
        );
        addTearDown(container.dispose);

        final sub = container.listen(profileStatsProvider, (_, _) {});
        addTearDown(sub.close);
        for (var i = 0; i < 12; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        final stats = container.read(profileStatsProvider);
        expect(
          stats.isLoading,
          isTrue,
          reason: 'spend unknown + balance mid-flight must keep the skeleton, '
              'never emit data with an empty spentByCurrency (false 0.000)',
        );
      },
    );
  });
}
