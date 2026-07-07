import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/supported_currencies.dart';
import '../../../core/providers/balance_aggregate_freshness_provider.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/services/money_serializer.dart';
import '../../auth/providers/auth_provider.dart';
import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../trip/models/trip_model.dart';
import '../models/group_activity_log_model.dart';
import '../models/group_balance_aggregate_model.dart';
import '../models/group_member_model.dart';
import '../services/group_activity_service.dart';
import '../services/group_settlement_service.dart';
import '../services/member_name_resolver.dart';
import 'group_provider.dart';

// ---------------------------------------------------------------------------
// Service providers
// ---------------------------------------------------------------------------

/// Provider for [GroupSettlementService].
final groupSettlementServiceProvider = Provider<GroupSettlementService>(
  (ref) => GroupSettlementService(),
);

/// Provider for [GroupActivityService].
final groupActivityServiceProvider = Provider<GroupActivityService>(
  (ref) => GroupActivityService(),
);

// ---------------------------------------------------------------------------
// groupSettlementsProvider
// ---------------------------------------------------------------------------

/// Reactive stream of non-deleted group-level settlements.
///
/// Backed by [GroupSettlementService.watchGroupSettlements]. Group settlements
/// live at `groups/{groupId}/settlements` — separate from event-level
/// settlements in `groups/{groupId}/events/{eventId}/settlements`.
final groupSettlementsProvider =
    StreamProvider.family<List<Settlement>, String>((ref, groupId) {
      final service = ref.read(groupSettlementServiceProvider);
      return service.watchGroupSettlements(groupId);
    });

// ---------------------------------------------------------------------------
// groupActivityProvider
// ---------------------------------------------------------------------------

/// Per-group window feeding the cross-group activity feed. Lives HERE (beside
/// the provider) because `dashboard_providers.dart` imports this file one-way;
/// its merged-feed cap (`kCrossGroupActivityMergedCap`) lives over there.
///
/// 15/group so the merged feed's filter chips operate on real history — the
/// old 5/group window let entries age out before a filter was ever tapped.
const kCrossGroupActivityPerGroupLimit = 15;

/// Reactive stream of the most recent group-level activity entries
/// ([kCrossGroupActivityPerGroupLimit] per group).
///
/// Backed by [GroupActivityService.watchRecentActivity]. Activity entries
/// live at `groups/{groupId}/activity`. Sole watcher is
/// `crossGroupActivityProvider` — the per-group history screen paginates via
/// `fetchActivityPageRaw` instead, so widening this limit widens the existing
/// listeners without adding any (#104 axis).
final groupActivityProvider =
    StreamProvider.family<List<GroupActivityLog>, String>((ref, groupId) {
      final service = ref.read(groupActivityServiceProvider);
      return service.watchRecentActivity(
        groupId,
        limit: kCrossGroupActivityPerGroupLimit,
      );
    });

// ---------------------------------------------------------------------------
// GroupBalances typedef
// ---------------------------------------------------------------------------

/// Record type for the group balance computation result.
///
/// Consumed by the group dashboard UI widgets and group settlement screens.
///
/// Fields:
/// - [balances]: Per-CURRENCY per-member balances aggregated across all group
///   events and group-level settlements (#382 PR-1). Bucket keys are
///   fence-validated currencies; every bucket lists every known uid, zeros
///   included. No money records → empty map. Amounts in different currencies
///   are NEVER summed (no FX).
/// - [totalSpent]: Per-currency sum of all expenses across all group events.
/// - [eventCount]: Number of events included in the computation.
/// - [perEventBreakdown]: memberId → eventId → currency → netBalance for that
///   member in that event (#382 PR-3 buckets the drill-down; a no-money event
///   carries an explicit synthetic-OMR zero row). Used for drill-down UI views.
/// - [memberNames]: memberId → displayName map for settlement rendering.
/// - [memberRawNames]: memberId → raw displayName map for settlement writes.
typedef GroupBalances = ({
  Map<String, List<UserBalance>> balances,
  Map<String, Decimal> totalSpent,
  int eventCount,
  Map<String, Map<String, Map<String, Decimal>>> perEventBreakdown,
  Map<String, String> memberNames,
  Map<String, String> memberRawNames,
});

// ---------------------------------------------------------------------------
// groupBalancesProvider
// ---------------------------------------------------------------------------

