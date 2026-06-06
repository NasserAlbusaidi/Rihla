import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../keys/home_keys.dart';

/// Cross-group balance hero, saffron-direction styling.
///
/// White card on paper, italic header, big sage/rust amount, mini split bar
/// showing the relative weight of "owed to you" vs "you owe", and a legend
/// row beneath. The figures come from [crossGroupBalanceOnceProvider] (one-shot
/// reads, #104 — the home tree holds no per-event listeners); the split-bar
/// derivation walks each group's per-user balance to split the net into positive
/// and negative components.
class BalanceHeroCard extends ConsumerWidget {
  const BalanceHeroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(crossGroupBalanceOnceProvider);

    return balanceAsync.when(
      loading: SkeletonLoader.dashboardHero,
      error: (e, _) => _ErrorCard(),
      data: (balance) => _LoadedCard(balance: balance),
    );
  }
}

class _LoadedCard extends StatelessWidget {
  const _LoadedCard({required this.balance});
  final CrossGroupBalance balance;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // owed/owes split is folded into crossGroupBalanceOnceProvider's existing
    // fan-out (#110) — no second walk over groupBalancesProvider here.
    final owedToUser = balance.owedToUser;
    final userOwes = balance.userOwes;

    final net = balance.net;
    final isPositive = net > Decimal.zero;
    final isNegative = net < Decimal.zero;
    final caption = isPositive
        ? context.l10n.homeNetYoureOwed
        : isNegative
        ? context.l10n.homeNetYouOwe
        : context.l10n.homeAllSettledAcrossJourneys;
    final captionAccent = isPositive
        ? context.l10n.homeOwed
        : isNegative
        ? context.l10n.homeOwe
        : null;
    final tone = isPositive
        ? AmountTone.sage
        : isNegative
        ? AmountTone.rust
        : AmountTone.ink;

    return Container(
      key: HomeKeys.balanceHeroCard,
      margin: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      padding: const EdgeInsetsDirectional.fromSTEB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(context.spacing.radiusSheet),
        boxShadow: context.shadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  context.l10n.homeAcrossAllJourneys,
                  style: AppTypography.display(
                    fontSize: 16,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              Text(
                'OMR',
                style: AppTypography.mono(
                  fontSize: 9,
                  color: colors.textSecondary,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          RAmount(
            value: net,
            currency: 'OMR',
            showCurrency: false,
            size: 44,
            sign: !net.isZero,
            tone: tone,
            weight: FontWeight.w500,
          ),
          const SizedBox(height: 6),
          _CaptionLine(text: caption, accent: captionAccent, tone: tone),
          const SizedBox(height: 18),
          _SplitBar(owedToUser: owedToUser, userOwes: userOwes),
          const SizedBox(height: 10),
          _SplitLegend(owedToUser: owedToUser, userOwes: userOwes),
        ],
      ),
    );
  }
}

extension on Decimal {
  bool get isZero => this == Decimal.zero;
}

class _CaptionLine extends StatelessWidget {
  const _CaptionLine({
    required this.text,
    required this.accent,
    required this.tone,
  });
  final String text;
  final String? accent;
  final AmountTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accentColor = switch (tone) {
      AmountTone.sage => colors.success,
      AmountTone.rust => colors.error,
      _ => colors.textPrimary,
    };
    if (accent == null) {
      return Text(
        text,
        style: AppTypography.sans(fontSize: 13, color: colors.textSecondary),
      );
    }
    // Reusable spans: ink-3 caption with the accent word highlighted.
    final parts = text.split(accent!);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: parts.first,
            style: AppTypography.sans(
              fontSize: 13,
              color: colors.textSecondary,
            ),
          ),
          TextSpan(
            text: accent,
            style: AppTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
          if (parts.length > 1)
            TextSpan(
              text: parts.last,
              style: AppTypography.sans(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _SplitBar extends StatelessWidget {
  const _SplitBar({required this.owedToUser, required this.userOwes});
  final Decimal owedToUser;
  final Decimal userOwes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pos = owedToUser.toDouble();
    final neg = userOwes.toDouble();
    final total = pos + neg;
    final posFraction = total > 0 ? pos / total : 0.5;
    final negFraction = total > 0 ? neg / total : 0.5;
    final hasAny = total > 0;

    return SizedBox(
      height: 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Row(
          children: [
            if (hasAny)
              Expanded(
                flex: (posFraction * 1000).round(),
                child: Container(color: colors.success),
              ),
            if (hasAny)
              Expanded(
                flex: (negFraction * 1000).round(),
                child: Container(color: colors.error),
              ),
            // Settled: a full-width bar in the settled/sage tone — an
            // intentional "all square" zeroed state (#146), not the ambiguous
            // gray rule that read as a half-built element.
            if (!hasAny) Expanded(child: Container(color: colors.success)),
          ],
        ),
      ),
    );
  }
}

class _SplitLegend extends StatelessWidget {
  const _SplitLegend({required this.owedToUser, required this.userOwes});
  final Decimal owedToUser;
  final Decimal userOwes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Two-line stack — keeps amounts readable on narrow phones without
    // overflowing the card. Wireframe inlines them but on real device widths
    // (≤ 360 px) the inline layout overflows; the two-line form matches the
    // visual weight while staying tabular.
    return Column(
      children: [
        _LegendLine(
          dotColor: colors.success,
          label: context.l10n.homeOwedToYou,
          amount: owedToUser,
        ),
        const SizedBox(height: 6),
        _LegendLine(
          dotColor: colors.error,
          label: context.l10n.homeYouOwe,
          amount: userOwes,
        ),
      ],
    );
  }
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({
    required this.dotColor,
    required this.label,
    required this.amount,
  });

  final Color dotColor;
  final String label;
  final Decimal amount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        _LegendDot(color: dotColor),
        SizedBox(width: context.spacing.space8),
        Expanded(
          child: Text(
            label,
            style: AppTypography.sans(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        ),
        RAmount(value: amount, size: 12, tone: AmountTone.ink),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: HomeKeys.balanceHeroCard,
      margin: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(context.spacing.radiusSheet),
        boxShadow: context.shadows.raised,
      ),
      child: Text(
        context.l10n.homeBalanceUnavailable,
        style: AppTypography.sans(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
