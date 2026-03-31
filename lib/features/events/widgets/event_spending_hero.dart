import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/utils/formatters.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../trip/providers/trip_provider.dart';
import '../models/event_model.dart';
import '../../../core/theme/tokens/color_tokens.dart';

/// Dark hero card showing total event spending and user balance status.
///
/// Uses [EventRef]-based providers (D-17 bridge removal).
/// Replaces [ExpenseSummaryHero] for event screens.
class EventSpendingHero extends ConsumerWidget {
  final Event event;
  final VoidCallback onTap;

  const EventSpendingHero({
    super.key,
    required this.event,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EventRef eventRef = (groupId: event.groupId, eventId: event.id);
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final balancesAsync = ref.watch(
      eventBalancesProvider((eventRef: eventRef, event: event)),
    );
    final currentParticipant = ref.watch(currentParticipantProvider(event.id));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: AppColorTokens.light.headerGradient,
          boxShadow: [
            BoxShadow(
              color: AppColorTokens.light.headerGradientStart.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
          image: const DecorationImage(
            image: AssetImage('assets/textures/grain.png'),
            repeat: ImageRepeat.repeat,
            opacity: 0.035,
            fit: BoxFit.none,
            alignment: Alignment.topLeft,
          ),
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

                    final userBalance = balancesAsync.maybeWhen(
                      data: (balances) =>
                          balances.cast<UserBalance?>().firstWhere(
                            (b) => b?.participantId == currentParticipant?.id,
                            orElse: () => null,
                          ),
                      orElse: () => null,
                    );
                    final net = userBalance?.netBalance ?? Decimal.zero;
                    final isOwed = net > Decimal.zero;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Iconsax.wallet_3,
                                      color: AppColorTokens.light.primary,
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
                              if (net != Decimal.zero)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (isOwed
                                                ? AppColorTokens.light.success
                                                : AppColorTokens.light.error)
                                            .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    isOwed ? 'OWED' : 'OWE',
                                    style: TextStyle(
                                      color: isOwed
                                          ? AppColorTokens.light.primary
                                          : AppColorTokens.light.error,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
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
                                            Decimal.parse(
                                              value.toStringAsFixed(3),
                                            ),
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
                                    if (net != Decimal.zero)
                                      TweenAnimationBuilder<double>(
                                        tween: Tween<double>(
                                          begin: 0,
                                          end: net.abs().toDouble(),
                                        ),
                                        duration:
                                            const Duration(milliseconds: 800),
                                        curve: Curves.easeOutCubic,
                                        builder: (context, value, child) {
                                          final formatted =
                                              AppFormatters.formatCurrency(
                                            Decimal.parse(
                                              value.toStringAsFixed(3),
                                            ),
                                            event.currency,
                                          );
                                          return Text(
                                            isOwed
                                                ? 'Settlements pending: +$formatted'
                                                : 'Pending payment: -$formatted',
                                            style: TextStyle(
                                              color: isOwed
                                                  ? AppColorTokens.light.primary
                                                      .withValues(alpha: 0.8)
                                                  : AppColorTokens.light.error
                                                      .withValues(alpha: 0.8),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          );
                                        },
                                      )
                                    else
                                      const Text(
                                        'All balances settled',
                                        style: TextStyle(
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
                  loading: () => Center(
                    child: CircularProgressIndicator(color: AppColorTokens.light.primary),
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
