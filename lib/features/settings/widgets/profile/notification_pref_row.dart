import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../keys/profile_keys.dart';

class NotificationPrefRow extends StatelessWidget {
  const NotificationPrefRow({
    super.key,
    required this.leading,
    required this.value,
    required this.permissionDenied,
    required this.errored,
    required this.onChanged,
    required this.onOpenSettings,
    required this.onRetry,
  });

  final Widget leading;
  final bool value;

  /// OS permission is denied. The control stays interactive but routes to the
  /// OS settings page instead of toggling the pref — the toggle can't re-request
  /// permission itself on Android 13+ (#470).
  final bool permissionDenied;

  /// Registration failed (a transient FCM/Firestore token-write error): the
  /// user is opted-in but receives nothing. The switch reads OFF and a tap
  /// retries instead of toggling the pref (#482). Mutually exclusive with
  /// [permissionDenied]; denial takes precedence if both somehow hold.
  final bool errored;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Denied → deep-link to OS settings; errored → retry; otherwise toggle the
    // pref. In the first two the switch stays visually OFF (nothing is being
    // delivered), so a tap is a recovery action, not a value flip.
    final String subtitle;
    final VoidCallback onTap;
    if (permissionDenied) {
      subtitle = context.l10n.profileNotificationsDisabledHint;
      onTap = onOpenSettings;
    } else if (errored) {
      subtitle = context.l10n.profileNotificationsErrorHint;
      onTap = onRetry;
    } else {
      subtitle = context.l10n.profileNotificationsSubtitle;
      onTap = () => onChanged(!value);
    }
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          key: ProfileKeys.notificationToggleTile,
          onTap: onTap,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    leading,
                    SizedBox(width: context.spacing.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.l10n.profilePreferencesNotifications,
                            style: AppTypography.sans(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: AppTypography.sans(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      key: ProfileKeys.notificationSwitch,
                      value: value,
                      onChanged: permissionDenied
                          ? (_) => onOpenSettings()
                          : errored
                          ? (_) => onRetry()
                          : onChanged,
                      activeThumbColor: colors.primary,
                      activeTrackColor: colors.primary,
                      inactiveTrackColor: colors.cardSoft,
                    ),
                  ],
                ),
              ),
              Container(height: 0.5, color: colors.rule),
            ],
          ),
        ),
      ),
    );
  }
}
