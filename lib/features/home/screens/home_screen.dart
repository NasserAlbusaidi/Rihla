import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../groups/providers/group_provider.dart';
import '../../groups/widgets/group_card.dart';

/// Groups-first home screen (D-01).
///
/// Replaces the legacy trip-based home screen. Displays the current user's
/// groups via [userGroupsProvider], with a FAB for create/join actions.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(userGroupsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            const OfflineBanner(),
            Expanded(
              child: groupsAsync.when(
                data: (groups) => RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(userGroupsProvider);
                    // Wait briefly for the new stream to emit its first value
                    await ref.read(userGroupsProvider.future);
                  },
                  color: AppColors.primary,
                  child: groups.isEmpty
                      ? const EmptyStateView(
                          icon: Iconsax.people,
                          title: 'No groups yet',
                          message:
                              'Create a group with friends or enter an invite code to join one.',
                        )
                      : _buildGroupList(context, groups),
                ),
                loading: _buildSkeletonCards,
                error: (e, st) {
                  debugPrint('Groups load error: $e');
                  return EmptyStateView(
                    icon: Iconsax.warning_2,
                    title: "Couldn't load groups",
                    message: e.toString(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFabBottomSheet(context),
        backgroundColor: AppColors.primary,
        child: const Icon(Iconsax.add, color: AppColors.textOnPrimary),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppColors.space24,
        AppColors.space32,
        AppColors.space24,
        AppColors.space8,
      ),
      child: Text(
        'Your Groups',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
    );

    if (!reduceMotion) {
      header = header
          .animate()
          .fadeIn(duration: 600.ms)
          .slideY(begin: -0.1, end: 0, curve: Curves.easeOutCubic);
    }

    return header;
  }

  Widget _buildGroupList(BuildContext context, List groups) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppColors.space24,
        vertical: AppColors.space16,
      ),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        Widget card = Padding(
          padding: const EdgeInsets.only(bottom: AppColors.space16),
          child: GroupCard(
            group: group,
            onTap: () => _navigateToGroupDetail(context, group),
          ),
        );

        if (!reduceMotion) {
          card = card
              .animate()
              .fadeIn(duration: 400.ms)
              .slideY(
                begin: 0.05,
                end: 0,
                curve: Curves.easeOutCubic,
                delay: Duration(milliseconds: 50 * min(index, 5)),
              );
        }

        return card;
      },
    );
  }

  Widget _buildSkeletonCards() {
    return SkeletonLoader.groupList(count: 3);
  }

  void _navigateToGroupDetail(BuildContext context, dynamic group) {
    context.push('/group/${group.id}');
  }

  void _showFabBottomSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Create a Group
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppColors.space16,
              ),
              minTileHeight: 64,
              leading: const Icon(Iconsax.people, color: AppColors.primary),
              title: Text(
                'Create a Group',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/create-group');
              },
            ),
            // Join a Group
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppColors.space16,
              ),
              minTileHeight: 64,
              leading: const Icon(
                Iconsax.login_1,
                color: AppColors.textSecondary,
              ),
              title: Text(
                'Join a Group',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/join-group');
              },
            ),
          ],
        ),
      ),
    );
  }
}
