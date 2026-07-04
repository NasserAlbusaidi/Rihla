import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/app_messenger.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../groups/providers/group_provider.dart';
import '../services/auth_email_link_config.dart';
import '../services/auth_email_link_recognizer.dart';
import '../services/auth_error_humanizer.dart';
import '../services/auth_recovery_service.dart';
import 'auth_provider.dart';
import 'shell_emptiness_gate.dart';

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

void _showSnack(
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = appMessengerKey.currentState;
  if (messenger == null) return;
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade700 : null,
      behavior: SnackBarBehavior.floating,
      duration: duration,
    ),
  );
}

/// Resolves the mounted app's [AppLocalizations] via
/// `appMessengerKey.currentContext`, mirroring the #843
/// `recovery_outcome_notice_provider.dart` precedent (#841 PR-3). Returns
/// `null` when no context is mounted or it carries no `Localizations`
/// ancestor — callers fall back to the EN literal in that case.
AppLocalizations? _l10n() {
  final ctx = appMessengerKey.currentContext;
  if (ctx == null) return null;
  try {
    return AppLocalizations.of(ctx);
  } catch (_) {
    return null;
  }
}

String _humanize(FirebaseAuthException error) =>
    humanizeAuthErrorCode(error.code, l10n: _l10n());

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
    final link = emailLinkFromUri(uri);
    if (link == null) return;

    if (!isRecognizedAuthEmailLink(uri)) {
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
        _l10n()?.authEmailLinkNoPendingEmail ??
            'Open Rihla from the device where you requested the email, '
                'or enter the email again here.',
        isError: true,
      );
      return;
    }

    final op = service.readInFlightOp() ?? AuthRecoveryService.opLink;
    // PII-safe trail for release builds (#439): op kind only, never the
    // email/link/oobCode.
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(category: 'auth.recovery', message: 'dispatch op=$op'),
      ),
    );

    try {
      if (op == AuthRecoveryService.opRecover) {
        // #647: an email RECOVER is a cross-UID discard-shell swap —
        // restoreWithEmailLink engages isolation + a guaranteed restart in its
        // finally, so it CANNOT be aborted once entered. Gate it on the
        // OUTGOING anon shell being provably empty BEFORE the call, mirroring
        // the Profile restore affordance and the durable-credential sheet. A
        // populated shell would be silently orphaned: its trips were flushed to
        // the server under the old anon UID, and after the swap the user is the
        // recovered UID with none of them (#414/#216 lineage). Latent today
        // (anon can't create/join behind the durable-gate), live once join is
        // un-gated (#648 — this blocks it).
        final gateTimeout = ref.read(shellEmptinessGateTimeoutProvider);
        if (!await outgoingShellProvablyEmpty(
          readUser: () => ref.read(firebaseUserProvider.future),
          readGroups: () => ref.read(userGroupsProvider.future),
          timeout: gateTimeout,
        )) {
          FirebaseConfig.log(
            'Recovery: recover swap BLOCKED — shell not provably empty',
          );
          unawaited(
            Sentry.addBreadcrumb(
              Breadcrumb(
                category: 'auth.recovery',
                message: 'recover swap blocked (non-empty/unresolved shell)',
              ),
            ),
          );
          // A blocked recover performed no swap and no restart, so a lingering
          // inFlightOp='recover' is a PHANTOM that would keep dispatching this
          // stale recovery on later boots. Clear the handshake; the next
          // legitimate recover re-arms it via sendRecoveryLink. The live anon
          // SESSION is never signed out (#213/#414). Guarded: a failed prefs
          // write must not crash the listener.
          try {
            await service.clearInFlightOp();
            await service.clearPendingEmail();
          } catch (error, stackTrace) {
            FirebaseConfig.log(
              'Recovery: clearing op-state after block failed',
              error: error,
              stackTrace: stackTrace,
            );
          }
          _showSnack(
            _l10n()?.authEmailLinkRecoverBlocked ??
                'Recovery would switch to your saved account and leave this '
                    "device's current trips behind — they're tied to a "
                    "temporary identity that can't be moved. Resolve them "
                    'first.',
            isError: true,
            duration: const Duration(seconds: 8),
          );
          return;
        }
        final result = await service.restoreWithEmailLink(link);
        FirebaseConfig.log('Recovery: restoreWithEmailLink succeeded');
        ref.read(pendingEmailLinkProvider.notifier).state = null;
        final restoredEmail = result.user?.email ?? pendingEmail;
        _showSnack(
          _l10n()?.authEmailLinkRestored(restoredEmail) ??
              'Restored $restoredEmail',
        );
      } else {
        final result = await service.completeEmailLink(link);
        FirebaseConfig.log('Recovery: completeEmailLink succeeded');
        ref.read(pendingEmailLinkProvider.notifier).state = null;
        final linkedEmail = result.user?.email ?? pendingEmail;
        _showSnack(
          _l10n()?.authEmailLinkLinked(linkedEmail) ?? 'Linked $linkedEmail',
        );
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
      // Reaches here only on the non-restarting paths (link op, or a
      // pre-isolation throw) — the restarting recover path is captured by
      // the #439 outcome marker on the next boot instead.
      unawaited(
        Sentry.captureMessage(
          'recovery_dispatch_failed op=$op code=${error.code}',
          level: SentryLevel.error,
        ),
      );
      _showSnack(_humanize(error), isError: true);
    } catch (error, stack) {
      FirebaseConfig.log(
        'Recovery: $op completion failed',
        error: error,
        stackTrace: stack,
      );
      unawaited(Sentry.captureException(error, stackTrace: stack));
      _showSnack(
        _l10n()?.authEmailLinkGenericError ??
            "Couldn't complete the email link. Try again.",
        isError: true,
      );
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
