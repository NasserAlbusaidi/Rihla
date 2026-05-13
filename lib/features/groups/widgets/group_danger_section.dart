import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../keys/group_keys.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import 'delete_group_sheet.dart';

/// Danger zone section widget for GroupSettingsScreen.
///
/// Shows a Leave Group tile (all members) and a Delete Group tile (creator
/// only). Leave still uses an AlertDialog confirmation; Delete opens the
/// wireframe-aligned bottom sheet (`delete_group_sheet.dart`) with a
/// type-to-confirm gate. After leave or delete, navigates to /home.
class GroupDangerSection extends ConsumerWidget {
  const GroupDangerSection({
    super.key,
    required this.groupId,
    required this.isCreator,
    this.groupName,
  });

  final String groupId;
  final bool isCreator;

  /// Used as the type-to-confirm token on the delete sheet. When null we fall
  /// back to a generic "the group" prompt — callers should pass the real name
  /// (creator-only screens always have it).
  final String? groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      key: GroupKeys.dangerSection,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: context.shadows.raised,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLeaveGroupTile(context, ref),
              if (isCreator) ...[
                Divider(height: 1, color: context.colors.inputFill),
                _buildDeleteGroupTile(context, ref),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context) {
    return Row(
      children: [
        Icon(Iconsax.warning_2, size: 16, color: context.colors.errorText),
        const SizedBox(width: 6),
        Text(
          'DANGER ZONE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.colors.errorText,
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
                color: context.colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Iconsax.logout,
                  size: 18,
                  color: context.colors.errorText,
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
                  color: context.colors.errorText,
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
                color: context.colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  Iconsax.trash,
                  size: 18,
                  color: context.colors.errorText,
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
                  color: context.colors.errorText,
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
            color: context.colors.textPrimary,
          ),
        ),
        content: Text(
          "You'll lose access to all events and data in this group.",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: context.colors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Stay in group',
              style: TextStyle(color: context.colors.textSecondary),
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
                color: context.colors.errorText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.read(groupBalancesProvider(groupId));
    final balances = balancesAsync.valueOrNull;
    final memberCount = balances?.balances.length ?? 0;

    showDeleteGroupSheet(
      context,
      groupName: groupName ?? 'this group',
      memberCount: memberCount,
      onConfirm: () {
        HapticService.medium();
        _executeDelete(context, ref);
      },
    );
  }

  Future<void> _executeLeave(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Bug 9: Block leave if current user has an outstanding balance.
    final uid = FirebaseConfig.currentUser?.uid;
    final balancesAsync = ref.read(groupBalancesProvider(groupId));
    final balances = balancesAsync.valueOrNull;
    if (balances != null && uid != null) {
      final userBalance = balances.balances.where(
        (b) => b.participantId == uid,
      );
      if (userBalance.isNotEmpty &&
          userBalance.first.netBalance != Decimal.zero) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Settle up before leaving the group.'),
              action: SnackBarAction(
                label: 'Settle Up',
                onPressed: () => context.push('/group/$groupId/settle-up'),
              ),
            ),
          );
        }
        return;
      }
    }

    // Log member_left activity (D-14) — fire-and-forget before navigation.
    try {
      final actorId = FirebaseConfig.currentUser?.uid ?? '';
      final actorName = ref.read(settingsProvider).deviceName.isNotEmpty
          ? ref.read(settingsProvider).deviceName
          : 'Someone';
      ref
          .read(groupActivityServiceProvider)
          .logGroupEvent(
            groupId: groupId,
            type: 'member_left',
            actorId: actorId,
            actorName: actorName,
            description: 'left the group',
          );
    } catch (_) {
      // Activity logging failure must never crash the leave flow.
    }

    try {
      await ref.read(groupServiceProvider).leaveGroup(groupId: groupId);
      router.go('/home');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to leave group: $e')),
      );
    }
  }

  Future<void> _executeDelete(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Bug 9: Block delete if ANY member has an outstanding balance.
    final balancesAsync = ref.read(groupBalancesProvider(groupId));
    final balances = balancesAsync.valueOrNull;
    if (balances != null) {
      final hasOutstanding = balances.balances.any(
        (b) => b.netBalance != Decimal.zero,
      );
      if (hasOutstanding) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'All members must settle up before deleting the group.',
              ),
            ),
          );
        }
        return;
      }
    }

    try {
      await ref.read(groupServiceProvider).deleteGroup(groupId: groupId);
      router.go('/home');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete group: $e')),
      );
    }
  }
}
