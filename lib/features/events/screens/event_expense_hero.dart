import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/types/event_ref.dart';
import '../../../core/utils/formatters.dart';
import '../../ledger/providers/expense_provider.dart';
import '../models/event_model.dart';

/// Dark hero card showing total event spending.
///
/// Replaces the Trip-facade-based [ExpenseSummaryHero] for events.
/// Uses [eventExpensesProvider] with EventRef (no Trip facade)
/// per the bridge removal in Plan 04-05.
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
      onTap: onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: SizedBox.expand(
            child: Stack(
              children: [
                // Abstract visual element
                Positioned(
                  top: -30,
                  right: -30,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                expensesAsync.when(
                  data: (expenses) {
                    Decimal totalExpenses = Decimal.zero;
                    for (final e in expenses) {
                      totalExpenses = totalExpenses + e.amount;
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppColors.space24,
                        vertical: AppColors.space16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Iconsax.wallet_3,
                                  color: AppColors.mint,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'SPENDING',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TweenAnimationBuilder<double>(
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
                                            color: Colors.white,
                                            fontSize: 28,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -1,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${expenses.length} expense${expenses.length != 1 ? "s" : ""}',
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Iconsax.arrow_right_3,
                                color: Colors.white24,
                                size: 20,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.mint),
                  ),
                  error: (_, __) => const Center(
                    child: Text(
                      'Could not load expenses',
                      style: TextStyle(
                        color: Colors.white38,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
