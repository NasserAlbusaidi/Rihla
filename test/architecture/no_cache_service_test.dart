// Architecture enforcement test for ARCH-04 / issue #50.
//
// Phase 36 Plan 06 decomposed the `CacheService` god-class and the misnamed
// `BalanceCacheRepository`. Issue #50 then removed the SQLite cache layer
// entirely: it provided no capability over Firestore offline persistence and
// was the home of the cross-UID leak (#45) and the vestigial trip-centric FK
// schema (#49). These tests assert the layer stays gone — if any of these
// files reappear, the removal regressed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ARCH-04: CacheService decomposition', () {
    test('lib/core/services/cache_service.dart does not exist', () {
      expect(
        File('lib/core/services/cache_service.dart').existsSync(),
        isFalse,
        reason: 'cache_service.dart was decomposed in Phase 36 Plan 06; do not '
            're-introduce it.',
      );
    });

    test('lib/core/services/balance_cache_repository.dart does not exist', () {
      expect(
        File('lib/core/services/balance_cache_repository.dart').existsSync(),
        isFalse,
        reason: 'balance_cache_repository.dart was folded into Expense/'
            'Settlement cache repos in Phase 36 Plan 06; do not re-introduce.',
      );
    });
  });

  group('issue #50: SQLite cache layer removed', () {
    test('lib/core/services/cache/ directory does not exist', () {
      expect(
        Directory('lib/core/services/cache').existsSync(),
        isFalse,
        reason:
            'The SQLite domain cache repositories were removed in issue #50 — '
            'Firestore offline persistence (firebase_config.dart) is the only '
            'cache. Do not re-introduce a hand-rolled SQLite cache.',
      );
    });

    test('lib/core/services/local_database.dart does not exist', () {
      expect(
        File('lib/core/services/local_database.dart').existsSync(),
        isFalse,
        reason:
            'LocalDatabase (safar_cache.db) was removed in issue #50. Firestore '
            'offline persistence handles offline reads and write replay.',
      );
    });

    test('lib/features/auth/services/uid_change_listener.dart does not exist',
        () {
      expect(
        File('lib/features/auth/services/uid_change_listener.dart')
            .existsSync(),
        isFalse,
        reason:
            'UidChangeListener existed only to wipe the SQLite cache on UID '
            'swap. With the cache gone it has no role. The Firestore-cache '
            'cross-UID seal (#45) is a separate isolation barrier (PR 2), not '
            'this listener.',
      );
    });
  });
}
