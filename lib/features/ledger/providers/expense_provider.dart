import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/cache_service.dart';
import '../../logistics/models/sub_group_model.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../trip/providers/trip_provider.dart';
import '../../trip/models/trip_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';

/// Loading state for expense operations
final expenseLoadingProvider = StateProvider<bool>((ref) => false);

/// Error state for expense operations
final expenseErrorProvider = StateProvider<String?>((ref) => null);

/// Stream of expenses for the current trip with offline caching
final tripExpensesProvider = StreamProvider.family<List<Expense>, String>((
  ref,
  tripId,
) {
  return SupabaseConfig.client
      .from('expenses')
      .stream(primaryKey: ['id'])
      .eq('trip_id', tripId)
      .order('created_at', ascending: false)
      .asyncMap((data) async {
        final result = await SupabaseConfig.client
            .from('expenses')
            .select(
              '*, expense_categories(*), participants!payer_participant_id(*)',
            )
            .eq('trip_id', tripId)
            .eq('is_deleted', false)
            .order('created_at', ascending: false);

        final expenses = (result as List)
            .map((json) => Expense.fromJson(json as Map<String, dynamic>))
            .toList();

        // Cache expenses for offline access
        await CacheService.cacheExpenses(tripId, expenses);

        return expenses;
      })
      .handleError((error) async {
        // On error (offline), return cached expenses
        debugPrint('📡 Network error, using cached expenses: $error');
        return await CacheService.getCachedExpenses(tripId);
      });
});

/// Stream of settlements for the current trip
final tripSettlementsProvider = StreamProvider.family<List<Settlement>, String>((
  ref,
  tripId,
) {
  return SupabaseConfig.client
      .from('settlements')
      .stream(primaryKey: ['id'])
      .eq('trip_id', tripId)
      .order('settled_at', ascending: false)
      .asyncMap((data) async {
        final result = await SupabaseConfig.client
            .from('settlements')
            .select(
              '*, payer_participant:participants!payer_participant_id(*), recipient_participant:participants!recipient_participant_id(*)',
            )
            .eq('trip_id', tripId)
            .eq('is_deleted', false)
            .order('settled_at', ascending: false);

        final settlements = (result as List)
            .map((json) => Settlement.fromJson(json as Map<String, dynamic>))
            .toList();

        // Cache settlements for offline access
        await CacheService.cacheSettlements(tripId, settlements);

        return settlements;
      })
      .handleError((error) async {
        // On error (offline), return cached settlements
        debugPrint('📡 Network error, using cached settlements: $error');
        return await CacheService.getCachedSettlements(tripId);
      });
});

/// Expense service provider
final expenseServiceProvider = Provider<ExpenseService>((ref) {
  return ExpenseService(ref);
});

/// Expense service for CRUD operations
class ExpenseService {
  final Ref _ref;

  ExpenseService(this._ref);

  SupabaseClient get _client => SupabaseConfig.client;

  /// Add a new expense
  Future<Expense?> addExpense({
    required String tripId,
    required String payerParticipantId,
    required Decimal amount,
    String? description,
    ExpenseScope scope = ExpenseScope.global,
    String? subGroupId,
    List<String>? customSplitParticipants,
    String? receiptUrl,
    String? categoryId,
    String? note,
  }) async {
    _ref.read(expenseLoadingProvider.notifier).state = true;
    _ref.read(expenseErrorProvider.notifier).state = null;

    try {
      final data = await _client
          .from('expenses')
          .insert({
            'trip_id': tripId,
            'payer_participant_id': payerParticipantId,
            'amount': amount.toString(),
            'description': description,
            'scope': scope.value,
            'sub_group_id': scope == ExpenseScope.subGroup ? subGroupId : null,
            'custom_split_participants': scope == ExpenseScope.custom
                ? customSplitParticipants
                : null,
            'receipt_url': receiptUrl,
            'category_id': categoryId,
            'note': note,
          })
          .select('*, expense_categories(name, icon), participants!payer_participant_id(*)')
          .single();

      _ref.read(expenseLoadingProvider.notifier).state = false;
      return Expense.fromJson(data);
    } catch (e) {
      debugPrint('❌ addExpense FAILED: $e');
      _ref.read(expenseErrorProvider.notifier).state = e.toString();
      _ref.read(expenseLoadingProvider.notifier).state = false;
      return null;
    }
  }

