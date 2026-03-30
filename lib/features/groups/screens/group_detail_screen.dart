import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/skeleton_primitives.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../ledger/models/expense_model.dart' show UserBalance;
import '../../events/providers/event_provider.dart';
import '../../events/widgets/event_card.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/group_activity_tile.dart';
import '../widgets/group_member_balance_card.dart';
import '../widgets/group_stats_grid.dart';
import '../widgets/invite_code_display.dart';

/// Group dashboard screen — Phase 20 redesign.
///
/// Layout per D-07, D-08, D-09, D-10:
/// - 2x2 stats grid above the fold (always visible, D-08)
/// - Settle-up CTA when current user balance is non-zero (D-10)
/// - Section order: Events → Members & Balances → Invite Code → Activity (D-09)
/// - Skeleton loading replaces CircularProgressIndicator
///
/// Converted to ConsumerStatefulWidget to track accordion expand state
/// (_expandedMemberId) for GroupMemberBalanceCard (D-13).
class GroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  /// Accordion state — only one member card is expanded at a time (D-13).
  String? _expandedMemberId;

  String get groupId => widget.groupId;

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(groupId));

    return Scaffold(
      key: GroupKeys.detailScreen,
      backgroundColor: AppColors.background,
      floatingActionButton: Semantics(
        label: 'Create event',
        button: true,
        child: FloatingActionButton(
          onPressed: () => context.push('/group/$groupId/create-event'),
          backgroundColor: AppColors.primary,
          shape: const CircleBorder(),
          child: const Icon(Iconsax.add, color: Colors.black),
        ),
      ),
      body: groupAsync.when(
        data: (group) {
          if (group == null) {
            return const Center(child: Text('Group not found'));
          }
          return _buildContent(context, group);
        },
        loading: () => _buildLoading(context),
        error: (e, st) => const Center(child: Text('Error loading group')),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Group group) {
    final balancesAsync = ref.watch(groupBalancesProvider(groupId));

    // Use injectable currentUserIdProvider for testability (Phase 18 P03 pattern)
    final currentUid = ref.watch(currentUserIdProvider);

    final balancesData = balancesAsync.valueOrNull;

    // Find current user's balance for stats grid and settle-up CTA
    UserBalance? currentUserBalance;
    if (balancesData != null && currentUid != null) {
      try {
        currentUserBalance = balancesData.balances.firstWhere(
          (b) => b.participantId == currentUid,
        );
      } catch (_) {
        currentUserBalance = null;
      }
    }

    // Settle-up CTA visibility: show only when user has a non-zero balance
    final showSettleUpCta = currentUserBalance != null &&
        currentUserBalance.netBalance != Decimal.zero;

    return Column(
      children: [
        ModuleHeader(
          title: group.name,
          subtitle: 'Created ${DateFormat('MMM d, yyyy').format(group.createdAt)}',
          actions: [
            IconButton(
              icon: const Icon(
                Iconsax.setting_2,
                color: Colors.white,
                size: 22,
              ),
              onPressed: () => context.push('/group/$groupId/settings'),
            ),
          ],
          useDarkTheme: true,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppColors.space24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppColors.space16),

                // --- 2x2 Stats grid (D-08: always visible) ---
                GroupStatsGrid(
                  userNetBalance:
                      currentUserBalance?.netBalance ?? Decimal.zero,
                  groupTotal: balancesData?.totalSpent ?? Decimal.zero,
                  activeMembers: group.memberIds.length,
                  eventCount: balancesData?.eventCount ?? 0,
                  currency: group.currency,
                ),
                const SizedBox(height: AppColors.space16),

                // --- Settle-up CTA (D-10: conditional on non-zero balance) ---
                if (showSettleUpCta) ...[
                  SizedBox(
                    width: double.infinity,
                    height: AppColors.buttonHeight,
                    child: ElevatedButton(
                      key: GroupKeys.settleUpCta,
                      onPressed: () =>
                          context.push('/group/$groupId/settle-up'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textOnPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppColors.radiusMedium),
                        ),
                      ),
                      child: const Text(
                        'Settle Up',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppColors.space24),
                ] else
                  const SizedBox(height: AppColors.space8),

                // --- Events (D-09: before Members) ---
                _buildEventsSection(context, group, balancesData, currentUid),
                const SizedBox(height: AppColors.space24),

                // --- Members & Balances ---
                _buildMembersBalancesSection(context, group, balancesAsync),
                const SizedBox(height: AppColors.space24),

                // --- Invite Code (D-30: below events) ---
                _buildInviteSection(context, group),
                const SizedBox(height: AppColors.space24),

                // --- Recent Activity (D-34) ---
                _buildActivitySection(context),
                const SizedBox(height: AppColors.space32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Events section — D-09: rendered before Members & Balances.
  ///
  /// Passes personalBalance from perEventBreakdown to each EventCard.
  Widget _buildEventsSection(
    BuildContext context,
    Group group,
    GroupBalances? balancesData,
    String? currentUid,
  ) {
    final eventsAsync = ref.watch(groupEventsProvider(groupId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with optional count chip when events exist
        eventsAsync.when(
          data: (events) => Row(
            children: [
              Text(
                'Events',
                key: GroupKeys.eventsSection,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (events.isNotEmpty)
                Container(
                  key: GroupKeys.eventsCountChip,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppColors.space8,
                    vertical: AppColors.space4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusSmall),
                  ),
                  child: Text(
                    '${events.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
            ],
          ),
          loading: () =>
              Text('Events', style: Theme.of(context).textTheme.titleMedium),
          error: (e, st) =>
              Text('Events', style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: AppColors.space12),
        // Event list or empty state
        eventsAsync.when(
          data: (events) {
            if (events.isEmpty) {
              return const EmptyStateView(
                key: GroupKeys.noEventsEmpty,
                icon: Iconsax.calendar_add,
                title: 'No events yet',
                message:
                    'Tap the + button to create the first event for this group.',
              );
            }
            // Pre-compute per-user event breakdown map for event card wiring
            final userEventBreakdown = currentUid != null
                ? (balancesData?.perEventBreakdown[currentUid] ?? {})
                : <String, Decimal>{};

            return Column(
              children: [
                for (int i = 0; i < events.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppColors.space12),
                  EventCard(
                    event: events[i],
                    personalBalance: userEventBreakdown[events[i].id],
                    onTap: () => context.push(
                      '/group/$groupId/event/${events[i].id}',
                    ),
                  ),
                ],
              ],
            );
          },
          loading: () => SkeletonLoader.eventCard(count: 2),
          error: (e, _) => Text(
            "Couldn't load events",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
          ),
        ),
      ],
    );
  }

  /// Members & Balances section — D-09: rendered after Events.
  ///
  /// Shows GroupMemberBalanceCard for each member with accordion expand control.
  /// onSettleUpTap is wired with preSelectedMemberId for D-22 entry point 2.
  /// onEventTap navigates to the event's LedgerScreen for FIN-01 per-event drill-down.
  Widget _buildMembersBalancesSection(
    BuildContext context,
    Group group,
    AsyncValue<GroupBalances> balancesAsync,
  ) {
    // Build event names map from the watched events list
    final eventsAsync = ref.watch(groupEventsProvider(groupId));
    final eventNames = <String, String>{};
    for (final event in eventsAsync.valueOrNull ?? []) {
      eventNames[event.id] = event.name;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Members & Balances',
          key: GroupKeys.membersAndBalancesSection,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppColors.space12),
        balancesAsync.when(
          data: (balancesData) {
            if (balancesData.balances.isEmpty) {
              return Text(
                'No members yet',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
              );
            }
            return Column(
              children: [
                for (int i = 0; i < balancesData.balances.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppColors.space8),
                  GroupMemberBalanceCard(
                    balance: balancesData.balances[i],
                    perEventBreakdown: balancesData.perEventBreakdown[
                            balancesData.balances[i].participantId] ??
                        const {},
                    eventNames: eventNames,
                    currency: group.currency,
                    isExpanded: _expandedMemberId ==
                        balancesData.balances[i].participantId,
                    onExpandChanged: (expanded) {
                      setState(() {
                        _expandedMemberId = expanded
                            ? balancesData.balances[i].participantId
                            : null;
                      });
                    },
                    onEventTap: (eventId) =>
                        _navigateToEventLedger(context, eventId, group),
                    onSettleUpTap:
                        balancesData.balances[i].netBalance != Decimal.zero
                            ? () => context.push(
                                  '/group/$groupId/settle-up?memberId=${balancesData.balances[i].participantId}',
                                )
                            : null,
                  ),
                ],
              ],
            );
          },
          loading: () => SkeletonLoader.generic(count: 3),
          error: (e, _) => Text(
            "Couldn't load balances",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
          ),
        ),
      ],
    );
  }

  /// Invite code section — moved below events per D-30.
  Widget _buildInviteSection(BuildContext context, Group group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Invite Code',
          key: GroupKeys.inviteCodeSection,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppColors.space12),
        InviteCodeDisplay(code: group.inviteCode),
        const SizedBox(height: AppColors.space12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: AppColors.buttonHeight,
                child: ElevatedButton.icon(
                  icon: const Icon(Iconsax.copy, size: 16),
                  label: const Text('Copy'),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppColors.radiusMedium),
                    ),
                  ),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: group.inviteCode),
                    );
                    HapticService.success();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Invite code copied'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: AppColors.space12),
            Expanded(
              child: SizedBox(
                height: AppColors.buttonHeight,
                child: OutlinedButton.icon(
                  icon: const Icon(Iconsax.share, size: 16),
                  label: const Text('Share'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppColors.radiusMedium),
                    ),
                  ),
                  onPressed: () {
                    Share.share(
                      'Join my group on Rihla! Use code ${group.inviteCode} to join.',
                      subject: 'Join ${group.name}',
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Recent Activity section — shows last 5 entries with "See all" link (D-34).
  Widget _buildActivitySection(BuildContext context) {
    final activityAsync = ref.watch(groupActivityProvider(groupId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Activity',
          key: GroupKeys.recentActivitySection,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppColors.space8),
        activityAsync.when(
          data: (activities) {
            if (activities.isEmpty) {
              return Text(
                'No activity yet',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
              );
            }
            // Show up to 5 entries
            final displayed = activities.take(5).toList();
            return Column(
              children: displayed
                  .map((a) => GroupActivityTile(activity: a))
                  .toList(),
            );
          },
          loading: () => SkeletonLoader.groupList(count: 3),
          error: (e, _) => Text(
            "Couldn't load activity",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
          ),
        ),
        TextButton(
          key: GroupKeys.seeAllActivityButton,
          onPressed: () => context.push('/group/$groupId/activity'),
          child: const Text(
            'See all activity',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Column(
      children: [
        const ModuleHeader(
          title: 'Loading...',
          subtitle: '',
          useDarkTheme: true,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppColors.space24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppColors.space16),
                // Stats grid skeleton — 2x2 grid
                const Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          SkeletonBlock(
                            width: double.infinity,
                            height: 72,
                            borderRadius: AppColors.radiusSmall,
                          ),
                          SizedBox(height: AppColors.space8),
                          SkeletonBlock(
                            width: double.infinity,
                            height: 72,
                            borderRadius: AppColors.radiusSmall,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: AppColors.space8),
                    Expanded(
                      child: Column(
                        children: [
                          SkeletonBlock(
                            width: double.infinity,
                            height: 72,
                            borderRadius: AppColors.radiusSmall,
                          ),
                          SizedBox(height: AppColors.space8),
                          SkeletonBlock(
                            width: double.infinity,
                            height: 72,
                            borderRadius: AppColors.radiusSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppColors.space16),
                // CTA skeleton
                const SkeletonBlock(
                  width: double.infinity,
                  height: AppColors.buttonHeight,
                  borderRadius: AppColors.radiusMedium,
                ),
                const SizedBox(height: AppColors.space24),
                // Section header skeleton
                const SkeletonBar(width: 80, height: 16),
                const SizedBox(height: AppColors.space12),
                // Event cards skeleton
                SkeletonLoader.eventCard(count: 2),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Navigate to a specific event's LedgerScreen (FIN-01 per-event drill-down).
  void _navigateToEventLedger(
    BuildContext context,
    String eventId,
    Group group,
  ) {
    context.push('/group/$groupId/event/$eventId/ledger');
  }
}
