import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class ExpenseTopBar extends StatelessWidget {
  const ExpenseTopBar({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.isLoading,
    required this.onClose,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final bool isLoading;
  final VoidCallback onClose;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 20, 8),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                tooltip: context.l10n.commonClose,
                icon: const Icon(Iconsax.close_circle, size: 20),
                color: context.colors.textPrimary,
                onPressed: onClose,
              ),
            ),
            Text(
              title,
              style: AppTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: isLoading ? null : onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: context.colors.textOnPrimary,
                  minimumSize: const Size(64, 40),
                  padding: EdgeInsetsDirectional.fromSTEB(
                    context.spacing.space16,
                    9,
                    context.spacing.space16,
                    11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      context.spacing.radiusSmall,
                    ),
                  ),
                  textStyle: AppTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.22,
                  ).copyWith(leadingDistribution: TextLeadingDistribution.even),
                ),
                child: isLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.colors.textOnPrimary,
                        ),
                      )
                    : Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
