import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/offline_repository.dart';
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
  return ref
      .read(gearServiceProvider)
      .watchGearItems(eventRef.groupId, eventRef.eventId);
});

/// @Deprecated('Use eventGearItemsProvider with EventRef')
///
/// Legacy stream of gear items from SQLite (Supabase path).
/// Retained for backward compatibility with screens not yet migrated to Firestore.
final tripGearProvider = StreamProvider.family<List<GearItem>, String>((
  ref,
  tripId,
) {
  return ref.read(offlineRepositoryProvider).watchGearItems(tripId);
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

/// Gear statistics
class GearStats {
  final int total;
  final int unclaimed;
  final int claimed;
  final int packed;

  const GearStats({
    this.total = 0,
    this.unclaimed = 0,
    this.claimed = 0,
    this.packed = 0,
  });

  double get readyPercentage => total > 0 ? packed / total : 0;
  int get pending => unclaimed + claimed;
}
