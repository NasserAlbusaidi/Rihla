import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/formatters.dart';

/// V5R hero kind — drives copy, sign treatment, and tonal color.
enum LedgerHeroKind { positive, negative, settled, empty }

/// One per-currency hero line (#382 PR-5): the current user's net for that
/// bucket plus the count of people they are unsettled with in it.
typedef LedgerHeroLine = ({String currency, Decimal net, int peopleCount});

/// Italic Instrument Serif statement hero. The money is *inline* with the prose.
///
/// Copy variants:
///   positive   →  localized balance owed to the current user.
///   negative   →  localized balance owed by the current user.
///   settled    →  localized settled-state copy plus inline sage badge.
///   empty      →  localized empty-state copy.
///
/// Multi-line mode (#382 PR-5): when [lines] carries 2+ entries the hero
/// stacks one statement per currency bucket ([kind]/[amount]/[currency] are
/// ignored — mixed signs have no honest single kind, each line self-explains).
class LedgerHeroStatement extends StatelessWidget {
  const LedgerHeroStatement({
    super.key,
    required this.kind,
    required this.amount,
    required this.currency,
    this.peopleCount = 0,
    this.lines = const [],
  });

  final LedgerHeroKind kind;
  final Decimal amount;
  final String currency;
  final int peopleCount;
  final List<LedgerHeroLine> lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    if (lines.length >= 2) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines.length; i++)
              Padding(
                padding: EdgeInsetsDirectional.only(top: i == 0 ? 0 : 6),
                child: _statementLine(
                  context,
                  positive: lines[i].net > Decimal.zero,
                  amount: lines[i].net,
                  currency: lines[i].currency,
                  peopleCount: lines[i].peopleCount,
                  baseSize: 24,
                ),
              ),
          ],
        ),
      );
    }

    final double baseSize = kind == LedgerHeroKind.empty ? 28 : 32;
    final baseStyle = AppTypography.displayOf(
      context,
      fontSize: baseSize,
      color: colors.textPrimary,
      letterSpacing: -0.5,
      height: 1.1,
    );
    final tailStyle = baseStyle.copyWith(color: colors.textSecondary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: switch (kind) {
        LedgerHeroKind.positive => _statementLine(
          context,
          positive: true,
          amount: amount,
          currency: currency,
          peopleCount: peopleCount,
          baseSize: baseSize,
        ),
        LedgerHeroKind.negative => _statementLine(
          context,
          positive: false,
          amount: amount,
          currency: currency,
          peopleCount: peopleCount,
          baseSize: baseSize,
        ),
        LedgerHeroKind.settled => _SettledRow(baseStyle: baseStyle),
        LedgerHeroKind.empty => _ProseRow(
          baseStyle: baseStyle,
          tailStyle: tailStyle,
          children: [
            TextSpan(text: '${l10n.ledgerHeroEmptyPrefix} — '),
            TextSpan(text: l10n.ledgerHeroEmptyTail, style: tailStyle),
          ],
        ),
      },
    );
  }

  static Widget _statementLine(
    BuildContext context, {
    required bool positive,
    required Decimal amount,
    required String currency,
    required int peopleCount,
    required double baseSize,
  }) {
    final colors = context.colors;
    final l10n = context.l10n;
    final baseStyle = AppTypography.displayOf(
      context,
      fontSize: baseSize,
      color: colors.textPrimary,
      letterSpacing: -0.5,
      height: 1.1,
    );
    final tailStyle = baseStyle.copyWith(color: colors.textSecondary);
    // Hero balance figure — Latin digits in every locale; stays raw display()
    // on purpose (#841).
    final numStyle = AppTypography.display(
      fontSize: baseSize,
      color: positive ? colors.successText : colors.errorText,
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

    return _ProseRow(
      baseStyle: baseStyle,
      tailStyle: tailStyle,
      children: [
        TextSpan(
          text: positive
              ? '${l10n.ledgerHeroPositivePrefix} '
              : '${l10n.ledgerHeroNegativePrefix} ',
        ),
        _inlineMoney(
          amount.abs(),
          sign: positive ? '+' : '−',
          currency: currency,
          numStyle: numStyle,
          prefixStyle: monoPrefixStyle,
          fractionStyle: fractionStyle,
        ),
        TextSpan(
          text: positive
              ? ' ${l10n.ledgerHeroPositiveTail(peopleCount)}'
              : ' ${l10n.ledgerHeroNegativeTail(peopleCount)}',
          style: tailStyle,
        ),
      ],
    );
  }

  static InlineSpan _inlineMoney(
    Decimal value, {
    required String sign,
    required String currency,
    required TextStyle numStyle,
    required TextStyle prefixStyle,
    required TextStyle fractionStyle,
  }) {
    final formatted = value.abs().toStringAsFixed(
      AppFormatters.currencyConfig[currency]?.decimals ?? 3,
    );
    final dot = formatted.indexOf('.');
    final whole = dot == -1 ? formatted : formatted.substring(0, dot);
    final frac = dot == -1 ? '' : formatted.substring(dot);
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      // #144: force LTR so the code / whole / fraction pieces and the
      // directional padding don't reverse under an Arabic (RTL) ambient
      // direction. Wrapping in Directionality (not just Row.textDirection)
      // also gives the child Text widgets an LTR base direction.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 3),
              child: Text('$sign$currency', style: prefixStyle),
            ),
            Text(whole, style: numStyle),
            if (frac.isNotEmpty) Text(frac, style: fractionStyle),
          ],
        ),
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
    final l10n = context.l10n;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        Text(l10n.ledgerAllSquare, style: baseStyle),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: context.spacing.space4),
          decoration: BoxDecoration(
            // sage-soft tint approximation against paper bg.
            color: colors.success.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(context.spacing.radiusPill),
          ),
          child: Text(
            l10n.ledgerSettledBadge,
            style: AppTypography.caption(
              context,
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
