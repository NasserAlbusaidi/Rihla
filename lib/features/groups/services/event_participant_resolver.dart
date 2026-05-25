import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/services/member_name_resolver.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/trip/models/trip_model.dart';

/// Output of [buildEventParticipants]: the participant list to feed
/// `BalanceCalculator.calculateBalances`, plus a UID-keyed [MemberDisplay]
/// map so callers can derive raw-name maps for `addSettlement` write paths
/// without re-invoking the resolver.
typedef EventParticipantResolution =
    ({List<Participant> participants, Map<String, MemberDisplay> displays});

/// Build the participant list for an event balance computation. Includes
/// every UID that touches money in the event — event roster, expense payer,
/// `customSplitParticipants`, `splitDistribution.keys`, settlement payer,
/// settlement recipient — so the calculator can credit/debit every actor
/// and `sum(netBalance) == 0` holds at the per-event view.
///
/// `resolveDisplay` decides per-call-site name scope. Per-event callers pass
/// a wrapper around [MemberNameResolver.resolveEventScoped]; group-rollup
/// callers pass a wrapper around [MemberNameResolver.resolveGroupScoped].
/// The helper harvests fallback names from `expense.payerName`,
/// `settlement.payerName`, and `settlement.recipientName` and forwards them
/// so pure-orphan UIDs (no live member doc, no tombstone, not in
/// `event.participantNames`) get a real human name instead of the
/// `'Former member'` literal — which would otherwise be persisted into new
/// settlement docs via the SettleUp screen's userRawNames map.
///
/// Caller responsibilities:
/// - `settlements` must be event-scoped only. Group-scoped settlements
///   flow through `groupSettlementsProvider` and are applied separately by
///   the group rollup.
/// - `expenses` and `settlements` should already be `isDeleted == false`
///   filtered; the helper defends anyway.
EventParticipantResolution buildEventParticipants({
  required Event event,
  required Iterable<Expense> expenses,
  required Iterable<Settlement> settlements,
  required MemberDisplay Function(String uid, {String? fallbackName})
  resolveDisplay,
}) {
  final liveExpenses = expenses.where((e) => !e.isDeleted);
  final liveSettlements = settlements.where((s) => !s.isDeleted);

  final financialUids = <String>{};
  final fallbackNames = <String, String>{};
  void recordName(String uid, String? name) {
    if (name == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    fallbackNames.putIfAbsent(uid, () => trimmed);
  }

  for (final e in liveExpenses) {
    financialUids.add(e.payerParticipantId);
    recordName(e.payerParticipantId, e.payerName);
    final custom = e.customSplitParticipants;
    if (custom != null) financialUids.addAll(custom);
    final dist = e.splitDistribution;
    if (dist != null) financialUids.addAll(dist.keys);
  }
  for (final s in liveSettlements) {
    final p = s.payerParticipantId;
    if (p != null) {
      financialUids.add(p);
      recordName(p, s.payerName);
    }
    final r = s.recipientParticipantId;
    if (r != null) {
      financialUids.add(r);
      recordName(r, s.recipientName);
    }
  }

  // Liveness is a display concern, not an inclusion criterion. Sort the
  // financial-only UIDs before appending so iteration order is deterministic
  // for tests and the EventCommandCenter roster strip (event roster preserved
  // in declared order; remainder alpha-sorted).
  final rosterUids = event.participantIds.toSet();
  final sortedFinancialOnly = financialUids
      .where((uid) => !rosterUids.contains(uid))
      .toList()
    ..sort();
  final unionUids = <String>{...event.participantIds, ...sortedFinancialOnly};

  final displays = <String, MemberDisplay>{};
  final participants = <Participant>[];
  for (final uid in unionUids) {
    final display = resolveDisplay(uid, fallbackName: fallbackNames[uid]);
    displays[uid] = display;
    participants.add(
      Participant(
        id: uid,
        tripId: event.id,
        role: ParticipantRole.member,
        joinedAt: event.createdAt,
        displayName: MemberNameResolver.format(display),
      ),
    );
  }
  return (participants: participants, displays: displays);
}
