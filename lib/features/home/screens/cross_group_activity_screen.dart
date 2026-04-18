import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../shared/widgets/empty_state_view.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/activity_row.dart';

/// Full-screen cross-group activity feed (Phase 23).
///
/// Displays activity entries from ALL groups in a single feed with group
/// name labels. Uses the existing [crossGroupActivityProvider] which returns
/// the top 5 most recent entries across all groups.
///
/// Visual pattern matches [GroupActivityScreen] — header with back button +
/// title, then a list body with empty/loading/error states.
class CrossGroupActivityScreen extends ConsumerWidget {
  const CrossGroupActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(crossGroupActivityProvider);
    return Scaffold(
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildBody(context, activityAsync)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.space16,
        vertical: context.spacing.space8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            decoration: BoxDecoration(
              color: context.colors.cardSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.colors.inputFill, width: 1),
              boxShadow: AppShadowTokens.standard.raised,
            ),
            child: IconButton(
              icon: const Icon(Iconsax.arrow_left, size: 20),
              onPressed: () => context.pop(),
              tooltip: 'Back',
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Text(
            'All Activity',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(width: 48), // balance the back button
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<CrossGroupActivityEntry>> activityAsync,
  ) {
    return activityAsync.when(
      loading: _buildSkeleton,
      error: (e, _) => const EmptyStateView(
        icon: Iconsax.warning_2,
        title: 'Could not load activity',
        message: 'Check your connection and try again.',
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const EmptyStateView(
            icon: Iconsax.activity,
            title: 'No activity yet',
            message: 'Activity from all your groups will appear here.',
          );
        }
        return ListView.separated(
          padding: EdgeInsets.symmetric(
            horizontal: context.spacing.space24,
            vertical: context.spacing.space12,
          ),
          itemCount: entries.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            thickness: 1,
            color: context.colors.border,
          ),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return ActivityRow(
              activity: entry.log,
              groupName: entry.groupName,
              groupId: entry.groupId,
              onTap: () => context.push('/group/${entry.groupId}'),
            );
          },
        );
      },
    );
  }

  /// Skeleton placeholder rows shown while activity data is loading.
  Widget _buildSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      itemCount: 5,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: context.colors.border,
      ),
      itemBuilder: (context, index) => const _SkeletonRow(),
    );
  }
}

/// A 52px skeleton placeholder for a single activity row.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: EdgeInsets.symmetric(vertical: context.spacing.space8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.colors.border,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: context.spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 12,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: context.colors.border,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 10,
                  width: 80,
                  decoration: BoxDecoration(
                    color: context.colors.inputFill,
                    borderRadius: BorderRadius.circular(5),
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