/// Central aggregation provider for cross-event group balances.
///
/// Implemented as `Provider.family` (NOT StreamProvider.family) — this pattern
/// enables `ref.watch` calls inside a loop over a variable-length events list,
/// which is not possible in StreamProvider bodies (per RESEARCH Pitfall 2).
///
/// Computation:
/// 1. Watch [groupEventsProvider] for the list of events in the group.
/// 2. Watch [groupMembersProvider] for unified participant identity (D-04).
/// 3. For each event, watch [eventExpensesProvider] and [eventSettlementsProvider].
/// 4. Watch [groupSettlementsProvider] for cross-event settlements (D-07).
/// 5. Run [BalanceCalculator] per event with event-local participants, adding
///    former financial actors only to the events where they appear.
/// 6. Sum per-user net balances, apply group-scoped settlement adjustments,
///    and build formatted/raw member name maps for UI and write paths.
///
/// Returns [AsyncValue.loading] while any required stream has no value yet.
/// Returns [AsyncValue.error] if the events stream fails.
/// Returns [AsyncValue.data] wrapping a [GroupBalances] record once all data
/// is available.
///
/// The provider automatically recomputes whenever any watched stream emits.
final groupBalancesProvider = Provider.family<AsyncValue<GroupBalances>, String>((
  ref,
  groupId,
) {
  // Step 1: Watch the events list
  final eventsAsync = ref.watch(groupEventsProvider(groupId));
  if (eventsAsync.isLoading && !eventsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (eventsAsync.hasError) {
    return AsyncValue.error(eventsAsync.error!, eventsAsync.stackTrace!);
  }
  final events = eventsAsync.valueOrNull ?? [];

  // Step 2: Watch group members (UID-based identity per D-04)
  final membersAsync = ref.watch(groupMembersProvider(groupId));
  if (membersAsync.isLoading && !membersAsync.hasValue) {
    return const AsyncValue.loading();
  }
  final members = membersAsync.valueOrNull ?? [];

  // Step 3: Watch group-level settlements (D-07)
  final groupSettlementsAsync = ref.watch(groupSettlementsProvider(groupId));

  // Step 4: For each event, watch expenses and settlements.
  // ref.watch inside a loop is valid in Provider.family bodies (RESEARCH Pitfall 2).
  final allExpenses = <Expense>[];
  final allEventSettlements = <Settlement>[];

  for (final event in events) {
    final eventRef = (groupId: groupId, eventId: event.id);
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));

    if ((expensesAsync.isLoading && !expensesAsync.hasValue) ||
        (settlementsAsync.isLoading && !settlementsAsync.hasValue)) {
      continue;
    }
    // Skip events that errored (e.g., permission-denied) — treat as 0
    // expenses/settlements rather than blocking the entire balance chain.
    if ((expensesAsync.hasError && !expensesAsync.hasValue) ||
        (settlementsAsync.hasError && !settlementsAsync.hasValue)) {
      continue;
    }

    allExpenses.addAll(expensesAsync.valueOrNull ?? []);
    allEventSettlements.addAll(settlementsAsync.valueOrNull ?? []);
  }

  // Proceed with available data even if some events are still loading —
  // returning AsyncValue.loading() here deadlocks the balance card when
  // new events have zero expenses.
  return AsyncValue.data(
    computeGroupBalances(
      events: events,
      members: members,
      allExpenses: allExpenses,
      allEventSettlements: allEventSettlements,
      groupSettlements: groupSettlementsAsync.valueOrNull ?? const [],
    ),
  );
});

/// Event ids in [groupId] whose expense OR settlement read HARD-ERRORED — not
/// merely loading. Mirrors the error-skip in [groupBalancesProvider] (the
/// `hasError && !hasValue` branch) so the in-group settle-up surface can WARN
/// that the displayed balance is incomplete instead of presenting a partial sum
/// as authoritative (#244).
///
/// Iterates the SAME [groupEventsProvider] list and the SAME per-event
/// [eventExpensesProvider]/[eventSettlementsProvider] instances the live
/// balance provider sums, so the "incomplete" warning can never disagree with
/// the events the balance silently zeroed. Loading ≠ partial: a still-loading
/// event (`isLoading && !hasValue`) is NOT flagged, matching the live provider's
/// separate loading-skip. A soft-deleted event never enters the events list, so
/// it never appears here.
final groupFailedEventIdsProvider = Provider.family<Set<String>, String>((
  ref,
  groupId,
) {
  final events =
      ref.watch(groupEventsProvider(groupId)).valueOrNull ?? const <Event>[];
  final failed = <String>{};
  for (final event in events) {
    final eventRef = (groupId: groupId, eventId: event.id);
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
    if ((expensesAsync.hasError && !expensesAsync.hasValue) ||
        (settlementsAsync.hasError && !settlementsAsync.hasValue)) {
      failed.add(event.id);
    }
  }
  return failed;
});

/// All non-deleted EVENT settlements across [groupId] that belong to a
/// decomposed group settle-up (#752 — `groupSettleUpId != null`). The group
/// settle-up history UNIONS these with the group-settlement docs so a
/// single-event settle-up (which writes per-event docs + 0 group docs) still
/// appears in group history instead of vanishing.
///
/// Iterates the SAME [groupEventsProvider] list and the SAME per-event
/// [eventSettlementsProvider] instances the live balance provider watches — and
/// since `eventSettlementsProvider` is a cached `StreamProvider.family`, this
/// adds NO new Firestore listeners (it re-uses the already-open streams). A
/// soft-deleted event never enters the events list, so its settlements never
/// appear here.
final groupTaggedEventSettlementsProvider =
    Provider.family<List<Settlement>, String>((ref, groupId) {
      final events =
          ref.watch(groupEventsProvider(groupId)).valueOrNull ??
          const <Event>[];
      final tagged = <Settlement>[];
      for (final event in events) {
        final eventRef = (groupId: groupId, eventId: event.id);
        final settlements =
            ref.watch(eventSettlementsProvider(eventRef)).valueOrNull ??
            const <Settlement>[];
        for (final s in settlements) {
          if (s.groupSettleUpId != null && !s.isDeleted) tagged.add(s);
        }
      }
      return tagged;
    });

