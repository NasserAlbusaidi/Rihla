import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/firebase_functions_service.dart';
import '../../../core/services/local_database.dart';
import '../models/account_job_status.dart';
import '../models/delete_account_output.dart';
import '../providers/auth_provider.dart';

typedef DeleteAccountCallable = Future<DeleteAccountOutput> Function();
typedef StartOrResumeDeleteAccountJob =
    Future<AccountJobStatusSnapshot> Function();
typedef AdvanceDeleteAccountJob =
    Future<AccountJobStatusSnapshot> Function({required String jobId});
typedef GetDeleteAccountJobStatus =
    Future<AccountJobStatusSnapshot> Function({required String jobId});
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
    SharedPreferences? prefs,
    DeleteAccountCallable? deleteAccountCallable,
    StartOrResumeDeleteAccountJob? startOrResumeDeleteAccountJob,
    AdvanceDeleteAccountJob? advanceDeleteAccountJob,
    GetDeleteAccountJobStatus? getDeleteAccountJobStatus,
    LocalCacheWipe? wipeLocalCache,
  }) : _auth = auth,
       _prefs = prefs,
       _deleteAccountCallable =
           deleteAccountCallable ??
           (() => FirebaseFunctionsService().deleteAccount()),
       _startOrResumeDeleteAccountJob =
           startOrResumeDeleteAccountJob ??
           (() => FirebaseFunctionsService().startOrResumeDeleteAccountJob()),
       _advanceDeleteAccountJob =
           advanceDeleteAccountJob ??
           (({required jobId}) => FirebaseFunctionsService()
               .advanceDeleteAccountJob(jobId: jobId)),
       _getDeleteAccountJobStatus =
           getDeleteAccountJobStatus ??
           (({required jobId}) => FirebaseFunctionsService()
               .getDeleteAccountJobStatus(jobId: jobId)),
       _wipeLocalCache = wipeLocalCache ?? LocalDatabase.wipeAndReinitialize;

  final FirebaseAuth _auth;
  final SharedPreferences? _prefs;
  final DeleteAccountCallable _deleteAccountCallable;
  final StartOrResumeDeleteAccountJob _startOrResumeDeleteAccountJob;
  final AdvanceDeleteAccountJob _advanceDeleteAccountJob;
  final GetDeleteAccountJobStatus _getDeleteAccountJobStatus;
  final LocalCacheWipe _wipeLocalCache;

  static const _pendingDeletionJobIdKey = 'auth.pendingDeletionJobId';

  Future<DeletionResult> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      FirebaseConfig.log('Deletion: no current user');
      return const DeletionNoUser();
    }
    if (_prefs != null) {
      return _deleteAccountViaJob();
    }
    return _deleteAccountViaLegacyCallable();
  }

  Future<AccountJobStatusSnapshot?> resumePendingDeletion() async {
    final jobId = _prefs?.getString(_pendingDeletionJobIdKey);
    if (jobId == null || jobId.isEmpty) return null;
    final status = await _getDeleteAccountJobStatus(jobId: jobId);
    if (status.status == AccountJobRunStatus.complete) {
      final output = _outputFromStatus(status);
      if (output == null) {
        await _clearPendingDeletion();
        return null;
      }
      final localResult = await _finishLocalDeletion(output);
      if (_serverDeletionNoLongerResumable(localResult)) {
        await _clearPendingDeletion();
        return null;
      }
      return status.copyWith(
        status: AccountJobRunStatus.failed,
        retryable: true,
        errorCode: 'local-cleanup-failed',
      );
    }
    return status;
  }

  Future<AccountJobStatusSnapshot> advanceAccountJob(
    AccountJobStatusSnapshot status,
  ) async {
    if (status.kind != AccountJobKind.deleteAccount) return status;
    final next = await _advanceDeleteAccountJob(jobId: status.jobId);
    if (next.status != AccountJobRunStatus.complete) return next;

    final output = _outputFromStatus(next);
    if (output == null) {
      return next.copyWith(
        status: AccountJobRunStatus.failed,
        retryable: true,
        errorCode: 'missing-output',
      );
    }
    final localResult = await _finishLocalDeletion(output);
    if (_serverDeletionNoLongerResumable(localResult)) {
      await _clearPendingDeletion();
      return next;
    }
    return next.copyWith(
      status: AccountJobRunStatus.failed,
      retryable: true,
      errorCode: 'local-cleanup-failed',
    );
  }

  Future<DeletionResult> _deleteAccountViaJob() async {
    AccountJobStatusSnapshot status;
    try {
      status = await _startOrResumeDeleteAccountJob();
      await _storePendingDeletion(status.jobId);
      if (status.status == AccountJobRunStatus.failed && status.retryable) {
        status = await _advanceDeleteAccountJob(jobId: status.jobId);
      }
      while (status.status == AccountJobRunStatus.running) {
        status = await _advanceDeleteAccountJob(jobId: status.jobId);
      }
    } catch (error, stack) {
      FirebaseConfig.log(
        'Deletion: server job failed',
        error: error,
        stackTrace: stack,
      );
      return DeletionError(error);
    }

    final output = _outputFromStatus(status);
    if (status.status == AccountJobRunStatus.failed) {
      if (status.errorCode == 'auth-delete-failed' && output != null) {
        FirebaseConfig.log('Deletion: server scrubbed data but auth failed');
        return DeletionServerScrubbedAuthDeleteFailed(output);
      }
      return DeletionError(
        StateError('Deletion job failed (${status.errorCode ?? status.phase})'),
      );
    }
    if (status.status != AccountJobRunStatus.complete || output == null) {
      return DeletionError(
        StateError('Deletion job did not complete (${status.status.wireName})'),
      );
    }

    final result = await _finishLocalDeletion(output);
    if (_serverDeletionNoLongerResumable(result)) await _clearPendingDeletion();
    return result;
  }

  Future<DeletionResult> _deleteAccountViaLegacyCallable() async {
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

  Future<DeletionResult> _finishLocalDeletion(
    DeleteAccountOutput output,
  ) async {
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

  Future<void> _storePendingDeletion(String jobId) async {
    if (_prefs == null) return;
    await _prefs.setString(_pendingDeletionJobIdKey, jobId);
  }

  Future<void> _clearPendingDeletion() async {
    await _prefs?.remove(_pendingDeletionJobIdKey);
  }

  DeleteAccountOutput? _outputFromStatus(AccountJobStatusSnapshot status) {
    final output = status.output;
    if (output == null) return null;
    return DeleteAccountOutput.fromJson(output);
  }

  bool _serverDeletionNoLongerResumable(DeletionResult result) {
    return result is DeletionOk || result is DeletionLocalCleanupFailed;
  }
}

final dataDeletionServiceProvider = Provider<DataDeletionService>((ref) {
  return DataDeletionService(
    auth: ref.read(firebaseAuthProvider),
    prefs: ref.watch(sharedPreferencesProvider),
  );
});
