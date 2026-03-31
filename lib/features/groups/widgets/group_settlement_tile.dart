import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../keys/group_keys.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// A single settlement row showing payer → payee and amount.
///
/// Optionally shows a per-event breakdown list and a Record / Confirm button
/// when the current user is the payer or recipient (isYourAction / isConfirm).
class GroupSettlementTile extends StatelessWidget {
  final String fromName;
  final String toName;
  final Decimal amount;
  final String currency;
  final Map<String, Decimal> breakdown;
  final bool showDivider;
  final bool isYourAction;
  final bool isHighlighted;
  final GlobalKey? tileKey;
  final VoidCallback? onRecord;

  const GroupSettlementTile({
    super.key,
    required this.fromName,
    required this.toName,
    required this.amount,
    required this.currency,
    required this.breakdown,
    this.showDivider = true,
    required this.isYourAction,
    this.isHighlighted = false,
    this.tileKey,
    this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: tileKey,
      color: isHighlighted
          ? AppColorTokens.light.primary.withValues(alpha: 0.05)
          : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar stack
                    SizedBox(
                      width: 52,
                      height: 32,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            child: _buildAvatar(fromName, isPayer: true),
                          ),
                          Positioned(
                            left: 20,
                            child: _buildAvatar(toName),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColorTokens.light.textPrimary,
                              ),
                              children: [
                                TextSpan(
                                  text: fromName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text: ' pays ',
                                  style: TextStyle(
                                    color: AppColorTokens.light.textMuted,
                                  ),
                                ),
                                TextSpan(
                                  text: toName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppFormatters.formatCurrency(amount, currency),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: isYourAction
                                  ? AppColorTokens.light.error
                                  : AppColorTokens.light.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Per-event breakdown (D-24)
                if (breakdown.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...breakdown.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(left: 64, top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              e.key,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColorTokens.light.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            ': ${AppFormatters.formatCurrency(e.value, currency)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColorTokens.light.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Record Settlement button
                if (onRecord != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColorTokens.light.primaryGradient,
                        borderRadius:
                            BorderRadius.circular(12),
                      ),
                      child: ElevatedButton(
                        key: isYourAction
                            ? GroupKeys.recordSettlementButton
                            : null,
                        onPressed: onRecord,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.black,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              12,
                            ),
                          ),
                        ),
                        child: Text(
                          isYourAction ? 'Record Settlement' : 'Confirm Received',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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

  Widget _buildAvatar(String name, {bool isPayer = false}) {
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

/// A container card that renders a list of [GroupSettlementTile]s for a
/// settlement group (e.g. "YOUR ACTIONS").
class GroupSettlementGroupCard extends StatelessWidget {
  final List<Widget> tiles;
  final bool isYourAction;

  const GroupSettlementGroupCard({
    super.key,
    required this.tiles,
    this.isYourAction = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColorTokens.light.border.withValues(alpha: 0.5)),
        boxShadow: isYourAction ? AppShadowTokens.standard.raised : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: tiles),
    );
  }
}
