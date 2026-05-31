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

  final allSettlements = <Settlement>[
    ...allEventSettlements,
    ...(groupSettlementsAsync.valueOrNull ?? []),
  ];

  // Proceed with available data even if some events are still loading —
  // returning AsyncValue.loading() here deadlocks the balance card when
  // new events have zero expenses.

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
  final groupSettlements = groupSettlementsAsync.valueOrNull ?? const [];
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

  final balances = allUids.map((uid) {
    final display = MemberNameResolver.resolveGroupScoped(
      uid: uid,
      members: members,
      fallbackName: uidToFallbackName[uid],
    );
    final eventNet = netBalancePerUid[uid] ?? Decimal.zero;
    final groupSettlementNet = groupScopedSettlementAdj[uid] ?? Decimal.zero;
    return UserBalance(
      participantId: uid,
      displayName: MemberNameResolver.format(display),
      totalPaid: totalPaidPerUid[uid] ?? Decimal.zero,
      totalOwed: totalOwedPerUid[uid] ?? Decimal.zero,
      netBalance: eventNet + groupSettlementNet,
    );
  }).toList();

  // Step 7: Compute per-event breakdown (RESEARCH Pattern 4). This drill-down
  // intentionally keeps using event.participantIds only; aggregate balances
  // above are the authoritative settle-up participant set.
  final perEventBreakdown = _buildPerEventBreakdown(events, ref, groupId);

  final memberNames = <String, String>{};
  final memberRawNames = <String, String>{};
  for (final uid in allUids) {
    final display = MemberNameResolver.resolveGroupScoped(
      uid: uid,
      members: members,
      fallbackName: uidToFallbackName[uid],
    );
    memberNames[uid] = MemberNameResolver.format(display);
    memberRawNames[uid] = display.rawName;
  }

  return AsyncValue.data((
    balances: balances,
    totalSpent: BalanceCalculator.calculateTotalExpenses(allExpenses),
    eventCount: events.length,
    perEventBreakdown: perEventBreakdown,
    memberNames: memberNames,
    memberRawNames: memberRawNames,
  ));
});

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
/// This function intentionally calls [ref.watch] — it is only ever called from
/// within the [groupBalancesProvider] Provider.family body where this is safe.
Map<String, Map<String, Decimal>> _buildPerEventBreakdown(
  List<Event> events,
  Ref ref,
  String groupId,
) {
  final breakdown = <String, Map<String, Decimal>>{};

  for (final event in events) {
    final eventRef = (groupId: groupId, eventId: event.id);
    final expenses =
        ref.watch(eventExpensesProvider(eventRef)).valueOrNull ?? [];
    final settlements =
        ref.watch(eventSettlementsProvider(eventRef)).valueOrNull ?? [];

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
