import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Hero card for the Gear screen (D-12).
///
/// Shows packed progress, priority item count badge, and Add Item CTA.
class GearHeroCard extends StatelessWidget {
  final int packedCount;
  final int totalCount;
  final int priorityCount;
  final VoidCallback onAddItem;

  const GearHeroCard({
    super.key,
    required this.packedCount,
    required this.totalCount,
    required this.priorityCount,
    required this.onAddItem,
  });

  @override
  Widget build(BuildContext context) {
    final progress =
        totalCount > 0 ? (packedCount / totalCount).clamp(0.0, 1.0) : 0.0;

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
            'PACKING PROGRESS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppColors.space8),
          // Packed count heading
          Text(
            'Packed $packedCount/$totalCount',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppColors.space12),
          // Progress bar
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation(AppColors.moduleLedger),
            borderRadius: BorderRadius.circular(2),
          ),
          if (priorityCount > 0) ...[
            const SizedBox(height: AppColors.space12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppColors.radiusSmall),
              ),
              child: Text(
                '$priorityCount priority',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.errorText,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppColors.space16),
          // Add Item CTA
          SizedBox(
            width: double.infinity,
            height: AppColors.buttonHeight,
            child: ElevatedButton(
              onPressed: onAddItem,
              child: const Text('Add Item'),
            ),
          ),
        ],
      ),
    );
  }
}
