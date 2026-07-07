import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

/// Re-listen attempts after a `permission-denied` stream error before the
/// error is surfaced. Bounded so a GENUINE access revocation still reaches
/// the UI (#358 no-access state) — it just arrives ~1-2s later than before.
const kListenRecoveryMaxRetries = 2;

/// Cap on waiting for queued writes to replay before re-listening. Offline,
/// `waitForPendingWrites()` never resolves — the timeout keeps the recovery
/// loop bounded; the re-listen then serves from cache without error.
const kListenRecoveryBarrierTimeout = Duration(seconds: 10);

/// Small settle delay between the replay barrier and the re-listen.
const kListenRecoveryBackoff = Duration(milliseconds: 400);

/// Waits for Firestore writes that were pending when called to reach the
/// backend (`FirebaseFirestore.waitForPendingWrites`). Injected in tests.
typedef ListenPendingWritesBarrier = Future<void> Function();

/// #997: a Firestore listen rejected with `permission-denied` is TERMINAL —
/// the SDK never retries it. After an offline group creation, the SDK's
/// re-established listens race the queued founding-batch replay on reconnect;
/// when the listens lose, every group-scoped stream dies permanently even
/// though the very next listen would be accepted. This wrapper re-subscribes
/// [subscribe] after awaiting the pending-write replay, a bounded number of
/// times, so the transient race heals invisibly while genuine revocation
/// still surfaces (the budget never resets within one subscription — a
/// revoked listen that emits cache data before each denial must not loop).
///
/// Non-permission errors are never retried (the SDK handles transient
/// unavailability itself). Barrier failures (timeout, unimplemented fake) are
/// swallowed and the retry proceeds — precedent: the recovery flows'
/// `waitForPendingWrites().timeout(...)` swallow-and-proceed.
Stream<T> recoverDeniedListen<T>(
  Stream<T> Function() subscribe, {
  required ListenPendingWritesBarrier pendingWritesBarrier,
  int maxRetries = kListenRecoveryMaxRetries,
  Duration backoff = kListenRecoveryBackoff,
  Duration barrierTimeout = kListenRecoveryBarrierTimeout,
}) async* {
  var retries = 0;
  while (true) {
    try {
      await for (final value in subscribe()) {
        yield value;
      }
      return;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied' || retries >= maxRetries) rethrow;
      retries++;
      try {
        await pendingWritesBarrier().timeout(barrierTimeout);
      } catch (_) {
        // Barrier timeout / not supported — re-listen anyway; cache serves.
      }
      await Future<void>.delayed(backoff);
    }
  }
}
