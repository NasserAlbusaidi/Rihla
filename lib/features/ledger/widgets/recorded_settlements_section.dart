import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/utils/formatters.dart';
import '../models/settlement_model.dart';
import '../../../core/theme/tokens/color_tokens.dart';

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
        title: Text(
          'RECORDED HISTORY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColorTokens.light.textMuted,
            letterSpacing: 1.0,
          ),
        ),
        trailing: Icon(
          Iconsax.arrow_down_1,
          size: 16,
          color: AppColorTokens.light.textMuted,
        ),
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColorTokens.light.cardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColorTokens.light.border.withValues(alpha: 0.5),
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
              Icon(
                Iconsax.tick_circle,
                size: 18,
                color: AppColorTokens.light.success,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: AppColorTokens.light.textSecondary,
                      fontSize: 13,
                    ),
                    children: [
                      TextSpan(
                        text: payerName,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppColorTokens.light.textPrimary,
                        ),
                      ),
                      const TextSpan(text: ' paid '),
                      TextSpan(
                        text: recipientName,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppColorTokens.light.textPrimary,
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
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColorTokens.light.success,
                    ),
                  ),
                  Text(
                    AppFormatters.formatRelativeDate(settlement.settledAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColorTokens.light.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: AppColorTokens.light.border),
      ],
    );
  }
}
