import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';
import '../keys/group_keys.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';

/// Danger zone section widget for GroupSettingsScreen.
///
/// Shows a Leave Group tile (all members) and a Delete Group tile (creator
/// only). Both trigger an AlertDialog confirmation before executing. After
/// leave or delete, navigates to /home (context.go — replaces route stack).
class GroupDangerSection extends ConsumerWidget {
  const GroupDangerSection({
    super.key,
    required this.groupId,
    required this.isCreator,
  });

  final String groupId;
  final bool isCreator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      key: GroupKeys.dangerSection,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColorTokens.light.cardSurface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadowTokens.standard.raised,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLeaveGroupTile(context, ref),
              if (isCreator) ...[
                Divider(height: 1, color: AppColorTokens.light.inputFill),
                _buildDeleteGroupTile(context, ref),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      children: [
        Icon(
          Iconsax.warning_2,
          size: 16,
          color: AppColorTokens.light.errorText,
        ),
        const SizedBox(width: 6),
        Text(
          'DANGER ZONE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColorTokens.light.errorText,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildLeaveGroupTile(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      key: GroupKeys.leaveGroupTile,
      onTap: () {
        HapticService.selection();
        _showLeaveDialog(context, ref);
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColorTokens.light.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Iconsax.logout,
                  size: 18,
                  color: AppColorTokens.light.errorText,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Leave Group',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColorTokens.light.errorText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteGroupTile(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      key: GroupKeys.deleteGroupTile,
      onTap: () {
        HapticService.selection();
        _showDeleteDialog(context, ref);
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColorTokens.light.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Iconsax.trash,
                  size: 18,
                  color: AppColorTokens.light.errorText,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Delete Group',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColorTokens.light.errorText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLeaveDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: GroupKeys.leaveGroupDialog,
        title: Text(
          'Leave group?',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColorTokens.light.textPrimary,
          ),
        ),
        content: Text(
          "You'll lose access to all events and data in this group.",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColorTokens.light.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Stay in group',
              style: TextStyle(color: AppColorTokens.light.textSecondary),
            ),
          ),
          TextButton(
            key: GroupKeys.leaveGroupConfirmButton,
            onPressed: () {
              Navigator.of(ctx).pop();
              HapticService.medium();
              _executeLeave(context, ref);
            },
            child: Text(
              'Leave group',
              style: TextStyle(
                color: AppColorTokens.light.errorText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: GroupKeys.deleteGroupDialog,
        title: Text(
          'Delete group?',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColorTokens.light.textPrimary,
          ),
        ),
        content: Text(
          'This will permanently delete the group and all its events. This cannot be undone.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColorTokens.light.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Keep group',
              style: TextStyle(color: AppColorTokens.light.textSecondary),
            ),
          ),
          TextButton(
            key: GroupKeys.deleteGroupConfirmButton,
            onPressed: () {
              Navigator.of(ctx).pop();
              HapticService.medium();
              _executeDelete(context, ref);
            },
            child: Text(
              'Delete group',
              style: TextStyle(
                color: AppColorTokens.light.errorText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _executeLeave(BuildContext context, WidgetRef ref) {
    // Log member_left activity (D-14) — fire-and-forget before navigation.
    try {
      final actorId = FirebaseConfig.currentUser?.uid ?? '';
      final actorName = FirebaseConfig.currentUser?.displayName ?? 'Someone';
      ref.read(groupActivityServiceProvider).logGroupEvent(
        groupId: groupId,
        type: 'member_left',
        actorId: actorId,
        actorName: actorName,
        description: 'left the group',
      );
    } catch (_) {
      // Activity logging failure must never crash the leave flow.
    }

    // Fire-and-forget — synchronous navigation per Phase 26 P01 decision.
    ref.read(groupServiceProvider).leaveGroup(groupId: groupId);
    if (context.mounted) {
      context.go('/home');
    }
  }

  void _executeDelete(BuildContext context, WidgetRef ref) {
    // Fire-and-forget — synchronous navigation per Phase 26 P01 decision.
    ref.read(groupServiceProvider).deleteGroup(groupId: groupId);
    if (context.mounted) {
      context.go('/home');
    }
  }
}
