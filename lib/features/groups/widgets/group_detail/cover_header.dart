import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../../../core/utils/share_helper.dart';

import '../../../../core/config/app_links.dart';
import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/cover_art.dart';
import '../../../../shared/widgets/r_icon_button.dart';
import '../../keys/group_keys.dart';
import '../../models/group_model.dart';
import 'overflow_menu.dart';

class CoverHeader extends StatelessWidget {
  const CoverHeader({required this.group});
  final Group group;

  @override
  Widget build(BuildContext context) {
    final statusBar = MediaQuery.of(context).padding.top;
    final memberCount = group.memberIds.length;
    return SizedBox(
      height: 168 + statusBar,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // #626: cache the procedural cover raster — this header lives in a
          // SliverToBoxAdapter (no automatic per-child RepaintBoundary).
          RepaintBoundary(child: CoverArt.fromSeed(group.name)),
          // Dark gradient overlay — transparent at top, ink at bottom.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  context.colors.textPrimary.withValues(alpha: 0.55),
                ],
                stops: const [0.4, 1.0],
              ),
            ),
          ),
          // Top buttons row.
          Positioned.directional(
            textDirection: Directionality.of(context),
            top: statusBar + 8,
            start: 12,
            end: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RIconButton(
                  icon: Iconsax.arrow_left,
                  matchTextDirection: true,
                  semanticLabel: context.l10n.commonBack,
                  onTap: () {
                    HapticService.lightClick();
                    final router = GoRouter.of(context);
                    if (router.canPop()) {
                      router.pop();
                    } else {
                      router.go('/home');
                    }
                  },
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // #291: surface "invite a friend" on the group screen —
                    // reuses the link-bearing share message (#277) instead of
                    // burying it in Group Settings.
                    RIconButton(
                      key: GroupKeys.groupDetailInviteButton,
                      icon: Iconsax.user_add,
                      semanticLabel: context.l10n.groupShareInviteSemantic,
                      onTap: () {
                        HapticService.selection();
                        shareText(
                          context,
                          context.l10n.groupShareInviteMessage(
                            group.name,
                            AppLinks.inviteUrl(group.inviteCode).toString(),
                            group.inviteCode,
                          ),
                          subject: context.l10n.groupShareSubject(group.name),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    // #807: promote per-group activity out of the overflow
                    // menu (the menu keeps its entry as a redundant path).
                    RIconButton(
                      key: GroupKeys.groupDetailActivityButton,
                      icon: Iconsax.clock,
                      semanticLabel: context.l10n.groupActivity,
                      onTap: () {
                        HapticService.lightClick();
                        GoRouter.of(
                          context,
                        ).push('/group/${group.id}/activity');
                      },
                    ),
                    const SizedBox(width: 8),
                    OverflowMenu(groupId: group.id),
                  ],
                ),
              ],
            ),
          ),
          // Bottom title block.
          Positioned.directional(
            textDirection: Directionality.of(context),
            start: 20,
            end: 20,
            top: statusBar + 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.groupMemberCountCaps(memberCount),
                  style: AppTypography.caption(
                    context,
                    fontSize: 9,
                    color: context.colors.textOnPrimary.withValues(alpha: 0.85),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  group.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.displayOf(
                    context,
                    fontSize: 30,
                    color: context.colors.textOnPrimary,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
