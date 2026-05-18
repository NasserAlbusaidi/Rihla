import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../keys/profile_keys.dart';

/// Notifications section widget for ProfileScreen.
///
/// Displays a push notification toggle tile with three states:
/// - ON (enabled): notifications are active
/// - OFF (enabled): notifications are off but can be turned on
/// - Disabled: OS permission was denied, tapping opens app settings
class ProfileNotificationsSection extends ConsumerWidget {
  const ProfileNotificationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifStatus = ref.watch(notificationStatusProvider);

    // Hydrate permission denied state on first build (Pitfall 2)
    _hydratePermissionStatus(ref);

    final isPermDenied = notifStatus == NotificationStatus.permissionDenied;
    final isOn = settings.pushNotificationsEnabled && !isPermDenied;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context),
        SizedBox(height: context.spacing.space8),
        _buildNotificationTile(context, ref, isOn: isOn, isPermDenied: isPermDenied),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          Iconsax.notification,
          size: 16,
          color: context.colors.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          context.l10n.profileNotificationsSectionLabel,
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

  Widget _buildNotificationTile(
    BuildContext context,
    WidgetRef ref, {
    required bool isOn,
    required bool isPermDenied,
  }) {
    final tile = Container(
      key: ProfileKeys.notificationToggleTile,
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.shadows.raised,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space16,
          vertical: context.spacing.space8,
        ),
        child: Row(
          children: [
            // 36px icon container (D-03)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.colors.inputFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Iconsax.notification,
                  size: 18,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            SizedBox(width: context.spacing.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.profileNotificationsTitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  if (isPermDenied) ...[
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.profileNotificationsDisabledHint,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch.adaptive(
              key: ProfileKeys.notificationSwitch,
              value: isOn,
              onChanged: isPermDenied
                  ? null
                  : (value) {
                      HapticService.selection();
                      ref
                          .read(settingsProvider.notifier)
                          .setPushNotificationsEnabled(value);
                    },
              activeThumbColor: context.colors.primary,
              activeTrackColor: context.colors.primary,
              inactiveTrackColor: context.colors.inputFill,
            ),
          ],
        ),
      ),
    );

    if (isPermDenied) {
      return GestureDetector(
        onTap: AppSettings.openAppSettings,
        child: tile,
      );
    }

    return tile;
  }

  /// Hydrate [notificationStatusProvider] from the OS permission state.
  ///
  /// Called once per build — the StateProvider deduplicates identical writes
  /// so multiple invocations are safe. This covers the cold-start case where
  /// the user had previously denied permission (Pitfall 2).
  ///
  /// Wrapped in try/catch because FirebaseMessaging.instance may throw
  /// if Firebase is not initialized (e.g., in test environments).
  void _hydratePermissionStatus(WidgetRef ref) {
    try {
      FirebaseMessaging.instance.getNotificationSettings().then((settings) {
        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          ref.read(notificationStatusProvider.notifier).state =
              NotificationStatus.permissionDenied;
        }
      }).catchError((Object err) {
        // Silently ignore — FCM may be unavailable in test environments
      });
    } catch (_) {
      // FirebaseMessaging.instance threw synchronously — not initialized
    }
  }
}
