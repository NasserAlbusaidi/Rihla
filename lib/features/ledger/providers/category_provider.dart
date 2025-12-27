import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/supabase_config.dart';
import '../models/expense_category_model.dart';

/// Loading state for category operations
final categoryLoadingProvider = StateProvider<bool>((ref) => false);

/// Error state for category operations
final categoryErrorProvider = StateProvider<String?>((ref) => null);

/// Stream of expense categories for a trip
final tripCategoriesProvider =
    StreamProvider.family<List<ExpenseCategory>, String>((ref, tripId) {
      SupabaseConfig.log(
        'tripCategoriesProvider: Starting stream for trip $tripId',
      );

      return SupabaseConfig.client
          .from('expense_categories')
          .stream(primaryKey: ['id'])
          .eq('trip_id', tripId)
          .order('is_default', ascending: false)
          .order('name', ascending: true)
          .map((data) {
            SupabaseConfig.log(
              'tripCategoriesProvider: Got ${data.length} categories',
            );
            return data
                .map(
                  (json) =>
                      ExpenseCategory.fromJson(json as Map<String, dynamic>),
                )
                .toList();
          });
    });

/// Category service provider
final categoryServiceProvider = Provider<CategoryService>((ref) {
  return CategoryService(ref);
});

/// Service for managing expense categories
class CategoryService {
  final Ref _ref;

  CategoryService(this._ref);

  /// Create a new custom category (leader only)
  Future<ExpenseCategory?> createCategory({
    required String tripId,
    required String name,
    String icon = 'other',
    String color = '#22C55E',
  }) async {
    _ref.read(categoryLoadingProvider.notifier).state = true;
    _ref.read(categoryErrorProvider.notifier).state = null;

    SupabaseConfig.log('createCategory: $name for trip $tripId');

    try {
      final data = await SupabaseConfig.client
          .from('expense_categories')
          .insert({
            'trip_id': tripId,
            'name': name,
            'icon': icon,
            'color': color,
            'is_default': false,
          })
          .select()
          .single();

      SupabaseConfig.log('createCategory: SUCCESS - id: ${data['id']}');
      _ref.read(categoryLoadingProvider.notifier).state = false;
      return ExpenseCategory.fromJson(data);
    } catch (e) {
      SupabaseConfig.log('createCategory: FAILED', error: e);
      _ref.read(categoryErrorProvider.notifier).state = e.toString();
      _ref.read(categoryLoadingProvider.notifier).state = false;
      return null;
    }
  }

  /// Update a category (leader only)
  Future<bool> updateCategory({
    required String categoryId,
    String? name,
    String? icon,
    String? color,
  }) async {
    SupabaseConfig.log('updateCategory: $categoryId');

    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (icon != null) updates['icon'] = icon;
      if (color != null) updates['color'] = color;

      await SupabaseConfig.client
          .from('expense_categories')
          .update(updates)
          .eq('id', categoryId);

      SupabaseConfig.log('updateCategory: SUCCESS');
      return true;
    } catch (e) {
      SupabaseConfig.log('updateCategory: FAILED', error: e);
      _ref.read(categoryErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Delete a custom category (leader only, can't delete defaults)
  Future<bool> deleteCategory(String categoryId) async {
    SupabaseConfig.log('deleteCategory: $categoryId');

    try {
      await SupabaseConfig.client
          .from('expense_categories')
          .delete()
          .eq('id', categoryId)
          .eq('is_default', false); // Can only delete non-default

      SupabaseConfig.log('deleteCategory: SUCCESS');
      return true;
    } catch (e) {
      SupabaseConfig.log('deleteCategory: FAILED', error: e);
      _ref.read(categoryErrorProvider.notifier).state = e.toString();
      return false;
    }
  }
}
