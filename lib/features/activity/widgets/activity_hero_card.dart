import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Hero card for the Activity screen — D-16.
///
/// Read-only card: shows entry count and last update time. No CTA button
/// (Activity feed is read-only per D-16).
class ActivityHeroCard extends StatelessWidget {
  /// Total number of activity log entries.
  final int entryCount;

  /// Pre-formatted relative time string (e.g., "2 hours ago") or
  /// "No activity yet" when the feed is empty.
  final String lastUpdate;

  const ActivityHeroCard({
    super.key,
    required this.entryCount,
    required this.lastUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppColors.space16,
        AppColors.space16,
        AppColors.space16,
        0,
      ),
      padding: const EdgeInsets.all(AppColors.space20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusLarge + 8),
        boxShadow: AppColors.shadowRaised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: "ACTIVITY" overline
          const Text(
            'ACTIVITY',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppColors.space8),
          // Row 2: entry count
          Text(
            '$entryCount entries',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppColors.space4),
          // Row 3: last update
          Text(
            'Last update: $lastUpdate',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
          // No CTA button — Activity is read-only per D-16
        ],
      ),
    );
  }
}
