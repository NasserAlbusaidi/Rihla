// #1102: a user rename is local-first, but its Firestore propagation performs
// uncached reads before staging the member updates. If those reads fail offline,
// the rename needs a durable reconciliation path when connectivity returns.
//
// FakeFirebaseFirestore acknowledges writes immediately, so the second attempt
// uses a never-completing Completer to model Firestore's real offline server-ack
// future (#412).

import 'dart:async';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/app_bootstrap_provider.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/display_name_propagation_service.dart';
import 'package:safar/core/services/settings_service.dart';

class _MockDisplayNamePropagationService extends Mock
    implements DisplayNamePropagationService {}

Future<void> _drainAsync() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('offline display-name rename retries on reconnect without awaiting '
      'the staged Firestore write (#1102/#412)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settingsService = SettingsService(prefs);
    final propagationService = _MockDisplayNamePropagationService();
    final neverAcknowledged = Completer<void>();
    var attempts = 0;

    when(() => propagationService.stage('Nasser')).thenAnswer((_) {
      attempts++;
      if (attempts == 1) {
        return Future<StagedDisplayNamePropagation?>.error(
          StateError('offline cold-cache member query failed'),
        );
      }
      return Future<StagedDisplayNamePropagation?>.value((
        ack: neverAcknowledged.future,
      ));
    });

    final settings = SettingsNotifier(
      settingsService,
      deviceLanguageCode: 'en',
      propagationServiceFactory: () => propagationService,
    );
    final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
      ..setOffline();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceLocalesProvider.overrideWithValue(const [Locale('en')]),
        settingsProvider.overrideWith((ref) => settings),
        connectivityProvider.overrideWith((ref) => connectivity),
      ],
    );
    addTearDown(container.dispose);

    container.read(appBootstrapProvider);
    await settings.setDeviceName('Nasser');
    await _drainAsync();

    expect(attempts, 1);
    expect(settings.state.deviceName, 'Nasser');
    expect(prefs.getString('settings_device_name'), 'Nasser');
    expect(settingsService.pendingDisplayNamePropagation, 'Nasser');

    connectivity.setOnline();
    await _drainAsync();

    expect(
      attempts,
      2,
      reason: 'the durable user rename must be reconciled when online',
    );
    expect(settingsService.pendingDisplayNamePropagation, isNull);
    expect(
      neverAcknowledged.isCompleted,
      isFalse,
      reason: 'offline Firestore writes wait for server acknowledgement',
    );
  });

  test(
    'no-Firebase-app propagation stays fail-open and retains the marker',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settingsService = SettingsService(prefs);
      final settings = SettingsNotifier(
        settingsService,
        deviceLanguageCode: 'en',
      );
      addTearDown(settings.dispose);

      await settings.setDeviceName('Ahmed');
      await _drainAsync();

      expect(settings.state.deviceName, 'Ahmed');
      expect(settingsService.pendingDisplayNamePropagation, 'Ahmed');
    },
  );

  test(
    'setDeviceName clears (not sets) the pending propagation marker when '
    'the name normalizes to empty, and never fires propagation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settingsService = SettingsService(prefs);
      await settingsService.savePendingDisplayNamePropagation('Stale');
      final propagationService = _MockDisplayNamePropagationService();
      final settings = SettingsNotifier(
        settingsService,
        deviceLanguageCode: 'en',
        propagationServiceFactory: () => propagationService,
      );
      addTearDown(settings.dispose);

      await settings.setDeviceName('   ');
      await _drainAsync();

      expect(settings.state.deviceName, '');
      expect(settingsService.pendingDisplayNamePropagation, isNull);
      verifyNever(() => propagationService.stage(any()));
    },
  );

  test('restore-seeded device name remains INBOUND-only (#990)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settingsService = SettingsService(prefs);
    final settings = SettingsNotifier(
      settingsService,
      deviceLanguageCode: 'en',
    );
    addTearDown(settings.dispose);

    expect(await settings.seedDeviceName('Nasser'), isTrue);

    expect(settings.state.deviceName, 'Nasser');
    expect(settingsService.pendingDisplayNamePropagation, isNull);
  });
}