/// Pure reduction from a group's events, members, and money records to a
/// [GroupBalances]. Extracted from [groupBalancesProvider] (#104) so the live
/// streaming path and the one-shot home path ([groupBalancesOnceProvider])
/// compute identical money — never diverge. Contains NO `ref`/provider reads:
/// callers assemble the inputs (live `ref.watch` or one-shot `.get()`) and pass
/// them in.
GroupBalances computeGroupBalances({
  required List<Event> events,
  required List<GroupMember> members,
  required List<Expense> allExpenses,
  required List<Settlement> allEventSettlements,
  required List<Settlement> groupSettlements,
}) {
  final allSettlements = <Settlement>[
    ...allEventSettlements,
    ...groupSettlements,
  ];

  final uidToFallbackName = <String, String>{};
  for (final event in events) {
    for (final entry in event.participantNames.entries) {
      uidToFallbackName.putIfAbsent(entry.key, () => entry.value);
    }
  }
  for (final settlement in allSettlements) {
    final payerId = settlement.payerParticipantId;
    final recipientId = settlement.recipientParticipantId;
    final payerName = settlement.payerName;
    final recipientName = settlement.recipientName;
    if (payerId != null && payerName != null) {
      uidToFallbackName.putIfAbsent(payerId, () => payerName);
    }
    if (recipientId != null && recipientName != null) {
      uidToFallbackName.putIfAbsent(recipientId, () => recipientName);
    }
  }
  for (final expense in allExpenses) {
    final payerName = expense.payerName;
    if (payerName != null) {
      uidToFallbackName.putIfAbsent(
        expense.payerParticipantId,
        () => payerName,
      );
    }
  }

  final expensesByEvent = <String, List<Expense>>{
    for (final event in events) event.id: <Expense>[],
  };
  final eventSettlementsByEvent = <String, List<Settlement>>{
    for (final event in events) event.id: <Settlement>[],
  };
  for (final expense in allExpenses) {
    expensesByEvent[expense.tripId]?.add(expense);
  }
  for (final settlement in allEventSettlements) {
    eventSettlementsByEvent[settlement.tripId]?.add(settlement);
  }

  // currency -> uid -> amount (#382 PR-1). The three maps share key sets per
  // currency because they fold from the same per-event bucket entries.
  final totalPaidByCurrency = <String, Map<String, Decimal>>{};
  final totalOwedByCurrency = <String, Map<String, Decimal>>{};
  final netByCurrency = <String, Map<String, Decimal>>{};
  final allMemberIds = members.map((m) => m.userId).toSet();
  final liveMemberIds = members
      .where((m) => !m.isTombstone)
      .map((m) => m.userId)
      .toSet();
  final allFormerFinancialActorsSeen = <String>{};

  for (final event in events) {
    final eventExpenses = expensesByEvent[event.id] ?? const <Expense>[];
    final eventSettlements =
        eventSettlementsByEvent[event.id] ?? const <Settlement>[];
    // Per-event universe = participantIds ∪ former financial actors (payers,
    // settlement parties, AND departed-member split recipients — #249). The
    // member-gate on the recipient fold lives in [eventBalanceUniverse].
    final eventParticipantUids = eventBalanceUniverse(
      event: event,
      expenses: eventExpenses,
      settlements: eventSettlements,
      allMemberIds: allMemberIds,
      liveMemberIds: liveMemberIds,
    );
    // Every non-live UID now in the universe is a former actor; record so they
    // surface in `allUids` → `balances` (with resolved names).
    allFormerFinancialActorsSeen.addAll(
      eventParticipantUids.difference(liveMemberIds),
    );
    if (eventParticipantUids.isEmpty) continue;

    final eventParticipants = eventParticipantUids.map((uid) {
      final display = MemberNameResolver.resolveGroupScoped(
        uid: uid,
        members: members,
        fallbackName: uidToFallbackName[uid],
      );
      return Participant(
        id: uid,
        tripId: event.id,
        role: ParticipantRole.member,
        joinedAt: event.createdAt,
        // Formatted for display. Raw names are exposed through memberRawNames
        // so write paths never persist the former-member suffix.
        displayName: MemberNameResolver.format(display),
      );
    }).toList();

    final eventBuckets = BalanceCalculator.calculateBalances(
      expenses: eventExpenses,
      settlements: eventSettlements,
      participants: eventParticipants,
    );

    eventBuckets.forEach((currency, eventBalances) {
      final paid = totalPaidByCurrency.putIfAbsent(currency, () => {});
      final owed = totalOwedByCurrency.putIfAbsent(currency, () => {});
      final net = netByCurrency.putIfAbsent(currency, () => {});
      for (final balance in eventBalances) {
        paid.update(
          balance.participantId,
          (value) => value + balance.totalPaid,
          ifAbsent: () => balance.totalPaid,
        );
        owed.update(
          balance.participantId,
          (value) => value + balance.totalOwed,
          ifAbsent: () => balance.totalOwed,
        );
        net.update(
          balance.participantId,
          (value) => value + balance.netBalance,
          ifAbsent: () => balance.netBalance,
        );
      }
    });
  }

  // Group-scoped settlements adjust ONLY their own per-doc currency bucket
  // (#382 PR-1 — fenced like the calculator's settlement fold; a legacy OMR
  // settlement in any group lands in the OMR bucket, the original obligation).
  final groupAdjByCurrency = <String, Map<String, Decimal>>{};
  for (final settlement in groupSettlements) {
    final currency = MoneySerializer.isSupported(settlement.currency)
        ? settlement.currency
        : 'OMR';
    final adj = groupAdjByCurrency.putIfAbsent(currency, () => {});
    final payerId = settlement.payerParticipantId;
    final recipientId = settlement.recipientParticipantId;
    if (payerId != null) {
      adj.update(
        payerId,
        (value) => value + settlement.amount,
        ifAbsent: () => settlement.amount,
      );
    }
    if (recipientId != null) {
      adj.update(
        recipientId,
        (value) => value - settlement.amount,
        ifAbsent: () => -settlement.amount,
      );
    }
  }

  final allUids = <String>{
    ...allMemberIds,
    ...allFormerFinancialActorsSeen,
    for (final m in totalPaidByCurrency.values) ...m.keys,
    for (final m in totalOwedByCurrency.values) ...m.keys,
    for (final m in netByCurrency.values) ...m.keys,
    for (final m in groupAdjByCurrency.values) ...m.keys,
  };

  // Resolve every uid once, then derive display + raw name maps from it.
  // Same-named LIVE members get a render-only ` (#last4)` discriminator (#196);
  // raw names stay raw because they feed the settlement write path.
  final displaysByUid = <String, MemberDisplay>{
    for (final uid in allUids)
      uid: MemberNameResolver.resolveGroupScoped(
        uid: uid,
        members: members,
        fallbackName: uidToFallbackName[uid],
      ),
  };
  final memberNames = MemberNameResolver.disambiguate(displaysByUid);
  final memberRawNames = <String, String>{
    for (final entry in displaysByUid.entries) entry.key: entry.value.rawName,
  };

  final allCurrencies = <String>{
    ...netByCurrency.keys,
    ...groupAdjByCurrency.keys,
  };
  final balances = <String, List<UserBalance>>{
    for (final currency in allCurrencies)
      currency: allUids.map((uid) {
        final eventNet = netByCurrency[currency]?[uid] ?? Decimal.zero;
        final groupSettlementNet =
            groupAdjByCurrency[currency]?[uid] ?? Decimal.zero;
        return UserBalance(
          participantId: uid,
          displayName:
              memberNames[uid] ??
              MemberNameResolver.format(displaysByUid[uid]!),
          totalPaid: totalPaidByCurrency[currency]?[uid] ?? Decimal.zero,
          totalOwed: totalOwedByCurrency[currency]?[uid] ?? Decimal.zero,
          netBalance: eventNet + groupSettlementNet,
        );
      }).toList(),
  };

  // Step 7: Compute per-event breakdown (RESEARCH Pattern 4). This drill-down
  // intentionally keeps using event.participantIds only; aggregate balances
  // above are the authoritative settle-up participant set.
  final perEventBreakdown = _buildPerEventBreakdown(
    events,
    expensesByEvent,
    eventSettlementsByEvent,
  );

  return (
    balances: balances,
    totalSpent: BalanceCalculator.calculateTotalExpensesByCurrency(allExpenses),
    eventCount: events.length,
    perEventBreakdown: perEventBreakdown,
    memberNames: memberNames,
    memberRawNames: memberRawNames,
  );
}

