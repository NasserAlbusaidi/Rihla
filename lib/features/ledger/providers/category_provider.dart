import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/expense_category_model.dart';

/// Default expense categories (hardcoded, no backend).
///
/// Custom categories via the legacy backend have been removed. These are the
/// built-in defaults that cover common expense types. Order, ids, display name,
/// icon and color are governed by the canonical catalog (`ledger_categories.dart`,
/// #689) — the `name`/`icon`/`color` fields below are vestigial fallbacks; all
/// picker/ledger display resolves by `id` through the catalog.
final tripCategoriesProvider =
    StreamProvider.family<List<ExpenseCategory>, String>((ref, tripId) {
      return Stream.value(_defaultCategories);
    });

const _defaultCategories = [
  ExpenseCategory(
    id: 'food',
    tripId: '',
    name: 'Food & Dining',
    icon: 'food',
    color: '#C2693B',
    isDefault: true,
  ),
  ExpenseCategory(
    id: 'groceries',
    tripId: '',
    name: 'Groceries',
    icon: 'gear',
    color: '#6F7A3A',
    isDefault: true,
  ),
  ExpenseCategory(
    id: 'drinks',
    tripId: '',
    name: 'Drinks',
    icon: 'food',
    color: '#C2693B',
    isDefault: true,
  ),
  ExpenseCategory(
    id: 'transport',
    tripId: '',
    name: 'Transport',
    icon: 'transport',
    color: '#8C6A2F',
    isDefault: true,
  ),
  ExpenseCategory(
    id: 'fuel',
    tripId: '',
    name: 'Fuel',
    icon: 'gas',
    color: '#8C6A2F',
    isDefault: true,
  ),
  ExpenseCategory(
    id: 'accommodation',
    tripId: '',
    name: 'Accommodation',
    icon: 'lodging',
    color: '#4F7B96',
    isDefault: true,
  ),
  ExpenseCategory(
    id: 'activities',
    tripId: '',
    name: 'Activities',
    icon: 'other',
    color: '#94517A',
    isDefault: true,
  ),
  ExpenseCategory(
    id: 'shopping',
    tripId: '',
    name: 'Shopping',
    icon: 'gear',
    color: '#94517A',
    isDefault: true,
  ),
  ExpenseCategory(
    id: 'fees',
    tripId: '',
    name: 'Fees',
    icon: 'other',
    color: '#4D5A6A',
    isDefault: true,
  ),
  ExpenseCategory(
    id: 'other',
    tripId: '',
    name: 'Other',
    icon: 'other',
    color: '#4D5A6A',
    isDefault: true,
  ),
];
