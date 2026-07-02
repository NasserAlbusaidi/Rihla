import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

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
/// row beneath. The figures come from [crossGroupHomeBalanceProvider] (#366 —
/// the server aggregate when online, the #104 one-shot fallback otherwise
/// reads, #104 — the home tree holds no per-event listeners); the split-bar
/// derivation walks each group's per-user balance to split the net into positive
/// and negative components.
class BalanceHeroCard extends ConsumerWidget {
  const BalanceHeroCard({super.key, this.onTap});

  /// When non-null, the loaded card becomes tappable (#284). The home screen
  /// wires this to scroll to the active-journeys list — the path to per-group
  /// settle-up (there is no cross-group settle screen).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(crossGroupHomeBalanceProvider);
    // #70: the currency for the all-settled state (when byCurrency is empty there
    // is no active bucket to read a currency from). Null ⇒ no/mixed currency ⇒
    // currency-agnostic zero.
    final settledCurrency = ref.watch(settledDisplayCurrencyProvider);

    return balanceAsync.when(
      loading: SkeletonLoader.dashboardHero,
      error: (e, _) => _ErrorCard(),
      data: (result) => _LoadedCard(
        balance: result.balance,
        partial: result.partial,
        settledCurrency: settledCurrency,
        onTap: onTap,
      ),
    );
  }
}

class _LoadedCard extends StatelessWidget {
  const _LoadedCard({
    required this.balance,
    this.partial = false,
    this.settledCurrency,
    this.onTap,
  });
  final CrossGroupBalance balance;

  /// #244: a per-event money read failed for at least one group, so [balance]
  /// is a partial sum. Renders the "may be incomplete" notice; the numbers
  /// still show (the "you're owed X (incomplete)" goal).
  final bool partial;

  /// #70: currency for the all-settled (empty [CrossGroupBalance.byCurrency])
  /// state. Null ⇒ render a currency-agnostic zero (no code, 2dp).
  final String? settledCurrency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final buckets = balance.byCurrency;
    // #261: one block per currency (there is no FX, so amounts in different
    // currencies are never summed). The trailing currency code sits inline in
    // the header ONLY when there is exactly one active currency bucket. Mixed
    // currency: each block carries its own code; all-settled (empty): no code.
    final single = buckets.length == 1;

    final children = <Widget>[
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
          if (single)
            Text(
              buckets.first.currency,
              style: AppTypography.mono(
                fontSize: 9,
                color: colors.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
        ],
      ),
    ];

    if (buckets.isEmpty) {
      children.add(const SizedBox(height: 14));
      children.add(
        _CurrencyBlock(
          bucket: null,
          showCode: false,
          settledCurrency: settledCurrency,
        ),
      );
    } else {
      for (var i = 0; i < buckets.length; i++) {
        if (i == 0) {
          children.add(const SizedBox(height: 14));
        } else {
          children.add(SizedBox(height: context.spacing.space20));
          children.add(
            Divider(height: 1, color: colors.border.withValues(alpha: 0.5)),
          );
          children.add(const SizedBox(height: 14));
        }
        children.add(_CurrencyBlock(bucket: buckets[i], showCode: !single));
      }
    }

    if (partial) {
      children.add(const SizedBox(height: 12));
      children.add(const _IncompleteNotice());
    }

    // #807: the card's tap only scrolls to the journeys strip (#284) — give
    // it a visible cue so the tap target stops being invisible. Gated on
    // onTap so a non-tappable card renders unchanged.
    if (onTap != null) {
      children.add(const SizedBox(height: 12));
      children.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            Icon(
              Iconsax.arrow_down_1,
              size: 14,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              context.l10n.homeBalanceHeroHint,
              style: AppTypography.sans(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final card = Container(
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
        children: children,
      ),
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// One currency's net + caption + split bar + legend. [bucket] null ⇒ the
/// all-settled state (net 0, no currency code). [showCode] adds a small code
/// label above the amount when the card shows MORE than one currency (the
/// single-currency card carries the code in the header row instead).
class _CurrencyBlock extends StatelessWidget {
  const _CurrencyBlock({
    required this.bucket,
    required this.showCode,
    this.settledCurrency,
  });
  final CurrencyBalance? bucket;
  final bool showCode;

  /// #70: only consulted when [bucket] is null (all-settled). The user's single
  /// group currency, or null ⇒ currency-agnostic zero.
  final String? settledCurrency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final b = bucket;
    final net = b?.net ?? Decimal.zero;
    final owedToUser = b?.owedToUser ?? Decimal.zero;
    final userOwes = b?.userOwes ?? Decimal.zero;
    // #70: an active bucket carries its own currency; the settled (null) state
    // falls back to the user's settled currency, or null ⇒ agnostic. An empty
    // code ('') drives RAmount's 2dp default with no code shown.
    final resolved = b?.currency ?? settledCurrency;
    final currency = resolved ?? '';
    final showLegendCode = resolved != null;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showCode) ...[
          Text(
            currency,
            style: AppTypography.mono(
              fontSize: 9,
              color: colors.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
        ],
        RAmount(
          value: net,
          currency: currency,
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
        _SplitLegend(
          owedToUser: owedToUser,
          userOwes: userOwes,
          currency: currency,
          showCode: showLegendCode,
        ),
      ],
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
  const _SplitLegend({
    required this.owedToUser,
    required this.userOwes,
    required this.currency,
    required this.showCode,
  });
  final Decimal owedToUser;
  final Decimal userOwes;
  final String currency;

  /// #70: false ⇒ render the legend amounts without a currency code (the
  /// agnostic settled state). Always true for an active bucket.
  final bool showCode;

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
          currency: currency,
          showCode: showCode,
        ),
        const SizedBox(height: 6),
        _LegendLine(
          dotColor: colors.error,
          label: context.l10n.homeYouOwe,
          amount: userOwes,
          currency: currency,
          showCode: showCode,
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
    required this.currency,
    required this.showCode,
  });

  final Color dotColor;
  final String label;
  final Decimal amount;
  final String currency;
  final bool showCode;

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
        RAmount(
          value: amount,
          currency: currency,
          showCurrency: showCode,
          size: 12,
          tone: AmountTone.ink,
        ),
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

/// #244: compact "balance may be incomplete" row appended to the hero when a
/// per-event money read failed for some group. Same warning language as the
/// settle-up banner, but a single inline row (no border box) so the hero stays
/// glanceable. The number above still renders.
class _IncompleteNotice extends StatelessWidget {
  const _IncompleteNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      key: HomeKeys.balanceIncompleteNotice,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Iconsax.warning_2, size: 14, color: colors.warning),
        SizedBox(width: context.spacing.space8),
        Expanded(
          child: Text(
            context.l10n.homeBalanceIncompleteNotice,
            style: AppTypography.sans(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
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
