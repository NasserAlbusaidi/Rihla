import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// A card containing a group of settlement tiles.
/// Renders pending settlements for a specific category (e.g., "Your Actions").
class SettlementGroupCard extends StatelessWidget {
  final List<Map<String, dynamic>> settlements;
  final bool isUrgent;
  final String currency;
  final void Function(Map<String, dynamic> settlement) onTap;

  const SettlementGroupCard({
    super.key,
    required this.settlements,
    required this.currency,
    required this.onTap,
    this.isUrgent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUrgent
              ? AppColorTokens.light.error.withValues(alpha: 0.2)
              : AppColorTokens.light.border.withValues(alpha: 0.5),
        ),
        boxShadow: isUrgent ? AppShadowTokens.standard.raised : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: settlements.asMap().entries.map((entry) {
          final index = entry.key;
          final settlement = entry.value;
          final isLast = index == settlements.length - 1;
          return SettlementTile(
            settlement: settlement,
            currency: currency,
            showDivider: !isLast,
            isUrgent: isUrgent,
            onTap: () => onTap(settlement),
          );
        }).toList(),
      ),
    );
  }
}

/// A single settlement tile showing payer → payee with amount.
class SettlementTile extends StatelessWidget {
  final Map<String, dynamic> settlement;
  final String currency;
  final bool showDivider;
  final bool isUrgent;
  final VoidCallback onTap;

  const SettlementTile({
    super.key,
    required this.settlement,
    required this.currency,
    required this.onTap,
    this.showDivider = true,
    this.isUrgent = false,
  });

  @override
  Widget build(BuildContext context) {
    final fromName = settlement['fromUserName'] as String;
    final toName = settlement['toUserName'] as String;
    final amount = (settlement['amount'] as Decimal);

    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar Visual Stack
                SizedBox(
                  width: 52,
                  height: 32,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        child: _buildSmallAvatar(fromName, isPayer: true),
                      ),
                      Positioned(left: 20, child: _buildSmallAvatar(toName)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Text Description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: TextStyle(
                            color: AppColorTokens.light.textPrimary,
                            fontSize: 14,
                          ),
                          children: [
                            TextSpan(
                              text: fromName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: ' → ',
                              style: TextStyle(
                                color: AppColorTokens.light.textMuted,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: toName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            AppFormatters.formatCurrency(amount, currency),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: isUrgent ? AppColorTokens.light.error : AppColorTokens.light.primary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (isUrgent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColorTokens.light.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'PAYMENT DUE',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: AppColorTokens.light.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Arrow icon
                Icon(
                  Iconsax.arrow_right_3,
                  size: 16,
                  color: AppColorTokens.light.textMuted,
                ),
              ],
            ),
          ),
          if (showDivider)
            Divider(
              height: 1,
              thickness: 1,
              color: AppColorTokens.light.border.withValues(alpha: 0.5),
              indent: 16,
              endIndent: 16,
            ),
        ],
      ),
    );
  }

  Widget _buildSmallAvatar(String name, {bool isPayer = false}) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isPayer ? AppColorTokens.light.cardSurface : AppColorTokens.light.inputFill,
        shape: BoxShape.circle,
        border: Border.all(
          color: isPayer ? AppColorTokens.light.primary : AppColorTokens.light.border,
          width: isPayer ? 2 : 1,
        ),
        boxShadow: AppShadowTokens.standard.raised,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isPayer ? AppColorTokens.light.textPrimary : AppColorTokens.light.textSecondary,
          ),
        ),
      ),
    );
  }
}
