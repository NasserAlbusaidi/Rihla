import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/utils/formatters.dart';
import '../models/expense_model.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// Premium bento-style summary card for the Settle Up screen.
/// Displays the current user's net balance, total pending, and total paid.
class SettlementSummaryCard extends StatelessWidget {
  final Decimal netBalance;
  final Decimal totalPending;
  final UserBalance myBalance;
  final String currency;
  final List<Map<String, dynamic>> myDebts;
  final VoidCallback? onSettleUp;

  const SettlementSummaryCard({
    super.key,
    required this.netBalance,
    required this.totalPending,
    required this.myBalance,
    required this.currency,
    this.myDebts = const [],
    this.onSettleUp,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = netBalance >= Decimal.zero;
    final accentColor = isPositive ? AppColorTokens.light.success : AppColorTokens.light.error;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.15),
            AppColorTokens.light.cardSurface.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withValues(alpha: 0.2), width: 1),
        boxShadow: AppShadowTokens.standard.floating,
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPositive ? 'YOU ARE OWED' : 'YOU OWE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        AppFormatters.formatCurrency(netBalance.abs(), currency),
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: AppColorTokens.light.textPrimary,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPositive ? Iconsax.receipt_add : Iconsax.receipt_minus,
                  color: accentColor,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(height: 1, color: AppColorTokens.light.border),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildSummaryMiniItem(
                'Trip Total Pending',
                AppFormatters.formatCurrency(totalPending, currency),
                Iconsax.status_up,
              ),
              const SizedBox(width: 32),
              _buildSummaryMiniItem(
                'Total Paid by You',
                AppFormatters.formatCurrency(myBalance.totalPaid, currency),
                Iconsax.wallet_check,
              ),
            ],
          ),
          if (!isPositive && netBalance.abs() > Decimal.zero) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppColorTokens.light.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColorTokens.light.primary.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: myDebts.isNotEmpty ? onSettleUp : null,
                  icon: const Icon(Iconsax.tick_circle, size: 18),
                  label: const Text('SETTLE UP'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.black,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryMiniItem(String label, String value, IconData icon) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColorTokens.light.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColorTokens.light.textMuted,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColorTokens.light.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
