import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/r_amount.dart';
import '../../providers/profile_stats_provider.dart';

/// The Spent stat value: per-currency lifetime spend (#378). No FX, so when a
/// user's groups span >1 currency we show one line per currency (hero-style)
/// rather than a nonsense cross-currency sum. Capped at 2 lines + a "+N"
/// overflow to keep the compact stat cell from growing unbounded.
class SpentValue extends StatelessWidget {
  const SpentValue({super.key, required this.spent});
  final List<CurrencySpend> spent;

  static const int _maxLines = 2;

  @override
  Widget build(BuildContext context) {
    // No spend yet (or no groups): preserve the original compact zero look —
    // there is no currency context, so render an OMR-precision zero.
    if (spent.isEmpty) {
      return RAmount(
        value: Decimal.zero,
        currency: 'OMR',
        showCurrency: false,
        size: 24,
      );
    }

    // Single currency is unambiguous → keep the large, code-less look.
    if (spent.length == 1) {
      final only = spent.first;
      return RAmount(
        value: only.amount,
        currency: only.currency,
        showCurrency: false,
        size: 24,
      );
    }

    // ≥2 currencies: stacked per-currency lines (code shown to disambiguate),
    // capped, with a "+N" overflow indicator for the rest.
    final colors = context.colors;
    final shown = spent.take(_maxLines).toList();
    final overflow = spent.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: RAmount(value: s.amount, currency: s.currency, size: 15),
          ),
        if (overflow > 0)
          Text(
            context.l10n.profileStatsSpentMore(overflow),
            style: AppTypography.sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
      ],
    );
  }
}
