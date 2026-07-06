import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../../ledger/providers/expense_provider.dart';

/// One entry in the Home "Active journeys" strip — a flattened event view
/// enriched with the current user's net balance and the participating members'
/// names for avatar stacking.
class ActiveJourneyEntry {
  const ActiveJourneyEntry({
    required this.eventId,
    required this.groupId,
    required this.title,
    required this.type,
    required this.memberNames,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    required this.nets,
    required this.fallbackCurrency,
    this.unresolvedBalance = false,
  });

  /// Event ID — used for routing taps to the event hub.
  final String eventId;

  /// Group ID the event belongs to.
  final String groupId;

  /// The current user's net balance per currency for this event — one entry
  /// per NON-ZERO bucket, GCC-first (#382 PR-5). Empty ⇔ settled everywhere,
  /// UNLESS [unresolvedBalance] is true (then it's "unknown", not settled).
  /// Each net is honest to its own currency (never relabeled to the group
  /// default).
  final List<({String currency, Decimal net})> nets;

  /// Currency for the settled zero line when [nets] is empty (= `group.currency`)
  /// — the card otherwise has no currency source for the all-zero render
  /// (#382 PR-5).
  final String fallbackCurrency;

  /// True when this event's group balance facade was loading/errored at
  /// build time — [nets] is a forced-empty placeholder, NOT a real "settled"
  /// read (#997 refute follow-up). Display-layer only: never persisted, and
  /// never gates whether the ticket itself appears (that comes from
  /// [groupEventsProvider] alone) — it only tells the ticket card to render
  /// a neutral placeholder instead of a false 0.000 net.
  final bool unresolvedBalance;

  /// Event name — `Event.name`.
  final String title;

  /// Event type — drives cover-art palette in the ticket card.
  final EventType type;

  /// Names of the event participants, in stable order.
  final List<String> memberNames;

  /// Event start date — may be null for events without one.
  final DateTime? startDate;

  /// Event end date — may be null for events without one.
  final DateTime? endDate;

  /// When the event was created — fallback sort key for undated events.
  final DateTime createdAt;

  /// Settled ⇔ every bucket zero (no non-zero lines) AND the balance is
  /// actually known — an unresolved facade is "unknown", never "settled".
  bool get isSettled => nets.isEmpty && !unresolvedBalance;
}

/// Window for "active": ongoing right now, OR starts within the next 60 days,
/// OR ended within the last 14 days. Past events outside that window fall off.
const _upcomingWindow = Duration(days: 60);
const _recentEndedWindow = Duration(days: 14);

bool _isActive(Event event, DateTime now) {
  final start = event.startDate;
  final end = event.endDate;

  // Both dates known — classify against `now`.
  if (start != null && end != null) {
    if (now.isAfter(start.subtract(const Duration(seconds: 1))) &&
        now.isBefore(end.add(const Duration(days: 1)))) {
      return true; // ongoing
    }
    if (start.isAfter(now) && start.difference(now) <= _upcomingWindow) {
      return true; // upcoming
    }
    if (end.isBefore(now) && now.difference(end) <= _recentEndedWindow) {
      return true; // recently ended
    }
    return false;
  }

  // Only a start date — upcoming or recently started.
  if (start != null) {
    final delta = start.difference(now);
    return delta.abs() <= _upcomingWindow;
  }

  // No dates at all — surface so the user can act on it; recent events first.
  return true;
}

/// Sort key — smaller value = higher priority on the strip.
///
/// Ongoing events: 0
/// Upcoming events: days until start (1..60)
/// Recently ended: 1000 + days since end (so they sort after upcoming)
/// Undated events: 500 + days since [fallback] (typically the event's creation
/// timestamp).
int _priority({
  required DateTime? start,
  required DateTime? end,
  required DateTime fallback,
  required DateTime now,
}) {
  if (start != null && end != null) {
    if (now.isAfter(start) && now.isBefore(end)) return 0;
    if (start.isAfter(now)) return start.difference(now).inDays + 1;
    if (end.isBefore(now)) return 1000 + now.difference(end).inDays;
  }
  if (start != null) {
    final days = start.difference(now).inDays.abs();
    return start.isAfter(now) ? days + 1 : 500 + days;
  }
  return 500 + now.difference(fallback).inDays;
}

/// One row in the add-expense target picker (#364) — an open event the
/// current user can actually write an expense into.
class AddExpenseTarget {
  const AddExpenseTarget({
    required this.groupId,
    required this.eventId,
    required this.eventName,
    required this.groupName,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
  });

  final String groupId;
  final String eventId;
  final String eventName;
  final String groupName;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime createdAt;
}

/// Aggregate result for the FAB picker (#364).
class AddExpenseTargets {
  const AddExpenseTargets({
    required this.active,
    required this.openByGroup,
    required this.totalOpen,
    required this.sole,
    required this.allResolved,
  });

