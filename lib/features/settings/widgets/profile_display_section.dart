import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/models/app_settings_model.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import 'theme_picker_sheet.dart';

/// Display section widget for ProfileScreen (D-05 / Phase 37).
///
/// Exposes a single "Theme" tile that opens [ThemePickerSheet]. The trailing
/// label reflects the current [AppThemeMode] — "System • Following device",
/// "Light", or "Dark".
///
/// Tile style mirrors [ProfileAboutSection] — same card container, same
/// icon-container + label + trailing layout.
class ProfileDisplaySection extends ConsumerWidget {
  const ProfileDisplaySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final label = switch (mode) {
      AppThemeMode.system => 'System • Following device',
      AppThemeMode.light => 'Light',
      AppThemeMode.dark => 'Dark',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context),
        SizedBox(height: context.spacing.space8),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: context.shadows.raised,
          ),
          child: _buildThemeTile(context, label),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.brightness_6_outlined,
          size: 16,
          color: context.colors.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          'DISPLAY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.colors.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildThemeTile(BuildContext context, String trailingLabel) {
    return GestureDetector(
      onTap: () => ThemePickerSheet.show(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space16,
          vertical: context.spacing.space8,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.colors.inputFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Icons.brightness_6_outlined,
                  size: 18,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            SizedBox(width: context.spacing.space12),
            Expanded(
              child: Text(
                'Theme',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            Text(
              trailingLabel,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
            ),
            SizedBox(width: context.spacing.space8),
            Icon(
              Iconsax.arrow_right_3,
              size: 16,
              color: context.colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
