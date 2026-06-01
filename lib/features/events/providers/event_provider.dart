import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event_model.dart';
import '../services/event_service.dart';

// ---------------------------------------------------------------------------
// State providers (mirror group_provider.dart pattern)
// ---------------------------------------------------------------------------

/// Whether an event operation (create/update/delete) is in progress.
final eventLoadingProvider = StateProvider<bool>((ref) => false);

/// Error message from the most recent event operation, or null.
final eventErrorProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// EventService provider
// ---------------------------------------------------------------------------

/// Provider for [EventService].
final eventServiceProvider = Provider<EventService>(EventService.new);

// ---------------------------------------------------------------------------
// Stream providers
// ---------------------------------------------------------------------------

/// Reactive stream of all non-deleted events in a group.
///
/// Sort order per D-25:
///   - Events without a startDate sort to the top (null-date first).
///   - All others sorted by createdAt descending (newest first).
///
/// The Firestore query filters isDeleted=false and orders by createdAt DESC.
/// Client-side sort overrides the order for null-date events (D-25).
final groupEventsProvider = StreamProvider.family<List<Event>, String>((
  ref,
  groupId,
) {
  return ref.watch(eventServiceProvider).watchGroupEvents(groupId);
});

/// Reactive stream for a single event by compound key {groupId, eventId}.
///
/// Returns null if the event does not exist or has been hard-deleted.
/// Uses a Dart record as the family parameter to avoid creating a custom
/// class for a two-field key.
final eventDetailProvider =
    StreamProvider.family<Event?, ({String groupId, String eventId})>((
      ref,
      params,
    ) {
      return ref
          .watch(eventServiceProvider)
          .watchEvent(groupId: params.groupId, eventId: params.eventId);
    });