  /// Update an existing expense and log the change
  Future<Expense?> updateExpense({
    required String expenseId,
    required Expense oldExpense,
    Decimal? newAmount,
    String? newDescription,
    ExpenseScope? newScope,
    String? newSubGroupId,
    List<String>? newCustomSplitParticipants,
    String? newCategoryId,
    String? editNote,
  }) async {
    debugPrint('✏️ updateExpense called for ID: $expenseId');
    debugPrint(
      '   Updates: amount=$newAmount, scope=$newScope, category=$newCategoryId',
    );
    _ref.read(expenseLoadingProvider.notifier).state = true;
    _ref.read(expenseErrorProvider.notifier).state = null;

    try {
      final userId = _client.auth.currentUser?.id;

      // Build update map with only changed fields
      final updates = <String, dynamic>{};
      if (newAmount != null && newAmount != oldExpense.amount) {
        updates['amount'] = newAmount.toString();
      }
      if (newDescription != null && newDescription != oldExpense.description) {
        updates['description'] = newDescription;
      }
      if (newScope != null && newScope != oldExpense.scope) {
        updates['scope'] = newScope.value;
        if (newScope == ExpenseScope.subGroup) {
          updates['sub_group_id'] = newSubGroupId;
          updates['custom_split_participants'] = null;
        } else if (newScope == ExpenseScope.custom) {
          updates['sub_group_id'] = null;
          updates['custom_split_participants'] = newCustomSplitParticipants;
        } else {
          updates['sub_group_id'] = null;
          updates['custom_split_participants'] = null;
        }
      }
      if (newCategoryId != null && newCategoryId != oldExpense.categoryId) {
        updates['category_id'] = newCategoryId;
      }

      debugPrint('   Built updates: $updates');

      if (updates.isEmpty) {
        debugPrint('   No changes detected, returning old expense');
        _ref.read(expenseLoadingProvider.notifier).state = false;
        return oldExpense;
      }

      // Log the edit to history
      debugPrint('   Logging to expense_history...');
      await _client.from('expense_history').insert({
        'expense_id': expenseId,
        'edited_by': userId,
        'old_amount': oldExpense.amount.toString(),
        'new_amount': (newAmount ?? oldExpense.amount).toString(),
        'old_description': oldExpense.description,
        'new_description': newDescription ?? oldExpense.description,
        'old_scope': oldExpense.scope.value,
        'new_scope': (newScope ?? oldExpense.scope).value,
        'edit_note': editNote,
      });

      // Update the expense
      debugPrint('   Updating expense in DB...');
      final data = await _client
          .from('expenses')
          .update(updates)
          .eq('id', expenseId)
          .select('*, expense_categories(name, icon), participants!payer_participant_id(*)')
          .single();

      debugPrint('✅ updateExpense SUCCESS');
      _ref.read(expenseLoadingProvider.notifier).state = false;
      return Expense.fromJson(data);
    } catch (e) {
      debugPrint('❌ updateExpense FAILED: $e');
      _ref.read(expenseErrorProvider.notifier).state = e.toString();
      _ref.read(expenseLoadingProvider.notifier).state = false;
      return null;
    }
  }

