import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Credential + the short-lived Apple authorization code from the same
/// authorization. The code is consumed ONLY by the 5.1.1(v) delete-time
/// revocation (`FirebaseAuth.revokeTokenWithAuthorizationCode`) — it is
/// single-use and expires in minutes, so it is never persisted.
typedef AppleCredentialBundle = ({
  AuthCredential credential,
  String? authorizationCode,
});

typedef GetAppleIDCredential =
    Future<AuthorizationCredentialAppleID> Function({
      required List<AppleIDAuthorizationScopes> scopes,
      String? nonce,
    });

/// Thin adapter over sign_in_with_apple (#1256), the Apple sibling of
/// [GoogleSignInGateway]. Two-phase on purpose (D1): the interactive sheet
/// runs HERE, before any isolation/auth mutation, so a user-cancel throws
/// with the anon shell fully intact and the conflict path can reuse the
/// credential without a second sheet.
class AppleSignInGateway {
  AppleSignInGateway({
    GetAppleIDCredential? getAppleIDCredential,
    Random? random,
  }) : _getAppleIDCredential =
           getAppleIDCredential ?? _defaultGetAppleIDCredential,
       _random = random ?? Random.secure();

  static Future<AuthorizationCredentialAppleID> _defaultGetAppleIDCredential({
    required List<AppleIDAuthorizationScopes> scopes,
    String? nonce,
  }) => SignInWithApple.getAppleIDCredential(scopes: scopes, nonce: nonce);

  final GetAppleIDCredential _getAppleIDCredential;
  final Random _random;

  static const _nonceChars =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';

  String _generateRawNonce([int length = 32]) => List.generate(
    length,
    (_) => _nonceChars[_random.nextInt(_nonceChars.length)],
  ).join();

  /// Runs the interactive Apple sheet and returns a Firebase credential ready
  /// for [User.linkWithCredential] / [FirebaseAuth.signInWithCredential],
  /// plus the fresh authorization code for delete-time revocation.
  ///
  /// Anti-replay: Apple receives the SHA-256 of the raw nonce; Firebase
  /// receives the raw nonce and verifies the token's hashed claim matches.
  /// Throws [SignInWithAppleAuthorizationException] (e.g. canceled) from the
  /// sheet; [StateError] when the sheet yields no identityToken.
  Future<AppleCredentialBundle> obtainCredential() async {
    final rawNonce = _generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final apple = await _getAppleIDCredential(
      scopes: const [AppleIDAuthorizationScopes.email],
      nonce: hashedNonce,
    );
    final idToken = apple.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Apple authorization returned no identityToken');
    }
    return (
      credential: AppleAuthProvider.credentialWithIDToken(
        idToken,
        rawNonce,
        AppleFullPersonName(),
      ),
      authorizationCode: apple.authorizationCode,
    );
  }
}
