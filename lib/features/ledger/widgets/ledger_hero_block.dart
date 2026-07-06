import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/formatters.dart';

/// Mono one-liner summarizing the trip total(s), expense count, and settlement
/// count. Hidden in the empty state by the caller. Renders one amount segment
/// per currency (#382 PR-1) — a single-currency event looks exactly as before.
class LedgerTripCaption extends StatelessWidget {
  const LedgerTripCaption({
    super.key,
    required this.totals,
    required this.expenseCount,
    required this.settledCount,
    this.label,
  });

  /// Per-currency totals, pre-sorted by the caller (GCC-first).
  final List<({String currency, Decimal total})> totals;
  final int expenseCount;
  final int settledCount;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final effectiveLabel = label ?? l10n.ledgerTripTotal;
    final labelStyle = AppTypography.caption(
      context,
      fontSize: 10,
      color: colors.textSecondary,
      letterSpacing: 1.4,
      fontWeight: FontWeight.w600,
    );
    // Per-currency trip-total amount — MONEY, stays mono in every locale
    // (#841); do not sweep into caption().
    final amountStyle = AppTypography.mono(
      fontSize: 11,
      color: colors.ink2,
      letterSpacing: 0.2,
      fontWeight: FontWeight.w600,
    );
    final tailStyle = AppTypography.caption(
      context,
      fontSize: 10,
      color: colors.textSecondary,
      letterSpacing: 0.3,
      fontWeight: FontWeight.w500,
    );
    // textMuted-decorative-justified: separator dots are non-text glyphs that
    // never carry meaning; lower contrast is intentional to recede behind the
    // labelled segments they delimit.
    final dotStyle = AppTypography.mono(
      fontSize: 10,
      color: colors.textMuted,
      fontWeight: FontWeight.w500,
    );

    final tail = settledCount > 0 && expenseCount > 0
        ? '${l10n.ledgerExpenseCount(expenseCount)} · '
              '${l10n.ledgerSettledCount(settledCount)}'
        : l10n.ledgerExpenseCount(expenseCount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 2,
        children: [
          Text(effectiveLabel, style: labelStyle),
          for (final t in totals) ...[
            Text('·', style: dotStyle),
            Text(
              AppFormatters.formatCurrency(t.total, t.currency),
              style: amountStyle,
            ),
          ],
          Text('·', style: dotStyle),
          Text(tail, style: tailStyle),
        ],
      ),
    );
  }
}
