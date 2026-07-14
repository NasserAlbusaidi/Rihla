import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/r_amount.dart';
import '../../../../shared/widgets/r_avatar.dart';

class OwesRow extends StatelessWidget {
  const OwesRow({
    super.key,
    required this.name,
    this.colorKey,
    required this.role,
    required this.owed,
    required this.currency,
    required this.showDivider,
  });

  final String name;

  /// Participant id (== member userId, #1168) — keys the avatar's palette
  /// slot on stable identity instead of the display name.
  final String? colorKey;

  final String? role;
  final Decimal owed;
  final String currency;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: showDivider ? colors.rule : Colors.transparent,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          RAvatar(name: name, size: 28, colorKey: colorKey),
          SizedBox(width: context.spacing.space12),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (role != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    role!,
                    style: AppTypography.sans(
                      fontSize: 11,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: context.spacing.space12),
          RAmount(value: owed, currency: currency, size: 13),
        ],
      ),
    );
  }
}
