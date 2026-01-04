import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../models/gear_item_model.dart';

/// Loading state for gear operations
final gearLoadingProvider = StateProvider<bool>((ref) => false);

/// Error state for gear operations
final gearErrorProvider = StateProvider<String?>((ref) => null);

/// Stream of gear items for a trip
final tripGearProvider = StreamProvider.family<List<GearItem>, String>((
  ref,
  tripId,
) {
  SupabaseConfig.log('tripGearProvider: Starting stream for trip $tripId');

  return SupabaseConfig.client
      .from('gear_items')
      .stream(primaryKey: ['id'])
      .eq('trip_id', tripId)
      .order('sequence_id', ascending: true)
      .asyncMap((data) async {
        // Client-side filtering for soft delete since stream builder might not support eq
        final activeItems = data
            .where((json) => json['is_deleted'] != true)
            .toList();

        SupabaseConfig.log(
          'tripGearProvider: Got ${activeItems.length} active items from stream, fetching with profiles...',
        );

        try {
          // Fetch with profile info
          final items = await SupabaseConfig.client
              .from('gear_items')
              .select('*, profiles!assigned_to(display_name, avatar_url)')
              .eq('trip_id', tripId)
              .eq('is_deleted', false)
              .order('sequence_id', ascending: true);

          SupabaseConfig.log(
            'tripGearProvider: SUCCESS - ${items.length} items',
          );
          return items.map((json) => GearItem.fromJson(json)).toList();
        } catch (e) {
          SupabaseConfig.log(
            'tripGearProvider: FAILED to fetch with profiles',
            error: e,
          );
          // Fallback: return active items without profile info (filtered for deleted)
          return activeItems.map((json) => GearItem.fromJson(json)).toList();
        }
      });
});

/// Gear items grouped by status
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

/// Gear service provider
final gearServiceProvider = Provider<GearService>((ref) {
  return GearService(ref);
});

/// Gear service for CRUD operations
class GearService {
  final Ref _ref;

  GearService(this._ref);

  SupabaseClient get _client => SupabaseConfig.client;

  /// Add a new gear item
  Future<GearItem?> addItem({
    required String tripId,
    required String itemName,
    bool isHighPriority = false,
  }) async {
    _ref.read(gearLoadingProvider.notifier).state = true;
    _ref.read(gearErrorProvider.notifier).state = null;

    SupabaseConfig.log('addItem: "$itemName" to trip $tripId');

    try {
      final data = await _client
          .from('gear_items')
          .insert({
            'trip_id': tripId,
            'item_name': itemName,
            'is_high_priority': isHighPriority,
          })
          .select()
          .single();

      SupabaseConfig.log('addItem: SUCCESS - id: ${data['id']}');
      _ref.read(gearLoadingProvider.notifier).state = false;
      return GearItem.fromJson(data);
    } catch (e) {
      SupabaseConfig.log('addItem: FAILED', error: e);
      _ref.read(gearErrorProvider.notifier).state = e.toString();
      _ref.read(gearLoadingProvider.notifier).state = false;
      return null;
    }
  }

  /// Delete a gear item
  Future<bool> deleteItem(String itemId) async {
    SupabaseConfig.log('deleteItem: $itemId');
    try {
      // Soft delete
      await _client
          .from('gear_items')
          .update({
            'is_deleted': true,
            'deleted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', itemId);
      SupabaseConfig.log('deleteItem: SUCCESS');
      return true;
    } catch (e) {
      SupabaseConfig.log('deleteItem: FAILED', error: e);
      _ref.read(gearErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Claim a gear item (assign to current user)
  Future<bool> claimItem(String itemId) async {
    final userId = _client.auth.currentUser?.id;
    SupabaseConfig.log('claimItem: $itemId by user $userId');

    try {
      if (userId == null) {
        SupabaseConfig.log('claimItem: FAILED - no user');
        return false;
      }

      await _client
          .from('gear_items')
          .update({'assigned_to': userId})
          .eq('id', itemId);
      SupabaseConfig.log('claimItem: SUCCESS');
      return true;
    } catch (e) {
      SupabaseConfig.log('claimItem: FAILED', error: e);
      _ref.read(gearErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Unclaim a gear item
  Future<bool> unclaimItem(String itemId) async {
    SupabaseConfig.log('unclaimItem: $itemId');
    try {
      await _client
          .from('gear_items')
          .update({'assigned_to': null, 'is_packed': false})
          .eq('id', itemId);
      SupabaseConfig.log('unclaimItem: SUCCESS');
      return true;
    } catch (e) {
      SupabaseConfig.log('unclaimItem: FAILED', error: e);
      _ref.read(gearErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Mark item as packed
  Future<bool> packItem(String itemId) async {
    SupabaseConfig.log('packItem: $itemId');
    try {
      await _client
          .from('gear_items')
          .update({'is_packed': true})
          .eq('id', itemId);
      SupabaseConfig.log('packItem: SUCCESS');
      return true;
    } catch (e) {
      SupabaseConfig.log('packItem: FAILED', error: e);
      _ref.read(gearErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Mark item as unpacked
  Future<bool> unpackItem(String itemId) async {
    SupabaseConfig.log('unpackItem: $itemId');
    try {
      await _client
          .from('gear_items')
          .update({'is_packed': false})
          .eq('id', itemId);
      SupabaseConfig.log('unpackItem: SUCCESS');
      return true;
    } catch (e) {
      SupabaseConfig.log('unpackItem: FAILED', error: e);
      _ref.read(gearErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Toggle item priority
  Future<bool> togglePriority(String itemId, bool isHigh) async {
    SupabaseConfig.log('togglePriority: $itemId to $isHigh');
    try {
      await _client
          .from('gear_items')
          .update({'is_high_priority': isHigh})
          .eq('id', itemId);
      SupabaseConfig.log('togglePriority: SUCCESS');
      return true;
    } catch (e) {
      SupabaseConfig.log('togglePriority: FAILED', error: e);
      _ref.read(gearErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Get gear statistics for a trip
  Future<GearStats> getStats(String tripId) async {
    SupabaseConfig.log('getStats: for trip $tripId');
    try {
      final data = await _client
          .from('gear_items')
          .select()
          .eq('trip_id', tripId)
          .eq('is_deleted', false);

      final items = data.map((json) => GearItem.fromJson(json)).toList();

      SupabaseConfig.log('getStats: ${items.length} total items');
      return GearStats(
        total: items.length,
        unclaimed: items.where((i) => i.status == GearStatus.unclaimed).length,
        claimed: items.where((i) => i.status == GearStatus.claimed).length,
        packed: items.where((i) => i.status == GearStatus.packed).length,
      );
    } catch (e) {
      SupabaseConfig.log('getStats: FAILED', error: e);
      return const GearStats();
    }
  }
}

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
