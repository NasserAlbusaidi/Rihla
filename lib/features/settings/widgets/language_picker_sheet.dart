import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Bottom sheet for picking the app language.
///
/// Unlocked in PR2a (l10n PR for Settings/Profile) — Arabic is now a live
/// option backed by translated ARBs for the Settings + Profile surfaces.
/// Ledger / Groups / Home stay English until PR2b + PR3.
class LanguagePickerSheet extends ConsumerWidget {
  const LanguagePickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(context.spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.languageSheetTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: context.spacing.space16),
            RadioGroup<String>(
              groupValue: current,
              onChanged: (code) async {
                if (code == null) return;
                HapticService.selection();
                await ref
                    .read(settingsProvider.notifier)
                    .setLanguage(code);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'en',
                    title: Text(context.l10n.languageEnglish),
                  ),
                  RadioListTile<String>(
                    value: 'ar',
                    title: Text(context.l10n.languageArabic),
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
