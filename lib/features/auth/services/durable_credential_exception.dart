import 'package:firebase_auth/firebase_auth.dart';

/// Base for durable-credential link conflicts (#1256): the chosen provider
/// account already backs a different Firebase user. Sealed so the sheet's
/// switch dispatch is exhaustive — routing an Apple conflict into the Google
/// restore (or vice versa) is the #414/#647 wrong-account swap class, made a
/// compile error here. Carries the exact credential that failed to link so
/// the switch path never re-prompts — never read
/// [FirebaseAuthException.credential], which can be null (flutterfire #9920).
sealed class LinkConflictException implements Exception {
  const LinkConflictException({required this.credential, required this.cause});

  final AuthCredential credential;
  final FirebaseAuthException cause;
}

class GoogleLinkConflictException extends LinkConflictException {
  const GoogleLinkConflictException({
    required super.credential,
    required super.cause,
  });

  @override
  String toString() =>
      'Google account already in use by another Rihla account '
      '(${cause.code}).';
}

class AppleLinkConflictException extends LinkConflictException {
  const AppleLinkConflictException({
    required super.credential,
    required super.cause,
  });

  @override
  String toString() =>
      'Apple account already in use by another Rihla account '
      '(${cause.code}).';
}
