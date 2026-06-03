import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final eventFinancialUids = <String>{
      for (final expense in eventExpenses) expense.payerParticipantId,
      for (final settlement in eventSettlements) ...[
        if (settlement.payerParticipantId != null)
          settlement.payerParticipantId!,
        if (settlement.recipientParticipantId != null)
          settlement.recipientParticipantId!,
      ],
    };
    final eventLocalFormerActors = eventFinancialUids.difference(liveMemberIds);
    allFormerFinancialActorsSeen.addAll(eventLocalFormerActors);

    final eventParticipantUids = <String>{
      ...event.participantIds,
      ...eventLocalFormerActors,
    };
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
/// - [net]: The current user's net balance across ALL groups (positive = owed
///   money, negative = owes money).
/// - [groupCount]: Total number of groups the user belongs to.
/// - [isLoading]: True if some group balance data is still loading (UI can
///   show partial data with a loading indicator).
typedef CrossGroupBalance =
    ({
      Decimal net,
      Decimal owedToUser,
      Decimal userOwes,
      int groupCount,
      bool isLoading,
    });

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
    return AsyncValue.data((
      net: Decimal.zero,
      owedToUser: Decimal.zero,
      userOwes: Decimal.zero,
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
    return AsyncValue.data((
      net: Decimal.zero,
      owedToUser: Decimal.zero,
      userOwes: Decimal.zero,
      groupCount: 0,
      isLoading: false,
    ));
  }

  var net = Decimal.zero;
  var owedToUser = Decimal.zero;
  var userOwes = Decimal.zero;
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
    net = net + groupNet;
    if (groupNet > Decimal.zero) {
      owedToUser += groupNet;
    } else if (groupNet < Decimal.zero) {
      userOwes += groupNet.abs();
    }
  }

  if (anyLoading && net == Decimal.zero) {
    return AsyncValue.data((
      net: Decimal.zero,
      owedToUser: owedToUser,
      userOwes: userOwes,
      groupCount: groups.length,
      isLoading: true,
    ));
  }
  return AsyncValue.data((
    net: net,
    owedToUser: owedToUser,
    userOwes: userOwes,
    groupCount: groups.length,
    isLoading: anyLoading,
  ));
});

// ---------------------------------------------------------------------------
// One-shot home aggregation (#104) — kills the O(G×E) permanent listener leak
// ---------------------------------------------------------------------------

// [ledgerRevisionProvider] (the liveness lever) lives in expense_provider.dart
// alongside the write services; this file imports it already.

/// One-shot variant of [groupBalancesProvider] for the always-mounted home
/// dashboard (#104).
///
/// The LIST inputs (events, members, group settlements) stay LIVE — they are
/// O(G) listeners, not the O(G×E) leak, and reusing the existing stream
/// providers inherits the #190 `isDeleted` group filter and the D-25 null-date
/// event sort unchanged (no re-implementation, no divergence). Only the
/// O(G×E) per-event expense/settlement reads are one-shot `.get()`.
///
/// Calls the SAME [computeGroupBalances] as the live provider, so the home
/// headline and the OUTBOUND in-group settle-up screen can never diverge.
final groupBalancesOnceProvider = FutureProvider.autoDispose
    .family<GroupBalances, String>((ref, groupId) async {
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
  for (final event in events) {
    allExpenses.addAll(await expenseService.getExpenses(groupId, event.id));
    allEventSettlements
        .addAll(await settlementService.getSettlements(groupId, event.id));
  }

  return computeGroupBalances(
    events: events,
    members: members,
    allExpenses: allExpenses,
    allEventSettlements: allEventSettlements,
    groupSettlements: groupSettlements,
  );
});

/// One-shot variant of [crossGroupBalanceProvider] for [BalanceHeroCard] (#104).
///
/// Reduces identically to the live provider: sums each group's per-user net
/// scalar ([UserBalance.netBalance], which already folds settlements), then
/// sign-splits that scalar into owed/owes. It does NOT sum `totalPaid` slices —
/// that would drop settlement effects.
final crossGroupBalanceOnceProvider =
    FutureProvider.autoDispose<CrossGroupBalance>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return (
      net: Decimal.zero,
      owedToUser: Decimal.zero,
      userOwes: Decimal.zero,
      groupCount: 0,
      isLoading: false,
    );
  }

  final groups = await ref.watch(userGroupsProvider.future);
  var net = Decimal.zero;
  var owedToUser = Decimal.zero;
  var userOwes = Decimal.zero;
  for (final group in groups) {
    final balances = await ref.watch(groupBalancesOnceProvider(group.id).future);
    final groupNet = balances.balances
            .where((b) => b.participantId == uid)
            .firstOrNull
            ?.netBalance ??
        Decimal.zero;
    net = net + groupNet;
    if (groupNet > Decimal.zero) {
      owedToUser += groupNet;
    } else if (groupNet < Decimal.zero) {
      userOwes += groupNet.abs();
    }
  }

  return (
    net: net,
    owedToUser: owedToUser,
    userOwes: userOwes,
    groupCount: groups.length,
    isLoading: false,
  );
});