// ---------------------------------------------------------------------------
// Helper: per-event breakdown
// ---------------------------------------------------------------------------

/// Builds a breakdown of each member's net balance per event, per currency
/// bucket (#382 PR-3).
///
/// Returns: memberId → { eventId → { currency → netBalance } }
///
/// For each event, participants are derived from [Event.participantIds] and
/// [Event.participantNames] (UID-based per D-04). Only events with at least
/// one participant are included. A no-money event yields an explicit
/// synthetic-OMR zero row per participant (mirrors the server oracle's
/// `bucketizeDrill` — there is no real currency to key the zeros).
///
/// Reuses the per-event expense/settlement maps the caller already built from
/// its own `ref.watch` fan-out — no redundant re-watch here (#112). The
/// participant set stays [Event.participantIds]-only on purpose: the aggregate
/// balances above fold in former financial actors, but the drill-down does not.
Map<String, Map<String, Map<String, Decimal>>> _buildPerEventBreakdown(
  List<Event> events,
  Map<String, List<Expense>> expensesByEvent,
  Map<String, List<Settlement>> eventSettlementsByEvent,
) {
  final breakdown = <String, Map<String, Map<String, Decimal>>>{};

  for (final event in events) {
    final expenses = expensesByEvent[event.id] ?? const <Expense>[];
    final settlements =
        eventSettlementsByEvent[event.id] ?? const <Settlement>[];

    // Build participants for this event only (UID-based per D-04)
    final participants = event.participantIds
        .map(
          (uid) => Participant(
            id: uid,
            tripId: event.id,
            role: ParticipantRole.member,
            joinedAt: event.createdAt,
            displayName: event.participantNames[uid],
          ),
        )
        .toList();

    if (participants.isEmpty) continue;

    final eventBuckets = BalanceCalculator.calculateBalances(
      expenses: expenses,
      settlements: settlements,
      participants: participants,
    );

    if (eventBuckets.isEmpty) {
      for (final p in participants) {
        breakdown.putIfAbsent(p.id, () => {})[event.id] = {'OMR': Decimal.zero};
      }
      continue;
    }
    eventBuckets.forEach((currency, eventBalances) {
      for (final b in eventBalances) {
        breakdown
                .putIfAbsent(b.participantId, () => {})
                .putIfAbsent(event.id, () => {})[currency] =
            b.netBalance;
      }
    });
  }

  return breakdown;
}

