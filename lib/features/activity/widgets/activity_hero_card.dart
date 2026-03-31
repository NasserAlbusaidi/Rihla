import 'package:flutter/material.dart';

import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

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
        16,
        16,
        16,
        0,
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(16 + 8),
        boxShadow: AppShadowTokens.standard.raised,
        image: const DecorationImage(
          image: AssetImage('assets/textures/grain.png'),
          repeat: ImageRepeat.repeat,
          opacity: 0.035,
          fit: BoxFit.none,
          alignment: Alignment.topLeft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: "ACTIVITY" overline
          Text(
            'ACTIVITY',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColorTokens.light.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          // Row 2: entry count
          Text(
            '$entryCount entries',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColorTokens.light.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          // Row 3: last update
          Text(
            'Last update: $lastUpdate',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AppColorTokens.light.textSecondary,
            ),
          ),
          // No CTA button — Activity is read-only per D-16
        ],
      ),
    );
  }
}
