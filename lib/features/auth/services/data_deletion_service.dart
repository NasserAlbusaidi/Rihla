import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/cache_isolation_controller.dart';
import '../../../core/services/cache_uid_barrier.dart';
import '../../../core/services/firebase_functions_service.dart';
import '../../../core/services/post_deletion_auth_barrier.dart';
import '../providers/auth_provider.dart';
import '../providers/cache_isolation_controller_provider.dart';
import 'apple_sign_in_gateway.dart';
import 'auth_recovery_service.dart';
import 'durable_account_marker.dart';

typedef DeleteAccountCallable = Future<void> Function();

/// Outcome of an in-app deletion attempt. The UI maps each case to a
/// different snack/dialog.
///
/// [partial] is the convergent-on-retry case: the server scrubbed some (or all)
/// data but threw before finishing (a per-group cascade failure, or the final
/// Auth-user delete failing). The session stays valid and a retry converges, so
/// the UI re-prompts to retry rather than signing out.
enum DeletionResult { ok, noUser, error, partial }

/// Server-side account deletion.
///
/// The Cloud Function performs the privileged Firestore/Auth cascade. After it
/// succeeds the account is gone server-side, so the client treats the local
/// teardown as a cross-UID swap (#45): mark the Firestore SDK cache dirty,
/// sign out, and trigger a true restart. The cold-boot barrier clears the
/// deleted UID's on-device cache before the first read. Isolation is engaged
/// only AFTER the cascade succeeds, so a failed cascade leaves the user on a
/// clean error path with no overlay.
class DataDeletionService {
  DataDeletionService({
    required FirebaseAuth auth,
    required SharedPreferences prefs,
    required CacheIsolationController cacheIsolationController,
    DeleteAccountCallable? deleteAccountCallable,
    AppleCredentialFactory? appleCredentialFactory,
  }) : _auth = auth,
       _prefs = prefs,
       _cacheIsolationController = cacheIsolationController,
       _deleteAccountCallable =
           deleteAccountCallable ??
           (() => FirebaseFunctionsService().deleteAccount()),
       _appleCredentialFactory =
           appleCredentialFactory ?? _defaultAppleCredentialFactory;

  final FirebaseAuth _auth;
  final SharedPreferences _prefs;
  final CacheIsolationController _cacheIsolationController;
  final DeleteAccountCallable _deleteAccountCallable;
  final AppleCredentialFactory _appleCredentialFactory;

  /// Shared gateway, mirroring [AuthRecoveryService]'s default.
  static final AppleSignInGateway _defaultAppleGateway = AppleSignInGateway();

  static Future<AppleCredentialBundle> _defaultAppleCredentialFactory() =>
      _defaultAppleGateway.obtainCredential();

  /// 5.1.1(v): apps offering Sign in with Apple must revoke the user's Apple
  /// token on account deletion (#1256). Apple authorization codes are
  /// single-use and short-lived, so a FRESH interactive authorization is
  /// required here — the link-time code is long expired. Best-effort by
  /// design: a cancel/offline/Apple failure logs and proceeds; deletion is
  /// never hostage to the Apple round-trip (the server cascade + deleteUser
  /// still sever the link).
  Future<void> _revokeAppleTokenBestEffort(User user) async {
    final hasApple = user.providerData.any((p) => p.providerId == 'apple.com');
    if (!hasApple) return;
    try {
      final bundle = await _appleCredentialFactory();
      final code = bundle.authorizationCode;
      if (code == null || code.isEmpty) {
        FirebaseConfig.log('Deletion: Apple revoke skipped (no auth code)');
        return;
      }
      await _auth.revokeTokenWithAuthorizationCode(code);
      FirebaseConfig.log('Deletion: Apple token revoked');
    } catch (error, stack) {
      FirebaseConfig.log(
        'Deletion: Apple revoke failed (non-fatal)',
        error: error,
        stackTrace: stack,
      );
    }
  }

  Future<DeletionResult> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      FirebaseConfig.log('Deletion: no current user');
      return DeletionResult.noUser;
    }
    await _revokeAppleTokenBestEffort(user);
    try {
      await _deleteAccountCallable();
    } catch (error, stack) {
      final result = _classifyFailure(error);
      FirebaseConfig.log(
        result == DeletionResult.partial
            ? 'Deletion: partial server cascade (convergent on retry)'
            : 'Deletion: server cascade failed',
        error: error,
        stackTrace: stack,
      );
      return result;
    }

    // Cascade succeeded — the account is gone server-side. Persist the UID so
    // a failed local signOut can be identified and retried on the cold boot.
    FirebaseConfig.log('Deletion: server cascade completed');
    await markExpectedDeletedUid(_prefs, user.uid);
    // #469: the durable account is gone — clear the device marker BEFORE the
    // restart (and before engageIsolation, outside the teardown try whose
    // signOut() could throw and skip it) so the next fresh-anon session is not
    // falsely blocked from deleting. Awaited so it flushes before the process
    // exits via restart().
    await clearDurableAccountEstablished(_prefs);
    _cacheIsolationController.engageIsolation();
    try {
      await markFirestorePersistenceDirty(_prefs);
      await _auth.signOut();
    } catch (error, stack) {
      FirebaseConfig.log(
        'Deletion: post-cascade local teardown failed (non-fatal)',
        error: error,
        stackTrace: stack,
      );
    } finally {
      await _cacheIsolationController.restart();
    }
    return DeletionResult.ok;
  }
}

/// Distinguishes a convergent partial deletion from a hard failure.
///
/// The server throws `HttpsError('internal', …, DeleteAccountOutput)` in two
/// convergent cases: a per-group cascade failure (`cascadeFailed` non-empty) or
/// a fully-scrubbed-but-Auth-alive failure (`cascadeFailed` empty,
/// `authUserDeleted: false`). Both carry the typed output in `details` and
/// converge on retry. Every other error (rate limit, auth, malformed input,
/// network) is a generic, non-convergent failure.
///
/// We require `cascadeFailed` to actually be a List (it's always a string array
/// in both convergent cases, possibly empty) rather than merely present — a
/// malformed platform response should fail loud as a generic error, not be
/// mistaken for a retryable partial on a destructive path.
DeletionResult _classifyFailure(Object error) {
  if (error is FirebaseFunctionsException &&
      error.code == 'internal' &&
      error.details is Map &&
      (error.details as Map)['cascadeFailed'] is List) {
    return DeletionResult.partial;
  }
  return DeletionResult.error;
}

final dataDeletionServiceProvider = Provider<DataDeletionService>((ref) {
  return DataDeletionService(
    auth: ref.read(firebaseAuthProvider),
    prefs: ref.read(sharedPreferencesProvider),
    cacheIsolationController: ref.read(cacheIsolationControllerProvider),
  );
});
