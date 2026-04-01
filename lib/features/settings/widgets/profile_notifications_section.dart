import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';
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
        _buildSectionHeader(),
        const SizedBox(height: 12),
        _buildNotificationTile(context, ref, isOn: isOn, isPermDenied: isPermDenied),
      ],
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      children: [
        Icon(
          Iconsax.notification,
          size: 16,
          color: AppColorTokens.light.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          'NOTIFICATIONS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColorTokens.light.textSecondary,
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
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadowTokens.standard.raised,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 36px icon container (D-03)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColorTokens.light.inputFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Iconsax.notification,
                  size: 18,
                  color: AppColorTokens.light.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Push Notifications',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColorTokens.light.textPrimary,
                    ),
                  ),
                  if (isPermDenied) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Enable in device Settings',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColorTokens.light.textSecondary,
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
                  : (value) async {
                      await HapticService.selection();
                      await ref
                          .read(settingsProvider.notifier)
                          .setPushNotificationsEnabled(value);
                    },
              activeThumbColor: AppColorTokens.light.primary,
              activeTrackColor: AppColorTokens.light.primary,
              inactiveTrackColor: AppColorTokens.light.inputFill,
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
  void _hydratePermissionStatus(WidgetRef ref) {
    FirebaseMessaging.instance.getNotificationSettings().then((settings) {
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        ref.read(notificationStatusProvider.notifier).state =
            NotificationStatus.permissionDenied;
      }
    }).catchError((Object _) {
      // Silently ignore — FCM may be unavailable in test environments
    });
  }
}
