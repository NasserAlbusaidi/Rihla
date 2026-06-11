import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../providers/auth_provider.dart';

/// Triggers the #441 PR3 Google restore (cross-UID discard-shell swap) from a
/// restore entry point (the home empty-state CTA).
///
/// On success the swap performs a true app restart, so this never returns to
/// the calling UI. A user-dismissed Credential Manager sheet
/// ([GoogleSignInExceptionCode.canceled]) is silent — the credential is
/// obtained BEFORE any isolation/auth change, so a cancel leaves the anon shell
/// fully intact. Any other error (missing `GOOGLE_SERVER_CLIENT_ID`, no idToken,
/// a failed sign-in) surfaces a snackbar.
Future<void> triggerGoogleRestore(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(authRecoveryServiceProvider).restoreWithGoogle();
    // success path restarts the app — nothing to do here.
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) return;
    if (!context.mounted) return;
    _snack(context, context.l10n.restoreGoogleFailed);
  } catch (_) {
    if (!context.mounted) return;
    _snack(context, context.l10n.restoreGoogleFailed);
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
}
