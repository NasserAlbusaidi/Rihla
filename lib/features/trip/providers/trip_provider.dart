import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/types/event_ref.dart';
import '../../events/providers/event_provider.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../models/trip_model.dart';

/// Provider for the current user's participant record in one known event.
///
/// Prefer this for route-scoped event screens. It avoids scanning every group
/// and uses [currentUserIdProvider], so tests can override identity without
/// bootstrapping Firebase Auth.
final currentEventParticipantProvider = Provider.family<Participant?, EventRef>(
  (ref, eventRef) {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return null;

    final event = ref.watch(eventDetailProvider(eventRef)).valueOrNull;
    if (event == null || !event.participantIds.contains(uid)) {
      return null;
    }

    return Participant(
      id: uid,
      tripId: event.id,
      role: event.createdBy == uid
          ? ParticipantRole.leader
          : ParticipantRole.member,
      joinedAt: event.createdAt,
      displayName: event.participantNames[uid] ?? '',
      userId: uid,
    );
  },
);
