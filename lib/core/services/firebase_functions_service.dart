import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/groups/models/claim_models.dart';
import '../../features/ledger/models/correct_settlement_result.dart';
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

  // -------------------------------------------------------------------------
  // #889 — server-authoritative settlement corrections. Replace the old
  // client-direct reverse writes (solo `onCorrect` sites + the deleted
  // `SettlementCorrectionService` WriteBatch) so every reverse row carries the
  // un-forgeable `correctionOfSettlementId` marker (rules deny the key on
  // client creates). Corrections are ONLINE-ONLY (HTTPS callables don't use
  // Firestore's offline write queue) — callers must never show queued-success
  // copy on these paths. Append-only (B3): originals are never mutated.
  // -------------------------------------------------------------------------

  /// Invoke the `correctSettlement` callable — a solo correction of one
  /// recorded payment, `scope: 'event'` (settle_up_screen.dart) or
  /// `scope: 'group'` (group_settle_up_screen.dart standalone correction).
  /// Throws [FirebaseFunctionsException] which callers map to UX.
  Future<CorrectSettlementResult> correctSettlement({
    required String groupId,
    required String scope,
    String? eventId,
    required String settlementId,
    required String correctionNote,
  }) async {
    final result = await _functions.httpsCallable('correctSettlement').call({
      'groupId': groupId,
      'scope': scope,
      'eventId': ?eventId,
      'settlementId': settlementId,
      'correctionNote': correctionNote,
    });
    return CorrectSettlementResult.fromData(result.data);
  }

  /// Invoke the `correctLogicalSettleUp` callable — reverses every live doc
  /// (event-scope slices + group-scope residual) sharing one `groupSettleUpId`
  /// atomically. Replaces the deleted `SettlementCorrectionService` client
  /// `WriteBatch` (#753) — the server validates the FULL logical set, past
  /// what rules-side `get()` validation on a client batch could afford for a
  /// large settle-up. Throws [FirebaseFunctionsException].
  Future<CorrectSettlementResult> correctLogicalSettleUp({
    required String groupId,
    required String groupSettleUpId,
    required String correctionNote,
  }) async {
    final result = await _functions
        .httpsCallable('correctLogicalSettleUp')
        .call({
          'groupId': groupId,
          'groupSettleUpId': groupSettleUpId,
          'correctionNote': correctionNote,
        });
    return CorrectSettlementResult.fromData(result.data);
  }
}
