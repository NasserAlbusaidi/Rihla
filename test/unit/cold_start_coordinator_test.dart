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

  test(
    'a failing deep-link step still runs bootstrap and notifications',
    () async {
      final calls = <String>[];
      final errors = <Object>[];

      await runColdStartCoordinator(
        resolveDeepLinks: () async => throw StateError('deep-link boom'),
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
        onStepError: (error, _) => errors.add(error),
      );

      // Recovery + notifications must NOT be suppressed by the early failure;
      // the dropped decision fails open (referrer not suppressed, join not
      // routed) so the deferred invite still gets a chance and gate/notifs run.
      expect(calls, [
        'referrer route=true',
        'gate skip=false',
        'bootstrap',
        'notifications initial=true',
      ]);
      expect(errors.single, isA<StateError>());
    },
  );

  test(
    'a failing bootstrap step still runs the notification sync',
    () async {
      final calls = <String>[];
      final errors = <Object>[];

      await runColdStartCoordinator(
        resolveDeepLinks: () async => const DeepLinkInitialDecision(
          joinRouted: false,
          suppressInstallReferrer: false,
        ),
        consumeInstallReferrer: ({required route}) async => false,
        replayGateIntent: ({required skipNavigation}) async {
          calls.add('gate');
        },
        activateAppBootstrap: () async => throw StateError('bootstrap boom'),
        runInitialNotificationSync: ({required handleInitialMessage}) async {
          calls.add('notifications');
        },
        onStepError: (error, _) => errors.add(error),
      );

      expect(calls, ['gate', 'notifications']);
      expect(errors.single, isA<StateError>());
    },
  );

  test(
    'a failing referrer step falls back to not-routed and runs the rest',
    () async {
      final calls = <String>[];
      final errors = <Object>[];

      await runColdStartCoordinator(
        resolveDeepLinks: () async => const DeepLinkInitialDecision(
          joinRouted: false,
          suppressInstallReferrer: false,
        ),
        consumeInstallReferrer: ({required route}) async =>
            throw StateError('referrer boom'),
        replayGateIntent: ({required skipNavigation}) async {
          calls.add('gate skip=$skipNavigation');
        },
        activateAppBootstrap: () async {
          calls.add('bootstrap');
        },
        runInitialNotificationSync: ({required handleInitialMessage}) async {
          calls.add('notifications initial=$handleInitialMessage');
        },
        onStepError: (error, _) => errors.add(error),
      );

      // Referrer failure → installReferrerRouted falls back to false, so the
      // join is treated as not-routed: gate replays and notifications route.
      expect(calls, [
        'gate skip=false',
        'bootstrap',
        'notifications initial=true',
      ]);
      expect(errors.single, isA<StateError>());
    },
  );
}
