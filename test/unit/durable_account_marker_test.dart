import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/providers/durable_account_marker_provider.dart';
import 'package:safar/features/auth/services/durable_account_marker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockUser extends Mock implements User {}

User _user({required bool anonymous}) {
  final u = _MockUser();
  when(() => u.uid).thenReturn('uid-x');
  when(() => u.isAnonymous).thenReturn(anonymous);
  return u;
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  group('durable_account_marker helpers', () {
    test('read defaults to false; mark sets it true', () async {
      expect(durableAccountEstablished(prefs), isFalse);
      await markDurableAccountEstablished(prefs);
      expect(durableAccountEstablished(prefs), isTrue);
    });

    test('clear removes the marker', () async {
      await markDurableAccountEstablished(prefs);
      await clearDurableAccountEstablished(prefs);
      expect(durableAccountEstablished(prefs), isFalse);
    });

    test('mark is idempotent (no-op when already set)', () async {
      await markDurableAccountEstablished(prefs);
      await markDurableAccountEstablished(prefs);
      expect(durableAccountEstablished(prefs), isTrue);
    });
  });

  group('durableAccountMarkerProvider', () {
    ProviderContainer containerFor(Stream<User?> authStream) {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authUserChangesProvider.overrideWith((ref) => authStream),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('marks the device when a durable (non-anon) user is observed', () async {
      final container = containerFor(Stream<User?>.value(_user(anonymous: false)));
      container.read(durableAccountMarkerProvider); // activate the listener
      await Future<void>.delayed(Duration.zero);

      expect(durableAccountEstablished(prefs), isTrue);
    });

    test('does NOT mark when only an anonymous user is observed', () async {
      final container = containerFor(Stream<User?>.value(_user(anonymous: true)));
      container.read(durableAccountMarkerProvider);
      await Future<void>.delayed(Duration.zero);

      expect(durableAccountEstablished(prefs), isFalse);
    });

    test('does NOT mark for a null (signed-out) user', () async {
      final container = containerFor(Stream<User?>.value(null));
      container.read(durableAccountMarkerProvider);
      await Future<void>.delayed(Duration.zero);

      expect(durableAccountEstablished(prefs), isFalse);
    });
  });
}
