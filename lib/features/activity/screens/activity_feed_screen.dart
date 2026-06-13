import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/localized_dates.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../events/providers/event_provider.dart';
import '../keys/activity_keys.dart';
import '../models/activity_log_model.dart';
import '../services/activity_service.dart';
import '../utils/activity_display.dart';
import '../utils/expense_audit_diff.dart';
import '../widgets/expense_audit_detail.dart';

/// Event activity feed — saffron travel-journal direction.
///
/// Chronological day-grouped feed of event-scoped activity logs (expense
/// creation/edits, member actions, and settlement changes).
///
/// Layout, top to bottom:
///   1. Top bar — back · italic event name · "ACTIVITY" mono caption
///   2. Day-grouped card-wrapped sections
///   3. Rows: category icon (MONEY/GEAR/DOCS) · actor + logText · timeago
const _kPageSize = 50;

class ActivityFeedScreen extends ConsumerStatefulWidget {
  const ActivityFeedScreen({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  final String groupId;
  final String eventId;

  @override
  ConsumerState<ActivityFeedScreen> createState() =>
      _ActivityFeedScreenState();
}

class _ActivityFeedScreenState extends ConsumerState<ActivityFeedScreen> {
  final List<ActivityLog> _activities = [];
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _initialError = false;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _loadPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200 && _hasMore && !_isLoadingMore) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final snap = await ref
          .read(activityServiceProvider)
          .fetchActivityPageRaw(
            widget.groupId,
            widget.eventId,
            startAfter: _lastDocument,
            limit: _kPageSize,
          );
      final newLogs = snap.docs
          .map((doc) => ActivityLog.fromFirestore({...doc.data(), 'id': doc.id}))
          .toList();
      if (!mounted) return;
      setState(() {
        _activities.addAll(newLogs);
        if (snap.docs.isNotEmpty) _lastDocument = snap.docs.last;
        _hasMore = snap.docs.length == _kPageSize; // compare to the request limit
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      final isInitial = _activities.isEmpty;
      setState(() {
        if (isInitial) _initialError = true; // initial failure -> error+retry view
        _isLoadingMore = false; // later-page failure -> keep loaded rows
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));
    return Scaffold(
      key: ActivityKeys.screen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              title: eventAsync.valueOrNull?.name ?? context.l10n.activityTitle,
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
                  return _buildActivityBody(context, event.participantNames);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityBody(
    BuildContext context,
    Map<String, String> participantNames,
  ) {
    if (_initialError && _activities.isEmpty) {
      return _ErrorView(
        onRetry: () {
          setState(() => _initialError = false);
          _loadPage();
        },
      );
    }
    if (_isLoadingMore && _activities.isEmpty) return const _LoadingShimmer();
    if (_activities.isEmpty) {
      return EmptyStateView(
        icon: Iconsax.activity,
        title: context.l10n.activityNoActivityTitle,
        message: context.l10n.activityEventEmptyMessage,
      );
    }
    final days = _groupByDay(context, _activities, DateTime.now());
    return ListView.builder(
      key: ActivityKeys.feedList,
      restorationId: 'activity_feed_scroll',
      controller: _scrollController,
      padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 24),
      itemCount: days.length + (_hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == days.length) {
          // Next-page footer reuses the same skeleton primitive instead of a
          // bare spinner, so the screen has ONE loading treatment (#488).
          return SkeletonLoader.expenseList(count: 1);
        }
        return Padding(
          key: ValueKey('activity-day-${days[i].label}'),
          padding: EdgeInsets.only(top: i == 0 ? context.spacing.space4 : 22),
          child: _DaySection(
            label: days[i].label,
            entries: days[i].entries,
            participantNames: participantNames,
          ),
        );
      },
    );
  }
}

// ──────────────────────────── Top bar

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 20, 0),
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
                Directionality.of(context) == TextDirection.rtl
                    ? Iconsax.arrow_right
                    : Iconsax.arrow_left,
                size: 20,
                color: colors.textPrimary,
              ),
            ),
          ),
          SizedBox(width: context.spacing.space4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.activityCaption,
                    style: AppTypography.mono(
                      fontSize: 10,
                      color: colors.textSecondary,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
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
  const _DaySection({
    required this.label,
    required this.entries,
    required this.participantNames,
  });
  final String label;
  final List<ActivityLog> entries;
  final Map<String, String> participantNames;

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
            borderRadius: BorderRadius.circular(context.spacing.radiusCard),
            boxShadow: context.shadows.raised,
          ),
          padding: EdgeInsets.symmetric(horizontal: context.spacing.space16),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++)
                _ActivityRow(
                  log: entries[i],
                  divider: i < entries.length - 1,
                  participantNames: participantNames,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.log,
    required this.divider,
    required this.participantNames,
  });
  final ActivityLog log;
  final bool divider;
  final Map<String, String> participantNames;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final actor = log.actorName ?? context.l10n.activitySomeone;
    final text = localizedEventActivityText(context.l10n, log);
    final diff = log.category == 'MONEY'
        ? ExpenseAuditDiff.fromMetadata(log.metadata)
        : const ExpenseAuditDiff();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
      child: Column(
        children: [
          Row(
            // Top-align so the category icon pins to the first line when a
            // long actor + verb phrase wraps to two lines (#159).
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CategoryIcon(category: log.category, eventType: log.eventType),
              SizedBox(width: context.spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
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
                            text: text,
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
                    if (diff.hasDetail)
                      ExpenseAuditDetail(
                        diff: diff,
                        eventType: log.eventType,
                        participantNames: participantNames,
                      ),
                  ],
                ),
              ),
              SizedBox(width: context.spacing.space8),
              Text(
                formatRelativeShort(context, log.createdAt),
                style: AppTypography.mono(
                  fontSize: 10,
                  color: colors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          if (divider) ...[
            SizedBox(height: context.spacing.space12),
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

List<_DayGroup> _groupByDay(
  BuildContext context,
  List<ActivityLog> logs,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final groups = <String, List<ActivityLog>>{};
  final order = <String>[];
  for (final log in logs) {
    final ts = log.createdAt;
    final day = DateTime(ts.year, ts.month, ts.day);
    final diff = today.difference(day).inDays;
    final label = diff == 0
        ? context.l10n.timelineToday
        : diff == 1
        ? context.l10n.timelineYesterday
        : formatShortMonthDay(context, ts);
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

// ──────────────────────────── States

class _LoadingShimmer extends StatelessWidget {
  const _LoadingShimmer();
  @override
  Widget build(BuildContext context) {
    // The shared, reduce-motion-aware skeleton primitive — same treatment the
    // cross-group activity feed uses (#488), so loading reads consistently.
    return SkeletonLoader.expenseList();
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      key: ActivityKeys.errorView,
      icon: Iconsax.activity,
      title: context.l10n.activityLoadFailedTitle,
      message: context.l10n.activityLoadFailedMessage,
      actionLabel: context.l10n.activityReload,
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
      title: context.l10n.activityEventMissingTitle,
      message: context.l10n.activityEventMissingMessage,
      actionLabel: context.l10n.commonGoHome,
      onAction: () => GoRouter.of(context).go('/home'),
    );
  }
}
