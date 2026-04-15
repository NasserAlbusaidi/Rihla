import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/types/event_ref.dart';
import '../models/gear_item_model.dart';
import '../services/gear_service.dart';

export '../services/gear_service.dart';

/// Loading state for gear operations
final gearLoadingProvider = StateProvider<bool>((ref) => false);

/// Error state for gear operations
final gearErrorProvider = StateProvider<String?>((ref) => null);

/// Gear service provider
final gearServiceProvider = Provider<GearService>((ref) => GearService());

/// NEW: Firestore-backed stream of gear items for an event.
///
/// Use this for all new code. Replaces [tripGearProvider].
final eventGearItemsProvider =
    StreamProvider.family<List<GearItem>, EventRef>((ref, eventRef) {
  debugPrint('[GEAR] watchGearItems: groupId=${eventRef.groupId}, eventId=${eventRef.eventId}');
  return ref
      .read(gearServiceProvider)
      .watchGearItems(eventRef.groupId, eventRef.eventId);
});

/// @Deprecated('Use eventGearItemsProvider with EventRef. Will be removed in 04-05.')
///
/// Legacy gear items stream — returns empty list until screens migrate in 04-05.
final tripGearProvider = StreamProvider.family<List<GearItem>, String>((
  ref,
  tripId,
) {
  return Stream.value([]);
});

/// Gear items grouped by status (uses SQLite legacy stream)
final gearByStatusProvider =
    Provider.family<AsyncValue<Map<GearStatus, List<GearItem>>>, String>((
      ref,
      tripId,
    ) {
      final allItems = ref.watch(tripGearProvider(tripId));
      return allItems.whenData((items) {
        return {
          GearStatus.unclaimed: items
              .where((i) => i.status == GearStatus.unclaimed)
              .toList(),
          GearStatus.claimed: items
              .where((i) => i.status == GearStatus.claimed)
              .toList(),
          GearStatus.packed: items
              .where((i) => i.status == GearStatus.packed)
              .toList(),
        };
      });
    });

