import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/auth/providers/auth_provider.dart';

void main() {
  group('currentUserProvider', () {
    test('mirrors authStateProvider value', () async {
      final user = MockUser(uid: 'u1', isAnonymous: false);
      final container = ProviderContainer(
        overrides: [
          authStateProvider
              .overrideWith((_) => Stream<fa.User?>.value(user)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authStateProvider.future);
      final current = container.read(currentUserProvider);
      expect(current?.uid, 'u1');
    });

    test('returns null when authStateProvider has no value', () {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (_) => const Stream<fa.User?>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(currentUserProvider), isNull);
    });
  });

  group('uidProvider', () {
    test('returns uid from authUserChangesProvider value', () async {
      final user = MockUser(uid: 'u42');
      final container = ProviderContainer(
        overrides: [
          authUserChangesProvider
              .overrideWith((_) => Stream<fa.User?>.value(user)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authUserChangesProvider.future);
      expect(container.read(uidProvider), 'u42');
    });

    test('returns null when user is null', () async {
      final container = ProviderContainer(
        overrides: [
          authUserChangesProvider
              .overrideWith((_) => Stream<fa.User?>.value(null)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authUserChangesProvider.future);
      expect(container.read(uidProvider), isNull);
    });
  });

  group('linkedEmailProvider', () {
    test('returns null when user has no email', () async {
      final user = MockUser(isAnonymous: true);
      final container = ProviderContainer(
        overrides: [
          authUserChangesProvider
              .overrideWith((_) => Stream<fa.User?>.value(user)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authUserChangesProvider.future);
      expect(container.read(linkedEmailProvider), isNull);
    });

    test('returns email when user has one', () async {
      final user = MockUser(
        uid: 'u1',
        email: 'alice@example.com',
        isAnonymous: false,
      );
      final container = ProviderContainer(
        overrides: [
          authUserChangesProvider
              .overrideWith((_) => Stream<fa.User?>.value(user)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authUserChangesProvider.future);
      expect(container.read(linkedEmailProvider), 'alice@example.com');
    });

    test('returns null when user is null', () async {
      final container = ProviderContainer(
        overrides: [
          authUserChangesProvider
              .overrideWith((_) => Stream<fa.User?>.value(null)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authUserChangesProvider.future);
      expect(container.read(linkedEmailProvider), isNull);
    });
  });
}
