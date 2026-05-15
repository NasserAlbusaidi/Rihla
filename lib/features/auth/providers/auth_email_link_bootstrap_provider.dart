import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
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

/// Starts the email-link listener early enough to catch cold-start links.
///
/// P0 just logged receipt; P1 wires the receive-side: when a Firebase
/// email-link arrives we attempt to complete it against the persisted
/// pending email and stash the URL in [pendingEmailLinkProvider] if we
/// can't (so the UI can finish the flow with a manual email prompt).
final authEmailLinkBootstrapProvider = Provider<void>((ref) {
  final appLinks = ref.watch(appLinksProvider);

  Future<void> handleUri(Uri uri) async {
    final link = _emailLinkFromUri(uri);
    if (link == null) return;

    if (!AuthEmailLinkConfig.looksLikeEmailAuthLink(link) &&
        !FirebaseConfig.auth.isSignInWithEmailLink(link)) {
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
      return;
    }

    // P4: dispatch by the in-flight operation flag set when the send
    // request was made. 'link' attaches the email to the current anon
    // UID; 'recover' swaps to the previously-linked UID. Default to
    // 'link' when nothing is set so legacy / pre-P4 flows still work.
    final op = service.readInFlightOp() ?? AuthRecoveryService.opLink;
    try {
      if (op == AuthRecoveryService.opRecover) {
        await service.completeRecovery(link);
        FirebaseConfig.log('Recovery: completeRecovery succeeded');
      } else {
        await service.completeEmailLink(link);
        FirebaseConfig.log('Recovery: completeEmailLink succeeded');
      }
      ref.read(pendingEmailLinkProvider.notifier).state = null;
    } on FirebaseAuthException catch (error, stack) {
      FirebaseConfig.log(
        'Recovery: $op completion failed (${error.code})',
        error: error,
        stackTrace: stack,
      );
    } catch (error, stack) {
      FirebaseConfig.log(
        'Recovery: $op completion failed',
        error: error,
        stackTrace: stack,
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
