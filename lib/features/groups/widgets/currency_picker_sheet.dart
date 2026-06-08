import 'package:flutter/material.dart';

import '../../../core/constants/supported_currencies.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/currency_display_name.dart';

/// Bottom sheet for picking a group's currency at CREATE time (#261).
///
/// Unlike the (removed) settings currency picker, this writes NOTHING to
/// [AppSettings] — it returns the picked ISO code to the caller via
/// [Navigator.pop], because a group's currency is a per-group, write-once value
/// (Model A: immutable after create). Offers all 10 supported codes in the
/// canonical GCC-first order ([kSupportedCurrencies]).
class CurrencyPickerSheet extends StatelessWidget {
  const CurrencyPickerSheet({super.key, required this.selected});

  /// The currently-selected ISO code (highlighted radio).
  final String selected;

  /// Opens the sheet and resolves to the picked ISO code, or null if dismissed.
  static Future<String?> show(BuildContext context, {required String selected}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CurrencyPickerSheet(selected: selected),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(context.spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.currencySheetTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: context.spacing.space4),
            Text(
              context.l10n.createGroupCurrencyHint,
              style: AppTypography.sans(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            SizedBox(height: context.spacing.space16),
            RadioGroup<String>(
              groupValue: selected,
              onChanged: (code) {
                if (code == null) return;
                HapticService.selection();
                Navigator.of(context).pop(code);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final code in kSupportedCurrencies)
                    RadioListTile<String>(
                      value: code,
                      title: Text(currencyDisplayName(code, context.l10n)),
                      subtitle: Text(code),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
