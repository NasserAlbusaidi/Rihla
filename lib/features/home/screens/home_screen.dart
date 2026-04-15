import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../shared/animations/fade_in_list.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/initials_circle.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../groups/models/group_model.dart';
import '../../groups/providers/group_provider.dart';
import '../../groups/widgets/group_card.dart';
import '../keys/home_keys.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/activity_row.dart';
import '../widgets/balance_hero_card.dart';
import '../widgets/bottom_nav_shell.dart';
import '../widgets/quick_action_tray.dart';
import '../widgets/weekly_spending_card.dart';
import '../../../core/theme/tokens/color_tokens.dart';

/// Groups-first home dashboard (Phase 18).
///
/// Full dashboard layout with balance hero card, quick-action tray,
/// group cards with personal balance, activity strip, weekly spending chart,
/// and a 4-tab bottom navigation shell.
///
/// Returns [BottomNavShell] wrapping [_DashboardContent]. This separation
/// keeps the nav shell stateful while the content adapts to provider state.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BottomNavShell(
      scaffoldKey: HomeKeys.screen,
      child: _DashboardContent(),
    );
  }
}

// ---------------------------------------------------------------------------
// _DashboardContent — private ConsumerStatefulWidget
// ---------------------------------------------------------------------------

/// Dashboard content for the Groups tab inside [BottomNavShell].
///
/// Delegates rendering to state-specific build methods based on [userGroupsProvider].
class _DashboardContent extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends ConsumerState<_DashboardContent> {

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(userGroupsProvider);

