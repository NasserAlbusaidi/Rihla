import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/split_mode.dart';
import '../../events/providers/event_provider.dart';
import '../../groups/models/group_member_model.dart';
import '../../groups/providers/group_provider.dart';
import '../../groups/services/member_name_resolver.dart';
import '../../trip/models/trip_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import 'expense_provider.dart';

/// Settlement name parts as the provider stores them: `null` ⇒ "unknown party"
/// (no `participantId` AND no persisted name) ⇒ the widget substitutes
/// `l10n.ledgerSomeone` / `ledgerSomeoneLower`. Keeping the l10n fallback in the
/// widget keeps this provider a PURE function of its data inputs (no
/// `BuildContext`), so it stays memoizable and unit-testable.
typedef LedgerSettlementNames = ({String? payerName, String? recipientName});

/// Everything the ledger needs that does NOT depend on the category filter (the
/// balance pass, the participant universe, and the render name maps). Bundled so
/// a chip-tap `setState` re-runs only the cheap filter pass, not this (#106).
typedef LedgerView = ({
  List<Participant> participants,
  Map<String, List<UserBalance>> balances,
  Map<String, Decimal> eventTotal,
  Map<String, String> rosterDisplayNames,
  Map<String, String> expensePayerDisplayNames,
  Map<String, LedgerSettlementNames> settlementDisplayNames,
  // #629: per-expense gross owed-by-uid, memoized once per data change so a
  // ledger row renders its signed share by lookup instead of re-running
  // `allocateExpenseOwed` per visible non-equal-split row on every chip-tap /
  // scroll. Populated ONLY for non-equal splits (shares/exact/percent) — the
  // equal-split row stays cheap widget arithmetic and never reads this. INBOUND
  // display-only: never read by a write path, `recomputeNet`, or the rules.
  Map<String, Map<String, Decimal>> owedByExpenseId,
});

