import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/providers/connectivity_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ConnectivityNotifier makeNotifier({Future<bool?> Function()? probe}) {
    return ConnectivityNotifier(connectivityProbe: probe ?? () async => null);
  }

  group('ConnectivityNotifier setters', () {
    test('starts online by default', () {
      final n = makeNotifier();
      addTearDown(n.dispose);
      expect(n.state, ConnectivityStatus.online);
    });

    test('setSyncing transitions to syncing', () {
      final n = makeNotifier();
      addTearDown(n.dispose);
      n.setSyncing();
      expect(n.state, ConnectivityStatus.syncing);
    });

    test('setOffline transitions to offline', () {
      final n = makeNotifier();
      addTearDown(n.dispose);
      n.setOffline();
      expect(n.state, ConnectivityStatus.offline);
    });

    test('setOnline returns state to online from offline', () {
      final n = makeNotifier();
      addTearDown(n.dispose);
      n.setOffline();
      expect(n.state, ConnectivityStatus.offline);
      n.setOnline();
      expect(n.state, ConnectivityStatus.online);
    });
  });

  group('ConnectivityNotifier.checkConnectivity', () {
    test('probe true → online', () async {
      final n = makeNotifier(probe: () async => true);
      addTearDown(n.dispose);
      n.setOffline();
      await n.checkConnectivity();
      expect(n.state, ConnectivityStatus.online);
    });

    test('probe false → offline', () async {
      final n = makeNotifier(probe: () async => false);
      addTearDown(n.dispose);
      await n.checkConnectivity();
      expect(n.state, ConnectivityStatus.offline);
    });

    test('probe null → state unchanged', () async {
      final n = makeNotifier(probe: () async => null);
      addTearDown(n.dispose);
      n.setSyncing();
      await n.checkConnectivity();
      expect(n.state, ConnectivityStatus.syncing);
    });
  });

  group('didChangeAppLifecycleState', () {
    test('paused state cancels the periodic timer (no exception)', () async {
      final n = makeNotifier(probe: () async => true);
      addTearDown(n.dispose);
      n.didChangeAppLifecycleState(AppLifecycleState.paused);
      // No throw and state remains as-is (online).
      expect(n.state, ConnectivityStatus.online);
    });

    test('inactive state cancels the periodic timer', () async {
      final n = makeNotifier(probe: () async => true);
      addTearDown(n.dispose);
      n.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(n.state, ConnectivityStatus.online);
    });

    test('resumed re-runs check and restarts the timer', () async {
      var probeCalls = 0;
      final n = makeNotifier(probe: () async {
        probeCalls++;
        return true;
      });
      addTearDown(n.dispose);

      n.didChangeAppLifecycleState(AppLifecycleState.paused);
      n.setOffline();
      n.didChangeAppLifecycleState(AppLifecycleState.resumed);
      // Drain microtask queue for checkConnectivity().
      await Future<void>.delayed(Duration.zero);

      expect(probeCalls, greaterThanOrEqualTo(1));
      expect(n.state, ConnectivityStatus.online);
    });
  });
}
