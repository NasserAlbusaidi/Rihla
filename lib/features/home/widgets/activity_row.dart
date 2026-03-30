import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/theme/app_theme.dart';
import '../../groups/models/group_activity_log_model.dart';

/// A single row in the cross-group activity feed.
///
/// Displays:
/// - A colored avatar circle with the first letter of [activity.actorName]
/// - Actor name + description text
/// - Group name tag chip
/// - Relative timestamp (via timeago)
///
/// The avatar color is deterministic based on [activity.actorName.hashCode],
/// ensuring the same actor always gets the same color.
class ActivityRow extends StatelessWidget {
  /// The activity log entry to display.
  final GroupActivityLog activity;

  /// The name of the group this activity belongs to (enriched from D-14).
  final String groupName;

  /// The group ID, used for navigation on tap.
  final String groupId;

  /// Optional tap handler.
  final VoidCallback? onTap;

  const ActivityRow({
    super.key,
    required this.activity,
    required this.groupName,
    required this.groupId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatarColor =
        Colors.primaries[activity.actorName.hashCode.abs() % Colors.primaries.length];
    final initial = activity.actorName.isNotEmpty
        ? activity.actorName[0].toUpperCase()
        : '?';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppColors.space4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: avatarColor,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: AppColors.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        activity.actorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: AppColors.space4),
                      Flexible(
                        child: Text(
                          activity.description,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          groupName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppColors.space8),
                      Text(
                        timeago.format(activity.timestamp),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
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
