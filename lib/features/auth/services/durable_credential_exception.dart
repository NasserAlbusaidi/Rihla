import 'package:firebase_auth/firebase_auth.dart';

/// Thrown by money-adjacent write paths when the current user is still
/// anonymous (#441 PR2). Screens pre-empt it with the Google gate sheet;
/// reaching this exception means the UI gate was bypassed (offline replay,
/// programmatic call) — the write must not proceed.
class DurableCredentialRequiredException implements Exception {
  const DurableCredentialRequiredException();

  @override
  String toString() => 'A linked account is required for this action.';
}

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
