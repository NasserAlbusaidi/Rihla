import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/services/cold_start_cache_barrier.dart';
import 'package:safar/features/auth/services/uid_change_listener.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockUser extends Mock implements firebase_auth.User {}

firebase_auth.User _userWithUid(String uid) {
  final user = _MockUser();
  when(() => user.uid).thenReturn(uid);
  when(() => user.email).thenReturn(null);
  return user;
}

void main() {
  group('uidChangeListenerProvider', () {
    late StreamController<firebase_auth.User?> userChanges;
    late int wipeCalls;
    late SharedPreferences prefs;
    late ProviderContainer container;

    setUp(() async {
      userChanges = StreamController<firebase_auth.User?>.broadcast();
      wipeCalls = 0;
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authUserChangesProvider.overrideWith((ref) => userChanges.stream),
          cacheWipeFnProvider.overrideWithValue(() async {
            wipeCalls++;
          }),
        ],
      );
      container.read(uidChangeListenerProvider);
    });

    tearDown(() async {
      container.dispose();
      await userChanges.close();
    });

    test('does not wipe on the first emission (cold-start baseline)', () async {
      userChanges.add(_userWithUid('uid-1'));
      await pumpEventQueue();

      expect(wipeCalls, 0);
    });

    test('wipes once when the UID actually changes', () async {
      userChanges.add(_userWithUid('uid-1'));
      await pumpEventQueue();
      expect(wipeCalls, 0);

      userChanges.add(_userWithUid('uid-2'));
      await pumpEventQueue();

      expect(wipeCalls, 1);
    });

    test('does not wipe when the same UID re-emits (linkWithCredential)', () async {
      final user = _userWithUid('uid-1');
      userChanges.add(user);
      await pumpEventQueue();
      userChanges.add(user);
      await pumpEventQueue();

      expect(wipeCalls, 0);
    });

    test('wipes on each distinct UID transition', () async {
      userChanges.add(_userWithUid('uid-1'));
      await pumpEventQueue();
      userChanges.add(_userWithUid('uid-2'));
      await pumpEventQueue();
      userChanges.add(_userWithUid('uid-3'));
      await pumpEventQueue();

      expect(wipeCalls, 2);
    });

    test('treats sign-out (null user) as a UID change from a real UID', () async {
      userChanges.add(_userWithUid('uid-1'));
      await pumpEventQueue();
      userChanges.add(null);
      await pumpEventQueue();

      expect(wipeCalls, 1);
    });

    test('T6 persists newUid to prefs AFTER wipe resolves', () async {
      userChanges.add(_userWithUid('uid-X'));
      await pumpEventQueue();
      expect(prefs.getString(lastObservedUidPrefsKey), isNull);

      userChanges.add(_userWithUid('uid-Y'));
      await pumpEventQueue();

      expect(wipeCalls, 1);
      expect(prefs.getString(lastObservedUidPrefsKey), 'uid-Y');
    });

    test('does not persist when wipe resolves with newUid == null', () async {
      userChanges.add(_userWithUid('uid-X'));
      await pumpEventQueue();
      userChanges.add(null);
      await pumpEventQueue();

      expect(wipeCalls, 1);
      expect(prefs.getString(lastObservedUidPrefsKey), isNull);
    });

    test('T6.5 serializes overlapping wipes; prefs reflects the FINAL uid', () async {
      // Rebuild with a wipe lambda that we can gate to verify serialization.
      container.dispose();
      final wipeStarts = <String>[];
      final wipeEnds = <String>[];
      final pending = <Completer<void>>[];
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authUserChangesProvider.overrideWith((ref) => userChanges.stream),
          cacheWipeFnProvider.overrideWithValue(() async {
            final id = 'w${wipeStarts.length}';
            wipeStarts.add(id);
            final completer = Completer<void>();
            pending.add(completer);
            await completer.future;
            wipeEnds.add(id);
          }),
        ],
      );
      container.read(uidChangeListenerProvider);

      userChanges.add(_userWithUid('uid-X'));
      await pumpEventQueue();
      userChanges.add(_userWithUid('uid-Y'));
      await pumpEventQueue();
      userChanges.add(_userWithUid('uid-Z'));
      await pumpEventQueue();

      // First wipe is in flight; second is queued behind it.
      expect(wipeStarts, ['w0']);
      expect(wipeEnds, isEmpty);
      expect(pending.length, 1);

      pending[0].complete();
      await pumpEventQueue();

      // Second wipe (for Z) starts only after first (for Y) ends.
      expect(wipeStarts, ['w0', 'w1']);
      expect(wipeEnds, ['w0']);
      expect(pending.length, 2);

      pending[1].complete();
      await pumpEventQueue();

      expect(wipeEnds, ['w0', 'w1']);
      expect(prefs.getString(lastObservedUidPrefsKey), 'uid-Z');
    });

    test('continues running after a wipe failure', () async {
      container.dispose();
      var failNext = true;
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authUserChangesProvider.overrideWith((ref) => userChanges.stream),
          cacheWipeFnProvider.overrideWithValue(() async {
            wipeCalls++;
            if (failNext) {
              failNext = false;
              throw StateError('boom');
            }
          }),
        ],
      );
      container.read(uidChangeListenerProvider);

      userChanges.add(_userWithUid('uid-1'));
      await pumpEventQueue();
      userChanges.add(_userWithUid('uid-2'));
      await pumpEventQueue();
      userChanges.add(_userWithUid('uid-3'));
      await pumpEventQueue();

      expect(wipeCalls, 2);
      // After the failed wipe-1→2 and successful wipe-2→3, prefs only reflects
      // the successful transition (uid-3). Failed wipe must not persist its uid.
      expect(prefs.getString(lastObservedUidPrefsKey), 'uid-3');
    });
  });
}
