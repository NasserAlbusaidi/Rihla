import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Hero card for the Logistics screen (D-13).
///
/// Shows group/member stats, unassigned count, and Create Group CTA.
class LogisticsHeroCard extends StatelessWidget {
  final int groupCount;
  final int memberCount;
  final int unassignedCount;
  final VoidCallback onCreateGroup;

  const LogisticsHeroCard({
    super.key,
    required this.groupCount,
    required this.memberCount,
    required this.unassignedCount,
    required this.onCreateGroup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppColors.space16,
        AppColors.space16,
        AppColors.space16,
        AppColors.space8,
      ),
      padding: const EdgeInsets.all(AppColors.space20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overline
          const Text(
            'ORGANIZATION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppColors.space8),
          // Groups · members heading
          Text(
            '$groupCount groups · $memberCount members',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (unassignedCount > 0) ...[
            const SizedBox(height: AppColors.space8),
            Text(
              '$unassignedCount unassigned',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.errorText,
              ),
            ),
          ],
          const SizedBox(height: AppColors.space16),
          // Create Group CTA
          SizedBox(
            width: double.infinity,
            height: AppColors.buttonHeight,
            child: ElevatedButton(
              onPressed: onCreateGroup,
              child: const Text('Create Group'),
            ),
          ),
        ],
      ),
    );
  }
}
