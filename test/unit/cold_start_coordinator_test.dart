import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/cold_start_coordinator.dart';
import 'package:safar/core/services/deep_link_service.dart';

void main() {
  test(
    'suppressed explicit auth link consumes referrer before bootstrap',
    () async {
      final calls = <String>[];

      await runColdStartCoordinator(
        resolveDeepLinks: () async {
          calls.add('deep-links');
          return const DeepLinkInitialDecision(
            joinRouted: false,
            suppressInstallReferrer: true,
          );
        },
        consumeInstallReferrer: ({required route}) async {
          calls.add('referrer route=$route');
          return false;
        },
        replayGateIntent: ({required skipNavigation}) async {
          calls.add('gate skip=$skipNavigation');
        },
        activateAppBootstrap: () async {
          calls.add('bootstrap');
        },
        runInitialNotificationSync: ({required handleInitialMessage}) async {
          calls.add('notifications initial=$handleInitialMessage');
        },
      );

      expect(calls, [
        'deep-links',
        'referrer route=false',
        'gate skip=false',
        'bootstrap',
        'notifications initial=true',
      ]);
    },
  );

  test(
    'winning deferred invite skips gate replay and initial notification route',
    () async {
      final calls = <String>[];

      await runColdStartCoordinator(
        resolveDeepLinks: () async {
          calls.add('deep-links');
          return const DeepLinkInitialDecision(
            joinRouted: false,
            suppressInstallReferrer: false,
          );
        },
        consumeInstallReferrer: ({required route}) async {
          calls.add('referrer route=$route');
          return true;
        },
        replayGateIntent: ({required skipNavigation}) async {
          calls.add('gate skip=$skipNavigation');
        },
        activateAppBootstrap: () async {
          calls.add('bootstrap');
        },
        runInitialNotificationSync: ({required handleInitialMessage}) async {
          calls.add('notifications initial=$handleInitialMessage');
        },
      );

      expect(calls, [
        'deep-links',
        'referrer route=true',
        'gate skip=true',
        'bootstrap',
        'notifications initial=false',
      ]);
    },
  );
}
