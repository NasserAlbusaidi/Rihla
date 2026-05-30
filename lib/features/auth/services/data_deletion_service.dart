import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/cache_isolation_controller.dart';
import '../../../core/services/cache_uid_barrier.dart';
import '../../../core/services/firebase_functions_service.dart';
import '../providers/auth_provider.dart';
import '../providers/cache_isolation_controller_provider.dart';

typedef DeleteAccountCallable = Future<void> Function();

/// Outcome of an in-app deletion attempt. The UI maps each case to a
/// different snack/dialog.
enum DeletionResult { ok, noUser, error }

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
  }) : _auth = auth,
       _prefs = prefs,
       _cacheIsolationController = cacheIsolationController,
       _deleteAccountCallable =
           deleteAccountCallable ??
           (() => FirebaseFunctionsService().deleteAccount());

  final FirebaseAuth _auth;
  final SharedPreferences _prefs;
  final CacheIsolationController _cacheIsolationController;
  final DeleteAccountCallable _deleteAccountCallable;

  Future<DeletionResult> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      FirebaseConfig.log('Deletion: no current user');
      return DeletionResult.noUser;
    }
    try {
      await _deleteAccountCallable();
    } catch (error, stack) {
      FirebaseConfig.log(
        'Deletion: server cascade failed',
        error: error,
        stackTrace: stack,
      );
      return DeletionResult.error;
    }

    // Cascade succeeded — the account is gone server-side. Engage isolation,
    // mark the cache dirty, then restart. Local signOut is best-effort: the
    // cold boot re-mints a fresh anon and the barrier clears the deleted UID's
    // cache regardless (the new UID also differs from the last-active marker).
    FirebaseConfig.log('Deletion: server cascade completed');
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

final dataDeletionServiceProvider = Provider<DataDeletionService>((ref) {
  return DataDeletionService(
    auth: ref.read(firebaseAuthProvider),
    prefs: ref.read(sharedPreferencesProvider),
    cacheIsolationController: ref.read(cacheIsolationControllerProvider),
  );
});
