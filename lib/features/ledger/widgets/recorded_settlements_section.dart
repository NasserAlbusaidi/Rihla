import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../models/settlement_model.dart';

/// Collapsible history section showing recorded/completed settlements.
class RecordedSettlementsSection extends StatelessWidget {
  final List<Settlement> settlements;
  final Map<String, String> participantNames;
  final String currency;

  const RecordedSettlementsSection({
    super.key,
    required this.settlements,
    required this.participantNames,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: const Text(
          'RECORDED HISTORY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
            letterSpacing: 1.0,
          ),
        ),
        trailing: const Icon(
          Iconsax.arrow_down_1,
          size: 16,
          color: AppColors.textMuted,
        ),
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              children: settlements.asMap().entries.map((entry) {
                final index = entry.key;
                final s = entry.value;
                final isLast = index == settlements.length - 1;
                return _buildHistoryItem(s, !isLast);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(Settlement settlement, bool showDivider) {
    final payerName =
        participantNames[settlement.payerParticipantId] ?? 'Unknown';
    final recipientName =
        participantNames[settlement.recipientParticipantId] ?? 'Unknown';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Iconsax.tick_circle,
                size: 18,
                color: AppColors.success,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    children: [
                      TextSpan(
                        text: payerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const TextSpan(text: ' paid '),
                      TextSpan(
                        text: recipientName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    AppFormatters.formatCurrency(settlement.amount, currency),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                  Text(
                    AppFormatters.formatRelativeDate(settlement.settledAt),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: AppColors.border),
      ],
    );
  }
}
