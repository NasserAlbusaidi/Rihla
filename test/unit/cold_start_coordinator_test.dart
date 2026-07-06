import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/cold_start_coordinator.dart';
import 'package:safar/core/services/deep_link_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
        'bootstrap',
        'notifications initial=true',
      ]);
    },
  );

  test('winning deferred invite skips initial notification route', () async {
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
      'bootstrap',
      'notifications initial=false',
    ]);
  });

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
      // routed) so the deferred invite still gets a chance and notifications run.
      expect(calls, [
        'referrer route=true',
        'bootstrap',
        'notifications initial=true',
      ]);
      expect(errors.single, isA<StateError>());
    },
  );

  test('a failing bootstrap step still runs the notification sync', () async {
    final calls = <String>[];
    final errors = <Object>[];

    await runColdStartCoordinator(
      resolveDeepLinks: () async => const DeepLinkInitialDecision(
        joinRouted: false,
        suppressInstallReferrer: false,
      ),
      consumeInstallReferrer: ({required route}) async => false,
      activateAppBootstrap: () async => throw StateError('bootstrap boom'),
      runInitialNotificationSync: ({required handleInitialMessage}) async {
        calls.add('notifications');
      },
      onStepError: (error, _) => errors.add(error),
    );

    expect(calls, ['notifications']);
    expect(errors.single, isA<StateError>());
  });

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
        activateAppBootstrap: () async {
          calls.add('bootstrap');
        },
        runInitialNotificationSync: ({required handleInitialMessage}) async {
          calls.add('notifications initial=$handleInitialMessage');
        },
        onStepError: (error, _) => errors.add(error),
      );

      // Referrer failure → installReferrerRouted falls back to false, so the
      // join is treated as not-routed and notifications route.
      expect(calls, ['bootstrap', 'notifications initial=true']);
      expect(errors.single, isA<StateError>());
    },
  );
}
