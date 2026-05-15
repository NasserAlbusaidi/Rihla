import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// V5R hero kind — drives copy, sign treatment, and tonal color.
enum LedgerHeroKind { positive, negative, settled, empty }

/// Italic Instrument Serif statement hero. The money is *inline* with the prose.
///
/// Copy variants:
///   positive   →  "You're up [+OMR 12.450] across N people."
///   negative   →  "You owe [−OMR 7.200] to N people."
///   settled    →  "All square."  (plus inline sage badge)
///   empty      →  "Nothing logged yet — add the first expense and we'll start the math."
class LedgerHeroStatement extends StatelessWidget {
  const LedgerHeroStatement({
    super.key,
    required this.kind,
    required this.amount,
    this.peopleCount = 0,
  });

  final LedgerHeroKind kind;
  final Decimal amount;
  final int peopleCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final double baseSize = kind == LedgerHeroKind.empty ? 28 : 32;

    final baseStyle = AppTypography.display(
      fontSize: baseSize,
      color: colors.textPrimary,
      letterSpacing: -0.5,
      height: 1.1,
    );
    final tailStyle = baseStyle.copyWith(color: colors.textSecondary);
    final numStyle = AppTypography.display(
      fontSize: baseSize,
      color: switch (kind) {
        LedgerHeroKind.positive => colors.successText,
        LedgerHeroKind.negative => colors.errorText,
        _ => colors.textPrimary,
      },
      letterSpacing: -0.6,
      height: 1.1,
    );
    final monoPrefixStyle = AppTypography.mono(
      fontSize: baseSize * 0.36,
      color: colors.textSecondary,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w500,
    );
    final fractionStyle = numStyle.copyWith(fontSize: baseSize * 0.62);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: switch (kind) {
        LedgerHeroKind.positive => _ProseRow(
          baseStyle: baseStyle,
          tailStyle: tailStyle,
          children: [
            const TextSpan(text: "You're up "),
            _inlineMoney(
              amount,
              sign: '+',
              numStyle: numStyle,
              prefixStyle: monoPrefixStyle,
              fractionStyle: fractionStyle,
            ),
            TextSpan(
              text: ' across $peopleCount '
                  '${peopleCount == 1 ? 'person' : 'people'}.',
              style: tailStyle,
            ),
          ],
        ),
        LedgerHeroKind.negative => _ProseRow(
          baseStyle: baseStyle,
          tailStyle: tailStyle,
          children: [
            const TextSpan(text: 'You owe '),
            _inlineMoney(
              amount.abs(),
              sign: '−',
              numStyle: numStyle,
              prefixStyle: monoPrefixStyle,
              fractionStyle: fractionStyle,
            ),
            TextSpan(
              text: ' to $peopleCount '
                  '${peopleCount == 1 ? 'person' : 'people'}.',
              style: tailStyle,
            ),
          ],
        ),
        LedgerHeroKind.settled => _SettledRow(baseStyle: baseStyle),
        LedgerHeroKind.empty => _ProseRow(
          baseStyle: baseStyle,
          tailStyle: tailStyle,
          children: [
            const TextSpan(text: 'Nothing logged yet — '),
            TextSpan(
              text: "add the first expense and we'll start the math.",
              style: tailStyle,
            ),
          ],
        ),
      },
    );
  }

  static InlineSpan _inlineMoney(
    Decimal value, {
    required String sign,
    required TextStyle numStyle,
    required TextStyle prefixStyle,
    required TextStyle fractionStyle,
  }) {
    final formatted = value.abs().toStringAsFixed(3);
    final dot = formatted.indexOf('.');
    final whole = dot == -1 ? formatted : formatted.substring(0, dot);
    final frac = dot == -1 ? '' : formatted.substring(dot);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Text('${sign}OMR', style: prefixStyle),
          ),
          Text(whole, style: numStyle),
          if (frac.isNotEmpty) Text(frac, style: fractionStyle),
        ],
      ),
    );
  }
}

class _ProseRow extends StatelessWidget {
  const _ProseRow({
    required this.baseStyle,
    required this.tailStyle,
    required this.children,
  });
  final TextStyle baseStyle;
  final TextStyle tailStyle;
  final List<InlineSpan> children;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(style: baseStyle, children: children),
      softWrap: true,
    );
  }
}

class _SettledRow extends StatelessWidget {
  const _SettledRow({required this.baseStyle});
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        Text('All square.', style: baseStyle),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            // sage-soft tint approximation against paper bg.
            color: colors.success.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Text(
            'SETTLED',
            style: AppTypography.mono(
              fontSize: 10,
              color: colors.successText,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Mono one-liner: "TRIP TOTAL · OMR 142.350 · 6 expenses · 2 settled".
///
/// Hide in the empty state (caller decision).
class LedgerTripCaption extends StatelessWidget {
  const LedgerTripCaption({
    super.key,
    required this.total,
    required this.expenseCount,
    required this.settledCount,
    this.label = 'TRIP TOTAL',
  });

  final Decimal total;
  final int expenseCount;
  final int settledCount;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelStyle = AppTypography.mono(
      fontSize: 10,
      color: colors.textSecondary,
      letterSpacing: 1.4,
      fontWeight: FontWeight.w600,
    );
    final amountStyle = AppTypography.mono(
      fontSize: 11,
      color: colors.ink2,
      letterSpacing: 0.2,
      fontWeight: FontWeight.w600,
    );
    final tailStyle = AppTypography.mono(
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
        ? '$expenseCount expense${expenseCount == 1 ? '' : 's'} · '
              '$settledCount settled'
        : '$expenseCount expense${expenseCount == 1 ? '' : 's'}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 2,
        children: [
          Text(label, style: labelStyle),
          Text('·', style: dotStyle),
          Text('OMR ${total.toStringAsFixed(3)}', style: amountStyle),
          Text('·', style: dotStyle),
          Text(tail, style: tailStyle),
        ],
      ),
    );
  }
}
