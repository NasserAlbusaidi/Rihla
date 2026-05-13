import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../services/auth_email_link_config.dart';

final appLinksProvider = Provider<AppLinks>((ref) => AppLinks());

/// Starts the P0 email-link listener early enough to catch cold-start links.
///
/// Later phases replace the debug log with link/recover orchestration. P0's
/// acceptance is that the app receives the credential URL in this handler.
final authEmailLinkBootstrapProvider = Provider<void>((ref) {
  final appLinks = ref.watch(appLinksProvider);
  final subscription = appLinks.uriLinkStream.listen(
    (uri) {
      final link = uri.toString();
      if (!AuthEmailLinkConfig.looksLikeEmailAuthLink(link) &&
          !FirebaseConfig.auth.isSignInWithEmailLink(link)) {
        return;
      }

      FirebaseConfig.log(
        'Firebase email-link credential URL received: '
        '${AuthEmailLinkConfig.redactForLogging(link)}',
      );
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
