import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/services/uid_change_listener.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';

class _MockUser extends Mock implements firebase_auth.User {}

class _FakeCacheOwnerStore implements CacheOwnerStore {
  String? ownerUid;

  @override
  String? readOwnerUid() => ownerUid;

  @override
  Future<void> saveOwnerUid(String? uid) async {
    ownerUid = uid;
  }
}

firebase_auth.User _userWithUid(String uid) {
  final user = _MockUser();
  when(() => user.uid).thenReturn(uid);
  return user;
}

ProviderContainer _container(Stream<firebase_auth.User?> stream) {
  final container = ProviderContainer(
    overrides: [
      authUserChangesProvider.overrideWith((ref) => stream),
      cacheWipeFnProvider.overrideWithValue(() async {}),
      cacheFileExistsProvider.overrideWithValue(() async => false),
      cacheOwnerStoreProvider.overrideWithValue(_FakeCacheOwnerStore()),
    ],
  );
  // Force the safe-UID pipeline to subscribe before any controller.add fires —
  // broadcast streams drop events that have no listeners yet.
  container.listen<String?>(currentUserIdProvider, (_, _) {});
  return container;
}

void main() {
  group('currentUserIdProvider', () {
    test('returns null while auth state is loading', () {
      final container = _container(const Stream.empty());
      addTearDown(container.dispose);

      expect(container.read(currentUserIdProvider), isNull);
    });

    test('returns the current Firebase user uid', () async {
      final controller = StreamController<firebase_auth.User?>.broadcast();
      addTearDown(controller.close);
      final container = _container(controller.stream);
      addTearDown(container.dispose);

      controller.add(_userWithUid('uid-original'));
      await pumpEventQueue();

      expect(container.read(currentUserIdProvider), equals('uid-original'));
    });

    test(
      'reactively swaps when Firebase Auth changes users mid-session',
      () async {
        final controller = StreamController<firebase_auth.User?>.broadcast();
        addTearDown(controller.close);
        final container = _container(controller.stream);
        addTearDown(container.dispose);

        controller.add(_userWithUid('uid-anon-debug'));
        await pumpEventQueue();
        expect(container.read(currentUserIdProvider), equals('uid-anon-debug'));

        // Simulate email-link recovery swapping the auth user.
        controller.add(_userWithUid('uid-recovered'));
        await pumpEventQueue();

        expect(
          container.read(currentUserIdProvider),
          equals('uid-recovered'),
          reason:
              'Provider must follow auth swaps so post-recovery participant '
              'lookups use the new UID (regression for 2026-05-16 incident).',
        );
      },
    );

    test('returns null when the user signs out', () async {
      final controller = StreamController<firebase_auth.User?>.broadcast();
      addTearDown(controller.close);
      final container = _container(controller.stream);
      addTearDown(container.dispose);

      controller.add(_userWithUid('uid-signed-in'));
      await pumpEventQueue();
      expect(container.read(currentUserIdProvider), equals('uid-signed-in'));

      controller.add(null);
      await pumpEventQueue();
      expect(container.read(currentUserIdProvider), isNull);
    });
  });
}
