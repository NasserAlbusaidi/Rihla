import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Thin adapter over the google_sign_in 7.x singleton (#441 PR1).
///
/// Owns the one-time [GoogleSignIn.initialize] handshake and converts the
/// Credential Manager result into a Firebase [AuthCredential], so
/// [AuthRecoveryService] stays unit-testable behind a `GoogleCredentialFactory`
/// seam — the plugin singleton needs live platform channels.
class GoogleSignInGateway {
  GoogleSignInGateway({GoogleSignIn? googleSignIn, String? serverClientId})
    : _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
      _serverClientId = serverClientId ?? defaultServerClientId;

  /// The Firebase project's WEB OAuth client ID, injected via config.json.
  ///
  /// Required on Android for an idToken: Firebase init here is Dart-only (no
  /// com.google.gms.google-services Gradle plugin), so the
  /// `default_web_client_id` resource google_sign_in would otherwise read
  /// does not exist.
  static const defaultServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  final GoogleSignIn _googleSignIn;
  final String _serverClientId;
  bool _initialized = false;

  /// Runs the interactive Google sign-in sheet and returns a credential ready
  /// for [User.linkWithCredential] or [FirebaseAuth.signInWithCredential].
  ///
  /// Throws [StateError] when `GOOGLE_SERVER_CLIENT_ID` is missing from
  /// config.json or the sheet yields no idToken; propagates
  /// [GoogleSignInException] (e.g. canceled) from the sheet itself.
  Future<AuthCredential> obtainCredential() async {
    if (_serverClientId.trim().isEmpty) {
      throw StateError(
        'GOOGLE_SERVER_CLIENT_ID is not configured — add the Firebase '
        "project's web OAuth client ID to config.json",
      );
    }
    if (!_initialized) {
      await _googleSignIn.initialize(serverClientId: _serverClientId);
      _initialized = true;
    }
    final account = await _googleSignIn.authenticate(
      scopeHint: const ['email'],
    );
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google authentication returned no idToken');
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }
}
