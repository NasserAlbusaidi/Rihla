import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/firebase_config.dart';

/// Provider for [FirebaseFunctionsService]. Override in tests to inject a fake
/// (e.g. the #190 deleteGroup callable) without touching Firebase.
final firebaseFunctionsServiceProvider = Provider<FirebaseFunctionsService>(
  (ref) => FirebaseFunctionsService(),
);

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

  /// Invoke the server-authoritative `deleteGroup` callable (#190).
  ///
  /// The server recomputes per-actor net balances, refuses with
  /// `failed-precondition` on any non-zero net, then soft-deletes the group +
  /// its events. Throws [FirebaseFunctionsException] which callers map to UX.
  Future<void> deleteGroup({required String groupId}) async {
    await _functions.httpsCallable('deleteGroup').call({'groupId': groupId});
  }

  /// Invoke the server-authoritative `leaveGroup` callable (#290).
  ///
  /// The server recomputes the LEAVER's net balance, refuses with
  /// `failed-precondition` on a non-zero net, then removes the uid from
  /// `memberIds` + deletes their member doc + logs `member_left`. Replaces the
  /// old client-side batch whose balance gate was skipped when balances were
  /// null (offline) — orphaning debt. Throws [FirebaseFunctionsException].
  Future<void> leaveGroup({required String groupId}) async {
    await _functions.httpsCallable('leaveGroup').call({'groupId': groupId});
  }

  /// Invoke the server-authoritative `removeMember` callable (#318).
  ///
  /// The creator-only callable recomputes the TARGET member's net balance,
  /// refuses with `failed-precondition` on a non-zero net, then removes the
  /// target uid from `memberIds` + deletes their member doc + logs
  /// `member_left`. Replaces the old client-side batch whose balance gate was
  /// skipped when balances were null (offline) — orphaning debt. Throws
  /// [FirebaseFunctionsException].
  Future<void> removeMember({
    required String groupId,
    required String targetUserId,
  }) async {
    await _functions
        .httpsCallable('removeMember')
        .call({'groupId': groupId, 'targetUserId': targetUserId});
  }
}
