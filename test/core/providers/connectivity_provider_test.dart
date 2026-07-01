import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/providers/connectivity_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Default probe null + an empty sync-signal stream ⇒ construction touches no
  // live mechanism, so setter/state-machine tests stay deterministic.
  ConnectivityNotifier makeNotifier({
    Future<bool?> Function()? probe,
    Future<void> Function()? pendingWritesBarrier,
    void Function(String groupId)? markBalanceAggregateMayBeStale,
  }) {
    return ConnectivityNotifier(
      connectivityProbe: probe ?? () async => null,
      syncSignals: () => const Stream<bool>.empty(),
      pendingWritesBarrier: pendingWritesBarrier ?? () async {},
      markBalanceAggregateMayBeStale: markBalanceAggregateMayBeStale,
    );
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

  group(
    'ConnectivityNotifier.checkConnectivity (init/resume one-shot probe)',
    () {
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
    },
  );

  group('sync-signal listener (#633)', () {
    test(
      'reconnect signal alone does NOT resolve queued-write syncing',
      () async {
        final signals = StreamController<bool>();
        final pendingWrites = Completer<void>();
        addTearDown(signals.close);
        final n = ConnectivityNotifier(
          connectivityProbe: () async => null, // no probe interference
          syncSignals: () => signals.stream,
          pendingWritesBarrier: () => pendingWrites.future,
        );
        addTearDown(n.dispose);

        n.noteQueuedWrite(); // a queued offline money-write
        expect(n.state, ConnectivityStatus.syncing);

        signals.add(false); // server reached, but money replay is unproven
        await Future<void>.delayed(Duration.zero);

        expect(n.state, ConnectivityStatus.syncing);
      },
    );

    test(
      'pending writes barrier resolves syncing → online without a probe',
      () async {
        final signals = StreamController<bool>();
        final pendingWrites = Completer<void>();
        addTearDown(signals.close);
        final n = ConnectivityNotifier(
          connectivityProbe: () async => null, // no probe interference
          syncSignals: () => signals.stream,
          pendingWritesBarrier: () => pendingWrites.future,
        );
        addTearDown(n.dispose);

        n.noteQueuedWrite();
        expect(n.state, ConnectivityStatus.syncing);

        signals.add(false); // reachability only
        await Future<void>.delayed(Duration.zero);
        expect(n.state, ConnectivityStatus.syncing);

        pendingWrites.complete(); // actual queued writes acknowledged
        await Future<void>.delayed(Duration.zero);

        expect(n.state, ConnectivityStatus.online);
      },
    );

    test('pending writes barrier failure resolves syncing → offline', () async {
      final pendingWrites = Completer<void>();
      final n = makeNotifier(pendingWritesBarrier: () => pendingWrites.future);
      addTearDown(n.dispose);

      n.noteQueuedWrite();
      expect(n.state, ConnectivityStatus.syncing);

      pendingWrites.completeError(Exception('user changed'));
      await Future<void>.delayed(Duration.zero);

      expect(n.state, ConnectivityStatus.offline);
    });

    test(
      'probe true does not clear syncing while writes are pending',
      () async {
        final pendingWrites = Completer<void>();
        final n = makeNotifier(
          probe: () async => true,
          pendingWritesBarrier: () => pendingWrites.future,
        );
        addTearDown(n.dispose);

        n.noteQueuedWrite();
        await n.checkConnectivity();

        expect(n.state, ConnectivityStatus.syncing);
        pendingWrites.complete();
      },
    );

    test('drop after a server snapshot (isFromCache:true) → offline', () async {
      final signals = StreamController<bool>();
      addTearDown(signals.close);
      final n = ConnectivityNotifier(
        connectivityProbe: () async => null,
        syncSignals: () => signals.stream,
      );
      addTearDown(n.dispose);

      signals.add(false); // server seen → online + latch set
      await Future<void>.delayed(Duration.zero);
      expect(n.state, ConnectivityStatus.online);

      signals.add(true); // connection dropped
      await Future<void>.delayed(Duration.zero);
      expect(n.state, ConnectivityStatus.offline);
    });

    test(
      'cold-start cache-first (isFromCache:true, no server seen) stays online',
      () async {
        final signals = StreamController<bool>();
        addTearDown(signals.close);
        final n = ConnectivityNotifier(
          connectivityProbe: () async => null,
          syncSignals: () => signals.stream,
        );
        addTearDown(n.dispose);

        signals.add(true); // cache-first emission before any server contact
        await Future<void>.delayed(Duration.zero);

        expect(n.state, ConnectivityStatus.online); // NOT false-flipped offline
      },
    );

    test('listener error events fail open (state unchanged)', () async {
      final signals = StreamController<bool>();
      addTearDown(signals.close);
      final n = ConnectivityNotifier(
        connectivityProbe: () async => null,
        syncSignals: () => signals.stream,
      );
      addTearDown(n.dispose);
      n.setOffline();

      signals.addError(Exception('permission-denied'));
      await Future<void>.delayed(Duration.zero);

      expect(n.state, ConnectivityStatus.offline); // no crash, no state change
    });
  });

  group('init probe on construct (#633)', () {
    test('probe false at construct → offline', () async {
      final n = ConnectivityNotifier(
        connectivityProbe: () async => false,
        syncSignals: () => const Stream<bool>.empty(),
      );
      addTearDown(n.dispose);

      await Future<void>.delayed(Duration.zero);
      expect(n.state, ConnectivityStatus.offline);
    });
  });

  group('didChangeAppLifecycleState', () {
    test('paused cancels the live subscription (no exception)', () async {
      final n = makeNotifier(probe: () async => true);
      addTearDown(n.dispose);
      n.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(n.state, ConnectivityStatus.online);
    });

    test('inactive cancels the live subscription', () async {
      final n = makeNotifier(probe: () async => true);
      addTearDown(n.dispose);
      n.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(n.state, ConnectivityStatus.online);
    });

    test('resumed re-runs the probe and re-subscribes', () async {
      var probeCalls = 0;
      final n = makeNotifier(
        probe: () async {
          probeCalls++;
          return true;
        },
      );
      addTearDown(n.dispose);

      n.didChangeAppLifecycleState(AppLifecycleState.paused);
      n.setOffline();
      n.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(probeCalls, greaterThanOrEqualTo(1));
      expect(n.state, ConnectivityStatus.online);
    });

    test('paused → resumed toggles the live subscription', () {
      final signals = StreamController<bool>.broadcast();
      addTearDown(signals.close);
      final n = ConnectivityNotifier(
        connectivityProbe: () async => null,
        syncSignals: () => signals.stream,
      );
      addTearDown(n.dispose);

      expect(n.isLiveCheckActive, isTrue);
      n.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(n.isLiveCheckActive, isFalse);
      n.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(n.isLiveCheckActive, isTrue);
    });
  });

  group('noteLocalWrite (#357)', () {
    test('offline → noteLocalWrite → syncing', () {
      final n = makeNotifier();
      addTearDown(n.dispose);
      n.setOffline();
      n.noteLocalWrite();
      expect(n.state, ConnectivityStatus.syncing);
    });

    test('offline noteLocalWrite marks the supplied aggregate group dirty', () {
      final marked = <String>[];
      final n = makeNotifier(markBalanceAggregateMayBeStale: marked.add);
      addTearDown(n.dispose);
      n.setOffline();

      n.noteLocalWrite(groupId: 'g1');

      expect(marked, ['g1']);
      expect(n.state, ConnectivityStatus.syncing);
    });

    test('online → noteLocalWrite → stays online (gated on offline)', () {
      final n = makeNotifier();
      addTearDown(n.dispose);
      n.noteLocalWrite();
      expect(n.state, ConnectivityStatus.online);
    });

    test(
      'online noteLocalWrite marks aggregate dirty without changing state',
      () {
        final marked = <String>[];
        final n = makeNotifier(markBalanceAggregateMayBeStale: marked.add);
        addTearDown(n.dispose);

        n.noteLocalWrite(groupId: 'g1');

        expect(marked, ['g1']);
        expect(n.state, ConnectivityStatus.online);
      },
    );

    test('syncing → noteLocalWrite → stays syncing (idempotent)', () {
      final n = makeNotifier();
      addTearDown(n.dispose);
      n.setOffline();
      n.noteLocalWrite();
      n.noteLocalWrite();
      expect(n.state, ConnectivityStatus.syncing);
    });

    test(
      'syncing clears to online when pending writes are acknowledged',
      () async {
        final pendingWrites = Completer<void>();
        final n = makeNotifier(
          probe: () async => true,
          pendingWritesBarrier: () => pendingWrites.future,
        );
        addTearDown(n.dispose);
        n.setOffline();
        n.noteLocalWrite();
        expect(n.state, ConnectivityStatus.syncing);
        pendingWrites.complete();
        await Future<void>.delayed(Duration.zero);
        expect(n.state, ConnectivityStatus.online);
      },
    );

    test('syncing falls back to offline while still disconnected', () async {
      final n = makeNotifier(probe: () async => false);
      addTearDown(n.dispose);
      n.setOffline();
      n.noteLocalWrite();
      await n.checkConnectivity();
      expect(n.state, ConnectivityStatus.offline);
    });
  });

  group('noteQueuedWrite (#412)', () {
    test('sets syncing even when state is online (stale-probe window)', () {
      final n = makeNotifier();
      addTearDown(n.dispose);
      n.setOnline();
      n.noteQueuedWrite();
      expect(n.state, ConnectivityStatus.syncing);
    });

    test('noteQueuedWrite marks the supplied aggregate group dirty', () {
      final marked = <String>[];
      final n = makeNotifier(markBalanceAggregateMayBeStale: marked.add);
      addTearDown(n.dispose);

      n.noteQueuedWrite(groupId: 'g1');

      expect(marked, ['g1']);
      expect(n.state, ConnectivityStatus.syncing);
    });

    test('sets syncing from offline', () {
      final n = makeNotifier();
      addTearDown(n.dispose);
      n.setOffline();
      n.noteQueuedWrite();
      expect(n.state, ConnectivityStatus.syncing);
    });

    test(
      'syncing resolves back to online when pending writes are acknowledged',
      () async {
        final pendingWrites = Completer<void>();
        final n = makeNotifier(
          probe: () async => true,
          pendingWritesBarrier: () => pendingWrites.future,
        );
        addTearDown(n.dispose);
        n.noteQueuedWrite();
        expect(n.state, ConnectivityStatus.syncing);
        pendingWrites.complete();
        await Future<void>.delayed(Duration.zero);
        expect(n.state, ConnectivityStatus.online);
      },
    );
  });

  group('startPeriodicChecks seam', () {
    test('defaults to running the live connectivity check', () {
      final signals = StreamController<bool>();
      addTearDown(signals.close);
      final n = ConnectivityNotifier(
        connectivityProbe: () async => null,
        syncSignals: () => signals.stream,
      );
      addTearDown(n.dispose);
      expect(n.isLiveCheckActive, isTrue);
    });

    test('can be disabled so widget tests get a listener-free notifier', () {
      // No controller: startPeriodicChecks:false never subscribes, and a
      // single-subscription controller's close() would hang unlistened.
      final n = ConnectivityNotifier(
        connectivityProbe: () async => null,
        syncSignals: () => const Stream<bool>.empty(),
        startPeriodicChecks: false,
      );
      addTearDown(n.dispose);
      expect(n.isLiveCheckActive, isFalse);
    });
  });
}
