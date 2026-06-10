import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/firebase_config.dart';

/// Provider for [FirebaseFunctionsService]. Override in tests to inject a fake
/// (e.g. the #190 deleteGroup callable) without touching Firebase.
final firebaseFunctionsServiceProvider = Provider<FirebaseFunctionsService>(
  (ref) => FirebaseFunctionsService(),
);

/// Structured result of the `cleanupAnonUidArtifacts` callable (#427).
///
/// The server consumes the cleanup intent (and deletes the old Auth user)
/// only when EVERY group migrated — a non-empty [cascadeFailed] means those
/// groups still carry the old UID and the intent was kept for a retry.
class CleanupOutcome {
  const CleanupOutcome({required this.cascadeFailed});

  final List<String> cascadeFailed;

  bool get complete => cascadeFailed.isEmpty;
}

class FirebaseFunctionsService {
  FirebaseFunctionsService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseConfig.functions;

  final FirebaseFunctions _functions;

  Future<CleanupOutcome> cleanupAnonUidArtifacts({
    required String oldUid,
    required String cleanupSecret,
  }) async {
    final result = await _functions
        .httpsCallable('cleanupAnonUidArtifacts')
        .call({'oldUid': oldUid, 'cleanupSecret': cleanupSecret});
    final raw = (result.data is Map)
        ? (result.data as Map)['cascadeFailed']
        : null;
    return CleanupOutcome(
      cascadeFailed: (raw is List)
          ? raw.whereType<String>().toList(growable: false)
          : const [],
    );
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
