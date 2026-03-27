import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/types/event_ref.dart';
import '../../events/models/event_model.dart';
import '../../trip/models/trip_model.dart';
import '../models/sub_group_model.dart';
import '../services/sub_group_service.dart';

export '../services/sub_group_service.dart';

/// Loading state for sub-group operations
final subGroupLoadingProvider = StateProvider<bool>((ref) => false);

/// Error state for sub-group operations
final subGroupErrorProvider = StateProvider<String?>((ref) => null);

/// Sub-group service provider
final subGroupServiceProvider =
    Provider<SubGroupService>((ref) => SubGroupService());

/// NEW: Firestore-backed stream of sub-groups for an event.
///
/// Use this for all new code. Replaces [tripSubGroupsProvider].
final eventSubGroupsProvider =
    StreamProvider.family<List<SubGroup>, EventRef>((ref, eventRef) {
  return ref
      .read(subGroupServiceProvider)
      .watchSubGroups(eventRef.groupId, eventRef.eventId);
});

/// @Deprecated('Use eventSubGroupsProvider with EventRef. Will be removed in 04-05.')
///
/// Legacy sub-groups stream — returns empty list until screens migrate in 04-05.
final tripSubGroupsProvider = StreamProvider.family<List<SubGroup>, String>((
  ref,
  tripId,
) {
  return Stream.value([]);
});

/// Derives a [List<Participant>] from an [Event]'s participantIds/participantNames.
///
/// Used by LogisticsScreen to show participants for drag-and-drop assignment.
/// No SQLite lookup needed — data comes from Firestore event document.
final eventLogisticsParticipantsProvider =
    Provider.family<List<Participant>, Event>((ref, event) {
  return event.participantIds.map((id) {
    return Participant(
      id: id,
      tripId: event.id,
      role: ParticipantRole.member,
      joinedAt: event.createdAt,
      displayName: event.participantNames[id],
      avatarUrl: null,
    );
  }).toList();
});
