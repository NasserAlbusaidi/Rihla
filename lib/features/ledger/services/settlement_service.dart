import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
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

  /// Add a new settlement (record a payment)
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

      debugPrint('✅ addSettlement SUCCESS: ${data['id']}');
      _ref.read(expenseLoadingProvider.notifier).state = false;
      return Settlement.fromJson(data);
    } catch (e) {
      debugPrint('❌ addSettlement FAILED: $e');
      _ref.read(expenseErrorProvider.notifier).state = e.toString();
      _ref.read(expenseLoadingProvider.notifier).state = false;
      return null;
    }
  }

  /// Delete a settlement
  Future<bool> deleteSettlement(String settlementId) async {
    try {
      // Soft delete
      await _client
          .from('settlements')
          .update({
            'is_deleted': true,
            'deleted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', settlementId);
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
