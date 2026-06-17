// #278 PR9 — typed results for the claim/merge callables. Each factory parses
// the raw callable `result.data` (a JS-object map over the wire) defensively, so
// a server field that's missing/null degrades to a safe default rather than
// throwing. The keys here MUST match the callable output interfaces exactly
// (listUnclaimedShadows.ts / requestClaimShadow.ts / decideClaimRequest.ts /
// listMyClaimRequests.ts / listGroupClaimRequests.ts).

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
int? _millis(Object? v) => v is num ? v.toInt() : null;

/// A claimable placeholder member surfaced pre-join by `listUnclaimedShadows`.
class UnclaimedShadow {
  const UnclaimedShadow({required this.shadowMemberId, required this.displayName});

  final String shadowMemberId;
  final String displayName;

  static List<UnclaimedShadow> listFromData(Object? data) {
    final raw = (data is Map ? data['shadows'] : null) as List? ?? const [];
    return raw
        .whereType<Map>()
        .map((m) => UnclaimedShadow(
              shadowMemberId: _str(m['shadowMemberId']),
              displayName: _str(m['displayName'], 'Member'),
            ))
        .toList(growable: false);
  }
}

/// Result of `requestClaimShadow` — a pending claim request was (re)opened.
class ClaimRequestResult {
  const ClaimRequestResult({
    required this.requestId,
    required this.status,
    required this.groupId,
  });

  final String requestId;
  final String status;
  final String groupId;

  factory ClaimRequestResult.fromData(Object? data) {
    final m = data is Map ? data : const {};
    return ClaimRequestResult(
      requestId: _str(m['requestId']),
      status: _str(m['status']),
      groupId: _str(m['groupId']),
    );
  }
}

/// Result of `decideClaimRequest` — the creator approved/declined a request.
class ClaimDecisionResult {
  const ClaimDecisionResult({
    required this.requestId,
    required this.status,
    required this.alreadyClaimed,
  });

  final String requestId;
  final String status;
  final bool alreadyClaimed;

  factory ClaimDecisionResult.fromData(Object? data) {
    final m = data is Map ? data : const {};
    return ClaimDecisionResult(
      requestId: _str(m['requestId']),
      status: _str(m['status']),
      alreadyClaimed: m['alreadyClaimed'] == true,
    );
  }
}

/// One of the caller's own claim requests (from `listMyClaimRequests`).
class MyClaimRequest {
  const MyClaimRequest({
    required this.requestId,
    required this.shadowMemberId,
    required this.shadowDisplayName,
    required this.status,
    this.createdAtMillis,
  });

  final String requestId;
  final String shadowMemberId;
  final String shadowDisplayName;
  final String status;
  final int? createdAtMillis;

  static List<MyClaimRequest> listFromData(Object? data) {
    final raw = (data is Map ? data['requests'] : null) as List? ?? const [];
    return raw
        .whereType<Map>()
        .map((m) => MyClaimRequest(
              requestId: _str(m['requestId']),
              shadowMemberId: _str(m['shadowMemberId']),
              shadowDisplayName: _str(m['shadowDisplayName']),
              status: _str(m['status']),
              createdAtMillis: _millis(m['createdAtMillis']),
            ))
        .toList(growable: false);
  }
}

/// One pending claim request as seen by the creator (`listGroupClaimRequests`).
class GroupClaimRequest {
  const GroupClaimRequest({
    required this.requestId,
    required this.requesterUid,
    required this.requesterDisplayName,
    required this.shadowMemberId,
    required this.shadowDisplayName,
    required this.status,
    this.createdAtMillis,
  });

  final String requestId;
  final String requesterUid;
  final String requesterDisplayName;
  final String shadowMemberId;
  final String shadowDisplayName;
  final String status;
  final int? createdAtMillis;

  static List<GroupClaimRequest> listFromData(Object? data) {
    final raw = (data is Map ? data['requests'] : null) as List? ?? const [];
    return raw
        .whereType<Map>()
        .map((m) => GroupClaimRequest(
              requestId: _str(m['requestId']),
              requesterUid: _str(m['requesterUid']),
              requesterDisplayName: _str(m['requesterDisplayName'], 'Someone'),
              shadowMemberId: _str(m['shadowMemberId']),
              shadowDisplayName: _str(m['shadowDisplayName'], 'Member'),
              status: _str(m['status']),
              createdAtMillis: _millis(m['createdAtMillis']),
            ))
        .toList(growable: false);
  }
}
