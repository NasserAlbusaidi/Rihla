import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../events/providers/event_provider.dart';
import '../keys/activity_keys.dart';
import '../models/activity_log_model.dart';
import '../services/activity_service.dart';

/// Event activity feed — saffron travel-journal direction.
///
/// Chronological day-grouped feed of event-scoped activity logs (expense
/// creation/edits, member actions, and settlement changes).
///
/// Layout, top to bottom:
///   1. Top bar — back · italic event name · "ACTIVITY" mono caption
///   2. Day-grouped card-wrapped sections
///   3. Rows: category icon (MONEY/GEAR/DOCS) · actor + logText · timeago
class ActivityFeedScreen extends ConsumerWidget {
  const ActivityFeedScreen({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  final String groupId;
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventRef = (groupId: groupId, eventId: eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));
    final activityAsync = ref.watch(eventActivityProvider(eventRef));

    return Scaffold(
      key: ActivityKeys.screen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              title: eventAsync.valueOrNull?.name ?? 'Activity',
              loading: eventAsync.isLoading,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: eventAsync.when(
                loading: () => const _LoadingShimmer(),
                error: (_, _) => _ErrorView(
                  onRetry: () => ref.invalidate(eventDetailProvider(eventRef)),
                ),
                data: (event) {
                  if (event == null) return const _NotFoundView();
                  return activityAsync.when(
                    loading: () => const _LoadingShimmer(),
                    error: (_, _) => _ErrorView(
                      onRetry: () =>
                          ref.invalidate(eventActivityProvider(eventRef)),
                    ),
                    data: (logs) => _Body(logs: logs),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────── Body / list

class _Body extends StatelessWidget {
  const _Body({required this.logs});
  final List<ActivityLog> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const EmptyStateView(
        icon: Iconsax.activity,
        title: 'No activity yet',
        message: 'Actions by you and your group members will appear here.',
      );
    }
    final days = _groupByDay(logs, DateTime.now());
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: days.length,
      itemBuilder: (ctx, i) => Padding(
        padding: EdgeInsets.only(top: i == 0 ? 4 : 22),
        child: _DaySection(label: days[i].label, entries: days[i].entries),
      ),
    );
  }
}

// ──────────────────────────── Top bar

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.loading});
  final String title;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkResponse(
            onTap: () {
              HapticService.lightClick();
              if (GoRouter.of(context).canPop()) {
                GoRouter.of(context).pop();
              }
            },
            radius: 24,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                Iconsax.arrow_left,
                size: 20,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ACTIVITY',
                    style: AppTypography.mono(
                      fontSize: 10,
                      color: colors.textSecondary,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loading ? '…' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.display(
                      fontSize: 22,
                      color: colors.textPrimary,
                      letterSpacing: -0.3,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────── Day section + row

class _DaySection extends StatelessWidget {
  const _DaySection({required this.label, required this.entries});
  final String label;
  final List<ActivityLog> entries;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: AppTypography.mono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 0.5, color: colors.rule2)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: context.shadows.raised,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++)
                _ActivityRow(log: entries[i], divider: i < entries.length - 1),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.log, required this.divider});
  final ActivityLog log;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final actor = log.actorName ?? 'Someone';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _CategoryIcon(category: log.category, eventType: log.eventType),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: actor,
                        style: AppTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: log.logText,
                        style: AppTypography.sans(
                          fontSize: 14,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeago.format(log.createdAt, locale: 'en_short'),
                style: AppTypography.mono(
                  fontSize: 10,
                  color: colors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          if (divider) ...[
            const SizedBox(height: 12),
            Container(height: 0.5, color: colors.rule),
          ],
        ],
      ),
    );
  }
}

/// Maps `category` (MONEY / GEAR / DOCS) and `eventType` (CREATE / UPDATE /
/// DELETE) into a colored icon tile. DELETE on any category renders muted.
class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.category, required this.eventType});
  final String category;
  final String eventType;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final muted = eventType == 'DELETE';
    final (bg, fg, icon) = switch (category) {
      'MONEY' =>
        muted
            ? (colors.cardSoft, colors.textSecondary, Iconsax.money_remove)
            : (colors.saffronSoft, colors.primaryDark, Iconsax.money_3),
      'GEAR' =>
        muted
            ? (colors.cardSoft, colors.textSecondary, Iconsax.box_remove)
            : (colors.cardSoft, colors.cat2, Iconsax.bag_2),
      'DOCS' =>
        muted
            ? (colors.cardSoft, colors.textSecondary, Iconsax.document_cloud)
            : (colors.cardSoft, colors.success, Iconsax.document_text),
      _ => (colors.cardSoft, colors.textSecondary, Iconsax.activity),
    };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.rule, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: fg),
    );
  }
}

// ──────────────────────────── Helpers

class _DayGroup {
  const _DayGroup({required this.label, required this.entries});
  final String label;
  final List<ActivityLog> entries;
}

List<_DayGroup> _groupByDay(List<ActivityLog> logs, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final groups = <String, List<ActivityLog>>{};
  final order = <String>[];
  for (final log in logs) {
    final ts = log.createdAt;
    final day = DateTime(ts.year, ts.month, ts.day);
    final diff = today.difference(day).inDays;
    final label = diff == 0
        ? 'Today'
        : diff == 1
        ? 'Yesterday'
        : '${_monthShort(ts.month)} ${ts.day}';
    if (!groups.containsKey(label)) {
      groups[label] = [];
      order.add(label);
    }
    groups[label]!.add(log);
  }
  return [
    for (final label in order) _DayGroup(label: label, entries: groups[label]!),
  ];
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

// ──────────────────────────── States

class _LoadingShimmer extends StatelessWidget {
  const _LoadingShimmer();
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: 3,
      itemBuilder: (ctx, i) => Padding(
        padding: EdgeInsets.only(top: i == 0 ? 4 : 16),
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: colors.cardSoft,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Iconsax.activity,
      title: "Couldn't load activity",
      message: 'Check your connection and try again.',
      actionLabel: 'Reload',
      onAction: onRetry,
    );
  }
}

class _NotFoundView extends StatelessWidget {
  const _NotFoundView();
  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Iconsax.warning_2,
      title: 'This event no longer exists',
      message: 'It may have been deleted.',
      actionLabel: 'Go Home',
      onAction: () => GoRouter.of(context).go('/home'),
    );
  }
}
