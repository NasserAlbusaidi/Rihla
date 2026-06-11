import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/features/auth/services/google_sign_in_gateway.dart';

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockAccount extends Mock implements GoogleSignInAccount {}

void main() {
  late _MockGoogleSignIn googleSignIn;

  setUp(() {
    googleSignIn = _MockGoogleSignIn();
    when(
      () => googleSignIn.initialize(
        serverClientId: any(named: 'serverClientId'),
      ),
    ).thenAnswer((_) async {});
  });

  _MockAccount accountWithIdToken(String? idToken) {
    final account = _MockAccount();
    when(
      () => account.authentication,
    ).thenReturn(GoogleSignInAuthentication(idToken: idToken));
    return account;
  }

  test('throws StateError when GOOGLE_SERVER_CLIENT_ID is missing, '
      'without touching the plugin', () async {
    // Test env has no dart-defines, so defaultServerClientId is empty.
    final gateway = GoogleSignInGateway(googleSignIn: googleSignIn);

    await expectLater(gateway.obtainCredential(), throwsStateError);
    verifyNever(
      () => googleSignIn.initialize(
        serverClientId: any(named: 'serverClientId'),
      ),
    );
  });

  test('initializes once with the server client id and returns a Google '
      'credential carrying the idToken', () async {
    when(
      () => googleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
    ).thenAnswer((_) async => accountWithIdToken('id-token-1'));
    final gateway = GoogleSignInGateway(
      googleSignIn: googleSignIn,
      serverClientId: 'client-id.apps.googleusercontent.com',
    );

    final first = await gateway.obtainCredential();
    final second = await gateway.obtainCredential();

    expect(first, isA<OAuthCredential>());
    final oauth = first as OAuthCredential;
    expect(oauth.providerId, GoogleAuthProvider.PROVIDER_ID);
    expect(oauth.idToken, 'id-token-1');
    expect(second, isA<OAuthCredential>());
    verify(
      () => googleSignIn.initialize(
        serverClientId: 'client-id.apps.googleusercontent.com',
      ),
    ).called(1);
    verify(
      () => googleSignIn.authenticate(scopeHint: const ['email']),
    ).called(2);
  });

  test('throws StateError when the sheet yields no idToken', () async {
    when(
      () => googleSignIn.authenticate(scopeHint: any(named: 'scopeHint')),
    ).thenAnswer((_) async => accountWithIdToken(null));
    final gateway = GoogleSignInGateway(
      googleSignIn: googleSignIn,
      serverClientId: 'client-id.apps.googleusercontent.com',
    );

    await expectLater(gateway.obtainCredential(), throwsStateError);
  });
}
