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

/// Starts the email-link listener early enough to catch cold-start links.
///
/// P0 just logged receipt; P1 wires the receive-side: when a Firebase
/// email-link arrives we attempt to complete it against the persisted
/// pending email and stash the URL in [pendingEmailLinkProvider] if we
/// can't (so the UI can finish the flow with a manual email prompt).
final authEmailLinkBootstrapProvider = Provider<void>((ref) {
  final appLinks = ref.watch(appLinksProvider);
  final subscription = appLinks.uriLinkStream.listen(
    (uri) async {
      final link = uri.toString();
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
    },
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
