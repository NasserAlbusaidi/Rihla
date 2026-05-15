import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  group('Firebase App Check release wiring', () {
    test('Flutter client activates debug and release App Check providers', () {
      final config = read('lib/core/config/firebase_config.dart');
      final main = read('lib/main.dart');
      final pubspec = read('pubspec.yaml');

      expect(pubspec, contains('firebase_app_check:'));
      expect(config, contains('FirebaseAppCheck.instance.activate'));
      expect(config, contains('AndroidDebugProvider'));
      expect(config, contains('AndroidPlayIntegrityProvider'));
      expect(config, contains('AppleDebugProvider'));
      expect(config, contains('AppleAppAttestWithDeviceCheckFallbackProvider'));
      expect(
        main,
        contains('useDebugAppCheck: !kReleaseMode || _useFirebaseEmulator'),
      );
    });

    test('join callable enforces App Check and has no public-launch TODO', () {
      final callable = read('functions/src/callables/joinGroupByInviteCode.ts');
      final readiness = read('tool/check_release_readiness.sh');

      expect(callable, contains('enforceAppCheck: true'));
      expect(callable, isNot(contains('TODO: enforce App Check')));
      expect(readiness, contains('App Check enforcement configured'));
      expect(readiness, contains('RIHLA_CONFIRM_APP_CHECK_READY'));
    });
  });
}
