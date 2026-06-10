import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
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

// RED → GREEN (#366 Task 10): homeGroupBalanceProvider is the SINGLE chooser
// between the server aggregate doc (online steady state — zero per-event
// reads) and the client once-path (offline/syncing/missing/degraded/legacy-
// mixed — the only source that sees the user's own queued offline writes,
// spec §0.7). These tests pin the chooser table row by row; the counting
// fakes prove the aggregate path issues ZERO one-shot money reads.

class _CountingExpenseService extends ExpenseService {
  _CountingExpenseService([this._seed = const {}])
      : super.withFirestore(FakeFirebaseFirestore());
  final Map<String, List<Expense>> _seed;
  int getCount = 0;

  @override
  Future<List<Expense>> getExpenses(String groupId, String eventId) async {
    getCount++;
    return _seed[eventId] ?? const <Expense>[];
  }
}

class _CountingSettlementService extends SettlementService {
  _CountingSettlementService()
      : super.withFirestore(FakeFirebaseFirestore());
  int getCount = 0;

  @override
  Future<List<Settlement>> getSettlements(
    String groupId,
    String eventId,
  ) async {
    getCount++;
    return const <Settlement>[];
  }
}

Group _makeGroup(String id, {String currency = 'OMR'}) => Group(
      id: id,
      name: 'Group $id',
      inviteCode: 'AAAAAA',
      createdBy: 'uid-a',
      memberIds: const ['uid-a', 'uid-b'],
      createdAt: DateTime(2025),
      currency: currency,
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
      createdAt: DateTime(2025),
    );

GroupMember _makeMember(String uid, String groupId) => GroupMember(
      id: uid,
      groupId: groupId,
      userId: uid,
      displayName: uid,
      role: 'MEMBER',
      joinedAt: DateTime(2025),
    );

Expense _makeExpense(String id, String payerId, Decimal amount, String eventId) =>
    Expense(
      id: id,
      tripId: eventId,
      payerParticipantId: payerId,
      amount: amount,
      scope: ExpenseScope.global,
      createdAt: DateTime(2025),
    );

Map<String, dynamic> _aggregateDoc({
  Map<String, dynamic>? netMilli,
  Map<String, dynamic>? perEventNetMilli,
  int eventCount = 2,
  List<String> currencies = const ['OMR'],
  bool degraded = false,
}) =>
    {
      'schemaVersion': 1,
      'currency': 'OMR',
      'currencies': currencies,
      'netMilli': netMilli ?? {'uid-a': -4000, 'uid-b': 4000},
      'perEventNetMilli': perEventNetMilli ??
          {
            'e1': {'uid-a': -4000, 'uid-b': 4000},
          },
      'eventCount': eventCount,
      'degraded': degraded,
      'sourceTimeMs': 1000,
    };

ConnectivityNotifier _notifier(ConnectivityStatus status) {
  final notifier = ConnectivityNotifier(
    connectivityProbe: () async => null,
    startPeriodicChecks: false,
  );
  switch (status) {
    case ConnectivityStatus.online:
      notifier.setOnline();
    case ConnectivityStatus.offline:
      notifier.setOffline();
    case ConnectivityStatus.syncing:
      notifier.setSyncing();
  }
  return notifier;
}

