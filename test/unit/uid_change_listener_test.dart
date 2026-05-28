import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/services/uid_change_listener.dart';

class _MockUser extends Mock implements firebase_auth.User {}

class _FakeCacheOwnerStore implements CacheOwnerStore {
  String? ownerUid;
  final savedOwnerUids = <String?>[];

  @override
  String? readOwnerUid() => ownerUid;

  @override
  Future<void> saveOwnerUid(String? uid) async {
    ownerUid = uid;
    savedOwnerUids.add(uid);
  }
}

firebase_auth.User _userWithUid(String uid) {
  final user = _MockUser();
  when(() => user.uid).thenReturn(uid);
  when(() => user.email).thenReturn(null);
  return user;
}

ProviderContainer _container({
  required Stream<firebase_auth.User?> userChanges,
  required CacheWipeFn wipe,
  _FakeCacheOwnerStore? ownerStore,
  CacheFileExistsFn? cacheFileExists,
}) {
  final container = ProviderContainer(
    overrides: [
      authUserChangesProvider.overrideWith((ref) => userChanges),
      cacheWipeFnProvider.overrideWithValue(wipe),
      cacheOwnerStoreProvider.overrideWithValue(
        ownerStore ?? _FakeCacheOwnerStore(),
      ),
      cacheFileExistsProvider.overrideWithValue(
        cacheFileExists ?? () async => false,
      ),
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
    late _FakeCacheOwnerStore ownerStore;

    setUp(() {
      userChanges = StreamController<firebase_auth.User?>.broadcast();
      wipeCalls = 0;
      ownerStore = _FakeCacheOwnerStore();
      container = _container(
        userChanges: userChanges.stream,
        ownerStore: ownerStore,
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
      'publishes first emission when there is no prior owner and no cache file',
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
        expect(ownerStore.ownerUid, 'uid-1');
      },
    );

    test(
      'wipes before publishing first emission when persisted owner differs',
      () async {
        final wipeCompleter = Completer<void>();
        ownerStore.ownerUid = 'uid-old';
        container.dispose();
        container = _container(
          userChanges: userChanges.stream,
          ownerStore: ownerStore,
          cacheFileExists: () async => true,
          wipe: () {
            wipeCalls++;
            return wipeCompleter.future;
          },
        );

        userChanges.add(_userWithUid('uid-new'));
        await pumpEventQueue();

        expect(wipeCalls, 1);
        expect(
          container.read(uidCacheBarrierProvider).phase,
          UidCacheBarrierPhase.wiping,
        );
        expect(container.read(safeUidProvider), isNull);
        expect(ownerStore.ownerUid, 'uid-old');

        wipeCompleter.complete();
        await pumpEventQueue();

        expect(
          container.read(uidCacheBarrierProvider).phase,
          UidCacheBarrierPhase.safe,
        );
        expect(container.read(safeUidProvider), 'uid-new');
        expect(ownerStore.ownerUid, 'uid-new');
      },
    );

    test(
      'wipes before publishing first emission when cache file has no owner',
      () async {
        final wipeCompleter = Completer<void>();
        container.dispose();
        container = _container(
          userChanges: userChanges.stream,
          ownerStore: ownerStore,
          cacheFileExists: () async => true,
          wipe: () {
            wipeCalls++;
            return wipeCompleter.future;
          },
        );

        userChanges.add(_userWithUid('uid-new'));
        await pumpEventQueue();

        expect(wipeCalls, 1);
        expect(
          container.read(uidCacheBarrierProvider).phase,
          UidCacheBarrierPhase.wiping,
        );
        expect(container.read(safeUidProvider), isNull);
        expect(ownerStore.ownerUid, isNull);

        wipeCompleter.complete();
        await pumpEventQueue();

        expect(
          container.read(uidCacheBarrierProvider).phase,
          UidCacheBarrierPhase.safe,
        );
        expect(container.read(safeUidProvider), 'uid-new');
        expect(ownerStore.ownerUid, 'uid-new');
      },
    );

    test('withholds the new UID until the cache wipe completes', () async {
      final wipeCompleter = Completer<void>();
      container.dispose();
      container = _container(
        userChanges: userChanges.stream,
        ownerStore: ownerStore,
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
          ownerStore: ownerStore,
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
      expect(ownerStore.savedOwnerUids, ['uid-1']);
    });
  });
}
