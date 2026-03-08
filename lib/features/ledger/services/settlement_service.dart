import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/cache_service.dart';
import '../../../core/services/offline_repository.dart';
import '../models/settlement_model.dart';
import '../providers/expense_provider.dart';

/// Settlement service provider
final settlementServiceProvider = Provider<SettlementService>((ref) {
  return SettlementService(ref);
});

/// Service for handling settlement operations
class SettlementService {
  final Ref _ref;

  SettlementService(this._ref);

  SupabaseClient get _client => SupabaseConfig.client;

  /// Add a new settlement (record a payment) — offline-safe
  Future<Settlement?> addSettlement({
    required String tripId,
    required String payerId,
    required String recipientId,
    required Decimal amount,
    String? note,
    String currency = 'OMR',
  }) async {
    debugPrint(
      '💰 addSettlement called: tripId=$tripId, payer=$payerId, recipient=$recipientId, amount=$amount',
    );
    _ref.read(expenseLoadingProvider.notifier).state = true;
    _ref.read(expenseErrorProvider.notifier).state = null;

    final repo = _ref.read(offlineRepositoryProvider);

    try {
      // Try Supabase first for server-generated ID
      try {
        debugPrint('   Inserting settlement into DB...');
        final data = await _client
            .from('settlements')
            .insert({
              'trip_id': tripId,
              'payer_participant_id': payerId,
              'recipient_participant_id': recipientId,
              'amount': amount.toString(),
              'note': note,
              'currency': currency,
              'settled_at': DateTime.now().toIso8601String(),
            })
            .select(
              '*, payer_participant:participants!payer_participant_id(*), recipient_participant:participants!recipient_participant_id(*)',
            )
            .single();

        final settlement = Settlement.fromJson(data);
        // Cache the server-returned settlement
        await CacheService.cacheSettlements(tripId, [settlement]);
        repo.notifyChange('settlements', tripId);
        debugPrint('✅ addSettlement SUCCESS: ${data['id']}');
        _ref.read(expenseLoadingProvider.notifier).state = false;
        return settlement;
      } catch (e) {
        // Supabase failed (offline) — save locally with generated ID
        debugPrint('Supabase settlement insert failed, saving locally: $e');
        final settlement = Settlement(
          id: repo.generateId(),
          tripId: tripId,
          payerParticipantId: payerId,
          recipientParticipantId: recipientId,
          amount: amount,
          note: note,
          settledAt: DateTime.now(),
        );
        await repo.saveSettlement(settlement);
        _ref.read(expenseLoadingProvider.notifier).state = false;
        return settlement;
      }
    } catch (e) {
      debugPrint('❌ addSettlement FAILED: $e');
      _ref.read(expenseErrorProvider.notifier).state = e.toString();
      _ref.read(expenseLoadingProvider.notifier).state = false;
      return null;
    }
  }

  /// Delete a settlement — offline-safe
  Future<bool> deleteSettlement(String settlementId, {required String tripId}) async {
    try {
      final repo = _ref.read(offlineRepositoryProvider);
      // Try Supabase first
      try {
        await _client
            .from('settlements')
            .update({
              'is_deleted': true,
              'deleted_at': DateTime.now().toIso8601String(),
            })
            .eq('id', settlementId);
      } catch (_) {
        // Offline — will sync later
      }
      // Always update local cache
      await repo.deleteSettlement(settlementId, tripId);
      return true;
    } catch (e) {
      _ref.read(expenseErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Get all settlements for a trip
  Future<List<Settlement>> getSettlements(String tripId) async {
    try {
      final data = await _client
          .from('settlements')
          .select(
            '*, payer_participant:participants!payer_participant_id(*), recipient_participant:participants!recipient_participant_id(*)',
          )
          .eq('trip_id', tripId)
          .eq('is_deleted', false)
          .order('settled_at', ascending: false);

      return (data as List).map((json) => Settlement.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }
}
