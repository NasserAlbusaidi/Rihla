import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/sync_service.dart';

void main() {
  group('calculateSyncRetryDelay', () {
    test('retryCount 0 gives delay between 1000-1999ms', () {
      for (var i = 0; i < 20; i++) {
        final delay = calculateSyncRetryDelay(0);
        expect(delay.inMilliseconds, greaterThanOrEqualTo(1000));
        expect(delay.inMilliseconds, lessThan(2000));
      }
    });

    test('retryCount 1 gives delay between 2000-2999ms', () {
      for (var i = 0; i < 20; i++) {
        final delay = calculateSyncRetryDelay(1);
        expect(delay.inMilliseconds, greaterThanOrEqualTo(2000));
        expect(delay.inMilliseconds, lessThan(3000));
      }
    });

    test('retryCount 2 gives delay between 4000-4999ms', () {
      for (var i = 0; i < 20; i++) {
        final delay = calculateSyncRetryDelay(2);
        expect(delay.inMilliseconds, greaterThanOrEqualTo(4000));
        expect(delay.inMilliseconds, lessThan(5000));
      }
    });

    test('retryCount 4 gives delay between 16000-16999ms', () {
      for (var i = 0; i < 20; i++) {
        final delay = calculateSyncRetryDelay(4);
        expect(delay.inMilliseconds, greaterThanOrEqualTo(16000));
        expect(delay.inMilliseconds, lessThan(17000));
      }
    });

    test('delays are never negative', () {
      for (var retry = 0; retry < 10; retry++) {
        for (var i = 0; i < 10; i++) {
          final delay = calculateSyncRetryDelay(retry);
          expect(delay.inMilliseconds, greaterThan(0));
        }
      }
    });

    test('multiple calls produce different values (jitter is random)', () {
      final delays = <int>{};
      // Run enough iterations that randomness should produce at least 2 distinct values
      for (var i = 0; i < 50; i++) {
        delays.add(calculateSyncRetryDelay(0).inMilliseconds);
      }
      expect(delays.length, greaterThan(1),
          reason: 'Jitter should produce varying delay values');
    });
  });
}
