import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/tokens/color_tokens.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../keys/group_keys.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/group_danger_section.dart';
import '../widgets/group_info_section.dart';
import '../widgets/group_members_section.dart';

/// Screen for managing group settings — name (creator-only), currency, invite
/// code, member management, and danger zone (leave / delete).
///
/// Follows the ProfileScreen layout pattern: no AppBar, inline back button,
/// SingleChildScrollView with 24px horizontal padding, three section widgets
/// with staggered entrance animations (D-08, D-09).
class GroupSettingsScreen extends ConsumerWidget {
  final String groupId;

  const GroupSettingsScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupDetailProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final currentUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      key: GroupKeys.settingsScreen,
      backgroundColor: AppColorTokens.light.scaffoldBackground,
      body: SafeArea(
        child: groupAsync.when(
          data: (group) {
            if (group == null) {
              return _buildError(context, ref, 'Group not found');
            }

            final members = membersAsync.valueOrNull ?? [];
            final isCreator = currentUserId == group.createdBy;

            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    _buildBackButton(context),
                    const SizedBox(height: 16),
                    GroupInfoSection(
                      group: group,
                      isCreator: isCreator,
                    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),
                    const SizedBox(height: 16),
                    GroupMembersSection(
                      groupId: groupId,
                      members: members,
                      currentUserId: currentUserId,
                      isCurrentUserCreator: isCreator,
                    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
                    const SizedBox(height: 16),
                    GroupDangerSection(
                      groupId: groupId,
                      isCreator: isCreator,
                    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                _buildBackButton(context),
                const SizedBox(height: 16),
                SkeletonLoader.generic(count: 3),
              ],
            ),
          ),
          error: (e, st) => _buildError(context, ref, null),
        ),
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: GroupKeys.settingsBackButton,
        decoration: BoxDecoration(
          color: AppColorTokens.light.inputFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColorTokens.light.inputFill),
        ),
        child: IconButton(
          icon: Icon(
            Iconsax.arrow_left,
            color: AppColorTokens.light.textPrimary,
            size: 20,
          ),
          onPressed: () => GoRouter.of(context).pop(),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, String? message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          _buildBackButton(context),
          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Icon(Iconsax.warning_2, size: 32, color: AppColorTokens.light.textSecondary),
                const SizedBox(height: 8),
                Text(
                  'Could not load settings',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColorTokens.light.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Check your connection and try again.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColorTokens.light.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => ref.invalidate(groupDetailProvider(groupId)),
                  child: Text(
                    'Try again',
                    style: TextStyle(color: AppColorTokens.light.primary),
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
