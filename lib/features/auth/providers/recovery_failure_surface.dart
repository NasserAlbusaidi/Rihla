import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/app_messenger.dart';
import '../services/recovery_diagnostics.dart';
import '../services/recovery_failure_notice.dart';
import 'auth_email_link_bootstrap_provider.dart' show humanizeAuthErrorCode;

final recoveryDiagnosticsProvider = Provider<RecoveryDiagnostics>(
  (ref) => const SentryRecoveryDiagnostics(),
);

/// Shows, reports, and clears a persisted recovery failure exactly once, after
/// the forced restart that pre-empted the live error SnackBar.
///
/// Called from app bootstrap after the first frame (so the root
/// `ScaffoldMessenger` is mounted). Emitting the Sentry event here — on a
/// stable process — is reliable, unlike the recover path which `System.exit`s
/// before an async send can flush.
Future<void> surfaceRecoveryFailureNotice({
  required SharedPreferences prefs,
  required RecoveryDiagnostics diagnostics,
  void Function(String message)? showMessage,
}) async {
  final notice = readRecoveryFailureNotice(prefs);
  if (notice == null) return;
  (showMessage ?? _showError)(humanizeAuthErrorCode(notice.code));
  diagnostics.captureFailure(
    'recover.surfaced',
    code: notice.code,
    data: {'op': notice.op},
  );
  await clearRecoveryFailureNotice(prefs);
}

void _showError(String message) {
  final messenger = appMessengerKey.currentState;
  if (messenger == null) return;
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
    ),
  );
}
