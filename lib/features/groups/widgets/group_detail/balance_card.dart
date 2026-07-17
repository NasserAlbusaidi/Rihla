import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/r_amount.dart';
import '../../../../shared/widgets/r_avatar.dart';
import '../../keys/group_keys.dart';
import '../../models/group_model.dart';
import 'primary_cta_button.dart';
import 'secondary_cta_button.dart';

class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.group,
    required this.lines,
    required this.memberNames,
    this.memberIds = const [],
    required this.onAddPrimary,
    required this.onSettleUp,
    this.balancesUnavailable = false,
  });

  final Group group;
  final List<({String currency, Decimal net})> lines;
  final List<String> memberNames;

  /// Member userIds paired 1:1 with [memberNames] (#1168) — keys the avatar
  /// stack's palette slot on stable identity instead of the display name.
  final List<String> memberIds;
  final VoidCallback onAddPrimary;
  final VoidCallback onSettleUp;

  /// #1030: the balance basis hard-errored (`hasError && !hasValue`). An
  /// empty [lines] then means "unknown", not "settled" — the caption must
  /// say so instead of the affirmative false "all settled". Stale-valued
  /// errors keep rendering their stale lines and never set this.
  final bool balancesUnavailable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final allPositive =
        lines.isNotEmpty && lines.every((l) => l.net > Decimal.zero);
    final allNegative =
        lines.isNotEmpty && lines.every((l) => l.net < Decimal.zero);
    final captionColor = balancesUnavailable
        ? colors.textSecondary
        : allPositive
        ? colors.success
        : allNegative
        ? colors.error
        : colors.textSecondary;
    // L7: tri-state caption only when all non-zero lines share one sign;
    // mixed signs → omitted (signed, toned amounts self-explain).
    // #1030: unavailable wins over everything — an errored basis must never
    // read as the affirmative "all settled".
    final String? captionText = balancesUnavailable
        ? context.l10n.settleUpCouldNotLoadBalances
        : lines.isEmpty
        ? context.l10n.groupAllSettled
        : allPositive
        ? context.l10n.groupTheyOweYou
        : allNegative
        ? context.l10n.groupYouOwe
        : null;

    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  context.l10n.groupYourBalanceHere,
                  style: AppTypography.displayOf(
                    context,
                    fontSize: 14,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              if (memberNames.isNotEmpty)
                // #807: the stack read as tappable but did nothing — wire it
                // to the members list it implies (group settings hosts it).
                // GestureDetector, not InkWell: a rectangular splash box would
                // clash with the overlapping circular avatars.
                Semantics(
                  button: true,
                  label: context.l10n.groupSettings,
                  child: GestureDetector(
                    key: GroupKeys.groupDetailMemberStack,
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticService.lightClick();
                      GoRouter.of(
                        context,
                      ).push('/group/${group.id}/settings');
                    },
                    child: RAvatarStack(
                      names: memberNames,
                      colorKeys: memberIds,
                      size: 22,
                      max: 4,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: context.spacing.space8),
          if (lines.length >= 2)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < lines.length; i++)
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            top: i == 0 ? 0 : 4,
                          ),
                          child: RAmount(
                            value: lines[i].net,
                            currency: lines[i].currency,
                            size: 24,
                            sign: true,
                            tone: lines[i].net > Decimal.zero
                                ? AmountTone.sage
                                : AmountTone.rust,
                          ),
                        ),
                    ],
                  ),
                ),
                if (captionText != null)
                  Text(
                    captionText,
                    style: AppTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: captionColor,
                    ),
                  ),
              ],
            )
          else
            _singleLineRow(context, captionText!, captionColor),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: PrimaryCtaButton(
                  icon: Iconsax.add,
                  label: context.l10n.eventNew,
                  onTap: onAddPrimary,
                ),
              ),
              SizedBox(width: context.spacing.space8),
              Expanded(
                child: SecondaryCtaButton(
                  label: context.l10n.groupSettleUp,
                  buttonKey: GroupKeys.settleUpCta,
                  onTap: onSettleUp,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 0/1-line render — byte-identical to the pre-PR-5 single-currency card
  /// for the all-zero and group-currency cases (L7); a sole foreign-currency
  /// line carries its code.
  Widget _singleLineRow(
    BuildContext context,
    String captionText,
    Color captionColor,
  ) {
    final line = lines.isEmpty ? null : lines.first;
    final net = line?.net ?? Decimal.zero;
    final tone = net > Decimal.zero
        ? AmountTone.sage
        : net < Decimal.zero
        ? AmountTone.rust
        : AmountTone.ink;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        RAmount(
          value: net,
          currency: line?.currency ?? group.currency,
          size: 32,
          sign: !net.isZero,
          tone: tone,
          showCurrency: line != null && line.currency != group.currency,
        ),
        const Spacer(),
        Text(
          captionText,
          style: AppTypography.sans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: captionColor,
          ),
        ),
      ],
    );
  }
}

extension on Decimal {
  bool get isZero => this == Decimal.zero;
}