// ---------------------------------------------------------------------------
// currentUserIdProvider — injectable UID for testability
// ---------------------------------------------------------------------------

/// Provides the current Firebase user's UID, or null if not authenticated.
///
/// Watches [authStateProvider] so consumers re-render when Firebase Auth swaps
/// users — critical for the email-link recovery flow, which switches the
/// anonymous session to the linked account. A plain Provider that read
/// `FirebaseConfig.currentUser?.uid` would cache the pre-recovery UID and
/// strand every participant lookup until the app was force-stopped.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).valueOrNull?.uid;
});

// ---------------------------------------------------------------------------
// CrossGroupBalance typedef
// ---------------------------------------------------------------------------

/// Record type for cross-group balance aggregation displayed in the balance
/// hero card.
///
/// Fields:
/// One currency's slice of the cross-group balance (#261).
/// [net] == [owedToUser] - [userOwes] for this currency.
typedef CurrencyBalance = ({
  String currency,
  Decimal net,
  Decimal owedToUser,
  Decimal userOwes,
});

/// Cross-group balance, BUCKETED per currency (#261 — there is no FX, so
/// amounts in different currencies are NEVER summed together).
///
/// - [byCurrency]: one entry per currency the user has ACTIVE balance in
///   ([CurrencyBalance.owedToUser] != 0 || [CurrencyBalance.userOwes] != 0),
///   sorted GCC-first ([kSupportedCurrencies]; an off-list legacy code sorts
///   last but is NEVER dropped). Empty ⇒ all settled / no groups.
/// - [groupCount]: total number of groups the user belongs to.
/// - [isLoading]: true if some group balance data is still loading.
typedef CrossGroupBalance = ({
  List<CurrencyBalance> byCurrency,
  int groupCount,
  bool isLoading,
});

/// #70: the currency for the cross-group ALL-SETTLED hero state — the user's
/// single distinct group currency, or null when they have zero groups or groups
/// spanning MORE THAN ONE currency (no single currency is honest, so the hero
/// renders a currency-agnostic zero). Used ONLY for the settled/empty render;
/// an ACTIVE balance carries its own per-currency bucket in [byCurrency].
///
/// Reads [userGroupsProvider] — the same groups source the once-provider awaits,
/// so the two cannot meaningfully disagree. Null while groups load (the hero is
/// showing the skeleton then anyway).
final settledDisplayCurrencyProvider = Provider<String?>((ref) {
  final groups = ref.watch(userGroupsProvider).valueOrNull;
  if (groups == null || groups.isEmpty) return null;
  final distinct = groups.map((g) => g.currency).toSet();
  return distinct.length == 1 ? distinct.single : null;
});

/// Bucket a per-currency accumulator into the sorted [CurrencyBalance] list:
/// keep only currencies with activity (owed or owes nonzero — so an offsetting
/// net-zero currency is still shown), GCC-first; an unknown code sorts last but
/// is NEVER dropped (dropping money is forbidden — the parity contract).
List<CurrencyBalance> _sortedCurrencyBuckets(
  Map<String, ({Decimal net, Decimal owedToUser, Decimal userOwes})> byCurrency,
) {
  final list = <CurrencyBalance>[];
  for (final e in byCurrency.entries) {
    if (e.value.owedToUser != Decimal.zero ||
        e.value.userOwes != Decimal.zero) {
      list.add((
        currency: e.key,
        net: e.value.net,
        owedToUser: e.value.owedToUser,
        userOwes: e.value.userOwes,
      ));
    }
  }
  int rank(String c) {
    final i = kSupportedCurrencies.indexOf(c);
    return i < 0 ? kSupportedCurrencies.length : i;
  }

  list.sort((a, b) {
    final r = rank(a.currency).compareTo(rank(b.currency));
    return r != 0 ? r : a.currency.compareTo(b.currency);
  });
  return list;
}

