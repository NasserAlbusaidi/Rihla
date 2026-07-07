import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/listen_recovery.dart';

FirebaseException _denied() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

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
}
