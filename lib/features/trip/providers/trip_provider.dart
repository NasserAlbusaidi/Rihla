import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/cache_service.dart';
import '../../events/providers/event_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../models/trip_model.dart';

/// Derived provider: list of group IDs the current user belongs to.
/// Used by [currentParticipantProvider] to scan events across groups.
final userGroupsForParticipantProvider = Provider<List<String>>((ref) {
  final groupsAsync = ref.watch(userGroupsProvider);
  return groupsAsync.valueOrNull?.map((g) => g.id).toList() ?? [];
});

/// Trip participants — reads from SQLite cache.
///
/// @Deprecated('Will be migrated to Firestore stream in 04-05.')
final tripLogisticsParticipantsProvider =
    StreamProvider.family<List<Participant>, String>((ref, tripId) async* {
  yield await CacheService.getCachedParticipants(tripId);
});

/// Provider for the current user's participant record in an event.
///
/// The [eventId] parameter is the event ID (same as bridgeTripId). This
/// provider looks up the Firebase UID in the Event's participantIds list,
/// which is stored in Firestore.
final currentParticipantProvider = Provider.family<Participant?, String>((
  ref,
  eventId,
) {
  String? uid;
  try {
    uid = FirebaseConfig.currentUser?.uid;
  } catch (_) {
    // Firebase not initialized (e.g. in tests)
  }

  if (uid == null) return null;

  // Find the event across all groups by scanning groupEventsProvider streams.
  final userGroups = ref.watch(userGroupsForParticipantProvider);
  for (final groupId in userGroups) {
    final eventsAsync = ref.watch(groupEventsProvider(groupId));
    final events = eventsAsync.valueOrNull;
    if (events == null) continue;
    final event = events.where((e) => e.id == eventId).firstOrNull;
    if (event != null && event.participantIds.contains(uid)) {
      final displayName = event.participantNames[uid] ?? '';
      return Participant(
        id: uid,
        tripId: eventId,
        role: event.createdBy == uid
            ? ParticipantRole.leader
            : ParticipantRole.member,
        joinedAt: event.createdAt,
        displayName: displayName,
        userId: uid,
      );
    }
  }
  return null;
});

