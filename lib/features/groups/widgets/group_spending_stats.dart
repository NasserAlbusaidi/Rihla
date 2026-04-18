import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Horizontal scrollable stats chips showing total group spending and top
/// spenders.
///
/// Per UI-SPEC Screen 2. Display-only — no tap interactions.
class GroupSpendingStats extends StatelessWidget {
  /// Total amount spent across all group events.
  final Decimal totalSpent;

  /// Number of events contributing to the total.
  final int eventCount;

  /// Currency code, typically 'OMR'.
  final String currency;

  /// Pre-computed top spenders (max 3). Each entry has a display name and
  /// a percentage of total spending (0–100).
  final List<({String name, double percentage})> topSpenders;

  const GroupSpendingStats({
    super.key,
    required this.totalSpent,
    required this.eventCount,
    required this.currency,
    required this.topSpenders,
  });

  @override
  Widget build(BuildContext context) {
    // Limit top spenders to 3 entries to avoid overflow.
    final displayedSpenders = topSpenders.take(3).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Total spending chip
          _StatsChip(
            icon: Iconsax.chart_2,
            label:
                '${AppFormatters.formatCurrency(totalSpent, currency)} across $eventCount events',
          ),
          if (displayedSpenders.isNotEmpty)
            const SizedBox(width: 8),
          // Top spender chips
          ...displayedSpenders.asMap().entries.map((entry) {
            final i = entry.key;
            final spender = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? 0 : 8,
              ),
              child: _StatsChip(
                icon: Iconsax.profile_circle,
                label:
                    '${spender.name} ${spender.percentage.toStringAsFixed(0)}%',
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// A single chip in the stats row.
class _StatsChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatsChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: context.colors.inputFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
