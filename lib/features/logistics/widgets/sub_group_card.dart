import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../models/sub_group_model.dart';

/// Card for a single sub-group in the Logistics screen (D-22).
///
/// Shows the group name and icon, capacity progress bar (4dp, moduleLogistics
/// fill), and member name chips. Has a 3dp dusty-teal top border accent.
class SubGroupCard extends StatelessWidget {
  final SubGroup subGroup;

  const SubGroupCard({
    super.key,
    required this.subGroup,
  });

  @override
  Widget build(BuildContext context) {
    final progress =
        subGroup.capacity > 0
            ? (subGroup.members.length / subGroup.capacity).clamp(0.0, 1.0)
            : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppColors.space16,
        vertical: 6,
      ),
      padding: const EdgeInsets.all(AppColors.space16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusLarge),
        boxShadow: AppColors.cardShadow,
        border: const Border(
          top: BorderSide(color: AppColors.moduleLogistics, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: icon + name + capacity fraction
          Row(
            children: [
              Icon(
                _iconForType(subGroup.type),
                size: 20,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppColors.space8),
              Expanded(
                child: Text(
                  subGroup.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${subGroup.members.length}/${subGroup.capacity}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppColors.space8),
          // Row 2: capacity progress bar
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: AppColors.border,
            valueColor:
                const AlwaysStoppedAnimation(AppColors.moduleLogistics),
            borderRadius: BorderRadius.circular(2),
          ),
          if (subGroup.members.isNotEmpty) ...[
            const SizedBox(height: AppColors.space8),
            // Row 3: member name chips
            Wrap(
              spacing: AppColors.space8,
              runSpacing: AppColors.space4,
              children: subGroup.members.map((member) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.selectionFill,
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusSmall),
                  ),
                  child: Text(
                    member.displayName ?? 'Unknown',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconForType(SubGroupType type) {
    return switch (type) {
      SubGroupType.car => Iconsax.car,
      SubGroupType.room => Iconsax.house,
      SubGroupType.team => Iconsax.people,
    };
  }
}
