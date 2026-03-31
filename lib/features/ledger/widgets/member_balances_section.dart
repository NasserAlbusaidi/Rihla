import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/utils/formatters.dart';
import '../models/expense_model.dart';
import '../../../core/theme/tokens/color_tokens.dart';

/// Horizontal scrollable list of member balance avatars.
/// Tapping a member shows a detailed balance tooltip dialog.
class MemberBalancesSection extends StatelessWidget {
  final List<UserBalance> balances;
  final String? currentParticipantId;
  final String currency;

  const MemberBalancesSection({
    super.key,
    required this.balances,
    required this.currency,
    this.currentParticipantId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BALANCES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: AppColorTokens.light.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: balances.isEmpty
                ? Center(
                    child: Text(
                      'No participants yet',
                      style: TextStyle(color: AppColorTokens.light.textMuted),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: balances.length,
                    itemBuilder: (context, index) {
                      final balance = balances[index];
                      final isMe = balance.participantId == currentParticipantId;
                      final isPositive = balance.netBalance >= Decimal.zero;

                      return GestureDetector(
                        onTap: () {
                          HapticService.lightClick();
                          _showBalanceTooltip(context, balance);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 12),
                          child: Column(
                            children: [
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: isMe
                                        ? AppColorTokens.light.primary
                                        : (isPositive
                                                  ? AppColorTokens.light.success
                                                  : AppColorTokens.light.error)
                                              .withValues(alpha: 0.15),
                                    child: Text(
                                      (balance.displayName ?? 'U')[0].toUpperCase(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isMe
                                            ? Colors.white
                                            : (isPositive ? AppColorTokens.light.success : AppColorTokens.light.error),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: isPositive ? AppColorTokens.light.success : AppColorTokens.light.error,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                      child: Icon(
                                        isPositive ? Icons.add : Icons.remove,
                                        size: 8,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: 60,
                                child: Text(
                                  isMe ? 'You' : (balance.displayName ?? 'User'),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isMe ? FontWeight.w600 : FontWeight.normal,
                                    color: AppColorTokens.light.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showBalanceTooltip(BuildContext context, UserBalance balance) {
    final isPositive = balance.netBalance >= Decimal.zero;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: isPositive
                  ? AppColorTokens.light.success.withValues(alpha: 0.15)
                  : AppColorTokens.light.error.withValues(alpha: 0.15),
              child: Text(
                (balance.displayName ?? 'U')[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isPositive ? AppColorTokens.light.success : AppColorTokens.light.error,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              balance.displayName ?? 'Unknown',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColorTokens.light.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColorTokens.light.inputFill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildBalanceRow(
                    'Total Paid',
                    balance.totalPaid,
                    AppColorTokens.light.primary,
                    currency,
                  ),
                  const SizedBox(height: 8),
                  _buildBalanceRow(
                    'Fair Share',
                    balance.totalOwed,
                    AppColorTokens.light.textMuted,
                    currency,
                  ),
                  const Divider(height: 24),
                  _buildBalanceRow(
                    isPositive ? 'Is Owed' : 'Owes',
                    balance.netBalance.abs(),
                    isPositive ? AppColorTokens.light.success : AppColorTokens.light.error,
                    currency,
                    isBold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isPositive
                  ? 'Paid more than their share'
                  : 'Paid less than their share',
              style: TextStyle(fontSize: 12, color: AppColorTokens.light.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceRow(
    String label,
    Decimal amount,
    Color color,
    String currency, {
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColorTokens.light.textSecondary,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          AppFormatters.formatCurrency(amount, currency),
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}
