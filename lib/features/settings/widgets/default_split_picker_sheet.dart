import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/models/split_mode.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/split_mode_display_name.dart';

/// Bottom sheet for picking the default split mode used when adding a new
/// expense.
class DefaultSplitPickerSheet extends ConsumerWidget {
  const DefaultSplitPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const DefaultSplitPickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        ref.watch(settingsProvider.select((s) => s.defaultSplitMode));
    final colors = context.colors;
    final l10n = context.l10n;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(context.spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.defaultSplitSheetTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: context.spacing.space4),
            Text(
              l10n.defaultSplitSheetSubtitle,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            SizedBox(height: context.spacing.space16),
            RadioGroup<SplitMode>(
              groupValue: current,
              onChanged: (mode) async {
                if (mode == null) return;
                HapticService.selection();
                await ref
                    .read(settingsProvider.notifier)
                    .setDefaultSplitMode(mode);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final mode in SplitMode.values)
                    RadioListTile<SplitMode>(
                      value: mode,
                      title: Text(splitModeDisplayName(mode, l10n)),
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
