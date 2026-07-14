import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class PrefRow extends StatelessWidget {
  const PrefRow({
    super.key,
    required this.label,
    this.leading,
    this.trailingText,
    this.trailing,
    this.onTap,
    this.divider = true,
    this.tileKey,
  });

  final Widget? leading;
  final String label;
  final String? trailingText;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;
  final Key? tileKey;

  PrefRow copyWith({bool? divider}) => PrefRow(
    leading: leading,
    label: label,
    trailingText: trailingText,
    trailing: trailing,
    onTap: onTap,
    divider: divider ?? this.divider,
    tileKey: tileKey,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trailingWidget =
        trailing ??
        (trailingText != null
            // #1184: keep the Flexible so a very long value ellipsizes instead
            // of overflowing, but Align the (short) value to the trailing edge —
            // a bare loose Flexible sizes to the text and parks it at the row's
            // centre. AlignmentDirectional mirrors for Arabic RTL.
            ? Flexible(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    trailingText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sans(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink());

    return InkWell(
      key: tileKey,
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  SizedBox(width: context.spacing.space12),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                trailingWidget,
              ],
            ),
          ),
          if (divider) Container(height: 0.5, color: colors.rule),
        ],
      ),
    );
  }
}
