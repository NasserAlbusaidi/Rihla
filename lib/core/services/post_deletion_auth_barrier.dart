import 'package:shared_preferences/shared_preferences.dart';

/// UID whose server-side account deletion succeeded before the forced restart.
const String kExpectedDeletedUidKey = 'auth.expectedDeletedUid';

/// Persists the only evidence that makes a restored session safe to discard.
Future<void> markExpectedDeletedUid(SharedPreferences prefs, String uid) async {
  final persisted = await prefs.setString(kExpectedDeletedUidKey, uid);
  if (!persisted) {
    throw StateError('Failed to persist the post-deletion auth marker');
  }
}

/// Retries local teardown only for the UID already deleted by the server.
///
/// A matching-marker sign-out failure deliberately keeps the marker and
/// propagates so the auth gate fails closed and its Retry action can try again.
Future<bool> reconcilePostDeletionAuthSession({
  required SharedPreferences prefs,
  required String? restoredUid,
  required Future<void> Function() signOut,
}) async {
  final expectedUid = prefs.getString(kExpectedDeletedUidKey);
  if (expectedUid == null) return false;
  if (restoredUid != expectedUid) {
    await prefs.remove(kExpectedDeletedUidKey);
    return false;
  }

  await signOut();
  await prefs.remove(kExpectedDeletedUidKey);
  return true;
}
