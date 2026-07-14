import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class ReconcileFooter extends StatelessWidget {
  const ReconcileFooter({
    super.key,
    required this.descriptor,
    required this.addsUpTo,
  });

  final Widget descriptor;
  final String addsUpTo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.success.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          descriptor,
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.check_rounded, size: 14, color: colors.successText),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  addsUpTo,
                  style: AppTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.successText,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