  static const empty = AddExpenseTargets(
    active: [],
    openByGroup: {},
    totalOpen: 0,
    sole: null,
    allResolved: true,
  );

  /// Open targets inside the [_isActive] window, [_priority]-sorted, uncapped.
  final List<AddExpenseTarget> active;

  /// EVERY open target keyed by group — window-independent, per-group
  /// [_priority]-sorted, groups with no open target omitted. Feeds the
  /// sheet's browse-all fallback so the D-4 filter lives in one place.
  final Map<String, List<AddExpenseTarget>> openByGroup;

  /// Every open target across all resolved groups — ignores the window, so an
  /// open event that ended long ago still counts (it stays reachable via the
  /// sheet's browse-all fallback).
  final int totalOpen;

  /// The fast-path target: non-null iff exactly one open event exists AND
  /// every group's event stream has resolved. May lie outside the window.
  final AddExpenseTarget? sole;

  /// False while any group's event stream is still loading (or errored) —
  /// the fast path must never fire on partial data.
  final bool allResolved;

  /// The FAB fast-path target (#900 / friction #1): the ranked top pick
  /// whenever one exists, so a 2+-group user stops paying the picker sheet
  /// on every add. **First line is the guard** — never fires on partial
  /// data, mirroring [sole]'s own `allResolved` guard. Falls through
  /// `active.first` (window-filtered, `_priority`-sorted) → [sole] (a single
  /// open event outside the window) → the highest-priority open target
  /// across ALL groups (still outside the window, but more than one open
  /// target exists). Zero open targets anywhere → null. A wrong guess is
  /// recoverable via the editor's "change destination" affordance — this is
  /// deliberately not gated on being "certainly correct."
  AddExpenseTarget? get preferred {
    if (!allResolved) return null;
    if (active.isNotEmpty) return active.first;
    return sole ?? _firstAcrossOpenByGroup(openByGroup);
  }
}

/// Flattens [openByGroup], preserving each group's own `_priority` order
/// (already sorted ascending at construction), and returns the globally
/// highest-priority target — i.e. the best of each group's own best. Only
/// reached by [AddExpenseTargets.preferred] when nothing is in the active
/// window and more than one open target exists (so [AddExpenseTargets.sole]
/// is null).
AddExpenseTarget? _firstAcrossOpenByGroup(
  Map<String, List<AddExpenseTarget>> openByGroup,
) {
  if (openByGroup.isEmpty) return null;
  final now = DateTime.now();
  AddExpenseTarget? best;
  int? bestPriority;
  for (final targets in openByGroup.values) {
    if (targets.isEmpty) continue;
    final candidate = targets.first;
    final priority = _priority(
      start: candidate.startDate,
      end: candidate.endDate,
      fallback: candidate.createdAt,
      now: now,
    );
    if (bestPriority == null || priority < bestPriority) {
      bestPriority = priority;
      best = candidate;
    }
  }
  return best;
}

/// Flattens every event across the user's groups into add-expense targets
/// for the tab-shell FAB (#364).
///
/// "Open" = not soft-deleted, not closed (#723), and the current user is an
/// event participant — `validExpenseCreate` requires `isEventParticipant`,
/// so offering a non-participant event would dead-end in `permission-denied`.
///
/// Same stream sources and error-swallow semantics as [activeJourneysProvider]
/// (both watch streams the always-mounted home tab already holds live).
final addExpenseTargetsProvider = Provider<AsyncValue<AddExpenseTargets>>((
  ref,
) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const AsyncValue.data(AddExpenseTargets.empty);

  final groupsAsync = ref.watch(userGroupsProvider);
  if (groupsAsync.isLoading && !groupsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (groupsAsync.hasError) {
    return AsyncValue.error(groupsAsync.error!, groupsAsync.stackTrace!);
  }

  final groups = groupsAsync.valueOrNull ?? [];
  final now = DateTime.now();
  var allResolved = true;
  var totalOpen = 0;
  AddExpenseTarget? lastOpen;
  final windowed = <(int, AddExpenseTarget)>[];
  final openByGroup = <String, List<AddExpenseTarget>>{};

  for (final group in groups) {
    final events = ref.watch(groupEventsProvider(group.id)).valueOrNull;
    if (events == null) {
      allResolved = false;
      continue;
    }
    final groupOpen = <(int, AddExpenseTarget)>[];
    for (final event in events) {
      final open = !event.isDeleted &&
          !event.isClosed &&
          event.participantIds.contains(uid);
      if (!open) continue;
      totalOpen++;
      final target = AddExpenseTarget(
        groupId: group.id,
        eventId: event.id,
        eventName: event.name,
        groupName: group.name,
        startDate: event.startDate,
        endDate: event.endDate,
        createdAt: event.createdAt,
      );
      lastOpen = target;
      final priority = _priority(
        start: event.startDate,
        end: event.endDate,
        fallback: event.createdAt,
        now: now,
      );
      groupOpen.add((priority, target));
      if (_isActive(event, now)) {
        windowed.add((priority, target));
      }
    }
    if (groupOpen.isNotEmpty) {
      groupOpen.sort((a, b) => a.$1.compareTo(b.$1));
      openByGroup[group.id] = [for (final entry in groupOpen) entry.$2];
    }
  }

  windowed.sort((a, b) => a.$1.compareTo(b.$1));
  return AsyncValue.data(
    AddExpenseTargets(
      active: [for (final entry in windowed) entry.$2],
      openByGroup: openByGroup,
      totalOpen: totalOpen,
      sole: allResolved && totalOpen == 1 ? lastOpen : null,
      allResolved: allResolved,
    ),
  );
});

