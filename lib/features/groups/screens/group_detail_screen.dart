import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/cover_art.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../../shared/widgets/section_header.dart';
import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../keys/group_keys.dart';
import '../models/group_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';

/// Group detail screen — saffron travel-journal direction.
///
/// Wireframe ref: `Wireframes/Rihla/hifi/screens-group.jsx` → `Hi_GroupDetail()`.
/// Layout, top to bottom:
///  1. Cover header (168px + status bar) — algorithmic cover art, dark
///     gradient overlay, floating back + overflow buttons, group name in
///     italic display with mono "GROUP · N MEMBERS" caption.
///  2. Balance card — sits below the cover with a comfortable gap. Italic
///     header + member avatar stack + RAmount(sign) + sage/rust caption + two CTAs
///     (New event · Settle up).
///  3. Events section — `SectionHeader` with member-visible "New event" action,
///     then per-event rows (56×56 cover swatch · mono type label · name ·
///     date range · per-user share).
///  4. Members section — card-wrapped rows with `RAvatar` · name + role
///     suffix · `RAmount` sign trailing.
///
/// Activity is intentionally NOT shown here — wireframe puts it on a
/// dedicated screen reached via the overflow menu's "Activity" entry.
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupDetailProvider(groupId));
    return Scaffold(
      key: GroupKeys.detailScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: groupAsync.when(
        data: (group) {
          if (group == null) return _NotFoundState(groupId: groupId);
          return _Content(group: group);
        },
        loading: () => const _LoadingState(),
        error: (_, _) => _ErrorState(
          onRetry: () => ref.invalidate(groupDetailProvider(groupId)),
        ),
      ),
    );
  }
}

// ──────────────────────────── Content

