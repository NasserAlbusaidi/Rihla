import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../shared/widgets/initials_circle.dart';
import '../keys/profile_keys.dart';
import '../providers/profile_stats_provider.dart';
import '../widgets/edit_name_bottom_sheet.dart';
import '../widgets/profile_about_section.dart';
import '../widgets/profile_display_section.dart';
import '../widgets/profile_notifications_section.dart';
import '../widgets/profile_stats_section.dart';
import '../widgets/profile_support_section.dart';

/// Profile screen displaying identity (initials circle + display name) and
/// cross-group stats (groups, events, total spending).
///
/// The screen is unrouted in this plan — routing is wired in Phase 25-02.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final stats = ref.watch(profileStatsProvider);
    final canPop = GoRouter.of(context).canPop();

    return Scaffold(
      key: ProfileKeys.screen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Optional back button (shown when pushed on nav stack)
                if (canPop) ...[
                  SizedBox(height: context.spacing.space12),
                  _buildBackButton(context),
                ],

                SizedBox(height: context.spacing.space12),

                // Identity section
                _buildIdentitySection(context, ref, settings.deviceName)
                    .animate()
                    .fadeIn(delay: 100.ms)
                    .slideY(begin: 0.1),

                SizedBox(height: context.spacing.space16),

                // Stats section
                ProfileStatsSection(stats: stats)
                    .animate()
                    .fadeIn(delay: 200.ms)
                    .slideY(begin: 0.1),

                const SizedBox(height: 10),

                // Notifications section (D-04: after Stats)
                const ProfileNotificationsSection()
                    .animate()
                    .fadeIn(delay: 300.ms)
                    .slideY(begin: 0.1),

                SizedBox(height: context.spacing.space12),

                // Display section (D-05 / Phase 37) — above About
                const ProfileDisplaySection()
                    .animate()
                    .fadeIn(delay: 350.ms)
                    .slideY(begin: 0.1),

                SizedBox(height: context.spacing.space12),

                // About section
                const ProfileAboutSection()
                    .animate()
                    .fadeIn(delay: 400.ms)
                    .slideY(begin: 0.1),

                SizedBox(height: context.spacing.space12),

                // Support section
                const ProfileSupportSection()
                    .animate()
                    .fadeIn(delay: 500.ms)
                    .slideY(begin: 0.1),

                SizedBox(height: context.spacing.space24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.inputFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.inputFill),
        ),
        child: IconButton(
          icon: Icon(
            Iconsax.arrow_left,
            color: context.colors.textPrimary,
            size: 20,
          ),
          onPressed: () => GoRouter.of(context).pop(),
        ),
      ),
    );
  }

  Widget _buildIdentitySection(
    BuildContext context,
    WidgetRef ref,
    String deviceName,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Initials circle — 64dp diameter
          InitialsCircle(
            key: ProfileKeys.initialsCircle,
            size: 64,
            name: deviceName,
          ),
          SizedBox(height: context.spacing.space12),
          // Name display or "Set your name" prompt
          if (deviceName.isNotEmpty)
            GestureDetector(
              onTap: () => _openEditSheet(context, ref, deviceName),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    deviceName,
                    key: ProfileKeys.displayName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  SizedBox(width: context.spacing.space8),
                  Icon(
                    Iconsax.edit_2,
                    size: 16,
                    color: context.colors.textSecondary,
                  ),
                ],
              ),
            )
          else
            GestureDetector(
              onTap: () => _openEditSheet(context, ref, deviceName),
              child: Text(
                'Set your name',
                key: ProfileKeys.setNamePrompt,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.colors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openEditSheet(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) {
    HapticService.selection();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => EditNameBottomSheet(
        currentName: ref.read(settingsProvider).deviceName,
        onSave: (name) async {
          await ref.read(settingsProvider.notifier).setDeviceName(name);
        },
      ),
    );
  }
}
