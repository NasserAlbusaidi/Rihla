import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/utils/currency_display_name.dart';
import '../../../../shared/widgets/directional_icon.dart';
import 'card_shell.dart';
import 'info_row.dart';

/// #382 PR-6: tappable row showing the picked currency (code + display name)
/// with a trailing chevron. Opens [CurrencyPickerSheet]. Add mode only.
class CurrencyRow extends StatelessWidget {
  const CurrencyRow({super.key, required this.currency, required this.onTap});

  final String currency;
  final VoidCallback onTap;

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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: CardShell(
          child: InfoRow(
            leading: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.selectionFill,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Iconsax.dollar_circle,
                size: 18,
                color: colors.primary,
              ),
            ),
            title: currencyDisplayName(currency, context.l10n),
            subtitle: currency,
            trailing: DirectionalIcon(
              Iconsax.arrow_right_3,
              size: 18,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
