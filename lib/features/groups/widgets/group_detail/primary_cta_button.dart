import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class PrimaryCtaButton extends StatelessWidget {
  const PrimaryCtaButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(spacing.radiusMedium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(spacing.radiusMedium),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: Ink(
              height: 42,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(spacing.radiusMedium),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 14, color: colors.textOnPrimary),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: AppTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textOnPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
