import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/r_amount.dart';
import '../../../../shared/widgets/skeleton_loader.dart';
import '../../keys/event_keys.dart';
import 'hub_state.dart';

/// The expanded per-currency balance display — reuses the hub's copy and
/// state machine (empty / settled / uniform-owed / uniform-owe / mixed).
class BalanceBlock extends StatelessWidget {
  const BalanceBlock({super.key, required this.state, required this.lines});

  final HubState state;
  final List<({String currency, Decimal net})> lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isOwed = state == HubState.youOwed;
    final label = switch (state) {
      HubState.youOwed => context.l10n.eventYouAreOwed,
      HubState.youOwe => context.l10n.eventYouOwe,
      HubState.mixed => context.l10n.eventYourBalance,
      _ => null,
    };

    return Column(
      key: EventKeys.balanceHeader,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text(
            label,
            style: AppTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          SizedBox(height: context.spacing.space4),
        ],
        // #1028: unavailable/pending render FIRST — with empty lines they
        // would otherwise fall through to the lines else-branch (empty
        // column), and with wrong non-empty lines they must never render.
        if (state == HubState.unavailable)
          Row(
            key: EventKeys.balanceHeaderUnavailable,
            children: [
              Icon(Iconsax.warning_2, size: 16, color: colors.warning),
              SizedBox(width: context.spacing.space8),
              Text(
                context.l10n.homeBalanceUnavailable,
                style: AppTypography.displayOf(
                  context,
                  fontSize: 20,
                  color: colors.textSecondary,
                  height: 1.05,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          )
        else if (state == HubState.pending)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: KeyedSubtree(
              key: EventKeys.balanceHeaderPending,
              child: SkeletonLoader.trailingBalance(),
            ),
          )
        else if (state == HubState.empty || state == HubState.settled)
          Text(
            state == HubState.settled
                ? context.l10n.eventAllSettled
                : context.l10n.eventNothingToSettleYet,
            style: AppTypography.displayOf(
              context,
              fontSize: 26,
              color: state == HubState.settled
                  ? colors.successText
                  : colors.textSecondary,
              height: 1.05,
              letterSpacing: -0.3,
            ),
          )
        else if (lines.length == 1)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: RAmount(
              value: lines.first.net.abs(),
              currency: lines.first.currency,
              size: 34,
              weight: FontWeight.w800,
              sign: true,
              tone: isOwed ? AmountTone.sage : AmountTone.rust,
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines.length; i++)
                Padding(
                  padding: EdgeInsetsDirectional.only(top: i == 0 ? 0 : 2),
                  child: RAmount(
                    value: lines[i].net,
                    currency: lines[i].currency,
                    size: 26,
                    weight: FontWeight.w800,
                    sign: true,
                    tone: lines[i].net > Decimal.zero
                        ? AmountTone.sage
                        : AmountTone.rust,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
