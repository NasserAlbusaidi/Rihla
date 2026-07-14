import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/skeleton_loader.dart';
import '../../../ledger/providers/expense_provider.dart';
import '../../keys/group_keys.dart';
import '../../models/group_model.dart';
import '../../providers/group_balance_provider.dart';
import 'member_row.dart';

class MembersCard extends StatelessWidget {
  const MembersCard({
    required this.group,
    required this.balancesAsync,
    required this.currentUid,
    this.forceLoading = false,
    this.membersHasError = false,
  });

  final Group group;
  final AsyncValue<GroupBalances> balancesAsync;
  final String? currentUid;

  /// #574: true while the group-detail staging-window retry is in progress —
  /// render a skeleton, never the transient "couldn't load members" error.
  final bool forceLoading;

  /// #574: true when the members read itself failed — `balancesAsync` swallows a
  /// members error into empty data, so the card needs this to show the real
  /// error instead of an endless "Loading members…".
  final bool membersHasError;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final data = balancesAsync.valueOrNull;

    // #382 PR-1: memberNames (currency-independent, spans every known uid)
    // is the row source — the bucket map is empty for a zero-money group, but
    // the members card must still list everyone. Same key set and order as
    // the old flat balances list.
    if (forceLoading || data == null || data.memberNames.isEmpty) {
      return Container(
        padding: EdgeInsets.symmetric(
          vertical: 18,
          horizontal: context.spacing.space16,
        ),
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(spacing.radiusLarge),
          boxShadow: context.shadows.raised,
        ),
        child: forceLoading
            ? SkeletonLoader.groupList(count: 3)
            : Text(
                (balancesAsync.hasError || membersHasError)
                    ? context.l10n.groupMembersLoadFailed
                    : context.l10n.groupMembersLoading,
                style: AppTypography.sans(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
      );
    }

    // #486: the hero owns the current user's net — list everyone ELSE here,
    // then a collapsed "You · shown above" row last that does NOT restate the
    // figure. (currentUid null / absent from the roster → no self-row, all
    // render as others.)
    final allMembers = data.memberNames.entries.toList();
    final others = allMembers.where((e) => e.key != currentUid).toList();
    final selfMatches = allMembers.where((e) => e.key == currentUid).toList();
    final self = selfMatches.isEmpty ? null : selfMatches.first;
    final rowCount = others.length + (self == null ? 0 : 1);
    // #630: one O(C×M) pivot for the whole roster; each row indexes it in O(1)
    // instead of re-running a per-row O(C×M) myNetByCurrency pivot.
    final netsByUid = pivotNetsByParticipant(data.balances);
    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space16),
      child: Column(
        children: [
          for (var i = 0; i < others.length; i++)
            MemberRow(
              name: others[i].value,
              userId: others[i].key,
              role: _roleFor(
                context: context,
                participantId: others[i].key,
                creatorId: group.createdBy,
                currentUid: currentUid,
              ),
              lines: nonZeroNetsGccFirst(
                netsByUid[others[i].key] ?? const {},
              ),
              groupCurrency: group.currency,
              divider: i < rowCount - 1,
              onTap: () => GoRouter.of(
                context,
              ).push('/group/${group.id}/settle-up?memberId=${others[i].key}'),
            ),
          if (self != null)
            MemberRow(
              key: GroupKeys.selfMemberRow,
              name: self.value,
              userId: self.key,
              role: context.l10n.groupRoleYou,
              lines: const [],
              groupCurrency: group.currency,
              divider: false,
              shownAbove: true,
              onTap: null,
            ),
        ],
      ),
    );
  }

  static String? _roleFor({
    required BuildContext context,
    required String participantId,
    required String creatorId,
    required String? currentUid,
  }) {
    if (currentUid != null && participantId == currentUid) {
      return context.l10n.groupRoleYou;
    }
    if (participantId == creatorId) return context.l10n.groupRoleCreator;
    return null;
  }
}