/// Fold one group's per-user [groupNet] (settlement-folded scalar) into the
/// per-currency accumulator keyed by the group's [currency]. Sign-splits the
/// net into the owed/owes components the hero renders.
void _accumulateBucket(
  Map<String, ({Decimal net, Decimal owedToUser, Decimal userOwes})> map,
  String currency,
  Decimal groupNet,
) {
  final prev =
      map[currency] ??
      (net: Decimal.zero, owedToUser: Decimal.zero, userOwes: Decimal.zero);
  map[currency] = (
    net: prev.net + groupNet,
    owedToUser: groupNet > Decimal.zero
        ? prev.owedToUser + groupNet
        : prev.owedToUser,
    userOwes: groupNet < Decimal.zero
        ? prev.userOwes + groupNet.abs()
        : prev.userOwes,
  );
}

// ---------------------------------------------------------------------------
// One-shot home aggregation (#104) — kills the O(G×E) permanent listener leak
// ---------------------------------------------------------------------------

// [ledgerRevisionProvider] (the liveness lever) lives in expense_provider.dart
// alongside the write services; this file imports it already.

/// One-shot balance plus the ids of events whose one-shot money read FAILED
/// (and were therefore dropped from [balances]). [failedEventIds] non-empty ⇒
/// [balances] is a PARTIAL sum (#244): the home hero renders an "incomplete"
/// affordance rather than presenting the partial number as authoritative.
///
/// Mirrors the live error-skip in [groupBalancesProvider] (the
/// `hasError && !hasValue` branch) and [groupFailedEventIdsProvider], but
/// computed from the SAME one-shot reads that produce [balances] — so the flag
/// can never disagree with the number.
typedef GroupBalancesOnce = ({
  GroupBalances balances,
  Set<String> failedEventIds,
});

/// Upper bound on every await inside [groupBalancesOnceProvider] (#997 D2).
/// A hung SDK read (gRPC wedge under DNS blackhole — the SDK never flips
/// offline) must degrade to the honest #244 partial/error states, never hold
/// home in a skeleton forever. Deliberately longer than `kWriteAckTimeout`:
/// a slow-but-succeeding read beats a spurious partial.
const kOnceReadDeadline = Duration(seconds: 8);

/// One-shot variant of [groupBalancesProvider] for the always-mounted home
/// dashboard (#104).
///
/// The LIST inputs (events, members, group settlements) stay LIVE — they are
/// O(G) listeners, not the O(G×E) leak, and reusing the existing stream
/// providers inherits the #190 `isDeleted` group filter and the D-25 null-date
/// event sort unchanged (no re-implementation, no divergence). Only the
/// O(G×E) per-event expense/settlement reads are one-shot `.get()`.
///
/// Per-event tolerance (#244): an event whose expense OR settlement read throws
/// (permission-denied / uncached-while-offline) is DROPPED and recorded in
/// `failedEventIds`, mirroring the live provider's silent error-skip — but the
/// drop is now surfaced so the home hero can warn instead of silently zeroing.
/// The COARSE list reads (events/members/group settlements) are awaited BEFORE
/// the per-event loop and are intentionally NOT caught: a whole-group read
/// failure still rejects the future (loud-safe → error card), because a wholly
/// unknown group is too coarse to silently drop.
///
/// Calls the SAME [computeGroupBalances] as the live provider, so the home
/// headline and the OUTBOUND in-group settle-up screen can never diverge.
final groupBalancesOnceProvider = FutureProvider.autoDispose
    .family<GroupBalancesOnce, String>((ref, groupId) async {
      // Register all stream dependencies SYNCHRONOUSLY (before any await) so the
      // provider re-runs when a list emits or the ledger revision bumps.
      final eventsFut = ref.watch(groupEventsProvider(groupId).future);
      final membersFut = ref.watch(groupMembersProvider(groupId).future);
      final groupSettlementsFut = ref.watch(
        groupSettlementsProvider(groupId).future,
      );
      ref.watch(ledgerRevisionProvider);

      // #997 D2: every await is deadline-bounded. Events/members timeouts
      // REJECT (facade error — honest "Balance unavailable"); a per-event or
      // group-settlements failure degrades to the #244 partial states below.
      final events = await eventsFut.timeout(kOnceReadDeadline);
      final members = await membersFut.timeout(kOnceReadDeadline);
      final groupSettlements = await groupSettlementsFut.timeout(
        kOnceReadDeadline,
      );

      final expenseService = ref.read(expenseServiceProvider);
      final settlementService = ref.read(settlementServiceProvider);
      final allExpenses = <Expense>[];
      final allEventSettlements = <Settlement>[];
      final failedEventIds = <String>{};
      for (final event in events) {
        try {
          // Read BOTH before mutating the accumulators — if either throws, neither
          // is added (the OR-drop semantics of the live `:153-156` skip: an event
          // with one failed money read contributes 0, never half-counted).
          final eventExpenses = await expenseService
              .getExpenses(groupId, event.id)
              .timeout(kOnceReadDeadline);
          final eventSettlements = await settlementService
              .getSettlements(groupId, event.id)
              .timeout(kOnceReadDeadline);
          allExpenses.addAll(eventExpenses);
          allEventSettlements.addAll(eventSettlements);
        } catch (_) {
          failedEventIds.add(event.id);
        }
      }

      return (
        balances: computeGroupBalances(
          events: events,
          members: members,
          allExpenses: allExpenses,
          allEventSettlements: allEventSettlements,
          groupSettlements: groupSettlements,
        ),
        failedEventIds: failedEventIds,
      );
    });

