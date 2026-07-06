import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class DeleteCard extends StatelessWidget {
  const DeleteCard({super.key, required this.enabled, required this.onDelete});

  final bool enabled;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Container(
        padding: EdgeInsets.all(context.spacing.space16),
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
          border: Border.all(color: colors.error.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.editorDeleteThisExpense,
                    style: AppTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.editorDeleteThisExpenseBody,
                    style: AppTypography.sans(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: context.spacing.space12),
            FilledButton.icon(
              onPressed: enabled ? onDelete : null,
              icon: const Icon(Iconsax.trash, size: 14),
              label: Text(context.l10n.commonDelete),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                // design-token-justified: white foreground on the rust
                // destructive delete CTA — no textOnError token exists.
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsetsDirectional.fromSTEB(14, 9, 14, 11),
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
            ),
          ],
        ),
      ),
    );
  }
}
