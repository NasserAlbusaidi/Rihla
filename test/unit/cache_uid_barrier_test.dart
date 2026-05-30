import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/services/cache_uid_barrier.dart';
import 'package:safar/core/services/firestore_cache_gate.dart';

/// Hand-rolled recording gate — FakeFirebaseFirestore.clearPersistence is
/// in-memory only and models neither terminate nor the ordering precondition,
/// so the barrier's contract is verified against this seam instead (#45).
class _RecordingCacheGate implements FirestoreCacheGate {
  _RecordingCacheGate(this.events);
  final List<String> events;
  int clearCount = 0;

  @override
  Future<void> clearPersistence() async {
    clearCount++;
    events.add('clear');
  }
}

void main() {
  group('shouldClearCache', () {
    test('null marker, no force, no dirty -> NO clear (first launch / upgrade rollout)', () {
      expect(
        shouldClearCache(lastActiveUid: null, currentUid: 'Y', dirty: false, forceClear: false),
        isFalse,
      );
    });

    test('null marker + forceClear -> clear (cold-start internal-error swap)', () {
      expect(
        shouldClearCache(lastActiveUid: null, currentUid: 'Y', dirty: false, forceClear: true),
        isTrue,
      );
    });

    test('drift (X != Y) -> clear', () {
      expect(
        shouldClearCache(lastActiveUid: 'X', currentUid: 'Y', dirty: false, forceClear: false),
        isTrue,
      );
    });

    test('same uid, not dirty -> NO clear', () {
      expect(
        shouldClearCache(lastActiveUid: 'X', currentUid: 'X', dirty: false, forceClear: false),
        isFalse,
      );
    });

    test('same uid + dirty -> clear (in-session swap returned to same uid)', () {
      expect(
        shouldClearCache(lastActiveUid: 'X', currentUid: 'X', dirty: true, forceClear: false),
        isTrue,
      );
    });
  });

  group('CacheUidBarrier.reconcile', () {
    test('drift clears, updates marker to current uid, resets dirty', () async {
      SharedPreferences.setMockInitialValues({
        kLastActiveUidKey: 'X',
        kFirestorePersistenceDirtyKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final gate = _RecordingCacheGate(<String>[]);

      await CacheUidBarrier(prefs: prefs, cacheGate: gate).reconcile('Y');

      expect(gate.clearCount, 1);
      expect(prefs.getString(kLastActiveUidKey), 'Y');
      expect(prefs.getBool(kFirestorePersistenceDirtyKey), isFalse);
    });

    test('same uid, not dirty -> no clear but marker still written', () async {
      SharedPreferences.setMockInitialValues({kLastActiveUidKey: 'X'});
      final prefs = await SharedPreferences.getInstance();
      final gate = _RecordingCacheGate(<String>[]);

      await CacheUidBarrier(prefs: prefs, cacheGate: gate).reconcile('X');

      expect(gate.clearCount, 0);
      expect(prefs.getString(kLastActiveUidKey), 'X');
    });

    test('forceClear clears even with a null marker (and adopts uid)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final gate = _RecordingCacheGate(<String>[]);

      await CacheUidBarrier(prefs: prefs, cacheGate: gate).reconcile('Y', forceClear: true);

      expect(gate.clearCount, 1);
      expect(prefs.getString(kLastActiveUidKey), 'Y');
    });

    test('first launch (null marker, no force/dirty) -> no clear, adopts uid', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final gate = _RecordingCacheGate(<String>[]);

      await CacheUidBarrier(prefs: prefs, cacheGate: gate).reconcile('Z');

      expect(gate.clearCount, 0);
      expect(prefs.getString(kLastActiveUidKey), 'Z');
    });

    test('clearPersistence completes BEFORE reconcile returns (ordering)', () async {
      SharedPreferences.setMockInitialValues({kLastActiveUidKey: 'X'});
      final prefs = await SharedPreferences.getInstance();
      final events = <String>[];
      final gate = _RecordingCacheGate(events);

      await CacheUidBarrier(prefs: prefs, cacheGate: gate).reconcile('Y');
      events.add('returned');

      expect(events, <String>['clear', 'returned']);
    });
  });
}
