import 'package:cloud_functions/cloud_functions.dart';

import '../../features/auth/models/account_job_status.dart';
import '../config/firebase_config.dart';

class FirebaseFunctionsService {
  FirebaseFunctionsService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseConfig.functions;

  final FirebaseFunctions _functions;

  Future<void> cleanupAnonUidArtifacts({
    required String oldUid,
    required String cleanupSecret,
  }) async {
    await _functions.httpsCallable('cleanupAnonUidArtifacts').call({
      'oldUid': oldUid,
      'cleanupSecret': cleanupSecret,
    });
  }

  Future<AccountJobStatusSnapshot> claimRecoveryCleanupJob({
    required String oldUid,
    required String cleanupSecret,
  }) async {
    final result = await _functions
        .httpsCallable('claimRecoveryCleanupJob')
        .call({'oldUid': oldUid, 'cleanupSecret': cleanupSecret});
    return AccountJobStatusSnapshot.fromJson(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  Future<AccountJobStatusSnapshot> advanceRecoveryCleanupJob({
    required String jobId,
  }) async {
    final result = await _functions
        .httpsCallable('advanceRecoveryCleanupJob')
        .call({'jobId': jobId});
    return AccountJobStatusSnapshot.fromJson(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  Future<AccountJobStatusSnapshot> getRecoveryCleanupJobStatus({
    required String jobId,
  }) async {
    final result = await _functions
        .httpsCallable('getRecoveryCleanupJobStatus')
        .call({'jobId': jobId});
    return AccountJobStatusSnapshot.fromJson(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  Future<void> deleteAccount() async {
    await _functions.httpsCallable('deleteAccount').call(<String, dynamic>{});
  }
}
