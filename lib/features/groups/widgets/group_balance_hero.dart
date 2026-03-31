import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/keys/shared_keys.dart';
import '../../../core/utils/formatters.dart';
import '../keys/group_keys.dart';
import '../../../core/theme/tokens/color_tokens.dart';

/// Dark gradient hero card showing total group spending and the current
/// user's net position, with a Settle Up CTA.
///
/// Receives data as constructor params — parent reads from
/// [groupBalancesProvider] and passes values down (NOT a ConsumerWidget).
///
/// Per UI-SPEC Screen 1 (D-21, D-22):
/// - D-21: Settle Up CTA is disabled when userNetBalance == 0.
/// - D-22: Tapping the card or the CTA calls [onSettleUp].
class GroupBalanceHero extends StatelessWidget {
  /// Total amount spent across all group events.
  final Decimal totalSpent;

  /// Current user's net balance (positive = owed money, negative = owes money).
  final Decimal userNetBalance;

  /// Currency code, typically 'OMR'.
  final String currency;

  /// Called when the Settle Up button or card is tapped (D-22).
  final VoidCallback onSettleUp;

  const GroupBalanceHero({
    super.key,
    required this.totalSpent,
    required this.userNetBalance,
    required this.currency,
    required this.onSettleUp,
  });

  @override
  Widget build(BuildContext context) {
    final isOwed = userNetBalance > Decimal.zero;
    final isSettled = userNetBalance == Decimal.zero;

    return GestureDetector(
      key: SharedKeys.groupBalanceHero,
      onTap: onSettleUp,
      child: Container(
        constraints: const BoxConstraints(minHeight: 140),
        padding: const EdgeInsets.all(24),
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
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Decorative circle (top-right)
              Positioned(
                top: -50,
                right: -50,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                ),
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: label + status pill
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'GROUP BALANCES',
                        key: GroupKeys.groupBalancesLabel,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      if (!isSettled)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (isOwed ? AppColorTokens.light.success : AppColorTokens.light.error)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isOwed ? 'YOU ARE OWED' : 'YOU OWE',
                            style: TextStyle(
                              color: isOwed ? AppColorTokens.light.primary : AppColorTokens.light.error,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Row 2: animated total spent
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 0,
                      end: totalSpent.toDouble(),
                    ),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Text(
                        AppFormatters.formatCurrency(
                          Decimal.parse(value.toStringAsFixed(3)),
                          currency,
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 4),

                  // Sub-line: user net position or settled text
                  if (isSettled)
                    const Text(
                      'All balances settled',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 0,
                        end: userNetBalance.abs().toDouble(),
                      ),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        final formatted = AppFormatters.formatCurrency(
                          Decimal.parse(value.toStringAsFixed(3)),
                          currency,
                        );
                        return Text(
                          isOwed
                              ? 'You are owed $formatted'
                              : 'You owe $formatted',
                          style: TextStyle(
                            color:
                                isOwed ? AppColorTokens.light.primary : AppColorTokens.light.error,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 16),

                  // Settle Up CTA
                  SizedBox(
                    width: double.infinity,
                    child: isSettled
                        ? const Text(
                            'All settled! No outstanding balances.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : GestureDetector(
                            key: SharedKeys.groupBalanceSettleUpButton,
                            onTap: onSettleUp,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                gradient: AppColorTokens.light.primaryGradient,
                                borderRadius: BorderRadius.circular(
                                  12,
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Iconsax.arrow_circle_right,
                                    color: Colors.black,
                                    size: 16,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Settle Up',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
