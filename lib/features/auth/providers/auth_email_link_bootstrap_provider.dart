import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/app_messenger.dart';
import '../services/auth_email_link_config.dart';
import '../services/auth_recovery_service.dart';
import 'auth_provider.dart';

final appLinksProvider = Provider<AppLinks>((ref) => AppLinks());

/// Latest email-link URL the bootstrap listener received but could not
/// auto-complete (typically because no pending email is saved — the
/// "different device" / "user opened the link before priming Settings"
/// case from spec §4.7). Cleared on successful completion. UI in later
/// phases reads this to surface a "Confirm your email" prompt.
final pendingEmailLinkProvider = StateProvider<String?>((ref) => null);

/// Canonical key for deduping repeated emissions of the same Firebase
/// email-auth link. Prefers `oobCode` (single-use, server-bound) and falls
/// back to the full URL string when the param is absent (e.g. malformed or
/// already-unwrapped links — still better than reprocessing blindly).
String _dedupeKey(String link) {
  final code = Uri.tryParse(link)?.queryParameters['oobCode'];
  return (code != null && code.isNotEmpty) ? 'oob:$code' : 'url:$link';
}

String? _emailLinkFromUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();

  if (scheme == 'rihla' && uri.host.toLowerCase() == 'auth-link') {
    final link = uri.queryParameters['link']?.trim();
    if (link == null || link.isEmpty) return null;
    return link;
  }

  if (scheme == 'https') {
    return uri.toString();
  }

  return null;
}

void _showSnack(String message, {bool isError = false}) {
  final messenger = appMessengerKey.currentState;
  if (messenger == null) return;
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade700 : null,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ),
  );
}

String _humanize(FirebaseAuthException error) {
  switch (error.code) {
    case 'invalid-action-code':
    case 'expired-action-code':
      return 'This link has expired or was already used. Send a new one.';
    case 'invalid-email':
      return "That email doesn't look valid.";
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'network-request-failed':
      return 'No connection. Try again when you\'re online.';
    case 'too-many-requests':
      return 'Too many attempts. Wait a few minutes and try again.';
    case 'email-already-in-use':
    case 'credential-already-in-use':
    case 'provider-already-linked':
      return 'This email is already linked to a Rihla account. '
          'Restore from that account instead.';
    default:
      return 'Something went wrong (${error.code}). Please try again.';
  }
}

/// Starts the email-link listener early enough to catch cold-start links.
///
/// Handles three cases:
///   1. `recover` op (Settings hadn't linked yet → user typed email on
///      Recover screen) → swap UID via `signInWithEmailLink`.
///   2. `link` op (default; Settings → "Link my email") → attach email to
///      the current anon UID via `linkWithCredential`. If the email is
///      already owned by another account (`email-already-in-use` and
///      friends) the conflict is surfaced as an error and the anon session
///      is left untouched (#414) — never auto-recover here.
///   3. No pending email at all → stash the link URL in
///      [pendingEmailLinkProvider] so the UI can finish with a manual
///      prompt.
///
/// Outcome is surfaced via `appMessengerKey` so the user sees a SnackBar
/// regardless of which screen they're on when the deep link arrives.
final authEmailLinkBootstrapProvider = Provider<void>((ref) {
  final appLinks = ref.watch(appLinksProvider);

  // Per-provider dedupe set. `app_links` can emit the same URI through both
  // `getInitialLink()` and `uriLinkStream` on the same cold start — without
  // this guard, the second handler call clobbers the success SnackBar with
  // the "no pending email" error path (prefs were cleared by the first call).
  final seenKeys = <String>{};

  Future<void> handleUri(Uri uri) async {
    final link = _emailLinkFromUri(uri);
    if (link == null) return;

    if (!AuthEmailLinkConfig.looksLikeEmailAuthLink(link) &&
        !FirebaseConfig.auth.isSignInWithEmailLink(link)) {
      return;
    }

    final key = _dedupeKey(link);
    if (!seenKeys.add(key)) {
      FirebaseConfig.log(
        'Recovery: duplicate email-link emission ignored '
        '(${AuthEmailLinkConfig.redactForLogging(link)})',
      );
      return;
    }

    FirebaseConfig.log(
      'Firebase email-link credential URL received: '
      '${AuthEmailLinkConfig.redactForLogging(link)}',
    );

    final service = ref.read(authRecoveryServiceProvider);
    final pendingEmail = service.readPendingEmail();
    if (pendingEmail == null) {
      FirebaseConfig.log(
        'Recovery: no pending email saved — surfacing link for UI prompt',
      );
      ref.read(pendingEmailLinkProvider.notifier).state = link;
      _showSnack(
        'Open Rihla from the device where you requested the email, '
        'or enter the email again here.',
        isError: true,
      );
      return;
    }

    final op = service.readInFlightOp() ?? AuthRecoveryService.opLink;

    try {
      if (op == AuthRecoveryService.opRecover) {
        final result = await service.restoreWithEmailLink(link);
        FirebaseConfig.log('Recovery: restoreWithEmailLink succeeded');
        ref.read(pendingEmailLinkProvider.notifier).state = null;
        _showSnack('Restored ${result.user?.email ?? pendingEmail}');
      } else {
        final result = await service.completeEmailLink(link);
        FirebaseConfig.log('Recovery: completeEmailLink succeeded');
        ref.read(pendingEmailLinkProvider.notifier).state = null;
        _showSnack('Linked ${result.user?.email ?? pendingEmail}');
      }
    } on FirebaseAuthException catch (error, stack) {
      // #414: a LINK that fails with email-already-in-use (and friends) must
      // NEVER auto-fall-back to restoreWithEmailLink — that swaps the anon
      // account away and orphans its data. Restoring into the other account
      // is an explicit action via the restore entries only.
      FirebaseConfig.log(
        'Recovery: $op completion failed (${error.code})',
        error: error,
        stackTrace: stack,
      );
      _showSnack(_humanize(error), isError: true);
    } catch (error, stack) {
      FirebaseConfig.log(
        'Recovery: $op completion failed',
        error: error,
        stackTrace: stack,
      );
      _showSnack("Couldn't complete the email link. Try again.", isError: true);
    }
  }

  unawaited(
    appLinks
        .getInitialLink()
        .then((uri) {
          if (uri != null) unawaited(handleUri(uri));
        })
        .catchError((Object error, StackTrace stackTrace) {
          FirebaseConfig.log(
            'Initial email-link lookup failed',
            error: error,
            stackTrace: stackTrace,
          );
        }),
  );

  final subscription = appLinks.uriLinkStream.listen(
    (uri) => unawaited(handleUri(uri)),
    onError: (Object error, StackTrace stackTrace) {
      FirebaseConfig.log(
        'Email-link listener failed',
        error: error,
        stackTrace: stackTrace,
      );
    },
  );

  ref.onDispose(() {
    unawaited(subscription.cancel());
  });
});
