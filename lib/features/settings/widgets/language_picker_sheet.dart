import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Bottom sheet for picking the app language.
///
/// Only English is functional today. Arabic is rendered as a locked option to
/// signal intent without enabling a half-translated experience. Full Arabic
/// support is tracked as T5.O in `docs/plans/coming-soon-implementations.md`.
class LanguagePickerSheet extends ConsumerWidget {
  const LanguagePickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const LanguagePickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(settingsProvider.select((s) => s.languageCode));
    final colors = context.colors;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(context.spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Language', style: Theme.of(context).textTheme.headlineSmall),
            SizedBox(height: context.spacing.space16),
            RadioGroup<String>(
              groupValue: current,
              onChanged: (code) async {
                if (code == null || code == 'ar') return;
                HapticService.selection();
                await ref
                    .read(settingsProvider.notifier)
                    .setLanguage(code);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RadioListTile<String>(
                    value: 'en',
                    title: Text('English'),
                  ),
                  RadioListTile<String>(
                    value: 'ar',
                    title: Text(
                      'العربية',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                    subtitle: Text(
                      'Coming soon',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                    enabled: false,
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
