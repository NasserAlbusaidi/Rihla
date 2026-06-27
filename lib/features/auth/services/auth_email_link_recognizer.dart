import '../../../core/config/firebase_config.dart';
import 'auth_email_link_config.dart';

String? emailLinkFromUri(Uri uri) {
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

bool isRecognizedAuthEmailLink(
  Uri uri, {
  bool Function(String link)? isFirebaseEmailLink,
}) {
  final link = emailLinkFromUri(uri);
  if (link == null) return false;
  if (AuthEmailLinkConfig.looksLikeEmailAuthLink(link)) return true;
  final firebasePredicate =
      isFirebaseEmailLink ?? FirebaseConfig.auth.isSignInWithEmailLink;
  try {
    return firebasePredicate(link);
  } catch (_) {
    return false;
  }
}
