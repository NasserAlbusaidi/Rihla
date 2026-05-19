import 'package:cloud_functions/cloud_functions.dart';

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

  Future<void> deleteAccount() async {
    await _functions.httpsCallable('deleteAccount').call(<String, dynamic>{});
  }
}
