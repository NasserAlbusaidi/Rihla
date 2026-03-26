import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/providers/connectivity_provider.dart';

// ConnectivityNotifier tests.
//
// The Firestore ping is an async network call that cannot be unit-tested
// without a live Firebase instance. We test the state-machine logic
// (state transitions and timer lifecycle) directly via the public API.

void main() {
  group('ConnectivityNotifier', () {
    late ProviderContainer container;
    late ConnectivityNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(connectivityProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    group('initial state', () {
      test('starts online', () {
        expect(container.read(connectivityProvider), ConnectivityStatus.online);
      });
    });

    group('state transitions', () {
      test('setOffline transitions to offline', () {
        notifier.setOffline();
        expect(container.read(connectivityProvider), ConnectivityStatus.offline);
      });

      test('setOnline transitions to online', () {
        notifier.setOffline();
        notifier.setOnline();
        expect(container.read(connectivityProvider), ConnectivityStatus.online);
      });

      test('setSyncing transitions to syncing', () {
        notifier.setSyncing();
        expect(container.read(connectivityProvider), ConnectivityStatus.syncing);
      });

      test('setOnline after syncing returns to online', () {
        notifier.setSyncing();
        notifier.setOnline();
        expect(container.read(connectivityProvider), ConnectivityStatus.online);
      });
    });

    group('dispose', () {
      test('can be disposed without error', () {
        // Provider container dispose calls notifier.dispose() which cancels the timer.
        expect(() => container.dispose(), returnsNormally);
      });
    });

    group('ConnectivityStatus enum', () {
      test('has online, offline, and syncing values', () {
        expect(ConnectivityStatus.values, containsAll([
          ConnectivityStatus.online,
          ConnectivityStatus.offline,
          ConnectivityStatus.syncing,
        ]));
      });
    });
  });
}
