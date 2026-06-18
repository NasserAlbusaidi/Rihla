import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/groups/models/claim_models.dart';
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

  // -------------------------------------------------------------------------
  // #278 PR9 — claim/merge. A real joiner discovers + requests a placeholder
  // ("shadow") member's spot pre-join (D8); the creator approves/declines. All
  // four PR8 callables + the PR9 discovery callable enforce App Check + reject
  // anonymous (D6). Each method PROPAGATES [FirebaseFunctionsException] so the
  // UI can branch on the code (internal = retryable; failed-precondition =
  // already-decided / claimer-present; permission-denied = non-creator).
  // -------------------------------------------------------------------------

  /// Discover claimable shadow members for an invite code, BEFORE joining.
  Future<List<UnclaimedShadow>> listUnclaimedShadows({
    required String inviteCode,
  }) async {
    final result = await _functions
        .httpsCallable('listUnclaimedShadows')
        .call({'inviteCode': inviteCode});
    return UnclaimedShadow.listFromData(result.data);
  }

  /// Open a claim request for a shadow (pre-join). Idempotent server-side.
  Future<ClaimRequestResult> requestClaimShadow({
    required String inviteCode,
    required String shadowMemberId,
    required String displayName,
  }) async {
    final result = await _functions.httpsCallable('requestClaimShadow').call({
      'inviteCode': inviteCode,
      'shadowMemberId': shadowMemberId,
      'displayName': displayName,
    });
    return ClaimRequestResult.fromData(result.data);
  }

  /// Creator approves/declines a claim request; approve runs the re-key engine.
  Future<ClaimDecisionResult> decideClaimRequest({
    required String groupId,
    required String requestId,
    required bool approve,
  }) async {
    final result = await _functions.httpsCallable('decideClaimRequest').call({
      'groupId': groupId,
      'requestId': requestId,
      'approve': approve,
    });
    return ClaimDecisionResult.fromData(result.data);
  }

  /// The requester polls their own claim requests' status (claimRequests is
  /// read-gated, so no client doc-listen).
  Future<List<MyClaimRequest>> listMyClaimRequests({
    required String inviteCode,
  }) async {
    final result = await _functions
        .httpsCallable('listMyClaimRequests')
        .call({'inviteCode': inviteCode});
    return MyClaimRequest.listFromData(result.data);
  }

  /// The creator polls the group's pending claim requests.
  Future<List<GroupClaimRequest>> listGroupClaimRequests({
    required String groupId,
  }) async {
    final result = await _functions
        .httpsCallable('listGroupClaimRequests')
        .call({'groupId': groupId});
    return GroupClaimRequest.listFromData(result.data);
  }
}
