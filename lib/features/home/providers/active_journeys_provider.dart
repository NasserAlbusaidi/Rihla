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
    required this.userBalance,
    required this.currency,
  });

  /// Event ID — used for routing taps to the event hub.
  final String eventId;

  /// Group ID the event belongs to.
  final String groupId;

  /// Currency of the bucket [userBalance] was selected from (#382 PR-3 —
  /// honest label, never relabeled to the group default); falls back to
  /// `group.currency` only when every bucket is zero.
  final String currency;

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

  /// Current user's net balance for this event (positive = owed, negative = owes).
  final Decimal userBalance;
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
    final balanceAsync = ref.watch(homeGroupBalanceProvider(group.id));
    final userEventBalances = balanceAsync.valueOrNull?.userPerEventNet ??
        const <String, Map<String, Decimal>>{};

    for (final event in activeEvents) {
      // One amount per ticket until #382 PR-5: the GCC-first non-zero bucket,
      // labeled with its own currency (honest — D11).
      final sel = selectNetBucket(
        userEventBalances[event.id] ?? const <String, Decimal>{},
        fallbackCurrency: group.currency,
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
        userBalance: sel.net,
        currency: sel.currency,
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
