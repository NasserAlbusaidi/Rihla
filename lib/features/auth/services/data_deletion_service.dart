import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/firebase_functions_service.dart';
import '../providers/auth_provider.dart';

typedef DeleteAccountCallable = Future<void> Function();

/// Outcome of an in-app deletion attempt. The UI maps each case to a
/// different snack/dialog.
enum DeletionResult { ok, noUser, error }

/// Server-side account deletion.
///
/// The Cloud Function performs the privileged Firestore/Auth cascade. The
/// client only starts the callable and signs out the now-deleted local
/// Firebase session. (On-device Firestore offline-cache cleanup is handled by
/// the UID-isolation barrier — issue #45 / PR 2 — not here.)
class DataDeletionService {
  DataDeletionService({
    required FirebaseAuth auth,
    DeleteAccountCallable? deleteAccountCallable,
  }) : _auth = auth,
       _deleteAccountCallable =
           deleteAccountCallable ??
           (() => FirebaseFunctionsService().deleteAccount());

  final FirebaseAuth _auth;
  final DeleteAccountCallable _deleteAccountCallable;

  Future<DeletionResult> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      FirebaseConfig.log('Deletion: no current user');
      return DeletionResult.noUser;
    }
    try {
      await _deleteAccountCallable();
      await _auth.signOut();
      FirebaseConfig.log('Deletion: server cascade completed');
      return DeletionResult.ok;
    } catch (error, stack) {
      FirebaseConfig.log(
        'Deletion: server cascade failed',
        error: error,
        stackTrace: stack,
      );
      return DeletionResult.error;
    }
  }
}

final dataDeletionServiceProvider = Provider<DataDeletionService>((ref) {
  return DataDeletionService(auth: ref.read(firebaseAuthProvider));
});