/// Flattens every event across the user's groups, filters to a sensible
/// "active" window, sorts by date proximity, and caps the list at 5.
///
/// Each entry carries the user's net balance for that event so the ticket
/// card can render the sage/rust trailing amount without re-deriving it.
///
/// Returns [AsyncValue.loading] until at least the groups list resolves.
/// Errors in individual group event streams are swallowed (those events
/// just don't appear) rather than blocking the whole strip.
final activeJourneysProvider =
    Provider<AsyncValue<List<ActiveJourneyEntry>>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const AsyncValue.data([]);

  final groupsAsync = ref.watch(userGroupsProvider);
  if (groupsAsync.isLoading && !groupsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (groupsAsync.hasError) {
    return AsyncValue.error(groupsAsync.error!, groupsAsync.stackTrace!);
  }

  final groups = groupsAsync.valueOrNull ?? [];
  if (groups.isEmpty) return const AsyncValue.data([]);

  final now = DateTime.now();
  final entries = <ActiveJourneyEntry>[];

  for (final group in groups) {
    final eventsAsync = ref.watch(groupEventsProvider(group.id));
    final events = eventsAsync.valueOrNull;
    if (events == null) continue;

    final activeEvents = events
        .where((event) => !event.isDeleted && _isActive(event, now))
        .toList(growable: false);
    if (activeEvents.isEmpty) continue;

    // #366: per-event nets come from the source-agnostic facade (the server
    // aggregate's perEventNetMilli slice when online, the #104 once-path
    // breakdown otherwise) — the strip holds no live per-event listeners
    // either way. The active-window filter above still watches the LIVE
    // groupEventsProvider, so event add/remove refreshes the strip.
    //
    // #997 refute follow-up: ticket EXISTENCE must never depend on this
    // facade — dropping a group's tickets while its balance is
    // loading/errored (the original #997 fix) turns into a false "No
    // upcoming journeys" empty state under sustained flaky network, worse
    // than the false 0.000 net it was fixing. So a loading/errored facade
    // only suppresses the NET DISPLAY for this group's tickets (via
    // `unresolvedBalance`) — the tickets themselves stay, sourced from
    // `activeEvents` above regardless of balance state.
    final balanceAsync = ref.watch(homeGroupBalanceProvider(group.id));
    final unresolvedBalance =
        (balanceAsync.isLoading && !balanceAsync.hasValue) ||
        (balanceAsync.hasError && !balanceAsync.hasValue);
    final userEventBalances = balanceAsync.valueOrNull?.userPerEventNet ??
        const <String, Map<String, Decimal>>{};

    for (final event in activeEvents) {
      // One line per non-zero currency bucket, GCC-first, each honest to its
      // own currency (#382 PR-5). Empty ⇔ settled — the card renders a single
      // zero line in `fallbackCurrency` (= group.currency). Forced empty
      // while `unresolvedBalance` — the card renders a neutral placeholder
      // instead (never a false settled zero).
      final nets = unresolvedBalance
          ? const <({String currency, Decimal net})>[]
          : nonZeroNetsGccFirst(
              userEventBalances[event.id] ?? const <String, Decimal>{},
            );
      entries.add(ActiveJourneyEntry(
        eventId: event.id,
        groupId: group.id,
        title: event.name,
        type: event.type,
        memberNames: event.participantIds
            .map((id) => event.participantNames[id] ?? '')
            .where((name) => name.isNotEmpty)
            .toList(growable: false),
        startDate: event.startDate,
        endDate: event.endDate,
        createdAt: event.createdAt,
        nets: nets,
        fallbackCurrency: group.currency,
        unresolvedBalance: unresolvedBalance,
      ));
    }
  }

  entries.sort((a, b) {
    final aPriority = _priority(
      start: a.startDate,
      end: a.endDate,
      fallback: a.createdAt,
      now: now,
    );
    final bPriority = _priority(
      start: b.startDate,
      end: b.endDate,
      fallback: b.createdAt,
      now: now,
    );
    return aPriority.compareTo(bPriority);
  });

  return AsyncValue.data(entries.take(5).toList(growable: false));
});
