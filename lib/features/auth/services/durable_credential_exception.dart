import 'package:firebase_auth/firebase_auth.dart';

/// Thrown by `AuthRecoveryService.linkGoogleToCurrentUser` when the Google
/// account is already bound to another Rihla account (#428). Carries the
/// exact credential that failed to link so the gate's switch path can hand
/// it to `restoreWithGoogle(credential:)` without a second Credential
/// Manager sheet — never read [FirebaseAuthException.credential], which can
/// be null (flutterfire #9920).
class GoogleLinkConflictException implements Exception {
  const GoogleLinkConflictException({
    required this.credential,
    required this.cause,
  });

  final AuthCredential credential;
  final FirebaseAuthException cause;

  @override
  String toString() =>
      'Google account already in use by another Rihla account '
      '(${cause.code}).';
}
