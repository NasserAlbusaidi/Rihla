import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/offline_repository.dart';
import '../../../core/types/event_ref.dart';
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

/// @Deprecated('Use eventSubGroupsProvider with EventRef')
///
/// Legacy stream of sub-groups from SQLite (Supabase path).
/// Retained for backward compatibility with screens not yet migrated to Firestore.
final tripSubGroupsProvider = StreamProvider.family<List<SubGroup>, String>((
  ref,
  tripId,
) {
  return ref.read(offlineRepositoryProvider).watchSubGroups(tripId);
});

/// Sub-groups filtered by type (uses SQLite legacy stream)
final subGroupsByTypeProvider =
    Provider.family<
      AsyncValue<List<SubGroup>>,
      ({String tripId, SubGroupType type})
    >((ref, params) {
      final allGroups = ref.watch(tripSubGroupsProvider(params.tripId));
      return allGroups.whenData(
        (groups) => groups.where((g) => g.type == params.type).toList(),
      );
    });
