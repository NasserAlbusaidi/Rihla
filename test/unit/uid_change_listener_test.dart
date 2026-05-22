import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/services/uid_change_listener.dart';

class _MockUser extends Mock implements firebase_auth.User {}

firebase_auth.User _userWithUid(String uid) {
  final user = _MockUser();
  when(() => user.uid).thenReturn(uid);
  when(() => user.email).thenReturn(null);
  return user;
}

ProviderContainer _container({
  required Stream<firebase_auth.User?> userChanges,
  required CacheWipeFn wipe,
}) {
  final container = ProviderContainer(
    overrides: [
      authUserChangesProvider.overrideWith((ref) => userChanges),
      cacheWipeFnProvider.overrideWithValue(wipe),
    ],
  );
  container.listen<UidCacheBarrierState>(
    uidCacheBarrierProvider,
    (_, _) {},
    fireImmediately: true,
  );
  return container;
}

void main() {
  group('uidCacheBarrierProvider', () {
    late StreamController<firebase_auth.User?> userChanges;
    late int wipeCalls;
    late ProviderContainer container;

    setUp(() {
      userChanges = StreamController<firebase_auth.User?>.broadcast();
      wipeCalls = 0;
      container = _container(
        userChanges: userChanges.stream,
        wipe: () async {
          wipeCalls++;
        },
      );
    });

    tearDown(() async {
      container.dispose();
      await userChanges.close();
    });

    test(
      'publishes the first emission as the safe cold-start baseline',
      () async {
        userChanges.add(_userWithUid('uid-1'));
        await pumpEventQueue();

        expect(wipeCalls, 0);
        expect(
          container.read(uidCacheBarrierProvider).phase,
          UidCacheBarrierPhase.safe,
        );
        expect(container.read(safeUidProvider), 'uid-1');
        expect(container.read(uidProvider), 'uid-1');
      },
    );

    test('withholds the new UID until the cache wipe completes', () async {
      final wipeCompleter = Completer<void>();
      container.dispose();
      container = _container(
        userChanges: userChanges.stream,
        wipe: () {
          wipeCalls++;
          return wipeCompleter.future;
        },
      );

      userChanges.add(_userWithUid('uid-1'));
      await pumpEventQueue();
      expect(container.read(safeUidProvider), 'uid-1');

      userChanges.add(_userWithUid('uid-2'));
      await pumpEventQueue();

      expect(wipeCalls, 1);
      expect(
        container.read(uidCacheBarrierProvider).phase,
        UidCacheBarrierPhase.wiping,
      );
      expect(container.read(safeUidProvider), isNull);
      expect(container.read(uidProvider), isNull);

      wipeCompleter.complete();
      await pumpEventQueue();

      expect(
        container.read(uidCacheBarrierProvider).phase,
        UidCacheBarrierPhase.safe,
      );
      expect(container.read(safeUidProvider), 'uid-2');
    });

    test(
      'failed wipe blocks safe UID publication until retry succeeds',
      () async {
        container.dispose();
        var failNext = true;
        container = _container(
          userChanges: userChanges.stream,
          wipe: () async {
            wipeCalls++;
            if (failNext) {
              failNext = false;
              throw StateError('boom');
            }
          },
        );

        userChanges.add(_userWithUid('uid-1'));
        await pumpEventQueue();
        userChanges.add(_userWithUid('uid-2'));
        await pumpEventQueue();

        expect(wipeCalls, 1);
        expect(
          container.read(uidCacheBarrierProvider).phase,
          UidCacheBarrierPhase.failed,
        );
        expect(container.read(safeUidProvider), isNull);

        await container.read(uidCacheBarrierProvider.notifier).retry();
        await pumpEventQueue();

        expect(wipeCalls, 2);
        expect(
          container.read(uidCacheBarrierProvider).phase,
          UidCacheBarrierPhase.safe,
        );
        expect(container.read(safeUidProvider), 'uid-2');
      },
    );

    test('does not wipe when the same UID re-emits', () async {
      final user = _userWithUid('uid-1');
      userChanges.add(user);
      await pumpEventQueue();
      userChanges.add(user);
      await pumpEventQueue();

      expect(wipeCalls, 0);
      expect(container.read(safeUidProvider), 'uid-1');
    });
  });
}