/// Filter-independent ledger view data for one event, memoized by [EventRef]
/// (#106).
///
/// A category-chip tap in [LedgerScreen] is a `setState`, which rebuilds the
/// body but does NOT change this provider's key or its watched streams — so the
/// expensive work (the full [BalanceCalculator.calculateBalances] Decimal pass
/// and the O(expenses)+O(settlements) [MemberNameResolver.resolveEventScoped]
/// name maps) is served from cache instead of recomputed on every tap.
///
/// Keyed by [EventRef] (NOT `({EventRef, Event})` like [eventBalancesProvider]):
/// [Event] equality is **id-only** (`event_model.dart`), so a key carrying the
/// event would serve a STALE value after a same-id participant rename/add. This
/// provider watches [eventDetailProvider] internally instead, giving both a
/// stable-across-chip-taps key AND a fresh recompute on any real event change.
///
/// Reproduces the former `_Body.build` inline logic verbatim, except the two
/// l10n settlement fallbacks are deferred to the widget (see
/// [LedgerSettlementNames]). Non-`autoDispose`, matching its sibling
/// [eventBalancesProvider] and the per-event streams it derives from.
final ledgerViewProvider = Provider.family<LedgerView, EventRef>((ref, eventRef) {
  final event = ref.watch(eventDetailProvider(eventRef)).valueOrNull;
  final expenses =
      ref.watch(eventExpensesProvider(eventRef)).valueOrNull ??
      const <Expense>[];
  final settlements =
      ref.watch(eventSettlementsProvider(eventRef)).valueOrNull ??
      const <Settlement>[];
  final members =
      ref.watch(groupMembersProvider(eventRef.groupId)).valueOrNull ??
      const <GroupMember>[];

  if (event == null) {
    // UNREACHABLE during render: _LedgerScreenState builds _Body (the sole
    // watcher of this provider) only inside `eventAsync.when(data: (event) {
    // if (event == null) return _NotFoundState; ... })`, watching the SAME
    // eventDetailProvider — so in any frame _Body renders, this value is
    // non-null. Defensive empty so a provider-level read can't NPE.
    return (
      participants: const <Participant>[],
      balances: const <String, List<UserBalance>>{},
      eventTotal: const <String, Decimal>{},
      rosterDisplayNames: const <String, String>{},
      expensePayerDisplayNames: const <String, String>{},
      settlementDisplayNames: const <String, LedgerSettlementNames>{},
      owedByExpenseId: const <String, Map<String, Decimal>>{},
    );
  }

  // #249: fold departed-member split recipients (and former payers/settlers)
  // into the universe so their owed shares aren't dropped from the display.
  final allMemberIds = members.map((m) => m.userId).toSet();
  final liveMemberIds =
      members.where((m) => !m.isTombstone).map((m) => m.userId).toSet();
  final universe = eventBalanceUniverse(
    event: event,
    expenses: expenses,
    settlements: settlements,
    allMemberIds: allMemberIds,
    liveMemberIds: liveMemberIds,
  );
  final displaysByUid = <String, MemberDisplay>{
    for (final id in universe)
      id: MemberNameResolver.resolveEventScoped(
        uid: id,
        event: event,
        members: members,
      ),
  };
  final participants = [
    for (final entry in displaysByUid.entries)
      Participant(
        id: entry.key,
        tripId: event.id,
        role: ParticipantRole.member,
        joinedAt: event.createdAt,
        displayName: MemberNameResolver.format(entry.value),
      ),
  ];
  // #289: disambiguate same-named LIVE members at the RENDER sites only. The
  // calc input (participants[].displayName above) stays plain format() so the
  // BalanceCalculator oracle is byte-identical; the discriminator never feeds
  // the calc or any write path.
  final rosterDisplayNames = MemberNameResolver.disambiguate(displaysByUid);
  final liveCounts = MemberNameResolver.liveNameCounts(displaysByUid.values);

  final balances = BalanceCalculator.calculateBalances(
    expenses: expenses,
    settlements: settlements,
    participants: participants,
  );

  final eventTotal =
      BalanceCalculator.calculateTotalExpensesByCurrency(expenses);

  final expensePayerDisplayNames = <String, String>{
    for (final expense in expenses)
      // #289: distinguish two same-named payers ("which Ahmed paid this?").
      expense.id: MemberNameResolver.discriminatedLabel(
        expense.payerParticipantId,
        MemberNameResolver.resolveEventScoped(
          uid: expense.payerParticipantId,
          event: event,
          members: members,
          fallbackName: expense.payerName,
        ),
        liveCounts,
      ),
  };

  final settlementDisplayNames = <String, LedgerSettlementNames>{
    for (final settlement in settlements)
      settlement.id: (
        payerName: settlement.payerParticipantId == null
            ? settlement.payerName
            : MemberNameResolver.discriminatedLabel(
                settlement.payerParticipantId!,
                MemberNameResolver.resolveEventScoped(
                  uid: settlement.payerParticipantId!,
                  event: event,
                  members: members,
                  fallbackName: settlement.payerName,
                ),
                liveCounts,
              ),
        recipientName: settlement.recipientParticipantId == null
            ? settlement.recipientName
            : MemberNameResolver.discriminatedLabel(
                settlement.recipientParticipantId!,
                MemberNameResolver.resolveEventScoped(
                  uid: settlement.recipientParticipantId!,
                  event: event,
                  members: members,
                  fallbackName: settlement.recipientName,
                ),
                liveCounts,
              ),
      ),
  };

  // #629: memoize the per-expense owed allocation the ledger row needs, so a
  // category-chip `setState` (which rebuilds the rows but NOT this provider) and
  // on-scroll row builds become map lookups instead of re-running the Decimal
  // allocation per visible row. Only NON-equal splits are memoized — the gate
  // below is byte-identical to `_ExpenseRow._isNonEqualSplit`, so the equal-split
  // row (which never reads this map) stays cheap. The call args are the EXACT set
  // the row passes today (`participantIds: const []` — ignored on the distribution
  // branch; `onFallback: null` — `calculateBalances` already fired the telemetry),
  // so the memoized value equals the row's prior in-build computation by
  // construction (single-sourced math; no oracle divergence).
  final owedByExpenseId = <String, Map<String, Decimal>>{
    for (final expense in expenses)
      if (expense.splitMode != null &&
          expense.splitMode != SplitMode.equally &&
          expense.splitDistribution != null &&
          expense.splitDistribution!.isNotEmpty)
        expense.id: BalanceCalculator.allocateExpenseOwed(
          amount: expense.amount,
          splitMode: expense.splitMode,
          splitDistribution: expense.splitDistribution,
          scope: expense.scope,
          customSplitParticipants: expense.customSplitParticipants,
          payerId: expense.payerParticipantId,
          participantIds: const <String>[],
          currency: expense.currency,
          onFallback: null,
        ),
  };

  return (
    participants: participants,
    balances: balances,
    eventTotal: eventTotal,
    rosterDisplayNames: rosterDisplayNames,
    expensePayerDisplayNames: expensePayerDisplayNames,
    settlementDisplayNames: settlementDisplayNames,
    owedByExpenseId: owedByExpenseId,
  );
});
