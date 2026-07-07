import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/utils/listen_recovery.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/services/expense_service.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';

FirebaseException _denied() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

class _StubExpenseService extends ExpenseService {
  _StubExpenseService() : super.withFirestore(FakeFirebaseFirestore());

  @override
  Future<List<Expense>> getExpenses(String groupId, String eventId) async =>
      const <Expense>[];
}

class _StubSettlementService extends SettlementService {
  _StubSettlementService() : super.withFirestore(FakeFirebaseFirestore());

  @override
  Future<List<Settlement>> getSettlements(
    String groupId,
    String eventId,
  ) async =>
      const <Settlement>[];
}

void main() {
  group('recoverDeniedListen (#997)', () {
    test('permission-denied then success → recovers, emissions preserved',
        () async {
      var subscribes = 0;
      final barrierCalls = <int>[];
      final out = recoverDeniedListen<int>(
        () {
          subscribes++;
          if (subscribes == 1) {
            return Stream<int>.error(_denied());
          }
          return Stream.fromIterable([1, 2]);
        },
        pendingWritesBarrier: () async => barrierCalls.add(subscribes),
        backoff: Duration.zero,
      );
      expect(await out.toList(), [1, 2]);
      expect(subscribes, 2);
      // The barrier ran BEFORE the re-listen: the #997 race resolves only
      // once the queued founding batch has replayed.
      expect(barrierCalls, [1]);
    });

    test('genuine revocation → error surfaces after the budget', () async {
      var subscribes = 0;
      final out = recoverDeniedListen<int>(
        () {
          subscribes++;
          return Stream<int>.error(_denied());
        },
        pendingWritesBarrier: () async {},
        backoff: Duration.zero,
      );
      await expectLater(out.toList(), throwsA(isA<FirebaseException>()));
      expect(subscribes, 1 + kListenRecoveryMaxRetries);
    });

    test('cache-emit-then-deny loop cannot retry forever (budget never resets)',
        () async {
      var subscribes = 0;
      final seen = <int>[];
      final out = recoverDeniedListen<int>(
        () {
          subscribes++;
          return Stream<int>.multi((c) {
            c.add(subscribes); // cached emission before the server denial
            c.addError(_denied());
            c.close();
          });
        },
        pendingWritesBarrier: () async {},
        backoff: Duration.zero,
      );
      await expectLater(
        out.forEach(seen.add),
        throwsA(isA<FirebaseException>()),
      );
      expect(subscribes, 1 + kListenRecoveryMaxRetries);
      expect(seen, [1, 2, 3]); // data still flowed through each attempt
    });

    test('non-permission error rethrows immediately, no retry', () async {
      var subscribes = 0;
      final out = recoverDeniedListen<int>(
        () {
          subscribes++;
          return Stream<int>.error(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          );
        },
        pendingWritesBarrier: () async {},
        backoff: Duration.zero,
      );
      await expectLater(out.toList(), throwsA(isA<FirebaseException>()));
      expect(subscribes, 1);
    });

    test('barrier throw/timeout is swallowed — retry still happens', () async {
      var subscribes = 0;
      final out = recoverDeniedListen<int>(
        () {
          subscribes++;
          if (subscribes == 1) return Stream<int>.error(_denied());
          return Stream.value(7);
        },
        pendingWritesBarrier: () async => throw UnimplementedError(),
        backoff: Duration.zero,
      );
      expect(await out.toList(), [7]);
    });

    test('clean close completes without resubscribe', () async {
      var subscribes = 0;
      final out = recoverDeniedListen<int>(
        () {
          subscribes++;
          return Stream.fromIterable([1]);
        },
        pendingWritesBarrier: () async {},
        backoff: Duration.zero,
      );
      expect(await out.toList(), [1]);
      expect(subscribes, 1);
    });
  });

  group('provider-layer #997 regression', () {
    // The field mechanism: the reconnect race terminally denies the events
    // listen; pre-fix, the once-path's uncaught `.future` await rejected and
    // homeGroupBalanceProvider stuck in AsyncError until app restart. With
    // the recovery wrapper underneath the stream, the provider never sees the
    // transient denial and the facade lands in data.
    test(
      'events listen denied once then recovers → home facade reaches data',
      () async {
        const gid = 'g1';
        final event = Event(
          id: 'e1',
          name: 'Event e1',
          type: EventType.trip,
          groupId: gid,
          createdBy: 'uid-a',
          participantIds: const ['uid-a', 'uid-b'],
          participantNames: const {'uid-a': 'A', 'uid-b': 'B'},
          modules: const EventModules(),
          createdAt: DateTime(2025),
        );
        var subscribes = 0;
        final container = ProviderContainer(
          overrides: [
            groupServiceProvider.overrideWith(
              // Aggregate doc absent → facade falls through to the once-path.
              (ref) => GroupService.withFirestore(ref, FakeFirebaseFirestore()),
            ),
            connectivityProvider.overrideWith(
              (ref) => ConnectivityNotifier(
                connectivityProbe: () async => null,
                startPeriodicChecks: false,
              )..setOnline(),
            ),
            currentUserIdProvider.overrideWith((_) => 'uid-a'),
            expenseServiceProvider.overrideWithValue(_StubExpenseService()),
            settlementServiceProvider.overrideWithValue(
              _StubSettlementService(),
            ),
            groupEventsProvider(gid).overrideWith(
              (_) => recoverDeniedListen<List<Event>>(
                () {
                  subscribes++;
                  if (subscribes == 1) {
                    return Stream<List<Event>>.error(_denied());
                  }
                  return Stream.value([event]);
                },
                pendingWritesBarrier: () async {},
                backoff: Duration.zero,
              ),
            ),
            groupMembersProvider(gid).overrideWith(
              (_) => Stream.value([
                GroupMember(
                  id: 'uid-a',
                  groupId: gid,
                  userId: 'uid-a',
                  displayName: 'A',
                  role: 'MEMBER',
                  joinedAt: DateTime(2025),
                ),
              ]),
            ),
            groupSettlementsProvider(gid)
                .overrideWith((_) => Stream.value(const <Settlement>[])),
          ],
        );
        addTearDown(container.dispose);
        container.listen(
          homeGroupBalanceProvider(gid),
          (_, _) {},
          fireImmediately: true,
        );

        for (var i = 0; i < 12; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        final state = container.read(homeGroupBalanceProvider(gid));
        expect(state.hasError, isFalse,
            reason: 'the transient denial must never reach the facade');
        expect(state.requireValue.eventCount, 1);
        expect(subscribes, 2);
      },
    );
  });
}
