import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

/// #382 PR-6: inline, non-blocking soft warning shown in the add-expense form
/// when the picked currency diverges from the event's dominant (most-frequent)
/// one — a fat-finger guard. Amber soft-notice idiom (tint + icon + text); it
/// never blocks submit and vanishes reactively when the dominant is picked.
class CurrencyMismatchNotice extends StatelessWidget {
  const CurrencyMismatchNotice({
    super.key,
    required this.selected,
    required this.dominant,
  });

  final String selected;
  final String dominant;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        context.spacing.space24,
        context.spacing.space8,
        context.spacing.space24,
        0,
      ),
      child: Container(
        padding: EdgeInsets.all(context.spacing.space12),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Iconsax.warning_2, size: 18, color: colors.warning),
            SizedBox(width: context.spacing.space8),
            Expanded(
              child: Text(
                context.l10n.editorCurrencyMismatch(selected, dominant),
                style: AppTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
