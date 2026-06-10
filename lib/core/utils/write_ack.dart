import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Outcome of racing a Firestore write against a server-ack timeout (#412).
enum WriteAck { acked, queued }

/// Bounded wait for a server ack before treating the write as queued-offline.
const kWriteAckTimeout = Duration(seconds: 5);

/// Races [ack] — a Firestore write future, which resolves only on SERVER
/// acknowledgement — against [timeout].
///
/// Returns [WriteAck.acked] when the server confirmed in time: callers keep
/// today's success flow. Returns [WriteAck.queued] on timeout: the SDK has
/// already applied the write to its local cache and queued it for replay on
/// reconnect (#412) — callers proceed optimistically. The still-pending future
/// is then observed in the background; a terminal failure (e.g. a rules
/// rejection on replay) is logged + sent to Sentry and forwarded to
/// [onLateError] — best-effort: the report (not the queued write) is lost if
/// the app dies first.
///
/// An error raised WITHIN the timeout (online rules rejection, validation)
/// propagates to the caller unchanged, so existing error UX keeps working.
///
/// [skipWait] short-circuits straight to the queued path — used when the
/// connectivity provider already reads non-online, so the user isn't made to
/// wait out a timeout the probe has already predicted.
Future<WriteAck> awaitServerAck(
  Future<void> ack, {
  Duration timeout = kWriteAckTimeout,
  bool skipWait = false,
  void Function(Object error, StackTrace stackTrace)? onLateError,
}) async {
  void observeLate() {
    unawaited(
      ack.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Queued write failed on replay: $error');
          unawaited(Sentry.captureException(error, stackTrace: stackTrace));
          onLateError?.call(error, stackTrace);
        },
      ),
    );
  }

  if (skipWait) {
    observeLate();
    return WriteAck.queued;
  }
  try {
    await ack.timeout(timeout);
    return WriteAck.acked;
  } on TimeoutException {
    observeLate();
    return WriteAck.queued;
  }
}
