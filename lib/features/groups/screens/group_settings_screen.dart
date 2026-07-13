import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/error_message_translator.dart';
import '../../../shared/widgets/r_icon_button.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/claim_requests_section.dart';
import '../widgets/group_danger_section.dart';
import '../widgets/group_info_section.dart';
import '../widgets/group_members_section.dart';

/// Screen for managing group settings.
///
/// Wireframe ref: `Wireframes/Rihla/hifi/screens-group.jsx` →
/// `Hi_GroupSettings()`.
class GroupSettingsScreen extends ConsumerWidget {
  const GroupSettingsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupDetailProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final currentUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      key: GroupKeys.settingsScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: groupAsync.when(
          data: (group) {
            if (group == null) return _ErrorState(groupId: groupId);

            final members = membersAsync.valueOrNull ?? [];
            final isCreator = currentUserId == group.createdBy;

            return Column(
              children: [
                _SettingsTopBar(groupId: groupId),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      context.spacing.space20,
                      6,
                      context.spacing.space20,
                      context.spacing.space20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GroupInfoSection(
                          group: group,
                          isCreator: isCreator,
                        ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.08),
                        const SizedBox(height: 10),
                        GroupMembersSection(
                          groupId: groupId,
                          members: members,
                          currentUserId: currentUserId,
                          isCurrentUserCreator: isCreator,
                        ).animate().fadeIn(delay: 160.ms).slideY(begin: 0.08),
                        const SizedBox(height: 10),
                        // #278 PR9: pending placeholder-claim requests (creator
                        // only; hidden when empty).
                        ClaimRequestsSection(
                          groupId: groupId,
                          isCreator: isCreator,
                        ),
                        _DefaultsSection(
                          group: group,
                          isCreator: isCreator,
                        ).animate().fadeIn(delay: 240.ms).slideY(begin: 0.08),
                        SizedBox(height: context.spacing.space12),
                        GroupDangerSection(
                          groupId: groupId,
                          isCreator: isCreator,
                          groupName: group.name,
                        ).animate().fadeIn(delay: 320.ms).slideY(begin: 0.08),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => Column(
            children: [
              _SettingsTopBar(groupId: groupId),
              Expanded(
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    context.spacing.space20,
                    6,
                    context.spacing.space20,
                    context.spacing.space20,
                  ),
                  child: SkeletonLoader.generic(count: 3),
                ),
              ),
            ],
          ),
          error: (_, _) => _ErrorState(groupId: groupId),
        ),
      ),
    );
  }
}

class _SettingsTopBar extends StatelessWidget {
  const _SettingsTopBar({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.spacing.space12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: RIconButton(
                variant: RIconButtonVariant.ghost,
                key: GroupKeys.settingsBackButton,
                icon: Iconsax.arrow_left,
                matchTextDirection: true,
                onTap: () {
                  final router = GoRouter.of(context);
                  if (router.canPop()) {
                    router.pop();
                  } else {
                    router.go('/home');
                  }
                },
              ),
            ),
            Text(
              key: GroupKeys.settingsTitle,
              context.l10n.groupSettingsTitle,
              style: AppTypography.sans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DefaultsSection extends StatelessWidget {
  const _DefaultsSection({required this.group, required this.isCreator});

  final Group group;
  final bool isCreator;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: context.l10n.groupDefaults,
          padding: EdgeInsets.zero,
        ),
        SizedBox(height: context.spacing.space8),
        Container(
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(spacing.radiusLarge),
            boxShadow: context.shadows.raised,
          ),
          padding: EdgeInsets.symmetric(horizontal: context.spacing.space16),
          child: Column(
            children: [
              _DefaultsRow(
                key: GroupKeys.settingsCurrencyTile,
                title: context.l10n.groupCurrency,
                value: group.currency,
                locked: true,
                divider: isCreator,
              ),
              // #363: settle-up mode is creator-only metadata (rules
              // isCreator()) — non-creators get no affordance at all.
              if (isCreator) _SimplifyDebtsRow(group: group),
            ],
          ),
        ),
        SizedBox(height: context.spacing.space8),
        Padding(
          padding: EdgeInsetsDirectional.only(start: spacing.space4),
          child: Text(
            context.l10n.groupCurrencyLockedNote,
            style: AppTypography.sans(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// #363: the per-group "Simplify debts" switch. ON (default; field absent on
/// legacy groups ⇒ true) keeps the min-transfers optimizer; OFF switches both
/// settle-up screens to the direct pro-rata fan-out. The write is a plain
/// 2-key Firestore update through [GroupService.setSimplifyDebts] — the SDK
/// queues it offline and the group stream echoes the local write immediately,
/// so nothing gates on the raw future (#412); awaiting only surfaces a rules
/// rejection as a snackbar (mirrors the rename/glyph error handling).
class _SimplifyDebtsRow extends ConsumerWidget {
  const _SimplifyDebtsRow({required this.group});

  final Group group;

  Future<void> _setValue(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    HapticService.lightClick();
    try {
      await ref
          .read(groupServiceProvider)
          .setSimplifyDebts(groupId: group.id, value: value);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyMessageFor(context, e)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.space8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.groupSimplifyDebtsTitle,
                  style: AppTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
                SizedBox(height: context.spacing.space4),
                Text(
                  group.simplifyDebts
                      ? l10n.groupSimplifyDebtsOnSubtitle
                      : l10n.groupSimplifyDebtsOffSubtitle,
                  style: AppTypography.sans(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: context.spacing.space12),
          Switch(
            key: GroupKeys.settingsSimplifyDebtsSwitch,
            value: group.simplifyDebts,
            onChanged: (value) => _setValue(context, ref, value),
          ),
        ],
      ),
    );
  }
}

class _DefaultsRow extends StatelessWidget {
  const _DefaultsRow({
    super.key,
    required this.title,
    required this.value,
    required this.divider,
    this.locked = false,
  });

  final String title;
  final String value;
  final bool divider;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: context.spacing.space4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              if (locked) ...[
                Icon(
                  Iconsax.lock,
                  size: 13,
                  color: context.colors.textSecondary,
                ),
                SizedBox(width: context.spacing.space4),
              ],
              Text(
                value,
                style: AppTypography.sans(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (divider) Container(height: 0.5, color: context.colors.rule),
      ],
    );
  }
}

class _ErrorState extends ConsumerWidget {
  const _ErrorState({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _SettingsTopBar(groupId: groupId),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Iconsax.warning_2,
                    size: 32,
                    color: context.colors.textSecondary,
                  ),
                  SizedBox(height: context.spacing.space8),
                  Text(
                    context.l10n.groupSettingsLoadFailed,
                    style: AppTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: context.spacing.space4),
                  Text(
                    context.l10n.activityLoadFailedMessage,
                    textAlign: TextAlign.center,
                    style: AppTypography.sans(
                      fontSize: 14,
                      color: context.colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: context.spacing.space16),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(groupDetailProvider(groupId)),
                    child: Text(
                      context.l10n.groupTryAgain,
                      style: AppTypography.sans(
                        fontSize: 14,
                        color: context.colors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
