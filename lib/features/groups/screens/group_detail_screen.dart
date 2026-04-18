import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../shared/animations/fade_in_list.dart';
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

/// Group dashboard screen — Phase 28 cleanup.
///
/// Layout per D-04, D-05, D-10, D-13, D-14:
/// - 2x2 stats grid above the fold (always visible, D-08)
/// - Settle-up CTA with primaryGradient when current user balance is non-zero (D-10)
/// - Section order: Header → Stats Grid → Settle-Up CTA → Events → Members & Balances → Activity (D-04)
/// - Invite code section removed (D-05 — moved to Phase 29)
/// - Provider rebuilds isolated via Consumer widget (D-02)
/// - FAB icon uses textOnPrimary (D-14)
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
      backgroundColor: context.colors.scaffoldBackground,
      floatingActionButton: Semantics(
        label: 'Create event',
        button: true,
        child: FloatingActionButton(
          onPressed: () {
            HapticService.lightClick();
            context.push('/group/$groupId/create-event');
          },
          backgroundColor: context.colors.primary,
          shape: const CircleBorder(),
          child: Icon(Iconsax.add, color: context.colors.textOnPrimary),
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
        error: (e, st) => Column(
          children: [
            const ModuleHeader(
              title: 'Group',
              subtitle: '',
              useDarkTheme: true,
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Iconsax.warning_2,
                      size: 48,
                      color: context.colors.textSecondary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load group',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: context.spacing.buttonHeight,
                      child: ElevatedButton(
                        onPressed: () =>
                            ref.invalidate(groupDetailProvider(groupId)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.colors.primary,
                          foregroundColor: context.colors.textOnPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              context.spacing.radiusMedium,
                            ),
                          ),
                        ),
                        child: Text(
                          'Try again',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: context.colors.textOnPrimary,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Group group) {
    return Column(
      children: [
        ModuleHeader(
          title: group.name,
          subtitle: 'Created ${DateFormat('MMM d, yyyy').format(group.createdAt)}',
          actions: [
            IconButton(
              icon: Icon(
                Iconsax.setting_2,
                color: context.colors.textOnPrimary,
                size: 22,
              ),
              onPressed: () => context.push('/group/$groupId/settings'),
            ),
          ],
          useDarkTheme: true,
        ),
        Expanded(
          child: RefreshIndicator(
            color: context.colors.primary,
            backgroundColor: context.colors.cardSurface,
            onRefresh: () async {
              // Invalidate Firestore-backed stream providers.
              // groupBalancesProvider is a computed Provider.family that
              // auto-recomputes — do NOT invalidate it directly.
              ref.invalidate(groupDetailProvider(groupId));
              ref.invalidate(groupEventsProvider(groupId));
              ref.invalidate(groupMembersProvider(groupId));
              ref.invalidate(groupActivityProvider(groupId));
              ref.invalidate(groupSettlementsProvider(groupId));
              // Brief delay for streams to re-establish
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // --- Stats grid + Settle-up CTA isolated in Consumer (D-02) ---
                Consumer(
                  builder: (context, ref, _) {
                    final balancesAsync =
                        ref.watch(groupBalancesProvider(groupId));
                    final currentUid = ref.watch(currentUserIdProvider);
                    final balancesData = balancesAsync.valueOrNull;

                    // Find current user's balance
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

                    final showSettleUpCta = currentUserBalance != null &&
                        currentUserBalance.netBalance != Decimal.zero;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- 2x2 Stats grid (D-08: always visible) ---
                        GroupStatsGrid(
                          userNetBalance:
                              currentUserBalance?.netBalance ?? Decimal.zero,
                          groupTotal:
                              balancesData?.totalSpent ?? Decimal.zero,
                          activeMembers: group.memberIds.length,
                          eventCount: balancesData?.eventCount ?? 0,
                          currency: group.currency,
                        ),
                        const SizedBox(height: 16),

                        // --- Settle-up CTA with gradient (D-10) ---
                        if (showSettleUpCta) ...[
                          SizedBox(
                            width: double.infinity,
                            height: context.spacing.buttonHeight,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient:
                                    context.colors.primaryGradient,
                                borderRadius: BorderRadius.circular(
                                  context.spacing.radiusMedium,
                                ),
                              ),
                              child: ElevatedButton(
                                key: GroupKeys.settleUpCta,
                                onPressed: () {
                                  HapticService.medium();
                                  // D-15: CTA entry point — do not remove
                                  context.push(
                                      '/group/$groupId/settle-up');
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      context.spacing.radiusMedium,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Settle Up',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: AppColorTokens
                                            .light.textOnPrimary,
                                      ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ] else
                          const SizedBox(height: 8),
                      ],
                    );
                  },
                ),

                // --- Events (D-04: before Members) ---
                _buildEventsSection(context, group),
                const SizedBox(height: 24),

                // --- Members & Balances ---
                _buildMembersBalancesSection(context, group),
                const SizedBox(height: 24),

                // --- Recent Activity (D-34) ---
                _buildActivitySection(context),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
      ],
    );
  }

  /// Events section — D-04: rendered before Members & Balances.
  ///
  /// Watches groupBalancesProvider internally for per-event breakdown.
  /// Passes personalBalance from perEventBreakdown to each EventCard.
  Widget _buildEventsSection(
    BuildContext context,
    Group group,
  ) {
    final eventsAsync = ref.watch(groupEventsProvider(groupId));
    final balancesData =
        ref.watch(groupBalancesProvider(groupId)).valueOrNull;
    final currentUid = ref.watch(currentUserIdProvider);

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
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.inputFill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${events.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.colors.textSecondary,
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
        const SizedBox(height: 12),
        // Event list or empty state
        eventsAsync.when(
          data: (events) {
            if (events.isEmpty) {
              return EmptyStateView(
                key: GroupKeys.noEventsEmpty,
                icon: Iconsax.calendar_add,
                title: 'No events yet',
                message: 'Create your first event to start planning together.',
                actionLabel: 'Create Event',
                onAction: () =>
                    context.push('/group/$groupId/create-event'),
              );
            }
            // Pre-compute per-user event breakdown map for event card wiring
            final userEventBreakdown = currentUid != null
                ? (balancesData?.perEventBreakdown[currentUid] ?? {})
                : <String, Decimal>{};

            return FadeInList(
              children: [
                for (int i = 0; i < events.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i > 0 ? 12 : 0),
                    child: EventCard(
                      event: events[i],
                      personalBalance: userEventBreakdown[events[i].id],
                      onTap: () => context.push(
                        '/group/$groupId/event/${events[i].id}',
                      ),
                    ),
                  ),
              ],
            );
          },
          loading: () => SkeletonLoader.eventCard(count: 2),
          error: (e, _) => Text(
            "Couldn't load events",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.colors.textSecondary,
                ),
          ),
        ),
      ],
    );
  }

  /// Members & Balances section — D-04: rendered after Events.
  ///
  /// Shows GroupMemberBalanceCard for each member with accordion expand control.
  /// Watches groupBalancesProvider internally.
  /// onSettleUpTap is wired with preSelectedMemberId for D-22 entry point 2.
  /// onEventTap navigates to the event's LedgerScreen for FIN-01 per-event drill-down.
  Widget _buildMembersBalancesSection(
    BuildContext context,
    Group group,
  ) {
    final balancesAsync = ref.watch(groupBalancesProvider(groupId));

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
        const SizedBox(height: 12),
        balancesAsync.when(
          data: (balancesData) {
            if (balancesData.balances.isEmpty) {
              return Text(
                'No members yet',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.colors.textSecondary,
                    ),
              );
            }
            return Column(
              children: [
                for (int i = 0; i < balancesData.balances.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
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
                            ? () {
                                // D-15: CTA entry point — do not remove
                                context.push(
                                  '/group/$groupId/settle-up?memberId=${balancesData.balances[i].participantId}',
                                );
                              }
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
                  color: context.colors.textSecondary,
                ),
          ),
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
        const SizedBox(height: 8),
        activityAsync.when(
          data: (activities) {
            if (activities.isEmpty) {
              return const EmptyStateView(
                icon: Iconsax.activity,
                title: 'No activity yet',
                message:
                    'Activity will appear here once events are created.',
              );
            }
            // Show up to 5 entries (D-16: compact tile variant)
            final displayed = activities.take(5).toList();
            return Column(
              children: displayed
                  .map((a) => GroupActivityTile(activity: a, compact: true))
                  .toList(),
            );
          },
          loading: () => SkeletonLoader.groupList(count: 3),
          error: (e, _) => Text(
            "Couldn't load activity",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.colors.textSecondary,
                ),
          ),
        ),
        TextButton(
          key: GroupKeys.seeAllActivityButton,
          // D-15: CTA entry point — do not remove
          onPressed: () => context.push('/group/$groupId/activity'),
          child: Text(
            'See all',
            style: TextStyle(
              color: context.colors.primary,
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
              horizontal: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                // Stats grid skeleton — 2x2 grid
                const Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          SkeletonBlock(
                            width: double.infinity,
                            height: 72,
                            borderRadius: 8,
                          ),
                          SizedBox(height: 8),
                          SkeletonBlock(
                            width: double.infinity,
                            height: 72,
                            borderRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        children: [
                          SkeletonBlock(
                            width: double.infinity,
                            height: 72,
                            borderRadius: 8,
                          ),
                          SizedBox(height: 8),
                          SkeletonBlock(
                            width: double.infinity,
                            height: 72,
                            borderRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // CTA skeleton
                const SkeletonBlock(
                  width: double.infinity,
                  height: 52,
                  borderRadius: 12,
                ),
                const SizedBox(height: 24),
                // Section header skeleton
                const SkeletonBar(width: 80, height: 16),
                const SizedBox(height: 12),
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
