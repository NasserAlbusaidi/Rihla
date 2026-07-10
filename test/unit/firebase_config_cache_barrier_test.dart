import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/config/firebase_config.dart';
import 'package:safar/core/services/cache_uid_barrier.dart';
import 'package:safar/core/services/firestore_cache_gate.dart';

class _RecordingCacheGate implements FirestoreCacheGate {
  int clearCount = 0;

  @override
  Future<void> clearPersistence() async => clearCount++;
}

void main() {
  group('ensureAnonymousSession cold-start cache barrier (#45)', () {
    test('clears on drift: restored uid differs from last-active marker', () async {
      SharedPreferences.setMockInitialValues({kLastActiveUidKey: 'old-uid'});
      final prefs = await SharedPreferences.getInstance();
      final gate = _RecordingCacheGate();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'restored-uid', isAnonymous: true),
      );

      await FirebaseConfig.ensureAnonymousSession(
        authOverride: auth,
        prefs: prefs,
        cacheGate: gate,
      );

      expect(gate.clearCount, 1);
      expect(prefs.getString(kLastActiveUidKey), 'restored-uid');
    });

    test('does NOT clear when restored uid matches the last-active marker', () async {
      SharedPreferences.setMockInitialValues({kLastActiveUidKey: 'restored-uid'});
      final prefs = await SharedPreferences.getInstance();
      final gate = _RecordingCacheGate();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'restored-uid', isAnonymous: true),
      );

      await FirebaseConfig.ensureAnonymousSession(
        authOverride: auth,
        prefs: prefs,
        cacheGate: gate,
      );

      expect(gate.clearCount, 0);
      expect(prefs.getString(kLastActiveUidKey), 'restored-uid');
    });

    test('runCacheBarrier:false never touches the gate (in-session reauth)', () async {
      SharedPreferences.setMockInitialValues({kLastActiveUidKey: 'old-uid'});
      final prefs = await SharedPreferences.getInstance();
      final gate = _RecordingCacheGate();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'restored-uid', isAnonymous: true),
      );

      await FirebaseConfig.ensureAnonymousSession(
        authOverride: auth,
        prefs: prefs,
        cacheGate: gate,
        runCacheBarrier: false,
      );

      expect(gate.clearCount, 0);
    });

    test('fresh anon sign-in adopts the new uid (null marker -> no clear)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final gate = _RecordingCacheGate();
      final auth = MockFirebaseAuth(signedIn: false);

      await FirebaseConfig.ensureAnonymousSession(
        authOverride: auth,
        prefs: prefs,
        cacheGate: gate,
      );

      expect(gate.clearCount, 0);
      expect(prefs.getString(kLastActiveUidKey), isNotNull);
    });

    // #1100: cold boot (main.dart) never injects `prefs` — the fallback to
    // `SharedPreferences.getInstance()` is the only path production actually
    // takes. Every other test in this file passes `prefs:` explicitly, which
    // bypasses that fallback line entirely.
    test('omitted prefs falls back to SharedPreferences.getInstance()', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final gate = _RecordingCacheGate();
      final auth = MockFirebaseAuth(signedIn: false);

      await FirebaseConfig.ensureAnonymousSession(
        authOverride: auth,
        cacheGate: gate,
      );

      expect(gate.clearCount, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kLastActiveUidKey), isNotNull);
    });
  });
}
