// googleAccountProvider + isDurableUserProvider (#428 PR-B).
//
// Both derive from authUserChangesProvider and must tolerate the no-Firebase
// test path (null user) the same way linkedEmailProvider does.

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';

class _MockUser extends Mock implements firebase_auth.User {}

class _MockUserInfo extends Mock implements firebase_auth.UserInfo {}

void main() {
  _MockUserInfo providerInfo(String providerId, {String? email}) {
    final info = _MockUserInfo();
    when(() => info.providerId).thenReturn(providerId);
    when(() => info.email).thenReturn(email);
    return info;
  }

  ProviderContainer containerWith(firebase_auth.User? user) {
    final container = ProviderContainer(
      overrides: [
        authUserChangesProvider.overrideWith(
          (ref) => Stream.value(user),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> settle(ProviderContainer c) async {
    // Let the overridden stream deliver its first event.
    await c.read(authUserChangesProvider.future);
  }

  group('googleAccountProvider', () {
    test('null user → null', () async {
      final c = containerWith(null);
      await settle(c);
      expect(c.read(googleAccountProvider), isNull);
    });

    test('anonymous user with no providerData → null', () async {
      final user = _MockUser();
      when(() => user.isAnonymous).thenReturn(true);
      when(() => user.providerData).thenReturn(const []);
      final c = containerWith(user);
      await settle(c);
      expect(c.read(googleAccountProvider), isNull);
    });

    test('google.com provider entry → its email surfaces', () async {
      final user = _MockUser();
      final infos = [
        providerInfo('password'),
        providerInfo('google.com', email: 'nasser@gmail.com'),
      ];
      when(() => user.isAnonymous).thenReturn(false);
      when(() => user.providerData).thenReturn(infos);
      final c = containerWith(user);
      await settle(c);
      expect(c.read(googleAccountProvider)?.email, 'nasser@gmail.com');
    });

    test('google.com entry with null email still reports linked', () async {
      final user = _MockUser();
      final infos = [providerInfo('google.com')];
      when(() => user.isAnonymous).thenReturn(false);
      when(() => user.providerData).thenReturn(infos);
      final c = containerWith(user);
      await settle(c);
      final account = c.read(googleAccountProvider);
      expect(account, isNotNull);
      expect(account!.email, isNull);
    });

    test('email-only linked user → null (no google entry)', () async {
      final user = _MockUser();
      final infos = [providerInfo('password', email: 'n@x.com')];
      when(() => user.isAnonymous).thenReturn(false);
      when(() => user.providerData).thenReturn(infos);
      final c = containerWith(user);
      await settle(c);
      expect(c.read(googleAccountProvider), isNull);
    });
  });

  group('appleAccountProvider (#1256)', () {
    test('null user → null', () async {
      final c = containerWith(null);
      await settle(c);
      expect(c.read(appleAccountProvider), isNull);
    });

    test('anonymous user with no providerData → null', () async {
      final user = _MockUser();
      when(() => user.isAnonymous).thenReturn(true);
      when(() => user.providerData).thenReturn(const []);
      final c = containerWith(user);
      await settle(c);
      expect(c.read(appleAccountProvider), isNull);
    });

    test('apple.com provider entry → its email surfaces', () async {
      final user = _MockUser();
      final infos = [
        providerInfo('password'),
        providerInfo('apple.com', email: 'n@privaterelay.appleid.com'),
      ];
      when(() => user.isAnonymous).thenReturn(false);
      when(() => user.providerData).thenReturn(infos);
      final c = containerWith(user);
      await settle(c);
      expect(
        c.read(appleAccountProvider)?.email,
        'n@privaterelay.appleid.com',
      );
    });

    test('apple.com entry with null email still reports linked (relay '
        'withheld)', () async {
      final user = _MockUser();
      final infos = [providerInfo('apple.com')];
      when(() => user.isAnonymous).thenReturn(false);
      when(() => user.providerData).thenReturn(infos);
      final c = containerWith(user);
      await settle(c);
      final account = c.read(appleAccountProvider);
      expect(account, isNotNull);
      expect(account!.email, isNull);
    });

    test('google-only linked user → null (no apple entry)', () async {
      final user = _MockUser();
      final infos = [providerInfo('google.com', email: 'n@gmail.com')];
      when(() => user.isAnonymous).thenReturn(false);
      when(() => user.providerData).thenReturn(infos);
      final c = containerWith(user);
      await settle(c);
      expect(c.read(appleAccountProvider), isNull);
    });
  });

  group('isDurableUserProvider', () {
    test('null user → false', () async {
      final c = containerWith(null);
      await settle(c);
      expect(c.read(isDurableUserProvider), isFalse);
    });

    test('anonymous user → false', () async {
      final user = _MockUser();
      when(() => user.isAnonymous).thenReturn(true);
      when(() => user.providerData).thenReturn(const []);
      final c = containerWith(user);
      await settle(c);
      expect(c.read(isDurableUserProvider), isFalse);
    });

    test('non-anonymous user → true (Google or email alike)', () async {
      final user = _MockUser();
      when(() => user.isAnonymous).thenReturn(false);
      when(() => user.providerData).thenReturn(const []);
      final c = containerWith(user);
      await settle(c);
      expect(c.read(isDurableUserProvider), isTrue);
    });
  });
}
