import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      child: Row(
        children: [
          Text(
            label,
            style: AppTypography.caption(
              context,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
