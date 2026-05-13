import 'package:firebase_auth/firebase_auth.dart';

/// Shared constants for Firebase Auth email links.
///
/// P0 intentionally centralizes the continue URL so Android App Links, iOS
/// Universal Links, Firebase Hosting, and the later auth helpers cannot drift.
class AuthEmailLinkConfig {
  const AuthEmailLinkConfig._();

  static const androidPackageName = 'com.safar.safar';
  static const iOSBundleId = 'com.safar.safar';
  static const hostingDomain = String.fromEnvironment(
    'RIHLA_AUTH_LINK_DOMAIN',
    defaultValue: 'rihla-safar.web.app',
  );
  static const customFirebaseHostingDomain = String.fromEnvironment(
    'RIHLA_AUTH_LINK_CUSTOM_DOMAIN',
  );
  static const continuePath = '/__/auth/links/continue';
  static const continueUrl = 'https://$hostingDomain$continuePath';

  static ActionCodeSettings actionCodeSettings() {
    final trimmedCustomDomain = customFirebaseHostingDomain.trim();
    return ActionCodeSettings(
      url: continueUrl,
      handleCodeInApp: true,
      androidPackageName: androidPackageName,
      androidInstallApp: true,
      iOSBundleId: iOSBundleId,
      // Pin the linkDomain to the Hosting domain so Firebase emits continue
      // URLs against `rihla-safar.web.app` (matched by the Android intent
      // filter and the iOS associated domain) rather than the default
      // `*.firebaseapp.com` auth domain, which wouldn't be deep-linked.
      linkDomain: trimmedCustomDomain.isEmpty
          ? hostingDomain
          : trimmedCustomDomain,
    );
  }

  static bool looksLikeEmailAuthLink(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) return false;
    if (uri.scheme != 'https') return false;
    if (uri.host != hostingDomain) return false;
    if (!uri.path.startsWith(continuePath)) return false;
    return uri.queryParameters['mode'] == 'signIn' &&
        uri.queryParameters.containsKey('oobCode');
  }

  static const _redactedQueryParams = {'oobCode', 'apiKey'};

  /// Returns a copy of [link] safe for logs and crash reports.
  ///
  /// Replaces `oobCode` (the single-use email-link credential) and `apiKey`
  /// with `REDACTED` so the URL structure stays useful for debugging without
  /// leaking an active credential.
  static String redactForLogging(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) return '<unparseable-link>';
    if (uri.queryParameters.isEmpty) return uri.toString();
    final redacted = <String, String>{
      for (final entry in uri.queryParameters.entries)
        entry.key: _redactedQueryParams.contains(entry.key)
            ? 'REDACTED'
            : entry.value,
    };
    return uri.replace(queryParameters: redacted).toString();
  }
}
