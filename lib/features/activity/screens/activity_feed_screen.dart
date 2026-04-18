import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../shared/animations/fade_in_list.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../events/providers/event_provider.dart';
import '../keys/activity_keys.dart';
import '../models/activity_log_model.dart';
import '../services/activity_service.dart';
import '../widgets/activity_entry_card.dart';
import '../widgets/activity_hero_card.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/gradient_tokens.dart';

/// Activity feed screen — Date-grouped timeline per D-21.
///
/// Takes string IDs per D-14. Migrated from Event/Group object params.
/// Displays ActivityHeroCard + date-grouped list of ActivityEntryCard widgets.
class ActivityFeedScreen extends ConsumerWidget {
  final String groupId;
  final String eventId;

  const ActivityFeedScreen({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventRef = (groupId: groupId, eventId: eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));
    final activityAsync = ref.watch(eventActivityProvider(eventRef));

    // Loading state — skeleton while event loads
    if (eventAsync.isLoading) {
      return Scaffold(
        backgroundColor: context.colors.scaffoldBackground,
        body: Column(
          children: [
            const ModuleHeader(
              title: 'Activity',
              useDarkTheme: true,
            ),
            Expanded(child: SkeletonLoader.cardList()),
          ],
        ),
      );
    }

    final event = eventAsync.valueOrNull;

    // Not-found state per D-11
    if (event == null) {
      return Scaffold(
        backgroundColor: context.colors.scaffoldBackground,
        body: Column(
          children: [
            const ModuleHeader(title: 'Not Found'),
            Expanded(
              child: EmptyStateView(
                icon: Iconsax.warning_2,
                title: 'This event no longer exists',
                message:
                    'It may have been deleted. Tap below to go back to your groups.',
                actionLabel: 'Go Home',
                onAction: () => context.go('/home'),
                iconColor: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: ActivityKeys.screen,
      backgroundColor: context.colors.scaffoldBackground,
      body: activityAsync.when(
        loading: () => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ModuleHeader(
                title: 'Activity',
                subtitle: event.name.toUpperCase(),
                useDarkTheme: true,
              ),
            ),
            SliverToBoxAdapter(
              child: SkeletonLoader.cardList(),
            ),
          ],
        ),
        error: (e, _) => Column(
          children: [
            ModuleHeader(
              title: 'Activity',
              subtitle: event.name.toUpperCase(),
              useDarkTheme: true,
            ),
            Expanded(
              child: EmptyStateView(
                icon: Iconsax.activity,
                title: "Couldn't load Activity",
                message: 'Check your connection and try again.',
                actionLabel: 'Reload',
                onAction: () => ref.invalidate(eventActivityProvider(eventRef)),
                iconColor: context.colors.textSecondary,
              ),
            ),
          ],
        ),
        data: (logs) {
          final entryCount = logs.length;
          final lastUpdate = logs.isNotEmpty
              ? timeago.format(logs.first.createdAt)
              : 'No activity yet';

          return CustomScrollView(
            slivers: [
              // 1. ModuleHeader
              SliverToBoxAdapter(
                child: ModuleHeader(
                  title: 'Activity',
                  subtitle: event.name.toUpperCase(),
                  useDarkTheme: true,
                ),
              ),
              // 2. ActivityHeroCard
              SliverToBoxAdapter(
                child: ActivityHeroCard(
                  entryCount: entryCount,
                  lastUpdate: lastUpdate,
                ),
              ),
              // 3. Date-grouped timeline or empty state
              if (logs.isEmpty)
                SliverFillRemaining(
                  child: EmptyStateView(
                    icon: Iconsax.activity,
                    title: 'No activity yet',
                    message:
                        'Actions by you and your group members will appear here.',
                    accentGradient: context.gradient(AppGradients.gray),
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: _buildGroupedTimeline(logs),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Builds the date-grouped timeline as a Column of section headers + entry cards.
  Widget _buildGroupedTimeline(List<ActivityLog> logs) {
    final grouped = _groupByDate(logs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries.map((entry) {
        final label = entry.key;
        final entries = entry.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DateSectionHeader(label: label),
            FadeInList(
              children: entries
                  .map((log) => ActivityEntryCard(log: log))
                  .toList(),
            ),
          ],
        );
      }).toList(),
    );
  }

  /// Groups activity logs by date label (TODAY, YESTERDAY, or formatted date).
  Map<String, List<ActivityLog>> _groupByDate(List<ActivityLog> logs) {
    final grouped = <String, List<ActivityLog>>{};
    final now = DateTime.now();
    for (final log in logs) {
      final label = _dateLabel(log.createdAt, now);
      grouped.putIfAbsent(label, () => []).add(log);
    }
    return grouped;
  }

  String _dateLabel(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final logDate = DateTime(date.year, date.month, date.day);
    if (logDate == today) return 'TODAY';
    if (logDate == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
    return DateFormat('MMM d').format(date);
  }
}

/// Section header for date groups in the activity timeline (D-21).
class _DateSectionHeader extends StatelessWidget {
  final String label;

  const _DateSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        4,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: context.colors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
