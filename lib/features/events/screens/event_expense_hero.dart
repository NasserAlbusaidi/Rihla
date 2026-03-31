import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../ledger/providers/expense_provider.dart';
import '../keys/event_keys.dart';
import '../models/event_model.dart';

/// Light-themed hero card showing total event spending.
///
/// Redesigned per D-14 (Phase 20 P02):
/// - Light surface card with border (not dark gradient)
/// - "TOTAL EXPENSES" overline label
/// - Teal "+ Add Expense" ActionChip
/// - TweenAnimationBuilder for animated amount counter
class EventExpenseHero extends ConsumerWidget {
  final Event event;
  final VoidCallback onTap;

  const EventExpenseHero({
    super.key,
    required this.event,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventRef = (groupId: event.groupId, eventId: event.id);
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));

    return GestureDetector(
      key: EventKeys.spendingHero,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.shadowRaised,
          image: const DecorationImage(
            image: AssetImage('assets/textures/grain.png'),
            repeat: ImageRepeat.repeat,
            opacity: 0.035,
            fit: BoxFit.none,
            alignment: Alignment.topLeft,
          ),
        ),
        padding: const EdgeInsets.all(AppColors.space16),
        child: expensesAsync.when(
          data: (expenses) {
            Decimal totalExpenses = Decimal.zero;
            for (final e in expenses) {
              totalExpenses = totalExpenses + e.amount;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Overline + add-expense chip row
                Row(
                  children: [
                    const Text(
                      'TOTAL EXPENSES',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    ActionChip(
                      key: EventKeys.addExpenseChip,
                      label: const Text(
                        '+ Add Expense',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppColors.space8,
                        vertical: 0,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: onTap,
                    ),
                  ],
                ),
                const SizedBox(height: AppColors.space8),
                // Animated total amount
                TweenAnimationBuilder<double>(
                  key: EventKeys.expenseHeroTotal,
                  tween: Tween<double>(
                    begin: 0,
                    end: totalExpenses.toDouble(),
                  ),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Text(
                      AppFormatters.formatCurrency(
                        Decimal.parse(value.toStringAsFixed(3)),
                        event.currency,
                      ),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -1,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 2),
                Text(
                  '${expenses.length} expense${expenses.length != 1 ? "s" : ""}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            );
          },
          loading: () => const SizedBox(
            height: 80,
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
          ),
          error: (e, st) => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppColors.space16),
            child: Text(
              'Could not load expenses',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
