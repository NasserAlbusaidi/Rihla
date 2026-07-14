import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/r_amount.dart';
import '../../../../shared/widgets/r_avatar.dart';

class MemberRow extends StatelessWidget {
  const MemberRow({
    super.key,
    required this.name,
    this.userId,
    required this.role,
    required this.lines,
    required this.groupCurrency,
    required this.divider,
    required this.onTap,
    this.shownAbove = false,
  });

  final String name;

  /// Member userId (#1168) — keys the avatar's palette slot on stable
  /// identity instead of the display name.
  final String? userId;

  final String? role;
  final List<({String currency, Decimal net})> lines;
  final String groupCurrency;
  final bool divider;
  final VoidCallback? onTap;

  /// #486: the current user's collapsed self-row — name + "(You)" but a muted
  /// "shown above" in place of a money figure (the hero owns their net), and
  /// no tap target (you can't settle up with yourself).
  final bool shownAbove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
            child: Row(
              children: [
                RAvatar(name: name, size: 32, colorKey: userId),
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      if (role != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          role!,
                          style: AppTypography.sans(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: context.spacing.space8),
                if (shownAbove)
                  Text(
                    context.l10n.groupBalanceShownAbove,
                    style: AppTypography.sans(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                  )
                else if (lines.isEmpty)
                  Text(
                    '—',
                    style: AppTypography.sans(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // L7: ≥2 lines → every line carries its code; a sole
                      // line only when foreign — keeps the single
                      // group-currency render byte-identical to pre-PR-5.
                      for (var i = 0; i < lines.length; i++)
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            top: i == 0 ? 0 : 2,
                          ),
                          child: RAmount(
                            value: lines[i].net,
                            currency: lines[i].currency,
                            size: 14,
                            sign: true,
                            showCurrency:
                                lines.length >= 2 ||
                                lines[i].currency != groupCurrency,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          if (divider) Container(height: 0.5, color: colors.rule),
        ],
      ),
    );
  }
}
