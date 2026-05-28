import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/services/cold_start_cache_barrier.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('runColdStartCacheBarrier', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('T1 identity drift X→Y with cache file → wipe + persist Y', () async {
      await prefs.setString(lastObservedUidPrefsKey, 'uid-X');
      var wipeCalls = 0;

      await runColdStartCacheBarrier(
        prefs: prefs,
        currentUid: 'uid-Y',
        cacheFileExists: () async => true,
        wipe: () async => wipeCalls++,
      );

      expect(wipeCalls, 1);
      expect(prefs.getString(lastObservedUidPrefsKey), 'uid-Y');
    });

    test('T2 residual cache, no persisted UID → wipe + seed prefs', () async {
      var wipeCalls = 0;

      await runColdStartCacheBarrier(
        prefs: prefs,
        currentUid: 'uid-A',
        cacheFileExists: () async => true,
        wipe: () async => wipeCalls++,
      );

      expect(wipeCalls, 1);
      expect(prefs.getString(lastObservedUidPrefsKey), 'uid-A');
    });

    test('T3 persisted UID matches current → no wipe; prefs unchanged value', () async {
      await prefs.setString(lastObservedUidPrefsKey, 'uid-X');
      var wipeCalls = 0;

      await runColdStartCacheBarrier(
        prefs: prefs,
        currentUid: 'uid-X',
        cacheFileExists: () async => true,
        wipe: () async => wipeCalls++,
      );

      expect(wipeCalls, 0);
      expect(prefs.getString(lastObservedUidPrefsKey), 'uid-X');
    });

    test('T4 clean install (no prefs, no cache file) → no wipe; seed prefs', () async {
      var wipeCalls = 0;

      await runColdStartCacheBarrier(
        prefs: prefs,
        currentUid: 'uid-A',
        cacheFileExists: () async => false,
        wipe: () async => wipeCalls++,
      );

      expect(wipeCalls, 0);
      expect(prefs.getString(lastObservedUidPrefsKey), 'uid-A');
    });

    test('T5 wipe completes BEFORE prefs is written when wipeCause != null', () async {
      await prefs.setString(lastObservedUidPrefsKey, 'uid-X');
      var prefsHeldOldUidDuringWipe = false;

      await runColdStartCacheBarrier(
        prefs: prefs,
        currentUid: 'uid-Y',
        cacheFileExists: () async => true,
        wipe: () async {
          prefsHeldOldUidDuringWipe =
              prefs.getString(lastObservedUidPrefsKey) == 'uid-X';
        },
      );

      expect(prefsHeldOldUidDuringWipe, isTrue);
      expect(prefs.getString(lastObservedUidPrefsKey), 'uid-Y');
    });

    test('T5b wipe failure → barrier rethrows; prefs NOT written; retry wipes again', () async {
      await prefs.setString(lastObservedUidPrefsKey, 'uid-X');
      var wipeCalls = 0;
      var failNext = true;

      Future<void> wipe() async {
        wipeCalls++;
        if (failNext) {
          failNext = false;
          throw StateError('boom');
        }
      }

      await expectLater(
        () => runColdStartCacheBarrier(
          prefs: prefs,
          currentUid: 'uid-Y',
          cacheFileExists: () async => true,
          wipe: wipe,
        ),
        throwsA(isA<StateError>()),
      );

      expect(wipeCalls, 1);
      expect(prefs.getString(lastObservedUidPrefsKey), 'uid-X');

      await runColdStartCacheBarrier(
        prefs: prefs,
        currentUid: 'uid-Y',
        cacheFileExists: () async => true,
        wipe: wipe,
      );

      expect(wipeCalls, 2);
      expect(prefs.getString(lastObservedUidPrefsKey), 'uid-Y');
    });

    test('null currentUid → no wipe, no prefs touch', () async {
      await prefs.setString(lastObservedUidPrefsKey, 'uid-X');
      var wipeCalls = 0;

      await runColdStartCacheBarrier(
        prefs: prefs,
        currentUid: null,
        cacheFileExists: () async => true,
        wipe: () async => wipeCalls++,
      );

      expect(wipeCalls, 0);
      expect(prefs.getString(lastObservedUidPrefsKey), 'uid-X');
    });
  });
}
