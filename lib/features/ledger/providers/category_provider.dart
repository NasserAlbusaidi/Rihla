import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/expense_category_model.dart';

/// Loading state for category operations.
final categoryLoadingProvider = StateProvider<bool>((ref) => false);

/// Error state for category operations.
final categoryErrorProvider = StateProvider<String?>((ref) => null);

/// Default expense categories (hardcoded, no backend).
///
/// Custom categories via the legacy backend have been removed. These are the
/// built-in defaults that cover common expense types.
final tripCategoriesProvider =
    StreamProvider.family<List<ExpenseCategory>, String>((ref, tripId) {
  return Stream.value(_defaultCategories);
});

final _defaultCategories = [
  ExpenseCategory(
    id: 'food',
    tripId: '',
    name: 'Food & Dining',
    icon: 'food',
    color: '#F59E0B',
    isDefault: true,
  ),
  ExpenseCategory(
    id: 'transport',
    tripId: '',
    name: 'Transport',
    icon: 'transport',
    color: '#3B82F6',
    isDefault: true,
  ),
  ExpenseCategory(
    id: 'accommodation',
    tripId: '',
    name: 'Accommodation',
    icon: 'lodging',
    color: '#8B5CF6',
    isDefault: true,
  ),
  ExpenseCategory(
    id: 'activities',
    tripId: '',
    name: 'Activities',
    icon: 'other',
    color: '#10B981',
    isDefault: true,
  ),
  ExpenseCategory(
    id: 'shopping',
    tripId: '',
    name: 'Shopping',
    icon: 'gear',
    color: '#EC4899',
    isDefault: true,
  ),
  ExpenseCategory(
    id: 'other',
    tripId: '',
    name: 'Other',
    icon: 'other',
    color: '#6B7280',
    isDefault: true,
  ),
];

/// Category service provider.
final categoryServiceProvider = Provider<CategoryService>((ref) {
  return CategoryService(ref);
});

/// Service for managing expense categories.
///
/// Custom category CRUD has been removed. Only default categories are
/// available. Create/update/delete methods return success/failure but are
/// no-ops for default categories.
class CategoryService {
  final Ref _ref;
  CategoryService(this._ref);

  Future<ExpenseCategory?> createCategory({
    required String tripId,
    required String name,
    String icon = 'other',
    String color = '#22C55E',
  }) async {
    // Custom categories not supported in this version.
    // Return null to indicate creation was not performed.
    return null;
  }

  Future<bool> updateCategory({
    required String categoryId,
    String? name,
    String? icon,
    String? color,
  }) async {
    return false;
  }

  Future<bool> deleteCategory(String categoryId) async {
    return false;
  }
}
