import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../ledger/models/settlement_model.dart';

/// History tab widget showing past recorded payments for a group.
///
/// Folds [_buildHistoryTab], [_buildHistoryTile], and [_buildHistoryAvatar]
/// from [GroupSettleUpScreen] into a single cohesive widget.
/// Internal tile and avatar helpers are private classes within this file.
///
/// Extracted as part of Phase 36 Plan 01 screen decomposition.
class SettleUpHistoryTab extends StatelessWidget {
  final AsyncValue<List<Settlement>> settlementsAsync;
  final String currency;

  const SettleUpHistoryTab({
    super.key,
    required this.settlementsAsync,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacingTokens.standard;

    return settlementsAsync.when(
      data: (settlements) {
        if (settlements.isEmpty) {
          return const EmptyStateView(
            icon: Iconsax.receipt_1,
            title: 'No recorded payments',
            message: 'Payments recorded in this group will appear here.',
          );
        }
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
            spacing.space20,
            spacing.space12,
            spacing.space20,
            spacing.space24,
          ),
          physics: const BouncingScrollPhysics(),
          itemCount: settlements.length,
          itemBuilder: (context, index) {
            return _HistoryTile(
              settlement: settlements[index],
              currency: currency,
              index: index,
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => EmptyStateView(
        icon: Iconsax.warning_2,
        title: 'Couldn\'t load history',
        message: 'Check your connection and try again.',
        iconColor: AppColorTokens.light.textSecondary,
      ),
    );
  }
}

/// A single history tile showing payer, recipient, amount, and date.
class _HistoryTile extends StatelessWidget {
  final Settlement settlement;
  final String currency;
  final int index;

  const _HistoryTile({
    required this.settlement,
    required this.currency,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacingTokens.standard;
    final payerName = settlement.payerName ?? 'Unknown';
    final recipientName = settlement.recipientName ?? 'Unknown';
    final dateStr = DateFormat('MMM d').format(settlement.settledAt);

    return Container(
      margin: EdgeInsets.only(bottom: spacing.space12),
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: AppShadowTokens.standard.raised,
        border: Border.all(
          color: AppColorTokens.light.border.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(spacing.space16),
        child: Row(
          children: [
            // Overlapping avatar pair
            SizedBox(
              width: 52,
              height: 32,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    child: _HistoryAvatar(name: payerName, isPayer: true),
                  ),
                  Positioned(
                    left: 20,
                    child: _HistoryAvatar(name: recipientName, isPayer: false),
                  ),
                ],
              ),
            ),
            SizedBox(width: spacing.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$payerName paid $recipientName',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColorTokens.light.textPrimary,
                    ),
                  ),
                  SizedBox(height: spacing.space4),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColorTokens.light.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              AppFormatters.formatCurrency(settlement.amount, currency),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColorTokens.light.textPrimary,
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: index * 50))
        .slideY(begin: 0.1, curve: Curves.easeOutCubic);
  }
}

/// Small circular avatar used in [_HistoryTile].
class _HistoryAvatar extends StatelessWidget {
  final String name;
  final bool isPayer;

  const _HistoryAvatar({
    required this.name,
    required this.isPayer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isPayer
            ? AppColorTokens.light.primary.withValues(alpha: 0.15)
            : AppColorTokens.light.inputFill,
        shape: BoxShape.circle,
        border: Border.all(
          color: isPayer
              ? AppColorTokens.light.primary.withValues(alpha: 0.4)
              : AppColorTokens.light.border,
          width: isPayer ? 2 : 1,
        ),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isPayer
                ? AppColorTokens.light.primary
                : AppColorTokens.light.textSecondary,
          ),
        ),
      ),
    );
  }
}
