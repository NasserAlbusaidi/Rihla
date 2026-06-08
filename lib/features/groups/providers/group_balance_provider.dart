import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/supported_currencies.dart';
import '../../auth/providers/auth_provider.dart';
import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../trip/models/trip_model.dart';
import '../models/group_activity_log_model.dart';
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

/// Reactive stream of the most recent group-level activity entries (default 5).
///
/// Backed by [GroupActivityService.watchRecentActivity]. Activity entries
/// live at `groups/{groupId}/activity`.
final groupActivityProvider =
    StreamProvider.family<List<GroupActivityLog>, String>((ref, groupId) {
      final service = ref.read(groupActivityServiceProvider);
      return service.watchRecentActivity(groupId);
    });

// ---------------------------------------------------------------------------
// GroupBalances typedef
// ---------------------------------------------------------------------------

/// Record type for the group balance computation result.
///
/// Consumed by the group dashboard UI widgets and group settlement screens.
///
/// Fields:
/// - [balances]: Per-member net balances aggregated across all group events
///   and group-level settlements.
/// - [totalSpent]: Sum of all expenses across all group events (OMR Decimal).
/// - [eventCount]: Number of events included in the computation.
/// - [perEventBreakdown]: memberId → eventId → netBalance for that member in
///   that event. Used for drill-down UI views.
/// - [memberNames]: memberId → displayName map for settlement rendering.
/// - [memberRawNames]: memberId → raw displayName map for settlement writes.
typedef GroupBalances = ({
  List<UserBalance> balances,
  Decimal totalSpent,
  int eventCount,
  Map<String, Map<String, Decimal>> perEventBreakdown,
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
final groupFailedEventIdsProvider =
    Provider.family<Set<String>, String>((ref, groupId) {
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

  final totalPaidPerUid = <String, Decimal>{};
  final totalOwedPerUid = <String, Decimal>{};
  final netBalancePerUid = <String, Decimal>{};
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

    final eventBalances = BalanceCalculator.calculateBalances(
      expenses: eventExpenses,
      settlements: eventSettlements,
      participants: eventParticipants,
    );

    for (final balance in eventBalances) {
      totalPaidPerUid.update(
        balance.participantId,
        (value) => value + balance.totalPaid,
        ifAbsent: () => balance.totalPaid,
      );
      totalOwedPerUid.update(
        balance.participantId,
        (value) => value + balance.totalOwed,
        ifAbsent: () => balance.totalOwed,
      );
      netBalancePerUid.update(
        balance.participantId,
        (value) => value + balance.netBalance,
        ifAbsent: () => balance.netBalance,
      );
    }
  }

  final groupScopedSettlementAdj = <String, Decimal>{};
  for (final settlement in groupSettlements) {
    final payerId = settlement.payerParticipantId;
    final recipientId = settlement.recipientParticipantId;
    if (payerId != null) {
      groupScopedSettlementAdj.update(
        payerId,
        (value) => value + settlement.amount,
        ifAbsent: () => settlement.amount,
      );
    }
    if (recipientId != null) {
      groupScopedSettlementAdj.update(
        recipientId,
        (value) => value - settlement.amount,
        ifAbsent: () => -settlement.amount,
      );
    }
  }

  final allUids = <String>{
    ...allMemberIds,
    ...allFormerFinancialActorsSeen,
    ...totalPaidPerUid.keys,
    ...totalOwedPerUid.keys,
    ...netBalancePerUid.keys,
    ...groupScopedSettlementAdj.keys,
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

  final balances = allUids.map((uid) {
    final eventNet = netBalancePerUid[uid] ?? Decimal.zero;
    final groupSettlementNet = groupScopedSettlementAdj[uid] ?? Decimal.zero;
    return UserBalance(
      participantId: uid,
      displayName:
          memberNames[uid] ?? MemberNameResolver.format(displaysByUid[uid]!),
      totalPaid: totalPaidPerUid[uid] ?? Decimal.zero,
      totalOwed: totalOwedPerUid[uid] ?? Decimal.zero,
      netBalance: eventNet + groupSettlementNet,
    );
  }).toList();

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
    totalSpent: BalanceCalculator.calculateTotalExpenses(allExpenses),
    eventCount: events.length,
    perEventBreakdown: perEventBreakdown,
    memberNames: memberNames,
    memberRawNames: memberRawNames,
  );
}

// ---------------------------------------------------------------------------
// Helper: per-event breakdown
// ---------------------------------------------------------------------------

/// Builds a breakdown of each member's net balance per event.
///
/// Returns: memberId → { eventId → netBalance }
///
/// For each event, participants are derived from [Event.participantIds] and
/// [Event.participantNames] (UID-based per D-04). Only events with at least
/// one participant are included.
///
/// Reuses the per-event expense/settlement maps the caller already built from
/// its own `ref.watch` fan-out — no redundant re-watch here (#112). The
/// participant set stays [Event.participantIds]-only on purpose: the aggregate
/// balances above fold in former financial actors, but the drill-down does not.
Map<String, Map<String, Decimal>> _buildPerEventBreakdown(
  List<Event> events,
  Map<String, List<Expense>> expensesByEvent,
  Map<String, List<Settlement>> eventSettlementsByEvent,
) {
  final breakdown = <String, Map<String, Decimal>>{};

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

    final eventBalances = BalanceCalculator.calculateBalances(
      expenses: expenses,
      settlements: settlements,
      participants: participants,
    );

    for (final b in eventBalances) {
      breakdown.putIfAbsent(b.participantId, () => {})[event.id] = b.netBalance;
    }
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
typedef CurrencyBalance =
    ({
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
typedef CrossGroupBalance =
    ({
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

// ---------------------------------------------------------------------------
// crossGroupBalanceProvider
// ---------------------------------------------------------------------------

/// Aggregates the current user's personal net balance across ALL groups.
///
/// Uses `Provider` (NOT `Provider.family` or `StreamProvider`) because there
/// is only one current user. Reads UID from [currentUserIdProvider] (injectable
/// for tests).
///
/// Pattern: identical to [groupBalancesProvider] — `ref.watch` in a loop over
/// variable-length groups list, which is safe in Provider bodies
/// (RESEARCH Pitfall 2).
///
/// Returns:
/// - [AsyncValue.loading] while [userGroupsProvider] has no value
/// - [AsyncValue.error] if [userGroupsProvider] errors
/// - [AsyncValue.data] with [CrossGroupBalance] containing net sum, group
///   count, and loading flag
final crossGroupBalanceProvider = Provider<AsyncValue<CrossGroupBalance>>((
  ref,
) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return const AsyncValue.data((
      byCurrency: <CurrencyBalance>[],
      groupCount: 0,
      isLoading: false,
    ));
  }

  final groupsAsync = ref.watch(userGroupsProvider);
  if (groupsAsync.isLoading && !groupsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (groupsAsync.hasError) {
    return AsyncValue.error(groupsAsync.error!, groupsAsync.stackTrace!);
  }
  final groups = groupsAsync.valueOrNull ?? [];
  if (groups.isEmpty) {
    return const AsyncValue.data((
      byCurrency: <CurrencyBalance>[],
      groupCount: 0,
      isLoading: false,
    ));
  }

  final byCurrencyMap =
      <String, ({Decimal net, Decimal owedToUser, Decimal userOwes})>{};
  var anyLoading = false;

  for (final group in groups) {
    final balancesAsync = ref.watch(groupBalancesProvider(group.id));
    if (balancesAsync.isLoading && !balancesAsync.hasValue) {
      anyLoading = true;
      continue;
    }
    final balances = balancesAsync.valueOrNull;
    if (balances == null) continue;
    final userBalance = balances.balances
        .where((b) => b.participantId == uid)
        .firstOrNull;
    final groupNet = userBalance?.netBalance ?? Decimal.zero;
    _accumulateBucket(byCurrencyMap, group.currency, groupNet);
  }

  return AsyncValue.data((
    byCurrency: _sortedCurrencyBuckets(byCurrencyMap),
    groupCount: groups.length,
    isLoading: anyLoading,
  ));
});

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
  final groupSettlementsFut =
      ref.watch(groupSettlementsProvider(groupId).future);
  ref.watch(ledgerRevisionProvider);

  final events = await eventsFut;
  final members = await membersFut;
  final groupSettlements = await groupSettlementsFut;

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
      final eventExpenses =
          await expenseService.getExpenses(groupId, event.id);
      final eventSettlements =
          await settlementService.getSettlements(groupId, event.id);
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

/// One-shot variant of [crossGroupBalanceProvider] for [BalanceHeroCard] (#104).
///
/// Reduces identically to the live provider: sums each group's per-user net
/// scalar ([UserBalance.netBalance], which already folds settlements), then
/// sign-splits that scalar into owed/owes. It does NOT sum `totalPaid` slices —
/// that would drop settlement effects.
///
/// [partial] (#244) is the OR over groups of "did a per-event read fail." A
/// whole-group reject (a coarse list-read failure inside
/// [groupBalancesOnceProvider]) still propagates → this future rejects → the
/// hero shows the error card (loud-safe preserved for the coarse case).
final crossGroupBalanceOnceProvider =
    FutureProvider.autoDispose<CrossGroupBalanceOnce>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return (
      balance: (
        byCurrency: const <CurrencyBalance>[],
        groupCount: 0,
        isLoading: false,
      ),
      partial: false,
    );
  }

  final groups = await ref.watch(userGroupsProvider.future);
  final byCurrencyMap =
      <String, ({Decimal net, Decimal owedToUser, Decimal userOwes})>{};
  var partial = false;
  for (final group in groups) {
    final result = await ref.watch(groupBalancesOnceProvider(group.id).future);
    partial = partial || result.failedEventIds.isNotEmpty;
    final groupNet =
        result.balances.balances
            .where((b) => b.participantId == uid)
            .firstOrNull
            ?.netBalance ??
        Decimal.zero;
    _accumulateBucket(byCurrencyMap, group.currency, groupNet);
  }

  return (
    balance: (
      byCurrency: _sortedCurrencyBuckets(byCurrencyMap),
      groupCount: groups.length,
      isLoading: false,
    ),
    partial: partial,
  );
});
