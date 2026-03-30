import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../keys/logistics_keys.dart';
import '../models/sub_group_model.dart';

/// Card for a single sub-group in the Logistics screen (D-22).
///
/// Shows the group name and icon, capacity progress bar (4dp, moduleLogistics
/// fill), member name chips, and delete/remove member actions.
/// Has a 3dp dusty-teal top border accent per D-22.
class SubGroupCard extends StatelessWidget {
  final SubGroup subGroup;
  final VoidCallback? onRenameGroup;
  final void Function(SubGroup group) onDeleteGroup;
  final void Function(SubGroup group) onAddMember;
  final void Function(SubGroupMember member, SubGroup group) onRemoveMember;

  const SubGroupCard({
    super.key,
    required this.subGroup,
    this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onAddMember,
    required this.onRemoveMember,
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
          // Row 1: icon + name + capacity fraction + more button
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
              IconButton(
                icon: const Icon(
                  Iconsax.more,
                  size: 20,
                  color: AppColors.textMuted,
                ),
                onPressed: () => onDeleteGroup(subGroup),
              ),
            ],
          ),
          const SizedBox(height: AppColors.space8),
          // Row 2: capacity progress bar
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation(AppColors.moduleLogistics),
            borderRadius: BorderRadius.circular(2),
          ),
          if (subGroup.members.isNotEmpty) ...[
            const SizedBox(height: AppColors.space8),
            // Row 3: member chips — tappable for remove confirmation
            Wrap(
              spacing: AppColors.space8,
              runSpacing: AppColors.space4,
              children: subGroup.members.map((member) {
                return GestureDetector(
                  onTap: () => _confirmRemoveMember(context, member),
                  child: Container(
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
                      _memberInitial(member),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (subGroup.members.length < subGroup.capacity) ...[
            const SizedBox(height: AppColors.space8),
            GestureDetector(
              onTap: () => onAddMember(subGroup),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Iconsax.add, size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      '${subGroup.capacity - subGroup.members.length} open',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmRemoveMember(BuildContext context, SubGroupMember member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'REMOVE MEMBER',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        content: Text(
          'Remove ${member.displayName?.toUpperCase()} from ${subGroup.name.toUpperCase()}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            key: LogisticsKeys.removeButton,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'REMOVE',
              style: TextStyle(
                color: AppColors.errorText,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      HapticService.lightClick();
      onRemoveMember(member, subGroup);
    }
  }

  String _memberInitial(SubGroupMember member) {
    final name = member.displayName;
    if (name != null && name.isNotEmpty) return name[0];
    return 'U';
  }

  IconData _iconForType(SubGroupType type) {
    return switch (type) {
      SubGroupType.car => Iconsax.car,
      SubGroupType.room => Iconsax.house,
      SubGroupType.team => Iconsax.people,
    };
  }
}
