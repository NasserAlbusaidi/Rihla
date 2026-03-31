import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../trip/models/trip_model.dart';
import '../keys/logistics_keys.dart';
import '../models/sub_group_model.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// A card that renders a single [SubGroup] with its member slots and drag-drop
/// target for adding participants.
///
/// Member slots are shown in a [Wrap] layout. Filled slots display the member's
/// avatar; empty slots show an add-icon placeholder. Tapping the more (...)
/// icon triggers [onDeleteGroup]; tapping an empty slot triggers [onAddMember].
class SubgroupCard extends StatelessWidget {
  final SubGroup group;
  final VoidCallback? onRenameGroup;
  final void Function(SubGroup group) onDeleteGroup;
  final void Function(SubGroup group) onAddMember;
  final void Function(SubGroupMember member, SubGroup group) onRemoveMember;
  final void Function(Participant participant) onDrop;

  const SubgroupCard({
    super.key,
    required this.group,
    this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onAddMember,
    required this.onRemoveMember,
    required this.onDrop,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<Participant>(
      onWillAcceptWithDetails: (details) => !group.isFull,
      onAcceptWithDetails: (details) {
        HapticService.lightClick();
        onDrop(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: AppColorTokens.light.cardSurface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: candidateData.isNotEmpty
                  ? AppColorTokens.light.primary
                  : AppColorTokens.light.inputFill,
              width: candidateData.isNotEmpty ? 2 : 1.5,
            ),
            boxShadow: candidateData.isNotEmpty
                ? [
                    BoxShadow(
                      color: AppColorTokens.light.primary.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : AppShadowTokens.standard.raised,
          ),
          child: Column(
            children: [
              _buildCardHeader(context),
              _buildMemberGrid(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColorTokens.light.inputFill,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColorTokens.light.inputFill,
                width: 1.5,
              ),
            ),
            child: Icon(
              group.type == SubGroupType.car
                  ? Iconsax.car
                  : Iconsax.house,
              color: AppColorTokens.light.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: onRenameGroup,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                      color: AppColorTokens.light.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: group.isFull
                          ? AppColorTokens.light.warning.withValues(alpha: 0.1)
                          : AppColorTokens.light.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${group.memberCount} / ${group.capacity} SLOTS FILLED',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: group.isFull
                            ? AppColorTokens.light.warning
                            : AppColorTokens.light.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Iconsax.more,
              size: 20,
              color: AppColorTokens.light.textMuted,
            ),
            onPressed: () => onDeleteGroup(group),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberGrid(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: List.generate(group.capacity, (index) {
          if (index < group.members.length) {
            return _buildMemberSlot(context, group.members[index]);
          }
          return _buildEmptySlot(context);
        }),
      ),
    );
  }

  Widget _buildMemberSlot(BuildContext context, SubGroupMember member) {
    return Column(
      children: [
        GestureDetector(
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: AppColorTokens.light.cardSurface,
                title: const Text(
                  'REMOVE MEMBER',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                content: Text(
                  'Remove ${member.displayName?.toUpperCase()} from ${group.name.toUpperCase()}?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('CANCEL'),
                  ),
                  TextButton(
                    key: LogisticsKeys.removeButton,
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                      'REMOVE',
                      style: TextStyle(
                        color: AppColorTokens.light.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              HapticService.lightClick();
              onRemoveMember(member, group);
            }
          },
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColorTokens.light.inputFill,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColorTokens.light.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Center(
              child: member.avatarUrl != null
                  ? ClipOval(
                      child: Image.network(
                        member.avatarUrl!,
                        fit: BoxFit.cover,
                        width: 60,
                        height: 60,
                      ),
                    )
                  : Text(
                      member.initials,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColorTokens.light.primary,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 60,
          child: Text(
            (member.displayName?.split(' ')[0] ?? 'UNK').toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: AppColorTokens.light.textSecondary,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptySlot(BuildContext context) {
    return GestureDetector(
      onTap: () => onAddMember(group),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColorTokens.light.scaffoldBackground,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColorTokens.light.inputFill,
                width: 2,
                style: BorderStyle.solid,
              ),
            ),
            child: Icon(
              Iconsax.add,
              color: AppColorTokens.light.textMuted,
              size: 20,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'OPEN',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              color: AppColorTokens.light.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
