import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../trip/models/trip_model.dart';
import '../models/group_activity_log_model.dart';
import '../services/group_activity_service.dart';
import '../services/group_settlement_service.dart';
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
typedef GroupBalances = ({
  List<UserBalance> balances,
  Decimal totalSpent,
  int eventCount,
  Map<String, Map<String, Decimal>> perEventBreakdown,
  Map<String, String> memberNames,
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
/// 5. Combine all expenses + settlements through [BalanceCalculator].
/// 6. Build per-event breakdown and member names map for UI.
///
/// Returns [AsyncValue.loading] while any required stream has no value yet.
/// Returns [AsyncValue.error] if the events stream fails.
/// Returns [AsyncValue.data] wrapping a [GroupBalances] record once all data
/// is available.
///
/// The provider automatically recomputes whenever any watched stream emits.
final groupBalancesProvider =
    Provider.family<AsyncValue<GroupBalances>, String>((ref, groupId) {
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
  if (members.isEmpty) return const AsyncValue.loading();

  // Step 3: Watch group-level settlements (D-07)
  final groupSettlementsAsync = ref.watch(groupSettlementsProvider(groupId));

  // Step 4: For each event, watch expenses and settlements.
  // ref.watch inside a loop is valid in Provider.family bodies (RESEARCH Pitfall 2).
  final allExpenses = <Expense>[];
  final allEventSettlements = <Settlement>[];
  var isLoadingAny = false;

  for (final event in events) {
    final eventRef = (groupId: groupId, eventId: event.id);
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));

    if ((expensesAsync.isLoading && !expensesAsync.hasValue) ||
        (settlementsAsync.isLoading && !settlementsAsync.hasValue)) {
      isLoadingAny = true;
      continue;
    }

    allExpenses.addAll(expensesAsync.valueOrNull ?? []);
    allEventSettlements.addAll(settlementsAsync.valueOrNull ?? []);
  }

  // Combine event settlements + group settlements (immutable — create new list)
  final allSettlements = <Settlement>[
    ...allEventSettlements,
    ...(groupSettlementsAsync.valueOrNull ?? []),
  ];

  if (isLoadingAny && allExpenses.isEmpty) {
    return const AsyncValue.loading();
  }

  // Step 5: Build unified participant list from group members (D-04 UID-based identity)
  final participants = members
      .map(
        (m) => Participant(
          id: m.userId,
          tripId: groupId, // sentinel — BalanceCalculator does not use tripId
          role: ParticipantRole.member,
          joinedAt: m.joinedAt,
          displayName: m.displayName,
        ),
      )
      .toList();

  // Step 6: Run BalanceCalculator on combined data (D-05)
  final balances = BalanceCalculator.calculateBalances(
    expenses: allExpenses,
    settlements: allSettlements,
    participants: participants,
  );

  // Step 7: Compute per-event breakdown (RESEARCH Pattern 4)
  final perEventBreakdown = _buildPerEventBreakdown(events, ref, groupId);

  // Step 8: Build member names map for settlement display
  final memberNames = {for (final m in members) m.userId: m.displayName};

  return AsyncValue.data((
    balances: balances,
    totalSpent: BalanceCalculator.calculateTotalExpenses(allExpenses),
    eventCount: events.length,
    perEventBreakdown: perEventBreakdown,
    memberNames: memberNames,
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
/// Using a Provider instead of reading [FirebaseConfig.currentUser] directly
/// makes [crossGroupBalanceProvider] testable via Riverpod overrides without
/// requiring a real Firebase Auth instance.
final currentUserIdProvider = Provider<String?>((ref) {
  return FirebaseConfig.currentUser?.uid;
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
typedef CrossGroupBalance = ({Decimal net, int groupCount, bool isLoading});

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
final crossGroupBalanceProvider = Provider<AsyncValue<CrossGroupBalance>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return AsyncValue.data(
      (net: Decimal.zero, groupCount: 0, isLoading: false),
    );
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
    return AsyncValue.data(
      (net: Decimal.zero, groupCount: 0, isLoading: false),
    );
  }

  var net = Decimal.zero;
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
    net = net + (userBalance?.netBalance ?? Decimal.zero);
  }

  if (anyLoading && net == Decimal.zero) return const AsyncValue.loading();
  return AsyncValue.data((
    net: net,
    groupCount: groups.length,
    isLoading: anyLoading,
  ));
});
