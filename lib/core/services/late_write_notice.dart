import 'package:flutter/material.dart';

import '../extensions/build_context_l10n.dart';
import '../utils/error_message_translator.dart';
import 'app_messenger.dart';

/// Presenter seam — swapped in tests, restored in tearDown. The default shows
/// a SnackBar on the root messenger; without a mounted messenger (app tearing
/// down, widget tests that never mount `appMessengerKey`) it is a silent
/// no-op: the notice is best-effort by the same contract as write_ack's late
/// observer.
@visibleForTesting
void Function(Object error) lateWriteNoticePresenter =
    defaultLateWriteNoticePresenter;

/// Called by `awaitServerAck`'s late-failure observer when a queued-offline
/// write is rejected on replay. Kept trivially thin so a presenter bug can
/// never break the observer (which additionally guards with try/catch).
void notifyLateWriteFailure(Object error) => lateWriteNoticePresenter(error);

/// Used when the messenger context can't resolve localizations — the notice
/// still fires rather than silently dropping the signal (mirrors the
/// recovery-outcome notice's EN-literal fallback).
const String _fallbackMessage =
    "A recent change couldn't be saved. Please check and re-enter it.";

void defaultLateWriteNoticePresenter(Object error) {
  final ctx = appMessengerKey.currentContext;
  final messenger = appMessengerKey.currentState;
  if (messenger == null) return;

  String message;
  try {
    message = ctx == null
        ? _fallbackMessage
        : ctx.l10n.lateWriteFailedNotice(friendlyMessageFor(ctx, error));
  } catch (_) {
    message = _fallbackMessage;
  }

  // Bursts QUEUE on purpose — N rejections at reconnect must produce N
  // notices, not a last-wins collapse (this chokepoint fires per-write,
  // unlike the one-shot recovery-outcome notice).
  messenger.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
  );
}
