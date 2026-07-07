import 'package:cloud_functions/cloud_functions.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../../shared/widgets/section_header.dart';
import '../keys/group_keys.dart';
import '../models/group_member_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import 'add_shadow_member_sheet.dart';

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
    // D6-R: addShadowMember accepts anonymous creators — the durable
    // boundary is at join/claim, not add-by-name.
    final canAddByName = isCurrentUserCreator;
    return Column(
      key: GroupKeys.membersSection,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: context.l10n.groupMembers,
          // #278 PR3: only the creator can add placeholder members by name.
          actionLabel: canAddByName ? context.l10n.groupAddMemberAction : null,
          actionKey: GroupKeys.addPersonAction,
          onActionTap: canAddByName
              ? () => AddShadowMemberSheet.show(context, groupId: groupId)
              : null,
          padding: EdgeInsets.zero,
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
        // #807: non-creators see no add/remove affordances — say why instead
        // of leaving the absence unexplained (locked-currency-note pattern).
        if (!canAddByName) ...[
          SizedBox(height: context.spacing.space8),
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: context.spacing.space4,
            ),
            child: Text(
              context.l10n.groupMembersCreatorOnlyNote,
              key: GroupKeys.membersCreatorOnlyNote,
              style: AppTypography.sans(
                fontSize: 12,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
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
          if (member.isShadow) ...[
            _buildShadowBadge(context, member),
            SizedBox(width: context.spacing.space8),
          ],
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

  /// #278 PR3: "Not joined yet" pill on a placeholder (shadow) member tile.
  Widget _buildShadowBadge(BuildContext context, GroupMember member) {
    return Container(
      key: GroupKeys.shadowBadge(member.id),
      padding: const EdgeInsetsDirectional.fromSTEB(8, 3, 8, 3),
      decoration: BoxDecoration(
        color: context.colors.cardSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.colors.rule2),
      ),
      child: Text(
        context.l10n.groupShadowNotJoinedBadge,
        style: AppTypography.sans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.colors.textSecondary,
        ),
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

    final messenger = ScaffoldMessenger.of(context);

    // UX-only short-circuit: when balances are LOADED and the target is not
    // square, show the settle-up hint without a round-trip. On the null/loading
    // path we fall through and let the SERVER decide — the removeMember callable
    // is the sole authority (#318). Never skip the callable just because the
    // local balance is null — that was the offline orphan-debt hole.
    if (balances != null) {
      // #382 PR-1: removable = the target is zero in EVERY currency bucket.
      // Absent from all buckets (no money activity) is settled.
      final hasOutstanding = balances.balances.values.any(
        (bucket) => bucket.any(
          (b) =>
              b.participantId == member.userId && b.netBalance != Decimal.zero,
        ),
      );
      if (hasOutstanding) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.groupSettleWithBeforeRemoving(member.displayName),
            ),
            // Flutter >=3.41 defaults action-bearing snackbars to persist:
            // true (never auto-dismiss) — #411.
            persist: false,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: context.l10n.groupSettleUp,
              onPressed: () => context.push('/group/$groupId/settle-up'),
            ),
          ),
        );
        return;
      }
    }

    // The server writes the `member_left` activity entry (#318). The client no
    // longer logs it — the old client-side log double-logged on success and
    // fired even when the remove write failed.
    try {
      await ref
          .read(groupServiceProvider)
          .removeMember(groupId: groupId, userId: member.userId);
    } on FirebaseFunctionsException catch (e) {
      // Already removed server-side (idempotent / never a member) → no-op.
      if (e.code == 'not-found') {
        return;
      }
      if (!context.mounted) return;
      if (e.code == 'failed-precondition') {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.groupSettleWithBeforeRemoving(member.displayName),
            ),
            // Flutter >=3.41 defaults action-bearing snackbars to persist:
            // true (never auto-dismiss) — #411.
            persist: false,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: context.l10n.groupSettleUp,
              onPressed: () => context.push('/group/$groupId/settle-up'),
            ),
          ),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.groupFailedRemoveMember(
              member.displayName,
              e.message ?? e.code,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
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