/// Home cross-group summary plus whether ANY group's one-shot dropped an event
/// (#244). [partial] ⇒ [balance] omits one or more events' money (a per-event
/// read failed); the home hero renders the "may be incomplete" affordance.
/// Atomic: number + flag come from one computation, so they can never disagree.
typedef CrossGroupBalanceOnce = ({CrossGroupBalance balance, bool partial});

// ---------------------------------------------------------------------------
// #366 — server-maintained balance aggregate + the home facade
// ---------------------------------------------------------------------------

/// Live stream of the server-maintained balance aggregate (#366).
///
/// ONE single-doc listener per group — O(G) total from the always-mounted
/// home, the same order as the live list providers; NOT a reopen of the #104
/// O(G×E) leak. Emits null while the doc is missing (group predates the first
/// `balanceReconciler` backfill), degraded, or malformed.
final groupBalanceAggregateProvider =
    StreamProvider.family<GroupBalanceAggregate?, String>((ref, groupId) {
      return ref.watch(groupServiceProvider).watchBalanceAggregate(groupId);
    });

/// What the home surfaces need from one group's balances, source-agnostic.
///
/// Per-currency end-to-end (#382 PR-3): [userNet] is currency → net,
/// [userPerEventNet] is eventId → currency → net (eventId-major, mirroring
/// the v2 aggregate doc). Amounts in different currencies are NEVER summed.
/// A uid absent from a net bucket is zero in that currency; settled ⇔ every
/// bucket zero, and an empty map ≡ an all-zero map (D10).
///
/// [partial] is only ever true on the fallback path (#244 — a per-event read
/// failed); the aggregate path saw every event server-side. [fromAggregate]
/// exists for tests/diagnostics, never for display branching.
typedef HomeGroupBalance = ({
  Map<String, Decimal> userNet,
  Map<String, Map<String, Decimal>> userPerEventNet,
  int eventCount,
  bool partial,
  bool fromAggregate,
});

HomeGroupBalance _homeBalanceFromAggregate(
  GroupBalanceAggregate aggregate,
  String uid,
) {
  return (
    userNet: aggregate.netFor(uid),
    userPerEventNet: aggregate.perEventNetFor(uid),
    eventCount: aggregate.eventCount,
    partial: false,
    fromAggregate: true,
  );
}

HomeGroupBalance _homeBalanceFromOnce(GroupBalancesOnce once, String uid) {
  final balances = once.balances;
  // Mirror the bucket key-set of the once-path balances: zero when the uid is
  // absent from a bucket (matches GroupBalanceAggregate.netFor).
  return (
    userNet: {
      for (final entry in balances.balances.entries)
        entry.key:
            entry.value
                .where((b) => b.participantId == uid)
                .firstOrNull
                ?.netBalance ??
            Decimal.zero,
    },
    userPerEventNet:
        balances.perEventBreakdown[uid] ??
        const <String, Map<String, Decimal>>{},
    eventCount: balances.eventCount,
    partial: once.failedEventIds.isNotEmpty,
    fromAggregate: false,
  );
}

bool _decimalMapEquals(Map<String, Decimal> a, Map<String, Decimal> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

bool _perEventNetEquals(
  Map<String, Map<String, Decimal>> a,
  Map<String, Map<String, Decimal>> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null || !_decimalMapEquals(entry.value, other)) return false;
  }
  return true;
}

bool _aggregateMatchesOnce({
  required HomeGroupBalance aggregate,
  required HomeGroupBalance once,
}) {
  if (once.partial) return false;
  return aggregate.eventCount == once.eventCount &&
      _decimalMapEquals(aggregate.userNet, once.userNet) &&
      _perEventNetEquals(aggregate.userPerEventNet, once.userPerEventNet);
}

void _clearStaleAggregateAfterBuild(Ref ref, String groupId) {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  Future<void>.microtask(() {
    if (disposed) return;
    ref
        .read(balanceAggregateFreshnessProvider.notifier)
        .clearGroupDirty(groupId);
  });
}

