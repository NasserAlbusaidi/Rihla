/// #1129: the `recordSettlement` callable's result — the client's only signal
/// about a settlement create (settlement creates are callable-only; there is
/// no optimistic local write to read back). Parsed FAIL-SAFE: a malformed or
/// missing field degrades to the conservative default (nothing recorded twice,
/// no missed ledger bump) rather than throwing in a success path.
class RecordSettlementResult {
  const RecordSettlementResult({
    required this.alreadyRecorded,
    required this.eventScopeWrites,
    required this.groupScopeWrites,
    required this.shouldBumpLedgerRevision,
    required this.settledAt,
  });

  /// True when this call was an idempotent replay of an already-recorded
  /// payment (network retry, or the #1093 same-observed-state racer): the
  /// payment exists exactly once and the UI shows "already recorded" copy —
  /// and MUST NOT re-offer the #367 WhatsApp nudge.
  final bool alreadyRecorded;

  final int eventScopeWrites;
  final int groupScopeWrites;

  /// Mirrors the correction-flow contract: event-scope content changed, so the
  /// home once-provider needs a `ledgerRevisionProvider` bump. Pure group
  /// writes return false (the once-provider watches group settlements live).
  final bool shouldBumpLedgerRevision;

  /// Server-stamped ISO instant shared by every doc of the call.
  final String settledAt;

  static RecordSettlementResult fromData(Object? data) {
    final map = data is Map ? data : const <Object?, Object?>{};
    final eventScopeWrites = map['eventScopeWrites'];
    final groupScopeWrites = map['groupScopeWrites'];
    final settledAt = map['settledAt'];
    return RecordSettlementResult(
      alreadyRecorded: map['alreadyRecorded'] == true,
      eventScopeWrites: eventScopeWrites is int ? eventScopeWrites : 0,
      groupScopeWrites: groupScopeWrites is int ? groupScopeWrites : 0,
      // Fail toward bumping: a spurious bump is one redundant refetch; a
      // missed bump is a stale (money-wrong) home balance.
      shouldBumpLedgerRevision: map['shouldBumpLedgerRevision'] != false,
      settledAt: settledAt is String ? settledAt : '',
    );
  }
}
