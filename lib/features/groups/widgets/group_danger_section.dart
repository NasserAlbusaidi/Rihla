import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../keys/group_keys.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import 'delete_group_sheet.dart';
import 'settings_section_header.dart';

/// Danger zone section widget for GroupSettingsScreen.
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
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.colors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
            border: Border.all(
              color: context.colors.error.withValues(alpha: 0.16),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsSectionHeader(
                title: isCreator
                    ? context.l10n.groupDangerZoneCreatorOnly
                    : context.l10n.groupDangerZone,
                color: context.colors.error,
              ),
              const SizedBox(height: 6),
              _buildLeaveGroupTile(context, ref),
              if (isCreator) ...[
                const SizedBox(height: 8),
                _buildDeleteGroupTile(context, ref),
              ],
            ],
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
      child: Row(
        children: [
          Expanded(
            child: _DangerCopy(
              title: context.l10n.groupLeaveThisGroup,
              subtitle: context.l10n.groupLeaveSubtitle,
            ),
          ),
          _DangerButton(
            label: context.l10n.groupLeave,
            onTap: () {
              HapticService.selection();
              _showLeaveDialog(context, ref);
            },
          ),
        ],
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
      child: Row(
        children: [
          Expanded(
            child: _DangerCopy(
              title: context.l10n.groupDeleteThisGroup,
              subtitle: context.l10n.groupDeleteSubtitle,
            ),
          ),
          _DangerButton(
            label: context.l10n.groupDelete,
            onTap: () {
              HapticService.selection();
              _showDeleteDialog(context, ref);
            },
          ),
        ],
      ),
    );
  }

  void _showLeaveDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: GroupKeys.leaveGroupDialog,
        title: Text(
          context.l10n.groupLeaveQuestion,
          style: AppTypography.sans(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        content: Text(
          context.l10n.groupLeaveBody,
          style: AppTypography.sans(
            fontSize: 14,
            color: context.colors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              context.l10n.groupStayInGroup,
              style: AppTypography.sans(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
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
              context.l10n.groupLeaveGroup,
              style: AppTypography.sans(
                fontSize: 14,
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
      groupName: groupName ?? context.l10n.groupDeleteThisGroup,
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
              content: Text(context.l10n.groupSettleBeforeLeaving),
              action: SnackBarAction(
                label: context.l10n.groupSettleUp,
                onPressed: () => context.push('/group/$groupId/settle-up'),
              ),
            ),
          );
        }
        return;
      }
    }

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
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.groupFailedLeave(e.toString()))),
        );
      }
    }
  }

  Future<void> _executeDelete(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final balancesAsync = ref.read(groupBalancesProvider(groupId));
    final balances = balancesAsync.valueOrNull;
    if (balances != null) {
      final hasOutstanding = balances.balances.any(
        (b) => b.netBalance != Decimal.zero,
      );
      if (hasOutstanding) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.groupSettleBeforeDeleting)),
          );
        }
        return;
      }
    }

    try {
      await ref.read(groupServiceProvider).deleteGroup(groupId: groupId);
      router.go('/home');
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.groupFailedDelete(e.toString()))),
        );
      }
    }
  }
}

class _DangerCopy extends StatelessWidget {
  const _DangerCopy({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.sans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: AppTypography.sans(
            fontSize: 12,
            color: context.colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.errorText,
      borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: AppTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.textOnPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
