import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../providers/auth_provider.dart';

/// Outcome of an in-app deletion attempt. The UI maps each case to a
/// different snack/dialog. `requiresRecentLogin` is the only branch the
/// user can recover from without contacting support — they sign out, sign
/// back in via the linked email, and retry.
enum DeletionResult { ok, requiresRecentLogin, noUser, error }

/// Best-effort in-app account deletion (account-recovery spec §6.2 +
/// plan §P6).
///
/// v1.2 scope: deletes the Firebase Auth user record. Cascading the
/// user's Firestore data (participant docs, authored expenses) is best
/// handled by an `auth.user.onDelete()` Cloud Function — wired in a
/// follow-up sprint. Until then, the auth deletion alone makes the data
/// unreachable from any app session because Firestore rules treat
/// `auth.uid` as the membership key.
class DataDeletionService {
  DataDeletionService({required FirebaseAuth auth}) : _auth = auth;

  final FirebaseAuth _auth;

  Future<DeletionResult> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      FirebaseConfig.log('Deletion: no current user');
      return DeletionResult.noUser;
    }
    try {
      await user.delete();
      FirebaseConfig.log('Deletion: auth user deleted');
      return DeletionResult.ok;
    } on FirebaseAuthException catch (error, stack) {
      if (error.code == 'requires-recent-login') {
        FirebaseConfig.log('Deletion: requires-recent-login');
        return DeletionResult.requiresRecentLogin;
      }
      FirebaseConfig.log(
        'Deletion: FirebaseAuthException ${error.code}',
        error: error,
        stackTrace: stack,
      );
      return DeletionResult.error;
    } catch (error, stack) {
      FirebaseConfig.log(
        'Deletion: unexpected failure',
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
