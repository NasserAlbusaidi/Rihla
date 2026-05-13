import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/split_mode.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Bottom sheet for picking the default split mode used when adding a new
/// expense.
///
/// Only [SplitMode.equally] is functional. Locked modes are shown so the
/// picker matches the wireframe and surfaces the v1.2 roadmap, but selecting
/// them is a no-op (`SplitMode.isAvailable`).
class DefaultSplitPickerSheet extends ConsumerWidget {
  const DefaultSplitPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
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

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(context.spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Default split',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: context.spacing.space4),
            Text(
              'Applied to new expenses. You can still change the split per expense.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            SizedBox(height: context.spacing.space16),
            RadioGroup<SplitMode>(
              groupValue: current,
              onChanged: (mode) async {
                if (mode == null || !mode.isAvailable) return;
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
                      title: Text(
                        mode.label,
                        style: mode.isAvailable
                            ? null
                            : TextStyle(color: colors.textSecondary),
                      ),
                      subtitle: mode.isAvailable
                          ? null
                          : Text(
                              'Locked — available in v1.2',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                      enabled: mode.isAvailable,
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
