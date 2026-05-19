import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../keys/group_keys.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/group_danger_section.dart';
import '../widgets/group_info_section.dart';
import '../widgets/group_members_section.dart';
import '../widgets/settings_section_header.dart';

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
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      20,
                      6,
                      20,
                      20,
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
                        _DefaultsSection(
                          currency: group.currency,
                        ).animate().fadeIn(delay: 240.ms).slideY(begin: 0.08),
                        const SizedBox(height: 12),
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
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 6, 20, 20),
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _GhostIconButton(
                key: GroupKeys.settingsBackButton,
                icon: Directionality.of(context) == TextDirection.rtl
                    ? Iconsax.arrow_right
                    : Iconsax.arrow_left,
                onTap: () {
                  if (GoRouter.of(context).canPop()) {
                    GoRouter.of(context).pop();
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

class _GhostIconButton extends StatelessWidget {
  const _GhostIconButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 18, color: context.colors.textPrimary),
        ),
      ),
    );
  }
}

class _DefaultsSection extends StatelessWidget {
  const _DefaultsSection({required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(title: context.l10n.groupDefaults),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(spacing.radiusLarge),
            boxShadow: context.shadows.raised,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _DefaultsRow(
                key: GroupKeys.settingsCurrencyTile,
                title: context.l10n.groupCurrency,
                value: currency,
                divider: true,
              ),
              _DefaultsRow(
                title: context.l10n.groupDefaultSplit,
                value: context.l10n.groupDefaultSplitEqual,
                divider: true,
              ),
              _DefaultsRow(
                title: context.l10n.groupReminders,
                value: context.l10n.groupRemindersWeekly,
                divider: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DefaultsRow extends StatelessWidget {
  const _DefaultsRow({
    super.key,
    required this.title,
    required this.value,
    required this.divider,
  });

  final String title;
  final String value;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
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
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Iconsax.warning_2,
                    size: 32,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.groupSettingsLoadFailed,
                    style: AppTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.activityLoadFailedMessage,
                    textAlign: TextAlign.center,
                    style: AppTypography.sans(
                      fontSize: 14,
                      color: context.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
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
