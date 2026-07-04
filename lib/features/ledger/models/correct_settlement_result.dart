// #889 — typed result for the correctSettlement/correctLogicalSettleUp
// callables. Parses the raw callable `result.data` (a JS-object map over the
// wire) defensively: a missing/wrong-type field degrades to a safe default
// rather than throwing. Keys MUST match the callable output interfaces
// exactly (functions/src/callables/correctSettlement.ts
// CorrectSettlementOutput / correctLogicalSettleUp.ts
// CorrectLogicalSettleUpOutput — the two share one wire shape).

int _int(Object? v) => v is num ? v.toInt() : 0;

/// Outcome of a `correctSettlement` or `correctLogicalSettleUp` invocation.
class CorrectSettlementResult {
  const CorrectSettlementResult({
    required this.eventScopeWrites,
    required this.groupScopeWrites,
    required this.repaired,
    required this.noop,
    required this.shouldBumpLedgerRevision,
  });

  final int eventScopeWrites;
  final int groupScopeWrites;
  final bool repaired;
  final bool noop;

  /// Whether the caller should bump `ledgerRevisionProvider` (#104/#233) — true
  /// when the callable wrote/confirmed an EVENT-scope reverse (direct event
  /// corrections; logical corrections with any event-scope slice). False for
  /// a standalone group-only correction (group settlements are live-watched)
  /// and for a legacy no-op (nothing written or confirmed).
  final bool shouldBumpLedgerRevision;

  factory CorrectSettlementResult.fromData(Object? data) {
    final m = data is Map ? data : const {};
    return CorrectSettlementResult(
      eventScopeWrites: _int(m['eventScopeWrites']),
      groupScopeWrites: _int(m['groupScopeWrites']),
      repaired: m['repaired'] == true,
      noop: m['noop'] == true,
      shouldBumpLedgerRevision: m['shouldBumpLedgerRevision'] == true,
    );
  }
}
