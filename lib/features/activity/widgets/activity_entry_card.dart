import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/theme/app_theme.dart';
import '../models/activity_log_model.dart';

/// Activity entry card for the date-grouped timeline — D-21.
///
/// Shows a deterministic-color avatar circle (initial of actor name),
/// a description derived from [ActivityLog.logText] and actor, plus a
/// relative time stamp.
class ActivityEntryCard extends StatelessWidget {
  final ActivityLog log;

  const ActivityEntryCard({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final actorName = log.actorName ?? 'Unknown';
    final initial = actorName.isNotEmpty ? actorName[0].toUpperCase() : '?';

    // Deterministic color from actor name hash — same as Phase 18 ActivityRow pattern
    final avatarColor =
        Colors.primaries[actorName.hashCode.abs() % Colors.primaries.length];

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppColors.space16,
        vertical: AppColors.space4,
      ),
      padding: const EdgeInsets.all(AppColors.space16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusLarge + 8),
        boxShadow: AppColors.shadowRaised,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar circle with deterministic color
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: avatarColor.withValues(alpha: 0.15),
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: avatarColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppColors.space12),
          // Content column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Line 1: actor name + action description
                Text(
                  log.logText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                // Line 2: relative time
                Text(
                  timeago.format(log.createdAt),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
