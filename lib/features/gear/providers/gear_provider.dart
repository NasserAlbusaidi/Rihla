import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/cache_service.dart';
import '../../../core/services/offline_repository.dart';
import '../models/gear_item_model.dart';

/// Loading state for gear operations
final gearLoadingProvider = StateProvider<bool>((ref) => false);

/// Error state for gear operations
final gearErrorProvider = StateProvider<String?>((ref) => null);

/// Stream of gear items — reads from SQLite
final tripGearProvider = StreamProvider.family<List<GearItem>, String>((
  ref,
  tripId,
) {
  return ref.read(offlineRepositoryProvider).watchGearItems(tripId);
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

  /// Add a new gear item — writes to SQLite immediately if offline
  Future<GearItem?> addItem({
    required String tripId,
    required String itemName,
    bool isHighPriority = false,
  }) async {
    _ref.read(gearLoadingProvider.notifier).state = true;
    _ref.read(gearErrorProvider.notifier).state = null;
    final repo = _ref.read(offlineRepositoryProvider);

    try {
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
        final item = GearItem.fromJson(data);
        await CacheService.cacheSingleGearItem(item);
        repo.notifyChange('gear_items', tripId);
        _ref.read(gearLoadingProvider.notifier).state = false;
        return item;
      } catch (e) {
        debugPrint('Supabase gear insert failed, saving locally: $e');
        final item = GearItem(
          id: repo.generateId(),
          tripId: tripId,
          itemName: itemName,
          isHighPriority: isHighPriority,
          createdAt: DateTime.now(),
        );
        await repo.saveGearItem(item);
        _ref.read(gearLoadingProvider.notifier).state = false;
        return item;
      }
    } catch (e) {
      _ref.read(gearErrorProvider.notifier).state = e.toString();
      _ref.read(gearLoadingProvider.notifier).state = false;
      return null;
    }
  }

  /// Delete a gear item — soft delete locally, try Supabase
  Future<bool> deleteItem(String itemId, {String? tripId}) async {
    try {
      final repo = _ref.read(offlineRepositoryProvider);
      try {
        await _client.from('gear_items').update({
          'is_deleted': true,
          'deleted_at': DateTime.now().toIso8601String(),
        }).eq('id', itemId);
      } catch (_) {
        // Offline
      }
      if (tripId != null) {
        await repo.deleteGearItem(itemId, tripId);
      }
      return true;
    } catch (e) {
      _ref.read(gearErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Claim a gear item (assign to current user) — update locally, try Supabase
  Future<bool> claimItem(String itemId, {String? tripId}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final repo = _ref.read(offlineRepositoryProvider);
    try {
      try {
        await _client.from('gear_items').update({'assigned_to': userId}).eq('id', itemId);
      } catch (_) {
        // Offline
      }
      if (tripId != null) {
        await repo.updateGearItem(itemId, tripId, {'assigned_to': userId});
      }
      return true;
    } catch (e) {
      _ref.read(gearErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Unclaim a gear item — update locally, try Supabase
  Future<bool> unclaimItem(String itemId, {String? tripId}) async {
    final repo = _ref.read(offlineRepositoryProvider);
    try {
      try {
        await _client.from('gear_items').update({'assigned_to': null, 'is_packed': false}).eq('id', itemId);
      } catch (_) {}
      if (tripId != null) {
        await repo.updateGearItem(itemId, tripId, {'assigned_to': null, 'is_packed': 0});
      }
      return true;
    } catch (e) {
      _ref.read(gearErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Mark item as packed — update locally, try Supabase
  Future<bool> packItem(String itemId, {String? tripId}) async {
    final repo = _ref.read(offlineRepositoryProvider);
    try {
      try {
        await _client.from('gear_items').update({'is_packed': true}).eq('id', itemId);
      } catch (_) {}
      if (tripId != null) {
        await repo.updateGearItem(itemId, tripId, {'is_packed': 1});
      }
      return true;
    } catch (e) {
      _ref.read(gearErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Mark item as unpacked — update locally, try Supabase
  Future<bool> unpackItem(String itemId, {String? tripId}) async {
    final repo = _ref.read(offlineRepositoryProvider);
    try {
      try {
        await _client.from('gear_items').update({'is_packed': false}).eq('id', itemId);
      } catch (_) {}
      if (tripId != null) {
        await repo.updateGearItem(itemId, tripId, {'is_packed': 0});
      }
      return true;
    } catch (e) {
      _ref.read(gearErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Toggle item priority — update locally, try Supabase
  Future<bool> togglePriority(String itemId, bool isHigh, {String? tripId}) async {
    final repo = _ref.read(offlineRepositoryProvider);
    try {
      try {
        await _client.from('gear_items').update({'is_high_priority': isHigh}).eq('id', itemId);
      } catch (_) {}
      if (tripId != null) {
        await repo.updateGearItem(itemId, tripId, {'is_high_priority': isHigh ? 1 : 0});
      }
      return true;
    } catch (e) {
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
