import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../keys/group_keys.dart';
import '../models/group_member_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import 'settings_section_header.dart';

/// Members section widget for GroupSettingsScreen.
///
/// Displays a card with a tile per member, showing an [RAvatar], display
/// name, creator badge (creator only), and a remove button (creator view, for
/// non-creator members). Balance gate blocks removal when member has a non-zero
/// balance (D-07).
class GroupMembersSection extends ConsumerWidget {
  const GroupMembersSection({
    super.key,
    required this.groupId,
    required this.members,
    required this.currentUserId,
    required this.isCurrentUserCreator,
  });

  final String groupId;
  final List<GroupMember> members;
  final String? currentUserId;
  final bool isCurrentUserCreator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      key: GroupKeys.membersSection,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(
          title: context.l10n.groupMembers,
          actionLabel: context.l10n.groupManage,
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: context.colors.cardSurface,
            borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
            boxShadow: context.shadows.raised,
          ),
          padding: EdgeInsets.symmetric(horizontal: context.spacing.space16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _buildMemberTiles(context, ref),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMemberTiles(BuildContext context, WidgetRef ref) {
    final tiles = <Widget>[];
    for (var i = 0; i < members.length; i++) {
      if (i > 0) {
        tiles.add(Container(height: 0.5, color: context.colors.rule));
      }
      tiles.add(_buildMemberTile(context, ref, members[i]));
    }
    return tiles;
  }

  Widget _buildMemberTile(
    BuildContext context,
    WidgetRef ref,
    GroupMember member,
  ) {
    final canRemove =
        isCurrentUserCreator &&
        currentUserId != null &&
        member.userId != currentUserId &&
        !member.isTombstone;

    return Padding(
      key: GroupKeys.memberTile(member.id),
      padding: EdgeInsets.symmetric(vertical: context.spacing.space8),
      child: Row(
        children: [
          RAvatar(size: 30, name: member.displayName),
          SizedBox(width: context.spacing.space12),
          Expanded(
            child: Text(
              member.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.sans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          _buildRoleLabel(context, member),
          if (canRemove)
            IconButton(
              key: GroupKeys.removeMemberButton(member.id),
              icon: Icon(
                Iconsax.user_minus,
                size: 20,
                color: context.colors.textSecondary,
              ),
              tooltip: context.l10n.groupRemoveMemberTooltip(
                member.displayName,
              ),
              onPressed: () {
                HapticService.selection();
                _handleRemove(context, ref, member);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRoleLabel(BuildContext context, GroupMember member) {
    final role = member.isCreator
        ? context.l10n.groupRoleCreator
        : member.userId == currentUserId
        ? context.l10n.groupRoleYou
        : context.l10n.groupRoleMember;
    return Text(
      key: member.isCreator ? GroupKeys.creatorBadge : null,
      role,
      style: AppTypography.sans(
        fontSize: 12,
        color: context.colors.textSecondary,
      ),
    );
  }

  Future<void> _handleRemove(
    BuildContext context,
    WidgetRef ref,
    GroupMember member,
  ) async {
    final balancesAsync = ref.read(groupBalancesProvider(groupId));
    final balances = balancesAsync.valueOrNull;

    if (balances != null) {
      final memberBalance = balances.balances.where(
        (b) => b.participantId == member.userId,
      );
      if (memberBalance.isNotEmpty &&
          memberBalance.first.netBalance != Decimal.zero) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.groupSettleWithBeforeRemoving(member.displayName),
            ),
            action: SnackBarAction(
              label: context.l10n.groupSettleUp,
              onPressed: () => context.push('/group/$groupId/settle-up'),
            ),
          ),
        );
        return;
      }
    }

    // Log member_left activity (D-14) — fire-and-forget before remove call.
    try {
      final actorId = FirebaseConfig.currentUser?.uid ?? '';
      ref
          .read(groupActivityServiceProvider)
          .logGroupEvent(
            groupId: groupId,
            type: 'member_left',
            actorId: actorId,
            actorName: ref.read(settingsProvider).deviceName.isNotEmpty
                ? ref.read(settingsProvider).deviceName
                : member.displayName,
            description: '${member.displayName} was removed from the group',
            metadata: {
              'memberAction': 'removed',
              'memberName': member.displayName,
            },
          );
    } catch (_) {
      // Activity logging failure must never crash the remove flow.
    }

    try {
      await ref
          .read(groupServiceProvider)
          .removeMember(
            groupId: groupId,
            memberId: member.id,
            userId: member.userId,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.groupFailedRemoveMember(
                member.displayName,
                e.toString(),
              ),
            ),
          ),
        );
      }
    }
  }
}