/// The SINGLE chooser between the server aggregate and the client once-path
/// for home display (#366 spec §0.7). Decision table:
///
/// - no signed-in uid                          → zeros
/// - connectivity != online (incl. `syncing`)  → once-path: the SDK cache +
///   queued local writes are FRESHER than any server doc while offline (the
///   post-#412 ledgerRevision bump fires on queued outcomes too)
/// - aggregate loading                          → loading
/// - aggregate present                          → aggregate (zero per-event
///   reads — the O(G×E) → O(G) win; per-currency since #382 PR-3)
/// - aggregate missing / degraded / stream error → once-path (today's
///   behavior, incl. the #244 partial affordance)
///
/// The aggregate is a DISPLAY CACHE — nothing may write money based on it;
/// settle-up and all in-group surfaces keep computing live.
final homeGroupBalanceProvider =
    Provider.family<AsyncValue<HomeGroupBalance>, String>((ref, groupId) {
      final uid = ref.watch(currentUserIdProvider);
      if (uid == null) {
        // #997 D5: uid null ⇒ the auth stream is still resolving (_AuthGate
        // guarantees an anon session) — loading, never a fabricated zero that
        // bypasses the #1005 display hardening.
        return const AsyncValue.loading();
      }

      // #623: watch the derived bool, not the whole enum. The facade only branches
      // on `== online`, so without `.select` every offline↔syncing transition
      // (noteLocalWrite fires one per queued write) needlessly recomputes the
      // balance for each group and the cross-group hero fold.
      final online = ref.watch(
        connectivityProvider.select((s) => s == ConnectivityStatus.online),
      );
      final aggregateMayBeStale = ref.watch(
        balanceAggregateFreshnessProvider.select(
          (dirty) => dirty.contains(groupId),
        ),
      );
      if (online) {
        final aggAsync = ref.watch(groupBalanceAggregateProvider(groupId));
        if (!aggregateMayBeStale && aggAsync.isLoading && !aggAsync.hasValue) {
          return const AsyncValue.loading();
        }
        final aggregate = aggAsync.valueOrNull;
        if (aggregate != null) {
          final aggregateHome = _homeBalanceFromAggregate(aggregate, uid);
          if (!aggregateMayBeStale) {
            return AsyncValue.data(aggregateHome);
          }
          final onceAsync = ref.watch(groupBalancesOnceProvider(groupId));
          return onceAsync.whenData((once) {
            final onceHome = _homeBalanceFromOnce(once, uid);
            if (_aggregateMatchesOnce(
              aggregate: aggregateHome,
              once: onceHome,
            )) {
              _clearStaleAggregateAfterBuild(ref, groupId);
              return aggregateHome;
            }
            return onceHome;
          });
        }
      }

      final onceAsync = ref.watch(groupBalancesOnceProvider(groupId));
      return onceAsync.whenData((once) => _homeBalanceFromOnce(once, uid));
    });

/// Cross-group fold over [homeGroupBalanceProvider] for [BalanceHeroCard].
///
/// LOADING until EVERY group resolves (a still-loading group must show the
/// skeleton, never a false all-settled zero). Per-currency buckets via the same
/// [_accumulateBucket]/[_sortedCurrencyBuckets] fold (#261 — no cross-currency
/// summing, ever).
///
/// #570: a single unreadable group is DROPPED, not fatal — the fold sums the
/// readable groups and flags `partial` so the hero shows the surviving total
/// plus the "may be incomplete" notice, mirroring the #244 per-event OR-drop.
/// ERROR is reserved for the total blackout (EVERY group hard-errors), where a
/// zero "all settled" hero would be a lie.
final crossGroupHomeBalanceProvider = Provider<AsyncValue<CrossGroupBalanceOnce>>((
  ref,
) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    // #997 D5 twin of the per-group facade: auth still resolving → loading.
    return const AsyncValue.loading();
  }

  final groupsAsync = ref.watch(userGroupsProvider);
  if (groupsAsync.isLoading && !groupsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (groupsAsync.hasError) {
    return AsyncValue.error(groupsAsync.error!, groupsAsync.stackTrace!);
  }
  final groups = groupsAsync.valueOrNull ?? [];

  final byCurrencyMap =
      <String, ({Decimal net, Decimal owedToUser, Decimal userOwes})>{};
  var partial = false;
  // #570: a single unreadable group must not blank the WHOLE hero. Mirror the
  // #244 per-event OR-drop at the group level — drop the unreadable group, flag
  // partial, sum the survivors. Capture the first error for the all-fail guard.
  var dropped = 0;
  Object? firstError;
  StackTrace? firstStack;
  for (final group in groups) {
    final balanceAsync = ref.watch(homeGroupBalanceProvider(group.id));
    if (balanceAsync.hasError && !balanceAsync.hasValue) {
      partial = true;
      dropped++;
      firstError ??= balanceAsync.error;
      firstStack ??= balanceAsync.stackTrace;
      continue;
    }
    if (balanceAsync.isLoading && !balanceAsync.hasValue) {
      return const AsyncValue.loading();
    }
    final balance = balanceAsync.requireValue;
    partial = partial || balance.partial;
    // #382 PR-3 (D12): fold per BUCKET currency (the honest key);
    // group.currency plays no part in the fold.
    for (final entry in balance.userNet.entries) {
      _accumulateBucket(byCurrencyMap, entry.key, entry.value);
    }
  }

  // Total blackout: every group was unreadable. A zero "all settled, may be
  // incomplete" hero would be a false negative — stay loud-safe (error card).
  if (groups.isNotEmpty && dropped == groups.length) {
    return AsyncValue.error(firstError!, firstStack ?? StackTrace.current);
  }

  return AsyncValue.data((
    balance: (
      byCurrency: _sortedCurrencyBuckets(byCurrencyMap),
      groupCount: groups.length,
      isLoading: false,
    ),
    partial: partial,
  ));
});
