import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/utils/formatters.dart';
import '../models/group_activity_log_model.dart';
import '../../../core/theme/tokens/color_tokens.dart';

/// A single activity log entry tile.
///
/// Per UI-SPEC Screen 5. Display-only — no tap interactions.
///
/// Activity types and their icons:
/// - event_created: [Iconsax.calendar_add] (mint)
/// - event_deleted: [Iconsax.calendar_remove] (textMuted)
/// - group_settlement: [Iconsax.tick_circle] (emerald)
/// - member_joined: [Iconsax.profile_add] (mint)
/// - member_left: [Iconsax.profile_delete] (textMuted)
class GroupActivityTile extends StatelessWidget {
  final GroupActivityLog activity;

  const GroupActivityTile({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _iconAndColor(activity.type);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon container
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),

          const SizedBox(width: 12),

          // Text column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Actor name + description on same line
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: activity.actorName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColorTokens.light.textPrimary,
                        ),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: activity.description,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColorTokens.light.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                // Relative timestamp
                Text(
                  AppFormatters.formatRelativeDate(activity.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColorTokens.light.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the icon and color for the given activity type.
  (IconData, Color) _iconAndColor(String type) {
    return switch (type) {
      'event_created' => (Iconsax.calendar_add, AppColorTokens.light.primary),
      'event_deleted' => (Iconsax.calendar_remove, AppColorTokens.light.textMuted),
      'group_settlement' => (Iconsax.tick_circle, AppColorTokens.light.success),
      'member_joined' => (Iconsax.profile_add, AppColorTokens.light.primary),
      'member_left' => (Iconsax.profile_delete, AppColorTokens.light.textMuted),
      _ => (Iconsax.info_circle, AppColorTokens.light.textMuted),
    };
  }
}
