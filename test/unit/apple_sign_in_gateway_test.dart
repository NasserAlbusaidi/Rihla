import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/services/apple_sign_in_gateway.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

AuthorizationCredentialAppleID _appleId({
  String? identityToken = 'stub-identity-token',
  String authorizationCode = 'stub-auth-code',
}) {
  return AuthorizationCredentialAppleID(
    userIdentifier: 'user-1',
    givenName: null,
    familyName: null,
    authorizationCode: authorizationCode,
    email: null,
    identityToken: identityToken,
    state: null,
  );
}

void main() {
  test('passes the SHA-256 of the raw nonce to Apple, raw to Firebase',
      () async {
    String? capturedNonce;
    final gateway = AppleSignInGateway(
      getAppleIDCredential: ({required scopes, String? nonce}) async {
        capturedNonce = nonce;
        return _appleId();
      },
    );

    final bundle = await gateway.obtainCredential();

    final oauth = bundle.credential as OAuthCredential;
    final rawNonce = oauth.rawNonce;
    expect(rawNonce, isNotNull);
    expect(rawNonce, hasLength(32));
    expect(
      capturedNonce,
      sha256.convert(utf8.encode(rawNonce!)).toString(),
    );
  });

  test('returns an apple.com OAuthCredential + pass-through auth code',
      () async {
    final gateway = AppleSignInGateway(
      getAppleIDCredential: ({required scopes, String? nonce}) async =>
          _appleId(authorizationCode: 'code-xyz'),
    );

    final bundle = await gateway.obtainCredential();

    final oauth = bundle.credential as OAuthCredential;
    expect(oauth.providerId, 'apple.com');
    expect(oauth.idToken, 'stub-identity-token');
    expect(bundle.authorizationCode, 'code-xyz');
  });

  test('null identityToken throws StateError', () async {
    final gateway = AppleSignInGateway(
      getAppleIDCredential: ({required scopes, String? nonce}) async =>
          _appleId(identityToken: null),
    );

    await expectLater(gateway.obtainCredential(), throwsStateError);
  });

  test('empty identityToken throws StateError', () async {
    final gateway = AppleSignInGateway(
      getAppleIDCredential: ({required scopes, String? nonce}) async =>
          _appleId(identityToken: ''),
    );

    await expectLater(gateway.obtainCredential(), throwsStateError);
  });

  test('SignInWithAppleAuthorizationException propagates unchanged', () async {
    const cancel = SignInWithAppleAuthorizationException(
      code: AuthorizationErrorCode.canceled,
      message: 'user canceled',
    );
    final gateway = AppleSignInGateway(
      getAppleIDCredential: ({required scopes, String? nonce}) async =>
          throw cancel,
    );

    await expectLater(
      gateway.obtainCredential(),
      throwsA(same(cancel)),
    );
  });

  test('default (un-injected) path reaches the real package call and throws '
      'in a test environment — no silent success without a platform', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final gateway = AppleSignInGateway();

    // No platform channel is live in unit tests: the ONLY acceptable outcome
    // is a throw. A completed credential here would mean the default seam
    // no longer calls the real plugin.
    await expectLater(gateway.obtainCredential(), throwsA(anything));
  });

  test('two calls produce different nonces', () async {
    final captured = <String?>[];
    final gateway = AppleSignInGateway(
      getAppleIDCredential: ({required scopes, String? nonce}) async {
        captured.add(nonce);
        return _appleId();
      },
      random: Random(7),
    );

    await gateway.obtainCredential();
    await gateway.obtainCredential();

    expect(captured, hasLength(2));
    expect(captured[0], isNot(captured[1]));
  });
}
