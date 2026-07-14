import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../shared/widgets/r_avatar.dart';
import '../../../../shared/widgets/wordmark_logo.dart';
import '../../../groups/providers/group_balance_provider.dart';
import '../../../settings/widgets/edit_name_bottom_sheet.dart';
import '../../keys/home_keys.dart';
import '../../providers/activity_unread_provider.dart';
import '../bottom_nav_shell.dart';
import 'icon_circle.dart';
import 'set_name_chip.dart';

class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceName = ref.watch(settingsProvider.select((s) => s.deviceName));
    // #1168: key the avatar's palette slot on the stable uid so this same
    // person's color matches everywhere else they're rendered.
    final currentUserId = ref.watch(currentUserIdProvider);
    // #818 Wave 4.1: the "?" avatar is otherwise a dead end — nothing cues
    // that tapping it lets you set a name. Self-hides the instant a name is
    // saved; no dismissal flag, no SharedPreferences key.
    final showSetNameChip = deviceName.trim().isEmpty;
    const avatarSize = 36.0;
    // #1077 §4: the tap target is 44dp while the painted avatar stays 36 —
    // the chip budget below must subtract the occupied width, not the visual.
    const avatarHitSize = 44.0;
    void openProfile() {
      HapticService.lightClick();
      context.push('/profile');
    }
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 6, 16, 0),
        // Stack so the wordmark sits on the bar's true geometric centre,
        // independent of the asymmetric clusters (avatar left vs search+bell
        // right). Row-with-Spacers centred it in the *leftover* space, so the
        // wider right cluster drifted it ~20px toward the avatar side — left
        // in LTR and mirrored to the right in RTL. Stack centring is
        // direction-agnostic and fixes both.
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep the optional chip inside the leading side's half of the
            // bar: after the avatar + gaps, budget against the centered
            // wordmark's MEASURED half-width (a constant guard is wrong under
            // test fonts, whose glyphs render far wider than production —
            // #1064). Its existing ellipsis then yields before it can paint
            // over the mark.
            final wordmarkHalfWidth =
                WordmarkLogo.measuredTextWidth(context) / 2;
            final setNameChipMaxWidth =
                (constraints.maxWidth / 2 -
                        wordmarkHalfWidth -
                        context.spacing.space8 -
                        avatarHitSize -
                        context.spacing.space8)
                    .clamp(0.0, double.infinity);
            return Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  children: [
                    Semantics(
                      button: true,
                      label: context.l10n.profileTitle,
                      onTap: openProfile,
                      excludeSemantics: true,
                      child: GestureDetector(
                        key: HomeKeys.profileAvatar,
                        behavior: HitTestBehavior.opaque,
                        onTap: openProfile,
                        // #1077 §4: 44dp hit box; the avatar stays 36px and
                        // keeps hugging the bar's start edge.
                        child: SizedBox(
                          width: avatarHitSize,
                          height: avatarHitSize,
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: RAvatar(
                              name: deviceName,
                              size: avatarSize,
                              colorKey: currentUserId,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (showSetNameChip) ...[
                      SizedBox(width: context.spacing.space8),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: setNameChipMaxWidth,
                          ),
                          child: SetNameChip(
                            onTap: () => _openEditNameSheet(context, ref),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // #900 friction #3 — PR-5b: global search entry point, left
                    // of the bell in the right cluster.
                    IconCircle(
                      key: HomeKeys.searchButton,
                      badgeKey: HomeKeys.searchButtonBadge,
                      icon: Iconsax.search_normal,
                      semanticLabel: context.l10n.searchTitle,
                      onTap: () {
                        HapticService.lightClick();
                        context.push('/search');
                      },
                    ),
                    SizedBox(width: context.spacing.space4),
                    IconCircle(
                      key: HomeKeys.activityBell,
                      badgeKey: HomeKeys.bellUnreadBadge,
                      icon: Iconsax.activity,
                      showBadge: ref.watch(activityUnreadProvider),
                      semanticLabel: context.l10n.homeBottomNavActivity,
                      onTap: () {
                        HapticService.lightClick();
                        // #818 Wave 5.2: select the History tab in place rather
                        // than pushing /activity — the route stays for deep links.
                        final scope = BottomNavTabScope.maybeOf(context);
                        if (scope != null) {
                          scope.selectTab(1);
                        } else {
                          context.push('/activity');
                        }
                      },
                    ),
                  ],
                ),
                const WordmarkLogo(size: 22),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openEditNameSheet(BuildContext context, WidgetRef ref) {
    HapticService.lightClick();
    // Same idiom as ProfileScreen._openEditSheet — opens EditNameBottomSheet
    // directly rather than routing through Profile.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => EditNameBottomSheet(
        currentName: '',
        onSave: (name) async {
          await ref.read(settingsProvider.notifier).setDeviceName(name);
        },
      ),
    );
  }
}
