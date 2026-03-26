import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../events/providers/event_provider.dart';
import '../../events/screens/event_command_center.dart';
import '../../events/screens/event_type_picker_screen.dart';
import '../../events/widgets/event_card.dart';
import '../../events/models/event_model.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/screens/ledger_screen.dart';
import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/group_activity_tile.dart';
import '../widgets/group_balance_hero.dart';
import '../widgets/group_member_balance_card.dart';
import '../widgets/group_spending_stats.dart';
import '../widgets/invite_code_display.dart';
import 'group_activity_screen.dart';
import 'group_settings_screen.dart';
import 'group_settle_up_screen.dart';

/// Group dashboard screen — restructured per D-27 layout contract.
///
/// Shows: hero card, spending stats, members+balances (merged), events,
/// invite code (D-30: moved below events), and recent activity section.
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
      backgroundColor: AppColors.background,
      floatingActionButton: Semantics(
        label: 'Create event',
        button: true,
        child: FloatingActionButton(
          onPressed: () => Navigator.of(context).push(
            AppPageRoute(
              builder: (_) => EventTypePickerScreen(groupId: groupId),
            ),
          ),
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

    // Safely retrieve UID — returns null when Firebase is not initialized
    // (e.g., in widget test environments).
    String? currentUid;
    try {
      currentUid = FirebaseConfig.currentUser?.uid;
    } catch (_) {
      currentUid = null;
    }

    // Determine if any expenses exist — gating hero + stats display (D-19)
    // hasExpensesData is non-null only when totalSpent > 0 (D-19 condition).
    final balancesData = balancesAsync.valueOrNull;
    final hasExpensesData = (balancesData != null &&
            balancesData.totalSpent > Decimal.zero)
        ? balancesData
        : null;

    // Find current user's balance for the hero card
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
              onPressed: () => Navigator.of(context).push(
                AppPageRoute(
                  builder: (_) => GroupSettingsScreen(groupId: group.id),
                ),
              ),
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
                const SizedBox(height: AppColors.space8),

                // --- Stats chips (member count + currency) ---
                _buildStatsRow(context, group),
                const SizedBox(height: AppColors.space24),

                // --- GroupBalanceHero + GroupSpendingStats (D-19: hidden until first expense) ---
                if (hasExpensesData != null) ...[
                  GroupBalanceHero(
                    totalSpent: hasExpensesData.totalSpent,
                    userNetBalance:
                        currentUserBalance?.netBalance ?? Decimal.zero,
                    currency: group.currency,
                    onSettleUp: () => Navigator.of(context).push(
                      AppPageRoute(
                        builder: (_) => GroupSettleUpScreen(
                          groupId: groupId,
                          group: group,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppColors.space16),
                  GroupSpendingStats(
                    totalSpent: hasExpensesData.totalSpent,
                    eventCount: hasExpensesData.eventCount,
                    currency: group.currency,
                    topSpenders: _computeTopSpenders(hasExpensesData),
                  ),
                  const SizedBox(height: AppColors.space24),
                ] else if (balancesAsync.isLoading) ...[
                  // Skeleton for hero area while loading
                  Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(AppColors.radiusMedium),
                    ),
                  ),
                  const SizedBox(height: AppColors.space24),
                ],

                // --- Members & Balances (replaces plain Members section, D-29) ---
                _buildMembersBalancesSection(context, group, balancesAsync),
                const SizedBox(height: AppColors.space24),

                // --- Events ---
                _buildEventsSection(context, group),
                const SizedBox(height: AppColors.space24),

                // --- Invite Code (moved below events per D-30) ---
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

  Widget _buildStatsRow(BuildContext context, Group group) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppColors.space8,
            vertical: AppColors.space4,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Iconsax.people,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppColors.space4),
              Text(
                '${group.memberIds.length} members',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppColors.space8),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppColors.space8,
            vertical: AppColors.space4,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppColors.radiusSmall),
          ),
          child: Text(
            group.currency,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  /// Members & Balances section — replaces the old plain Members section (D-29).
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
                            ? () => Navigator.of(context).push(
                                  AppPageRoute(
                                    builder: (_) => GroupSettleUpScreen(
                                      groupId: groupId,
                                      group: group,
                                      preSelectedMemberId: balancesData
                                          .balances[i].participantId,
                                    ),
                                  ),
                                )
                            : null,
                  ),
                ],
              ],
            );
          },
          loading: () => Column(
            children: List.generate(
              3,
              (i) => Padding(
                padding: EdgeInsets.only(
                  bottom: i < 2 ? AppColors.space8 : 0,
                ),
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusMedium),
                  ),
                ),
              ),
            ),
          ),
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

  Widget _buildEventsSection(BuildContext context, Group group) {
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
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (events.isNotEmpty)
                Container(
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
                icon: Iconsax.calendar_add,
                title: 'No events yet',
                message:
                    'Tap the + button to create the first event for this group.',
              );
            }
            return Column(
              children: [
                for (int i = 0; i < events.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppColors.space12),
                  EventCard(
                    event: events[i],
                    onTap: () {
                      Navigator.of(context).push(
                        AppPageRoute(
                          builder: (_) => EventCommandCenter(
                            event: events[i],
                            group: group,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            );
          },
          loading: () =>
              const Center(child: CircularProgressIndicator()),
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

  /// Invite code section — moved below events per D-30.
  Widget _buildInviteSection(BuildContext context, Group group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Invite Code',
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
          loading: () => Column(
            children: List.generate(
              5,
              (i) => Padding(
                padding: EdgeInsets.only(
                  bottom: i < 4 ? AppColors.space8 : 0,
                ),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius:
                        BorderRadius.circular(AppColors.radiusSmall),
                  ),
                ),
              ),
            ),
          ),
          error: (e, _) => Text(
            "Couldn't load activity",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            AppPageRoute(
              builder: (_) => GroupActivityScreen(groupId: groupId),
            ),
          ),
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
    return const Column(
      children: [
        ModuleHeader(
          title: 'Loading...',
          subtitle: '',
          useDarkTheme: true,
        ),
        Expanded(
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Computes the top 3 spenders as name+percentage pairs for GroupSpendingStats.
  List<({String name, double percentage})> _computeTopSpenders(
    GroupBalances data,
  ) {
    if (data.totalSpent == Decimal.zero) return [];
    final sorted = [...data.balances]
      ..sort((a, b) => b.totalPaid.compareTo(a.totalPaid));
    return sorted.take(3).map((b) {
      final ratio = (b.totalPaid / data.totalSpent)
          .toDecimal(scaleOnInfinitePrecision: 4);
      final pct = (ratio * Decimal.fromInt(100)).toDouble();
      return (
        name: b.displayName ?? 'Unknown',
        percentage: pct,
      );
    }).toList();
  }

  /// Navigate to a specific event's LedgerScreen (FIN-01 per-event drill-down).
  void _navigateToEventLedger(
    BuildContext context,
    String eventId,
    Group group,
  ) {
    final eventsAsync = ref.read(groupEventsProvider(groupId));
    Event? event;
    try {
      event = eventsAsync.valueOrNull?.firstWhere((e) => e.id == eventId);
    } catch (_) {
      event = null;
    }
    if (event != null) {
      Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => LedgerScreen(event: event!, group: group),
        ),
      );
    }
  }
}
