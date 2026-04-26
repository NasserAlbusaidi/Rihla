// Architecture enforcement test for ARCH-04.
//
// These tests assert that the god-class `CacheService` and the misnamed
// `BalanceCacheRepository` have been deleted after Phase 36 Plan 06 lands.
// They were created as RED tests and made GREEN by the decomposition in
// plan 36-06 (Wave 2).
//
// If either file re-appears (e.g. someone adds it back), this test fails.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ARCH-04: CacheService decomposition', () {
    test('lib/core/services/cache_service.dart does not exist', () {
      const path = 'lib/core/services/cache_service.dart';
      expect(
        File(path).existsSync(),
        isFalse,
        reason:
            'cache_service.dart was decomposed into 9 domain repositories '
            'under lib/core/services/cache/ in Phase 36 Plan 06. '
            'Do not re-introduce this file.',
      );
    });

    test('lib/core/services/balance_cache_repository.dart does not exist', () {
      const path = 'lib/core/services/balance_cache_repository.dart';
      expect(
        File(path).existsSync(),
        isFalse,
        reason:
            'balance_cache_repository.dart was folded into '
            'ExpenseCacheRepository and SettlementCacheRepository '
            'in Phase 36 Plan 06. Do not re-introduce this file.',
      );
    });

    test('lib/core/services/cache/ directory has exactly 7 repository files',
        () {
      const cacheDir = 'lib/core/services/cache';
      final dir = Directory(cacheDir);
      expect(
        dir.existsSync(),
        isTrue,
        reason: 'lib/core/services/cache/ must exist after Phase 36 Plan 06.',
      );

      final dartFiles = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      expect(
        dartFiles.length,
        equals(7),
        reason:
            'Expected exactly 7 domain repository files under '
            'lib/core/services/cache/ after Phase 39 strip dropped the gear '
            'and sub_group repositories. Found: '
            '${dartFiles.map((f) => f.uri.pathSegments.last).toList()}',
      );
    });
  });
}
