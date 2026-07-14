import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/r_avatar.dart';

class SplitPersonRow extends StatelessWidget {
  const SplitPersonRow({
    super.key,
    required this.name,
    this.colorKey,
    required this.label,
    required this.share,
    required this.currency,
    required this.isPayer,
    required this.isSelf,
  });

  /// Full disambiguated name — used for initials.
  final String name;

  /// Participant id (== member userId, #1168) — keys the avatar's palette
  /// slot on stable identity instead of the display name.
  final String? colorKey;

  /// Compact display label (first name + `(#…)` only on collision).
  final String label;
  final Decimal share;
  final String currency;
  final bool isPayer;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: EdgeInsets.symmetric(vertical: isSelf ? 2 : 0),
      padding: EdgeInsetsDirectional.fromSTEB(isSelf ? 8 : 0, 9, isSelf ? 8 : 0, 9),
      decoration: isSelf
          ? BoxDecoration(
              color: colors.selectionFill,
              borderRadius: BorderRadius.circular(10),
            )
          : null,
      child: Row(
        children: [
          RAvatar(name: name, size: 30, colorKey: colorKey),
          SizedBox(width: context.spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                if (isPayer) ...[
                  const SizedBox(height: 1),
                  Text(
                    context.l10n.editorPaidRole,
                    style: AppTypography.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryDark,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Wrapped LTR so the amount can't bidi-reorder in Arabic (#151).
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              AppFormatters.formatCurrency(share, currency),
              maxLines: 1,
              softWrap: false,
              style: AppTypography.mono(
                fontSize: 14,
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
