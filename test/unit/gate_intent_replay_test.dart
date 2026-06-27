import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/auth/services/gate_intent_replay.dart';
import 'package:safar/features/auth/services/pending_gate_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late List<String> navigations;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    navigations = [];
  });

  void go(String location) => navigations.add(location);

  group('GateIntentReplay.maybeReplay', () {
    test(
      'create marker navigates to /create-group and keeps the marker',
      () async {
        await PendingGateIntent.save(
          prefs,
          PendingGateIntent.create(
            groupName: 'G',
            displayName: 'N',
            currencyCode: 'OMR',
          ),
        );

        await GateIntentReplay.maybeReplay(prefs, go);

        expect(navigations, ['/create-group']);
        expect(PendingGateIntent.read(prefs), isNotNull);
      },
    );

    test('no marker → no navigation', () async {
      await GateIntentReplay.maybeReplay(prefs, go);
      expect(navigations, isEmpty);
    });

    test('expired marker → no navigation', () async {
      final stale = DateTime.now()
          .subtract(PendingGateIntent.ttl + const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      await prefs.setString(
        PendingGateIntent.prefsKey,
        '{"v":1,"type":"create","groupName":"G","displayName":"N",'
        '"atMillis":$stale}',
      );

      await GateIntentReplay.maybeReplay(prefs, go);

      expect(navigations, isEmpty);
    });

    test('pending recover op → no navigation, marker untouched', () async {
      await PendingGateIntent.save(
        prefs,
        PendingGateIntent.create(
          groupName: 'G',
          displayName: 'N',
          currencyCode: 'OMR',
        ),
      );
      await prefs.setString(
        AuthRecoveryService.inFlightOpPrefsKey,
        AuthRecoveryService.opRecover,
      );

      await GateIntentReplay.maybeReplay(prefs, go);

      expect(navigations, isEmpty);
      expect(PendingGateIntent.read(prefs), isNotNull);
    });

    test(
      'pending link op does NOT block replay (same-UID, no restart)',
      () async {
        await PendingGateIntent.save(
          prefs,
          PendingGateIntent.create(
            groupName: 'G',
            displayName: 'N',
            currencyCode: 'OMR',
          ),
        );
        await prefs.setString(
          AuthRecoveryService.inFlightOpPrefsKey,
          AuthRecoveryService.opLink,
        );

        await GateIntentReplay.maybeReplay(prefs, go);

        expect(navigations, ['/create-group']);
      },
    );

    test(
      'skipNavigation clears a pending create marker so it cannot hijack the next boot',
      () async {
        await PendingGateIntent.save(
          prefs,
          PendingGateIntent.create(
            groupName: 'G',
            displayName: 'N',
            currencyCode: 'OMR',
          ),
        );

        await GateIntentReplay.maybeReplay(prefs, go, skipNavigation: true);

        expect(navigations, isEmpty);
        expect(PendingGateIntent.read(prefs), isNull);

        await GateIntentReplay.maybeReplay(prefs, go);
        expect(navigations, isEmpty);
      },
    );
  });
}