  /// Delete an expense
  Future<bool> deleteExpense(String expenseId) async {
    debugPrint('🗑️ deleteExpense called with ID: $expenseId');
    try {
      await _client
          .from('expenses')
          .update({
            'is_deleted': true,
            'deleted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', expenseId);
      debugPrint('✅ deleteExpense SUCCESS for ID: $expenseId');
      return true;
    } catch (e) {
      debugPrint('❌ deleteExpense FAILED: $e');
      return false;
    }
  }
}

/// Provider for user balances in a trip
final tripBalancesProvider = FutureProvider.family<List<UserBalance>, String>((
  ref,
  tripId,
) async {
  final expenses = await ref.watch(tripExpensesProvider(tripId).future);
  final settlements = await ref.watch(tripSettlementsProvider(tripId).future);
  final participants = await ref.watch(
    tripLogisticsParticipantsProvider(tripId).future,
  );
  final subGroups = await ref.watch(tripSubGroupsProvider(tripId).future);

  return BalanceCalculator.calculateBalances(
    expenses: expenses,
    settlements: settlements,
    participants: participants,
    subGroups: subGroups,
  );
});

/// Balance calculation engine
class BalanceCalculator {
  /// Calculate balances with proper scope handling
  ///
  /// - Global: Split among all participants
  /// - Sub-Group: Split among members of the specified sub_group_id
  /// - Personal: Only the payer is responsible (no split)
  static List<UserBalance> calculateBalances({
    required List<Expense> expenses,
    required List<Participant> participants,
    List<Settlement> settlements = const [],
    List<SubGroup>? subGroups,
  }) {
    if (participants.isEmpty) return [];

    // Maps: participantId -> amounts
    final Map<String, Decimal> paidMap = {
      for (var p in participants) p.id: Decimal.zero,
    };
    final Map<String, Decimal> owedMap = {
      for (var p in participants) p.id: Decimal.zero,
    };

    // Build subgroup member lookup: subGroupId -> [participantIds]
    final Map<String, Set<String>> subGroupMembers = {};
    if (subGroups != null) {
      for (final sg in subGroups) {
        subGroupMembers[sg.id] = sg.members.map((m) => m.participantId).toSet();
      }
    }

    // Process each expense
    for (final expense in expenses) {
      final payerId = expense.payerParticipantId;

      // Track what payer paid
      if (paidMap.containsKey(payerId)) {
        paidMap[payerId] = paidMap[payerId]! + expense.amount;
      }

      // Determine who shares this expense based on scope
      Set<String> splitRecipients;

      switch (expense.scope) {
        case ExpenseScope.personal:
          // Personal: only the payer owes themselves (no redistribution)
          splitRecipients = {payerId};
          break;

        case ExpenseScope.subGroup:
          // Sub-Group: only members of the specified sub-group
          if (expense.subGroupId != null &&
              subGroupMembers.containsKey(expense.subGroupId)) {
            splitRecipients = Set.from(subGroupMembers[expense.subGroupId]!);
            // Note: Payer is NOT forced to be included.
            // If they paid for a group they are not in (e.g. parents treating kids),
            // they shouldn't bear a cost share.
          } else {
            // Fallback to global if sub-group not found
            splitRecipients = participants.map((p) => p.id).toSet();
          }
          break;

        case ExpenseScope.custom:
          // Custom: only the selected participants
          if (expense.customSplitParticipants != null &&
              expense.customSplitParticipants!.isNotEmpty) {
            splitRecipients = expense.customSplitParticipants!.toSet();
            // Note: Payer is NOT forced to be included.
          } else {
            // Fallback to global if no participants specified
            splitRecipients = participants.map((p) => p.id).toSet();
          }
          break;

        case ExpenseScope.global:
          // Global: everyone shares
          splitRecipients = participants.map((p) => p.id).toSet();
          break;
      }

      // Calculate per-head cost for this expense
      final splitCount = splitRecipients.length;
      if (splitCount == 0) continue;

      final perHead = (expense.amount / Decimal.fromInt(splitCount)).toDecimal(
        scaleOnInfinitePrecision: 3,
      );

      // Add to each recipient's owed amount
      for (final recipientId in splitRecipients) {
        if (owedMap.containsKey(recipientId)) {
          owedMap[recipientId] = owedMap[recipientId]! + perHead;
        }
      }
    }

    // Apply settlement adjustments
    final Map<String, Decimal> settlementAdjustmentMap = {
      for (var p in participants) p.id: Decimal.zero,
    };

    for (final s in settlements) {
      if (s.payerParticipantId != null &&
          settlementAdjustmentMap.containsKey(s.payerParticipantId)) {
        settlementAdjustmentMap[s.payerParticipantId!] =
            settlementAdjustmentMap[s.payerParticipantId!]! +
            Decimal.parse(s.amount.toString());
      }
      if (s.recipientParticipantId != null &&
          settlementAdjustmentMap.containsKey(s.recipientParticipantId)) {
        settlementAdjustmentMap[s.recipientParticipantId!] =
            settlementAdjustmentMap[s.recipientParticipantId!]! -
            Decimal.parse(s.amount.toString());
      }
    }

    // Build final balances
    return participants.map((p) {
      final totalPaid = paidMap[p.id] ?? Decimal.zero;
      final totalOwed = owedMap[p.id] ?? Decimal.zero;
      final settlementAdj = settlementAdjustmentMap[p.id] ?? Decimal.zero;

      // Net = (what they paid + settlements given) - what they owe
      final netBalance = (totalPaid + settlementAdj) - totalOwed;

      return UserBalance(
        participantId: p.id,
        displayName: p.displayName ?? 'Unknown',
        totalPaid: totalPaid,
        totalOwed: totalOwed,
        netBalance: netBalance,
      );
    }).toList();
  }

  static List<Map<String, dynamic>> calculateOptimalSettlements({
    required List<UserBalance> balances,
    Map<String, String>? userNames,
  }) {
    final debtors = balances.where((b) => b.netBalance < Decimal.zero).toList();
    final creditors = balances
        .where((b) => b.netBalance > Decimal.zero)
        .toList();

    debtors.sort((a, b) => a.netBalance.compareTo(b.netBalance));
    creditors.sort((a, b) => b.netBalance.compareTo(a.netBalance));

    final List<Map<String, dynamic>> settlements = [];
    int i = 0, j = 0;

    final List<Decimal> debtorBalances = debtors
        .map((d) => d.netBalance.abs())
        .toList();
    final List<Decimal> creditorBalances = creditors
        .map((c) => c.netBalance)
        .toList();

    while (i < debtorBalances.length && j < creditorBalances.length) {
      final amount = debtorBalances[i] < creditorBalances[j]
          ? debtorBalances[i]
          : creditorBalances[j];

      if (amount > Decimal.zero) {
        settlements.add({
          'fromUserId': debtors[i].participantId,
          'toUserId': creditors[j].participantId,
          'fromUserName':
              userNames?[debtors[i].participantId] ?? debtors[i].displayName,
          'toUserName':
              userNames?[creditors[j].participantId] ??
              creditors[j].displayName,
          'amount': amount,
        });
      }

      debtorBalances[i] -= amount;
      creditorBalances[j] -= amount;

      if (debtorBalances[i] <= Decimal.zero) i++;
      if (creditorBalances[j] <= Decimal.zero) j++;
    }

    return settlements;
  }

  static Decimal calculateTotalExpenses(List<Expense> expenses) {
    return expenses.fold(Decimal.zero, (sum, e) => sum + e.amount);
  }
}
