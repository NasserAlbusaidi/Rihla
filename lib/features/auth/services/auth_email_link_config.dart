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
}
