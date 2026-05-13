import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/formatters.dart';

/// Bottom sheet for picking the default currency used when creating new trips.
///
/// Existing trips retain their stored currency — this preference only affects
/// the default selection on the create-trip form.
class CurrencyPickerSheet extends ConsumerWidget {
  const CurrencyPickerSheet({super.key});

  /// Order shown in the picker. OMR first since the app is GCC-focused.
  static const _orderedCodes = ['OMR', 'AED', 'SAR', 'USD', 'EUR', 'GBP'];

  static const _displayNames = {
    'OMR': 'Omani rial',
    'AED': 'UAE dirham',
    'SAR': 'Saudi riyal',
    'USD': 'US dollar',
    'EUR': 'Euro',
    'GBP': 'British pound',
  };

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const CurrencyPickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(settingsProvider.select((s) => s.currencyCode));
    final colors = context.colors;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(context.spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Currency', style: Theme.of(context).textTheme.headlineSmall),
            SizedBox(height: context.spacing.space4),
            Text(
              'Default for new trips. Existing trips keep their currency.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            SizedBox(height: context.spacing.space16),
            RadioGroup<String>(
              groupValue: current,
              onChanged: (code) async {
                if (code == null) return;
                HapticService.selection();
                await ref
                    .read(settingsProvider.notifier)
                    .setCurrency(code);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final code in _orderedCodes)
                    RadioListTile<String>(
                      value: code,
                      title: Text(_displayNames[code] ?? code),
                      subtitle: Text(
                        '$code · ${AppFormatters.currencyConfig[code]?.symbol ?? ''}',
                        style: TextStyle(color: colors.textSecondary),
                      ),
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
