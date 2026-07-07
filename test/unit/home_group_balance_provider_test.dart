import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/providers/balance_aggregate_freshness_provider.dart';
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

// RED → GREEN (#366 Task 10; per-currency v2 #382 PR-3): homeGroupBalanceProvider
// is the SINGLE chooser between the server aggregate doc (online steady state —
// zero per-event reads) and the client once-path (offline/syncing/missing/
// degraded — the only source that sees the user's own queued offline writes,
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
  _CountingSettlementService() : super.withFirestore(FakeFirebaseFirestore());
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

Expense _makeExpense(
  String id,
  String payerId,
  Decimal amount,
  String eventId,
) => Expense(
  id: id,
  tripId: eventId,
  payerParticipantId: payerId,
  amount: amount,
  scope: ExpenseScope.global,
  createdAt: DateTime(2025),
);

Map<String, dynamic> _aggregateDoc({
  Map<String, dynamic>? netMilliByCurrency,
  Map<String, dynamic>? perEventNetMilliByCurrency,
  int eventCount = 2,
  bool degraded = false,
}) => {
  'schemaVersion': 2,
  'currency': 'OMR',
  'netMilliByCurrency':
      netMilliByCurrency ??
      {
        'OMR': {'uid-a': -4000, 'uid-b': 4000},
      },
  'perEventNetMilliByCurrency':
      perEventNetMilliByCurrency ??
      {
        'e1': {
          'OMR': {'uid-a': -4000, 'uid-b': 4000},
        },
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
        groupEventsProvider(
          gid,
        ).overrideWith((_) => Stream.value([_makeEvent('e1', gid)])),
        groupMembersProvider(gid).overrideWith(
          (_) => Stream.value([
            _makeMember('uid-a', gid),
            _makeMember('uid-b', gid),
          ]),
        ),
        groupSettlementsProvider(gid).overrideWith((_) => Stream.value([])),
      ],
    );
    addTearDown(container.dispose);
    container.listen(
      homeGroupBalanceProvider(gid),
      (_, _) {},
      fireImmediately: true,
    );
    return container;
  }

  Future<HomeGroupBalance> settle(ProviderContainer container) async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return container.read(homeGroupBalanceProvider(gid)).requireValue;
  }

  group('homeGroupBalanceProvider chooser (#366)', () {
    test(
      'online + aggregate present → doc values, ZERO one-shot reads',
      () async {
        await seedAggregate();
        final container = makeContainer(ConnectivityStatus.online);

        final result = await settle(container);

        expect(result.fromAggregate, isTrue);
        expect(result.userNet, {'OMR': Decimal.parse('-4')});
        expect(result.userPerEventNet, {
          'e1': {'OMR': Decimal.parse('-4')},
        });
        expect(result.eventCount, 2);
        expect(result.partial, isFalse);
        expect(
          expFake.getCount,
          0,
          reason: 'aggregate path must not issue per-event money reads',
        );
        expect(setFake.getCount, 0);
      },
    );

    test('online + doc missing → once-path fallback (reads happen)', () async {
      final container = makeContainer(ConnectivityStatus.online);

      final result = await settle(container);

      expect(result.fromAggregate, isFalse);
      // uid-b paid 20, equal split → uid-a owes 10 (OMR bucket).
      expect(result.userNet, {'OMR': Decimal.fromInt(-10)});
      expect(result.eventCount, 1);
      expect(expFake.getCount, greaterThan(0));
    });

    test('online + degraded doc → once-path fallback', () async {
      await seedAggregate(_aggregateDoc(degraded: true));
      final container = makeContainer(ConnectivityStatus.online);

      final result = await settle(container);

      expect(result.fromAggregate, isFalse);
      expect(result.userNet, {'OMR': Decimal.fromInt(-10)});
    });

    test(
      'online + TWO-bucket v2 doc → aggregate path, both buckets, zero reads',
      () async {
        // The inverse of the deleted PR-1 "legacy-mixed → fallback" pin: a
        // mixed-currency v2 doc is served straight from the aggregate (#382
        // PR-3 drops the Shim #1 single-currency collapse).
        await seedAggregate(
          _aggregateDoc(
            netMilliByCurrency: {
              'OMR': {'uid-a': -4000, 'uid-b': 4000},
              'AED': {'uid-a': 2500, 'uid-b': -2500},
            },
            perEventNetMilliByCurrency: {
              'e1': {
                'OMR': {'uid-a': -4000, 'uid-b': 4000},
                'AED': {'uid-a': 2500, 'uid-b': -2500},
              },
            },
          ),
        );
        final container = makeContainer(ConnectivityStatus.online);

        final result = await settle(container);

        expect(result.fromAggregate, isTrue);
        expect(result.userNet, {
          'OMR': Decimal.parse('-4'),
          'AED': Decimal.parse('2.5'),
        });
        expect(result.userPerEventNet, {
          'e1': {'OMR': Decimal.parse('-4'), 'AED': Decimal.parse('2.5')},
        });
        expect(
          expFake.getCount,
          0,
          reason:
              'a mixed-currency v2 doc must not fall back to one-shot '
              'per-event money reads',
        );
        expect(setFake.getCount, 0);
      },
    );

    test(
      'offline + aggregate present → once-path (local truth wins)',
      () async {
        await seedAggregate();
        final container = makeContainer(ConnectivityStatus.offline);

        final result = await settle(container);

        expect(result.fromAggregate, isFalse);
        expect(result.userNet, {'OMR': Decimal.fromInt(-10)});
        expect(expFake.getCount, greaterThan(0));
      },
    );

    test('syncing (queued writes may not have replayed) → once-path', () async {
      await seedAggregate();
      final container = makeContainer(ConnectivityStatus.syncing);

      final result = await settle(container);

      expect(result.fromAggregate, isFalse);
    });

    test(
      'online + dirty stale aggregate stays on once-path until aggregate catches up',
      () async {
        await seedAggregate();
        final container = makeContainer(ConnectivityStatus.online);
        container
            .read(balanceAggregateFreshnessProvider.notifier)
            .markGroupDirty(gid);

        final stale = await settle(container);

        expect(stale.fromAggregate, isFalse);
        expect(stale.userNet, {'OMR': Decimal.fromInt(-10)});
        expect(
          container.read(balanceAggregateFreshnessProvider),
          contains(gid),
        );

        await seedAggregate(
          _aggregateDoc(
            netMilliByCurrency: {
              'OMR': {'uid-a': -10000, 'uid-b': 10000},
            },
            perEventNetMilliByCurrency: {
              'e1': {
                'OMR': {'uid-a': -10000, 'uid-b': 10000},
              },
            },
            eventCount: 1,
          ),
        );

        final fresh = await settle(container);

        expect(fresh.fromAggregate, isTrue);
        expect(fresh.userNet, {'OMR': Decimal.fromInt(-10)});
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(balanceAggregateFreshnessProvider),
          isNot(contains(gid)),
        );
      },
    );

    test('revision bump while offline re-runs the fallback compute', () async {
      await seedAggregate();
      final container = makeContainer(ConnectivityStatus.offline);
      await settle(container);
      final before = expFake.getCount;

      container.read(ledgerRevisionProvider.notifier).state++;
      await settle(container);

      expect(
        expFake.getCount,
        greaterThan(before),
        reason: 'the bump contract survives on the fallback path',
      );
    });

    test('null uid (auth resolving) → loading without touching either source',
        () async {
      // #997 D5: a null uid means the auth stream has not resolved yet
      // (_AuthGate guarantees an anon session before SafarApp mounts) — the
      // facade must emit loading, never a fabricated data(zeros) that
      // bypasses the #1005 display hardening.
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

      final result = container.read(homeGroupBalanceProvider(gid));

      expect(result.isLoading, isTrue);
      expect(result.hasValue, isFalse);
      expect(expFake.getCount, 0);
      expect(setFake.getCount, 0);
    });

    test('null uid (auth resolving) → cross-group fold is loading too',
        () async {
      // #997 D5 twin: crossGroupHomeBalanceProvider had the identical
      // uid==null → data(zeros) shape.
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

      final result = container.read(crossGroupHomeBalanceProvider);

      expect(result.isLoading, isTrue);
      expect(result.hasValue, isFalse);
      expect(expFake.getCount, 0);
    });
  });

  group('crossGroupHomeBalanceProvider (#366)', () {
    test(
      'folds per BUCKET key, not group.currency; never cross-sums',
      () async {
        // #382 PR-3 (D12): the currency lives IN the bucket key. g2 is an
        // OMR-currency group whose v2 doc carries a USD bucket — the fold must
        // surface USD 2.5, not drop it into a group-currency OMR slot.
        await seedAggregate();
        await fakeDb
            .doc('groups/g2/aggregates/balance')
            .set(
              _aggregateDoc(
                netMilliByCurrency: {
                  'USD': {'uid-a': 2500},
                },
                perEventNetMilliByCurrency: <String, dynamic>{},
              ),
            );
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
          ],
        );
        addTearDown(container.dispose);
        container.listen(
          crossGroupHomeBalanceProvider,
          (_, _) {},
          fireImmediately: true,
        );

        for (var i = 0; i < 12; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        final result = container
            .read(crossGroupHomeBalanceProvider)
            .requireValue;

        expect(result.partial, isFalse);
        expect(result.balance.groupCount, 2);
        expect(result.balance.byCurrency, hasLength(2));
        final omr = result.balance.byCurrency.singleWhere(
          (b) => b.currency == 'OMR',
        );
        final usd = result.balance.byCurrency.singleWhere(
          (b) => b.currency == 'USD',
        );
        expect(omr.net, Decimal.parse('-4'));
        expect(usd.net, Decimal.parse('2.5'));
      },
    );

    test(
      'stays loading until EVERY group resolves (no false settled-zero flash)',
      () async {
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
            groupBalanceAggregateProvider(
              'g2',
            ).overrideWith((_) => const Stream.empty()),
          ],
        );
        addTearDown(container.dispose);
        container.listen(
          crossGroupHomeBalanceProvider,
          (_, _) {},
          fireImmediately: true,
        );

        for (var i = 0; i < 12; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        expect(
          container.read(crossGroupHomeBalanceProvider).isLoading,
          isTrue,
          reason:
              'one unresolved group must keep the hero on the skeleton, '
              'never a false all-settled zero',
        );
      },
    );
  });

  group('homeGroupBalanceProvider connectivity churn (#623)', () {
    test('offline→syncing does NOT re-evaluate the facade '
        '(watch the bool, not the enum)', () async {
      // noteLocalWrite() drives offline→syncing on every queued write. The
      // facade only branches on `== ConnectivityStatus.online`, which is false
      // in BOTH states, so this transition must not recompute (it would churn
      // every home group row + the cross-group hero fold).
      await seedAggregate();
      final container = makeContainer(ConnectivityStatus.offline);
      await settle(container);

      var churn = 0;
      container.listen(homeGroupBalanceProvider(gid), (_, _) => churn++);

      container.read(connectivityProvider.notifier).noteLocalWrite();
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        container.read(connectivityProvider),
        ConnectivityStatus.syncing,
        reason: 'noteLocalWrite() must have moved offline→syncing',
      );
      expect(
        churn,
        0,
        reason:
            'offline→syncing keeps the once-path branch — recomputing it '
            'churns the home balance for nothing (#623)',
      );
    });

    test(
      'syncing→online still re-evaluates (the online bool actually flips)',
      () async {
        await seedAggregate();
        final container = makeContainer(ConnectivityStatus.syncing);
        final before = await settle(container);
        expect(before.fromAggregate, isFalse);

        container.read(connectivityProvider.notifier).setOnline();
        for (var i = 0; i < 12; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        expect(
          container
              .read(homeGroupBalanceProvider(gid))
              .requireValue
              .fromAggregate,
          isTrue,
          reason:
              'a real online transition must switch to the aggregate path — '
              'the .select must not suppress a genuine bool flip',
        );
      },
    );
  });
}
