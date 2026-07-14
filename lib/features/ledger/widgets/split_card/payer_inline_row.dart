import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/r_avatar.dart';

class PayerInlineRow extends StatelessWidget {
  const PayerInlineRow({
    super.key,
    required this.name,
    this.colorKey,
    required this.onChange,
  });

  final String name;

  /// Payer participant id (== userId, #1168) — keys the avatar's palette
  /// slot on stable identity instead of the display name.
  final String? colorKey;

  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChange,
      child: Row(
        children: [
          RAvatar(name: name, size: 30, colorKey: colorKey),
          SizedBox(width: context.spacing.space12),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.sans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.inputFill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colors.rule2),
            ),
            child: Text(
              context.l10n.editorChange,
              style: AppTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
