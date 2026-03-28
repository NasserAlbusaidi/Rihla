import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';

/// Spending summary section showing total spend and optional category breakdown.
class SpendingSummarySection extends StatefulWidget {
  final List<Expense> expenses;
  final String currency;

  const SpendingSummarySection({
    super.key,
    required this.expenses,
    required this.currency,
  });

  @override
  State<SpendingSummarySection> createState() => _SpendingSummarySectionState();
}

class _SpendingSummarySectionState extends State<SpendingSummarySection> {
  bool _showByCategory = false;

  IconData _getCategoryIcon(String? iconName) {
    switch (iconName) {
      case 'gas':
        return Iconsax.gas_station;
      case 'food':
        return Iconsax.coffee;
      case 'gear':
        return Iconsax.bag_2;
      case 'lodging':
        return Iconsax.building;
      case 'transport':
        return Iconsax.car;
      default:
        return Iconsax.receipt;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Group expenses by category
    final Map<String, ({String name, String icon, Decimal total, int count})> categoryTotals = {};
    Decimal grandTotal = Decimal.zero;

    for (final e in widget.expenses) {
      grandTotal = grandTotal + e.amount;
      final key = e.categoryName ?? 'Other';
      final existing = categoryTotals[key];
      if (existing != null) {
        categoryTotals[key] = (
          name: existing.name,
          icon: e.categoryIcon ?? 'other',
          total: existing.total + e.amount,
          count: existing.count + 1,
        );
      } else {
        categoryTotals[key] = (
          name: key,
          icon: e.categoryIcon ?? 'other',
          total: e.amount,
          count: 1,
        );
      }
    }

    final sortedCategories = categoryTotals.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                key: LedgerKeys.spendingLabel,
                'SPENDING',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textMuted,
                  letterSpacing: 1.5,
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _showByCategory = !_showByCategory),
                child: Text(
                  _showByCategory ? 'Hide Categories' : 'By Category',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Total spending card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: AppColors.cardShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Iconsax.wallet_3, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Spent',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppFormatters.formatCurrency(grandTotal, widget.currency),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${widget.expenses.length} expenses',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // Category breakdown
          if (_showByCategory && sortedCategories.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
                boxShadow: AppColors.cardShadow,
              ),
              child: Column(
                children: sortedCategories.map((cat) {
                  final percentage = grandTotal > Decimal.zero
                      ? (cat.total / grandTotal).toDecimal(scaleOnInfinitePrecision: 4).toDouble() * 100
                      : 0.0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _getCategoryIcon(cat.icon),
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cat.name,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: percentage / 100,
                                  backgroundColor: AppColors.surfaceLight,
                                  color: AppColors.primary,
                                  minHeight: 4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              AppFormatters.formatCurrency(cat.total, widget.currency),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '${percentage.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