void main() {
  const gid = 'g1';

  late FakeFirebaseFirestore fakeDb;
  late _CountingExpenseService expFake;
  late _CountingSettlementService setFake;

  setUp(() {
    fakeDb = FakeFirebaseFirestore();
    expFake = _CountingExpenseService({
      'e1': [_makeExpense('x1', 'uid-b', Decimal.fromInt(20), 'e1')],
    });
    setFake = _CountingSettlementService();
  });

  Future<void> seedAggregate([Map<String, dynamic>? doc]) async {
    await fakeDb
        .doc('groups/$gid/aggregates/balance')
        .set(doc ?? _aggregateDoc());
  }

  ProviderContainer makeContainer(ConnectivityStatus status) {
    final container = ProviderContainer(
      overrides: [
        groupServiceProvider.overrideWith(
          (ref) => GroupService.withFirestore(ref, fakeDb),
        ),
        connectivityProvider.overrideWith((ref) => _notifier(status)),
        currentUserIdProvider.overrideWith((_) => 'uid-a'),
        expenseServiceProvider.overrideWithValue(expFake),
        settlementServiceProvider.overrideWithValue(setFake),
        userGroupsProvider.overrideWith((_) => Stream.value([_makeGroup(gid)])),
        groupEventsProvider(gid)
            .overrideWith((_) => Stream.value([_makeEvent('e1', gid)])),
        groupMembersProvider(gid).overrideWith(
          (_) => Stream.value(
            [_makeMember('uid-a', gid), _makeMember('uid-b', gid)],
          ),
        ),
        groupSettlementsProvider(gid).overrideWith((_) => Stream.value([])),
      ],
    );
    addTearDown(container.dispose);
    container.listen(homeGroupBalanceProvider(gid), (_, _) {},
        fireImmediately: true);
    return container;
  }

  Future<HomeGroupBalance> settle(ProviderContainer container) async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return container.read(homeGroupBalanceProvider(gid)).requireValue;
  }

  group('homeGroupBalanceProvider chooser (#366)', () {
    test('online + aggregate present → doc values, ZERO one-shot reads', () async {
      await seedAggregate();
      final container = makeContainer(ConnectivityStatus.online);

      final result = await settle(container);

      expect(result.fromAggregate, isTrue);
      expect(result.userNet, Decimal.parse('-4'));
      expect(result.userPerEventNet, {'e1': Decimal.parse('-4')});
      expect(result.eventCount, 2);
      expect(result.partial, isFalse);
      expect(expFake.getCount, 0,
          reason: 'aggregate path must not issue per-event money reads');
      expect(setFake.getCount, 0);
    });

    test('online + doc missing → once-path fallback (reads happen)', () async {
      final container = makeContainer(ConnectivityStatus.online);

      final result = await settle(container);

      expect(result.fromAggregate, isFalse);
      // uid-b paid 20, equal split → uid-a owes 10.
      expect(result.userNet, Decimal.fromInt(-10));
      expect(result.eventCount, 1);
      expect(expFake.getCount, greaterThan(0));
    });

    test('online + degraded doc → once-path fallback', () async {
      await seedAggregate(_aggregateDoc(degraded: true));
      final container = makeContainer(ConnectivityStatus.online);

      final result = await settle(container);

      expect(result.fromAggregate, isFalse);
      expect(result.userNet, Decimal.fromInt(-10));
    });

    test('online + legacy-mixed currencies (>1) → once-path fallback', () async {
      await seedAggregate(_aggregateDoc(currencies: ['OMR', 'USD']));
      final container = makeContainer(ConnectivityStatus.online);

      final result = await settle(container);

      expect(result.fromAggregate, isFalse);
    });

    test('offline + aggregate present → once-path (local truth wins)', () async {
      await seedAggregate();
      final container = makeContainer(ConnectivityStatus.offline);

      final result = await settle(container);

      expect(result.fromAggregate, isFalse);
      expect(result.userNet, Decimal.fromInt(-10));
      expect(expFake.getCount, greaterThan(0));
    });

    test('syncing (queued writes may not have replayed) → once-path', () async {
      await seedAggregate();
      final container = makeContainer(ConnectivityStatus.syncing);

      final result = await settle(container);

      expect(result.fromAggregate, isFalse);
    });

    test('revision bump while offline re-runs the fallback compute', () async {
      await seedAggregate();
      final container = makeContainer(ConnectivityStatus.offline);
      await settle(container);
      final before = expFake.getCount;

      container.read(ledgerRevisionProvider.notifier).state++;
      await settle(container);

      expect(expFake.getCount, greaterThan(before),
          reason: 'the bump contract survives on the fallback path');
    });

    test('null uid → zeros without touching either source', () async {
      await seedAggregate();
      final container = ProviderContainer(
        overrides: [
          groupServiceProvider.overrideWith(
            (ref) => GroupService.withFirestore(ref, fakeDb),
          ),
          connectivityProvider.overrideWith(
            (ref) => _notifier(ConnectivityStatus.online),
          ),
          currentUserIdProvider.overrideWith((_) => null),
          expenseServiceProvider.overrideWithValue(expFake),
          settlementServiceProvider.overrideWithValue(setFake),
        ],
      );
      addTearDown(container.dispose);

      final result =
          container.read(homeGroupBalanceProvider(gid)).requireValue;

      expect(result.userNet, Decimal.zero);
      expect(result.eventCount, 0);
      expect(expFake.getCount, 0);
    });
  });

  group('crossGroupHomeBalanceProvider (#366)', () {
    test('buckets per group currency from aggregate docs; never cross-sums', () async {
      await seedAggregate();
      await fakeDb.doc('groups/g2/aggregates/balance').set(_aggregateDoc(
            netMilli: {'uid-a': 2500},
            perEventNetMilli: <String, dynamic>{},
            currencies: ['USD'],
          ));
      final container = ProviderContainer(
        overrides: [
          groupServiceProvider.overrideWith(
            (ref) => GroupService.withFirestore(ref, fakeDb),
          ),
          connectivityProvider.overrideWith(
            (ref) => _notifier(ConnectivityStatus.online),
          ),
          currentUserIdProvider.overrideWith((_) => 'uid-a'),
          userGroupsProvider.overrideWith(
            (_) => Stream.value([
              _makeGroup(gid),
              _makeGroup('g2', currency: 'USD'),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(crossGroupHomeBalanceProvider, (_, _) {},
          fireImmediately: true);

      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final result =
          container.read(crossGroupHomeBalanceProvider).requireValue;

      expect(result.partial, isFalse);
      expect(result.balance.groupCount, 2);
      expect(result.balance.byCurrency, hasLength(2));
      final omr = result.balance.byCurrency
          .singleWhere((b) => b.currency == 'OMR');
      final usd = result.balance.byCurrency
          .singleWhere((b) => b.currency == 'USD');
      expect(omr.net, Decimal.parse('-4'));
      expect(usd.net, Decimal.parse('2.5'));
    });

    test('stays loading until EVERY group resolves (no false settled-zero flash)', () async {
      await seedAggregate();
      final container = ProviderContainer(
        overrides: [
          groupServiceProvider.overrideWith(
            (ref) => GroupService.withFirestore(ref, fakeDb),
          ),
          connectivityProvider.overrideWith(
            (ref) => _notifier(ConnectivityStatus.online),
          ),
          currentUserIdProvider.overrideWith((_) => 'uid-a'),
          userGroupsProvider.overrideWith(
            (_) => Stream.value([_makeGroup(gid), _makeGroup('g2')]),
          ),
          // g2's aggregate stream never emits → its facade stays loading.
          groupBalanceAggregateProvider('g2').overrideWith(
            (_) => const Stream.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(crossGroupHomeBalanceProvider, (_, _) {},
          fireImmediately: true);

      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        container.read(crossGroupHomeBalanceProvider).isLoading,
        isTrue,
        reason: 'one unresolved group must keep the hero on the skeleton, '
            'never a false all-settled zero',
      );
    });
  });
}
