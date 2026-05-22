import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/firebase_functions_service.dart';
import '../../../core/services/local_database.dart';
import '../models/delete_account_output.dart';
import '../providers/auth_provider.dart';

typedef DeleteAccountCallable = Future<DeleteAccountOutput> Function();
typedef LocalCacheWipe = Future<void> Function();

sealed class DeletionResult {
  const DeletionResult();
}

class DeletionOk extends DeletionResult {
  const DeletionOk(this.output);
  final DeleteAccountOutput output;
}

class DeletionNoUser extends DeletionResult {
  const DeletionNoUser();
}

class DeletionServerScrubbedAuthDeleteFailed extends DeletionResult {
  const DeletionServerScrubbedAuthDeleteFailed(this.output);
  final DeleteAccountOutput output;
}

class DeletionLocalCleanupFailed extends DeletionResult {
  const DeletionLocalCleanupFailed({required this.output, required this.error});

  final DeleteAccountOutput output;
  final Object error;
}

class DeletionLocalSignOutFailed extends DeletionResult {
  const DeletionLocalSignOutFailed({required this.output, required this.error});

  final DeleteAccountOutput output;
  final Object error;
}

class DeletionError extends DeletionResult {
  const DeletionError(this.error);
  final Object error;
}

/// Server-side account deletion.
///
/// The Cloud Function performs the privileged Firestore/Auth cascade. The
/// client only starts the callable, clears its per-UID SQLite cache, and signs
/// out the now-deleted local Firebase session.
class DataDeletionService {
  DataDeletionService({
    required FirebaseAuth auth,
    DeleteAccountCallable? deleteAccountCallable,
    LocalCacheWipe? wipeLocalCache,
  }) : _auth = auth,
       _deleteAccountCallable =
           deleteAccountCallable ??
           (() => FirebaseFunctionsService().deleteAccount()),
       _wipeLocalCache = wipeLocalCache ?? LocalDatabase.wipeAndReinitialize;

  final FirebaseAuth _auth;
  final DeleteAccountCallable _deleteAccountCallable;
  final LocalCacheWipe _wipeLocalCache;

  Future<DeletionResult> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      FirebaseConfig.log('Deletion: no current user');
      return const DeletionNoUser();
    }
    DeleteAccountOutput output;
    try {
      output = await _deleteAccountCallable();
    } on DeleteAccountPartialFailure catch (error, stack) {
      FirebaseConfig.log(
        'Deletion: server scrubbed data but auth delete failed',
        error: error,
        stackTrace: stack,
      );
      return DeletionServerScrubbedAuthDeleteFailed(error.output);
    } catch (error, stack) {
      FirebaseConfig.log(
        'Deletion: server cascade failed',
        error: error,
        stackTrace: stack,
      );
      return DeletionError(error);
    }

    Object? localWipeError;
    try {
      await _wipeLocalCache();
    } catch (error, stack) {
      localWipeError = error;
      FirebaseConfig.log(
        'Deletion: local cache wipe failed after server cascade',
        error: error,
        stackTrace: stack,
      );
    }

    try {
      await _auth.signOut();
    } catch (error, stack) {
      FirebaseConfig.log(
        'Deletion: local sign-out failed after server cascade',
        error: error,
        stackTrace: stack,
      );
      return DeletionLocalSignOutFailed(output: output, error: error);
    }

    if (localWipeError != null) {
      return DeletionLocalCleanupFailed(output: output, error: localWipeError);
    }

    FirebaseConfig.log('Deletion: server cascade completed');
    return DeletionOk(output);
  }
}

final dataDeletionServiceProvider = Provider<DataDeletionService>((ref) {
  return DataDeletionService(auth: ref.read(firebaseAuthProvider));
});
