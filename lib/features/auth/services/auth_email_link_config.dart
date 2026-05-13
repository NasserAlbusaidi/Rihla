import 'package:firebase_auth/firebase_auth.dart';

/// Shared constants for Firebase Auth email links.
///
/// P0 intentionally centralizes the continue URL so Android App Links, iOS
/// Universal Links, Firebase Hosting, and the later auth helpers cannot drift.
class AuthEmailLinkConfig {
  const AuthEmailLinkConfig._();

  static const androidPackageName = 'com.safar.safar';
  static const iOSBundleId = 'com.safar.safar';
  // Use the project's default Firebase Hosting `*.firebaseapp.com` alias —
  // NOT `*.web.app`. Both alias the same Hosting site, but post-Dynamic-Links
  // Firebase Auth auto-generates email-link continue URLs against
  // `<project>.firebaseapp.com` and explicitly rejects either default Hosting
  // domain as a value for `ActionCodeSettings.linkDomain`
  // (auth/invalid-hosting-link-domain). The App Links / Universal Links
  // setup must therefore target the firebaseapp.com alias for the deep-link
  // to match what Firebase actually emits.
  static const hostingDomain = String.fromEnvironment(
    'RIHLA_AUTH_LINK_DOMAIN',
    defaultValue: 'rihla-safar.firebaseapp.com',
  );
  // Reserved for a future real custom Hosting domain (e.g. `auth.rihla.app`).
  // Setting it via --dart-define switches both the continue URL and the
  // `linkDomain` field below to that domain.
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
      // Only set `linkDomain` when a real custom Hosting domain is configured.
      // Firebase rejects default Hosting domains (*.web.app / *.firebaseapp.com)
      // here with `auth/invalid-hosting-link-domain`; when omitted, Firebase
      // auto-selects the project's default `*.firebaseapp.com` alias, which
      // is exactly what we want.
      linkDomain: trimmedCustomDomain.isEmpty ? null : trimmedCustomDomain,
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
