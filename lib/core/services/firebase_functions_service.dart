import 'package:cloud_functions/cloud_functions.dart';

import '../config/firebase_config.dart';

class FirebaseFunctionsService {
  FirebaseFunctionsService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseConfig.functions;

  final FirebaseFunctions _functions;

  Future<void> cleanupAnonUidArtifacts({required String oldUid}) async {
    await _functions.httpsCallable('cleanupAnonUidArtifacts').call({
      'oldUid': oldUid,
    });
  }
}
