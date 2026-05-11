import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_settings_model.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Bottom sheet that lets the user pick the app's theme mode.
///
/// Three options: System (follow device), Light, Dark. Selection persists
/// immediately via `settingsProvider.setThemeMode(...)` (which writes through
/// to SharedPreferences) and dismisses the sheet.
///
/// Per D-06/D-22 (Phase 37): new widgets consume `AppSpacingTokens` via
/// `context.spacing.*` for all standard-token spacing values.
class ThemePickerSheet extends ConsumerWidget {
  const ThemePickerSheet({super.key});

  /// Convenience launcher — mirrors the shape of other sheet entry-points in
  /// the settings feature (e.g. `EditNameBottomSheet`).
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ThemePickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(settingsProvider.select((s) => s.themeMode));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(context.spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Theme', style: Theme.of(context).textTheme.headlineSmall),
            SizedBox(height: context.spacing.space16),
            RadioGroup<AppThemeMode>(
              groupValue: current,
              onChanged: (v) async {
                if (v == null) return;
                await ref.read(settingsProvider.notifier).setThemeMode(v);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _option(
                    context,
                    AppThemeMode.system,
                    'System',
                    'Follow device setting',
                  ),
                  _option(context, AppThemeMode.light, 'Light', 'Always light'),
                  _option(context, AppThemeMode.dark, 'Dark', 'Always dark'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(BuildContext c, AppThemeMode mode, String label, String desc) {
    return RadioListTile<AppThemeMode>(
      value: mode,
      title: Text(label),
      subtitle: Text(desc, style: TextStyle(color: c.colors.textSecondary)),
    );
  }
}