class _Content extends ConsumerWidget {
  const _Content({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(groupEventsProvider(group.id));
    final balancesAsync = ref.watch(groupBalancesProvider(group.id));
    final currentUid = ref.watch(currentUserIdProvider);
    final balances = balancesAsync.valueOrNull;
    final userNet = (balances == null || currentUid == null)
        ? Decimal.zero
        : (balances.balances
                  .where((b) => b.participantId == currentUid)
                  .firstOrNull
                  ?.netBalance ??
              Decimal.zero);

    return RefreshIndicator(
      color: context.colors.primary,
      backgroundColor: context.colors.cardSurface,
      onRefresh: () async {
        ref.invalidate(groupDetailProvider(group.id));
        ref.invalidate(groupEventsProvider(group.id));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _CoverHeader(group: group)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            sliver: SliverToBoxAdapter(
              child: _BalanceCard(
                group: group,
                userNet: userNet,
                memberNames:
                    balances?.memberNames.values.toList() ?? const <String>[],
                onAddPrimary: () {
                  HapticService.lightClick();
                  GoRouter.of(context).push('/group/${group.id}/create-event');
                },
                onSettleUp: () {
                  HapticService.lightClick();
                  GoRouter.of(context).push('/group/${group.id}/settle-up');
                },
              ).animate().fadeIn(delay: 80.ms, duration: 360.ms),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverToBoxAdapter(
            child: SectionHeader(
              key: GroupKeys.eventsSection,
              title: 'Events',
              actionLabel: 'New event',
              onActionTap: () =>
                  GoRouter.of(context).push('/group/${group.id}/create-event'),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: _eventsSliver(
              context: context,
              eventsAsync: eventsAsync,
              balances: balances,
              currentUid: currentUid,
              groupId: group.id,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 22)),
          const SliverToBoxAdapter(
            child: SectionHeader(
              key: GroupKeys.membersAndBalancesSection,
              title: 'Members',
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: _MembersCard(
                group: group,
                balancesAsync: balancesAsync,
                currentUid: currentUid,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _eventsSliver({
    required BuildContext context,
    required AsyncValue<List<Event>> eventsAsync,
    required GroupBalances? balances,
    required String? currentUid,
    required String groupId,
  }) {
    return eventsAsync.when(
      data: (events) {
        if (events.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: EmptyStateView(
                key: GroupKeys.noEventsEmpty,
                icon: Iconsax.calendar_add,
                title: 'No events yet',
                message: 'Create your first event to start planning together.',
                actionLabel: 'Create Event',
                onAction: () =>
                    GoRouter.of(context).push('/group/$groupId/create-event'),
              ),
            ),
          );
        }
        final perEvent = (currentUid != null && balances != null)
            ? balances.perEventBreakdown[currentUid] ?? const {}
            : const <String, Decimal>{};
        return SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final isLast = index == events.length - 1;
            return _EventRow(
              event: events[index],
              userShare: perEvent[events[index].id],
              divider: !isLast,
              onTap: () => GoRouter.of(
                context,
              ).push('/group/$groupId/event/${events[index].id}'),
            );
          }, childCount: events.length),
        );
      },
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            "Couldn't load events",
            style: AppTypography.sans(
              fontSize: 13,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────── Cover header

class _CoverHeader extends StatelessWidget {
  const _CoverHeader({required this.group});
  final Group group;

  @override
  Widget build(BuildContext context) {
    final statusBar = MediaQuery.of(context).padding.top;
    final memberCount = group.memberIds.length;
    return SizedBox(
      height: 168 + statusBar,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverArt.fromSeed(group.name),
          // Dark gradient overlay — transparent at top, ink at bottom.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  context.colors.textPrimary.withValues(alpha: 0.55),
                ],
                stops: const [0.4, 1.0],
              ),
            ),
          ),
          // Top buttons row.
          Positioned(
            top: statusBar + 8,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _PaperIconButton(
                  icon: Iconsax.arrow_left,
                  onTap: () {
                    HapticService.lightClick();
                    final router = GoRouter.of(context);
                    if (router.canPop()) {
                      router.pop();
                    } else {
                      router.go('/home');
                    }
                  },
                ),
                _OverflowMenu(groupId: group.id),
              ],
            ),
          ),
          // Bottom title block.
          Positioned(
            left: 20,
            right: 20,
            top: statusBar + 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GROUP · $memberCount MEMBER${memberCount == 1 ? '' : 'S'}',
                  style: AppTypography.mono(
                    fontSize: 9,
                    color: context.colors.textOnPrimary.withValues(alpha: 0.85),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  group.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.display(
                    fontSize: 30,
                    color: context.colors.textOnPrimary,
                    height: 1.05,
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

class _PaperIconButton extends StatelessWidget {
  const _PaperIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.cardSurface.withValues(alpha: 0.94),
      shape: const CircleBorder(),
      elevation: 1,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: colors.textPrimary),
        ),
      ),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Material(
      color: colors.cardSurface.withValues(alpha: 0.94),
      shape: const CircleBorder(),
      elevation: 1,
      child: PopupMenuButton<String>(
        tooltip: 'More',
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(spacing.radiusLarge),
        ),
        offset: const Offset(0, 44),
        icon: Icon(Iconsax.more, size: 18, color: colors.textPrimary),
        padding: EdgeInsets.zero,
        onSelected: (key) {
          switch (key) {
            case 'settings':
              GoRouter.of(context).push('/group/$groupId/settings');
            case 'activity':
              GoRouter.of(context).push('/group/$groupId/activity');
          }
        },
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: 'settings',
            child: Row(
              children: [
                Icon(Iconsax.setting_2, size: 16, color: colors.textPrimary),
                const SizedBox(width: 10),
                const Text('Group settings'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'activity',
            child: Row(
              children: [
                Icon(Iconsax.activity, size: 16, color: colors.textPrimary),
                const SizedBox(width: 10),
                const Text('Activity'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────── Balance card

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.group,
    required this.userNet,
    required this.memberNames,
    required this.onAddPrimary,
    required this.onSettleUp,
  });

  final Group group;
  final Decimal userNet;
  final List<String> memberNames;
  final VoidCallback onAddPrimary;
  final VoidCallback onSettleUp;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final isPositive = userNet > Decimal.zero;
    final isNegative = userNet < Decimal.zero;
    final tone = isPositive
        ? AmountTone.sage
        : isNegative
        ? AmountTone.rust
        : AmountTone.ink;
    final captionColor = isPositive
        ? colors.success
        : isNegative
        ? colors.error
        : colors.textSecondary;
    final captionText = isPositive
        ? 'they owe you'
        : isNegative
        ? 'you owe'
        : 'all settled';

    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Your balance here',
                  style: AppTypography.display(
                    fontSize: 14,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              if (memberNames.isNotEmpty)
                RAvatarStack(names: memberNames, size: 22, max: 4),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              RAmount(
                value: userNet,
                size: 32,
                sign: !userNet.isZero,
                tone: tone,
                showCurrency: false,
              ),
              const Spacer(),
              Text(
                captionText,
                style: AppTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: captionColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _PrimaryCtaButton(
                  icon: Iconsax.add,
                  label: 'New event',
                  onTap: onAddPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SecondaryCtaButton(
                  label: 'Settle up',
                  buttonKey: GroupKeys.settleUpCta,
                  onTap: onSettleUp,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrimaryCtaButton extends StatelessWidget {
  const _PrimaryCtaButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Material(
      color: colors.primary,
      borderRadius: BorderRadius.circular(spacing.radiusMedium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(spacing.radiusMedium),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: colors.textOnPrimary),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textOnPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryCtaButton extends StatelessWidget {
  const _SecondaryCtaButton({
    required this.label,
    required this.onTap,
    this.buttonKey,
  });
  final String label;
  final VoidCallback onTap;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Material(
      color: colors.cardSoft,
      borderRadius: BorderRadius.circular(spacing.radiusMedium),
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(spacing.radiusMedium),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(spacing.radiusMedium),
            border: Border.all(color: colors.rule, width: 0.5),
          ),
          child: Text(
            label,
            style: AppTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────── Event row

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.userShare,
    required this.divider,
    required this.onTap,
  });

  final Event event;
  final Decimal? userShare;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final dateLabel = _formatDates(event.startDate, event.endDate);
    final subtitle = dateLabel ?? _eventTypeLabel(event.type);
    final share = userShare ?? Decimal.zero;
    final hasShare = share != Decimal.zero;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(spacing.radiusMedium),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: CoverArt.forEventType(event.type),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _eventTypeLabel(event.type),
                        style: AppTypography.mono(
                          fontSize: 9,
                          color: colors.textSecondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        event.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.sans(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasShare)
                      RAmount(
                        value: share,
                        size: 15,
                        sign: true,
                        showCurrency: false,
                      )
                    else
                      Text(
                        '—',
                        style: AppTypography.sans(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      hasShare ? 'your share' : 'no share',
                      style: AppTypography.sans(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (divider) ...[
              const SizedBox(height: 12),
              Container(height: 0.5, color: colors.rule),
            ],
          ],
        ),
      ),
    );
  }

  static String? _formatDates(DateTime? start, DateTime? end) {
    String fmt(DateTime d) => '${_monthShort(d.month)} ${d.day}';
    if (start != null && end != null) return '${fmt(start)} — ${fmt(end)}';
    if (start != null) return fmt(start);
    if (end != null) return 'ends ${fmt(end)}';
    return null;
  }
}

String _eventTypeLabel(EventType t) {
  return switch (t) {
    EventType.trip => 'TRIP',
    EventType.camping => 'CAMPING',
    EventType.travel => 'TRAVEL',
    EventType.nightDayOut => 'NIGHT/DAY OUT',
    EventType.custom => 'EVENT',
  };
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String _monthShort(int m) => _months[m - 1];

// ──────────────────────────── Members card

class _MembersCard extends StatelessWidget {
  const _MembersCard({
    required this.group,
    required this.balancesAsync,
    required this.currentUid,
  });

  final Group group;
  final AsyncValue<GroupBalances> balancesAsync;
  final String? currentUid;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final data = balancesAsync.valueOrNull;

    if (data == null || data.balances.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(spacing.radiusLarge),
          boxShadow: context.shadows.raised,
        ),
        child: Text(
          balancesAsync.hasError ? "Couldn't load members" : 'Loading members…',
          style: AppTypography.sans(fontSize: 13, color: colors.textSecondary),
        ),
      );
    }

    final balances = data.balances;
    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < balances.length; i++)
            _MemberRow(
              name:
                  balances[i].displayName ??
                  data.memberNames[balances[i].participantId] ??
                  'Member',
              role: _roleFor(
                participantId: balances[i].participantId,
                creatorId: group.createdBy,
                currentUid: currentUid,
              ),
              net: balances[i].netBalance,
              divider: i < balances.length - 1,
              onTap: () => GoRouter.of(context).push(
                '/group/${group.id}/settle-up?memberId=${balances[i].participantId}',
              ),
            ),
        ],
      ),
    );
  }

  static String? _roleFor({
    required String participantId,
    required String creatorId,
    required String? currentUid,
  }) {
    if (currentUid != null && participantId == currentUid) return 'You';
    if (participantId == creatorId) return 'Creator';
    return null;
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.name,
    required this.role,
    required this.net,
    required this.divider,
    required this.onTap,
  });

  final String name;
  final String? role;
  final Decimal net;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                RAvatar(name: name, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      if (role != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          role!,
                          style: AppTypography.sans(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (net == Decimal.zero)
                  Text(
                    '—',
                    style: AppTypography.sans(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                  )
                else
                  RAmount(
                    value: net,
                    size: 14,
                    sign: true,
                    showCurrency: false,
                  ),
              ],
            ),
          ),
          if (divider) Container(height: 0.5, color: colors.rule),
        ],
      ),
    );
  }
}

// ──────────────────────────── Skeleton / states

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusBar = MediaQuery.of(context).padding.top;
    return Column(
      children: [
        SizedBox(
          height: 168 + statusBar,
          child: Container(color: colors.cardSoft),
        ),
        const Spacer(),
        CircularProgressIndicator(color: colors.primary),
        const Spacer(flex: 3),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyStateView(
            icon: Iconsax.warning_2,
            title: 'Could not load group',
            message: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: onRetry,
          ),
        ),
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  const _NotFoundState({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyStateView(
            icon: Iconsax.box_remove,
            title: 'Group not found',
            message: 'It may have been deleted, or the link is incorrect.',
            actionLabel: 'Back home',
            onAction: () => GoRouter.of(context).go('/home'),
          ),
        ),
      ),
    );
  }
}

extension on Decimal {
  bool get isZero => this == Decimal.zero;
}
