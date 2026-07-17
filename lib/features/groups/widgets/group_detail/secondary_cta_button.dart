import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class SecondaryCtaButton extends StatelessWidget {
  const SecondaryCtaButton({
    super.key,
    required this.label,
    required this.onTap,
    this.buttonKey,
  });
  final String label;
  final VoidCallback onTap;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(spacing.radiusMedium),
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(spacing.radiusMedium),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: Ink(
              height: 42,
              decoration: BoxDecoration(
                color: colors.cardSoft,
                borderRadius: BorderRadius.circular(spacing.radiusMedium),
                border: Border.all(color: colors.rule, width: 0.5),
              ),
              child: Center(
                child: Text(
                  label,
                  style: AppTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