    return SizedBox.expand(
      child: Column(
        children: [
          // Fixed header (always visible across all states)
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                24,
                16,
                16,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your Groups',
                    key: HomeKeys.yourGroupsHeader,
                    style:
                        Theme.of(context).textTheme.headlineLarge?.copyWith(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.small(
                        key: HomeKeys.createGroupFab,
                        onPressed: () => _showFabBottomSheet(context),
                        backgroundColor: AppColorTokens.light.primary,
                        heroTag: 'home_fab',
                        child: Icon(Iconsax.add, color: AppColorTokens.light.textOnPrimary),
                      ),
                      const SizedBox(width: 8),
                      Semantics(
                        label: 'Open profile',
                        button: true,
                        child: GestureDetector(
                          key: HomeKeys.profileAvatar,
                          onTap: () {
                            HapticService.lightClick();
                            context.push('/profile');
                          },
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: InitialsCircle(
                                size: 32,
                                name: ref.watch(settingsProvider).deviceName,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Content area (state-dependent)
          Expanded(
            child: groupsAsync.when(
              data: (groups) => groups.isEmpty
                  ? _buildEmptyState(context)
                  : _buildLoadedDashboard(context, groups),
              loading: _buildSkeletonState,
              error: (e, st) => _buildErrorState(context),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Loaded state
  // ---------------------------------------------------------------------------

  Widget _buildLoadedDashboard(BuildContext context, List groups) {
    final activityAsync = ref.watch(crossGroupActivityProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(userGroupsProvider);
        await ref.read(userGroupsProvider.future);
      },
      color: AppColorTokens.light.primary,
      child: CustomScrollView(
        // Large cache extent ensures all slivers are built even when
        // off-screen, which is required for widget tests to find them.
        cacheExtent: 2000,
        slivers: [
          // 1. Balance Hero Card
          const SliverToBoxAdapter(
            child: SizedBox(height: 12),
          ),
          const SliverToBoxAdapter(child: BalanceHeroCard()),

          // 2. Quick Action Tray
          SliverToBoxAdapter(
            child: QuickActionTray(
              onAddExpense: () => _handleGroupAction(context, 'expense'),
              onSettleUp: () => _handleGroupAction(context, 'settle'),
              onInviteFriend: () => _handleGroupAction(context, 'invite'),
              onActivity: () => context.push('/activity'),
            ),
          ),

          // 2a. "Your Groups (N)" section header (D-13, LAYT-02)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Your Groups (${groups.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),

          // 3. Group Cards
          // D-22 (FadeInList staggered animation) takes precedence over D-21
          // (SliverList.builder) for this section. FadeInList wraps a Column,
          // not a Sliver, so SliverToBoxAdapter bridges the gap.
          // This is safe for typical group counts (<20 groups per user).
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
            ),
            sliver: SliverToBoxAdapter(
              child: FadeInList(
                children: groups.map((group) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GroupCard(
                      group: group,
                      onTap: () => context.push('/group/${group.id}'),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // 4. Activity Section
          SliverToBoxAdapter(
            child: _buildActivitySection(context, activityAsync),
          ),

          // 5. Weekly Spending Card
          const SliverToBoxAdapter(child: WeeklySpendingCard()),

          // Bottom padding for scroll clearance above bottom nav
          const SliverToBoxAdapter(
            child: SizedBox(height: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildActivitySection(
    BuildContext context,
    AsyncValue<List<CrossGroupActivityEntry>> activityAsync,
  ) {
    return Padding(
      key: HomeKeys.activitySection,
      padding: const EdgeInsets.fromLTRB(
        16,
        12,
        16,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RECENT ACTIVITY',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              // textMuted (#9CA3AF) is DECORATIVE ONLY here — section overline label.
              // Functional text (descriptions, names) uses textSecondary.
              color: AppColorTokens.light.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          activityAsync.when(
            data: (entries) => entries.isEmpty
                ? Text(
                    'No activity yet',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColorTokens.light.textSecondary,
                    ),
                  )
                : Column(
                    children: entries
                        .map(
                          (entry) => ActivityRow(
                            activity: entry.log,
                            groupName: entry.groupName,
                            groupId: entry.groupId,
                            onTap: () => context.push('/group/${entry.groupId}'),
                          ),
                        )
                        .toList(),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty state
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState(BuildContext context) {
    return EmptyStateView(
      icon: Iconsax.people,
      title: 'Create your first group',
      message:
          'Plan trips, track expenses, and settle up with friends',
      actionLabel: 'Create Group',
      onAction: () => context.push('/create-group'),
    );
  }

  // ---------------------------------------------------------------------------
  // Error state
  // ---------------------------------------------------------------------------

  Widget _buildErrorState(BuildContext context) {
    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EmptyStateView(
                    icon: Iconsax.warning_2,
                    title: 'Something went wrong',
                    message:
                        'Check your connection and try again. Your travel groups are safely synced, but we need the internet to fetch latest updates.',
                    actionLabel: 'Retry',
                    onAction: () => ref.refresh(userGroupsProvider),
                  ),
                  TextButton(
                    // Phase 19 will wire offline data view
                    onPressed: () {},
                    child: Text(
                      'View Offline Data',
                      style: TextStyle(color: AppColorTokens.light.primary),
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

  // ---------------------------------------------------------------------------
  // Skeleton / loading state
  // ---------------------------------------------------------------------------

  Widget _buildSkeletonState() {
    // SingleChildScrollView with NeverScrollableScrollPhysics prevents overflow
    // while keeping the skeleton visible within bounded parent height.
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          SkeletonLoader.dashboardHero(),
          const SizedBox(height: 16),
          SkeletonLoader.groupList(count: 3),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FAB bottom sheet
  // ---------------------------------------------------------------------------

  void _showFabBottomSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColorTokens.light.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Create a Group
            ListTile(
              key: HomeKeys.createGroupOption,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
              ),
              minTileHeight: 64,
              leading: Icon(Iconsax.people, color: AppColorTokens.light.primary),
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
              key: HomeKeys.joinGroupOption,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
              ),
              minTileHeight: 64,
              leading: Icon(
                Iconsax.login_1,
                color: AppColorTokens.light.textSecondary,
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

  // ---------------------------------------------------------------------------
  // Quick-action handler (replaces _showGroupPicker)
  // ---------------------------------------------------------------------------

  void _handleGroupAction(BuildContext context, String action) {
    final groups = ref.read(userGroupsProvider).valueOrNull ?? [];

    if (groups.isEmpty) {
      final message = switch (action) {
        'expense' => 'Create a group first to add expenses',
        'settle' => 'Create a group first to settle up',
        'invite' => 'Create a group first to invite friends',
        _ => 'Create a group first',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    if (groups.length == 1) {
      if (action == 'invite') {
        _shareInviteCode(groups.first);
      } else {
        context.push('/group/${groups.first.id}');
      }
      return;
    }

    // 2+ groups — show picker
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColorTokens.light.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Choose a group',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColorTokens.light.textPrimary,
                ),
              ),
            ),
            ...groups.map(
              (group) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text(group.name),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (action == 'invite') {
                    _shareInviteCode(group);
                  } else {
                    context.push('/group/${group.id}');
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Share invite code via native share sheet
  // ---------------------------------------------------------------------------

  void _shareInviteCode(Group group) {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.zero;
    Share.share(
      'Join my group ${group.name} on Rihla! Code: ${group.inviteCode} — Download: https://play.google.com/store/apps/details?id=com.safar.safar',
      subject: 'Join ${group.name} on Rihla',
      sharePositionOrigin: origin,
    );
  }
}
