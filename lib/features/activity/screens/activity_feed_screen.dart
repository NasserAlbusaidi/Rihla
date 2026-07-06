import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/day_grouping.dart';
import '../../../core/utils/safe_deserialize.dart';
import '../../../shared/widgets/activity_day_section.dart';
import '../../../shared/widgets/activity_glyph.dart';
import '../../../shared/widgets/activity_row.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../events/embedded_panel_metrics.dart';
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
/// creation/edits, member actions, and settlement changes), rendered as the
/// Activity panel of the tabbed event view (#758; panel-only since #915 —
/// the tabbed shell owns chrome + back affordance).
///
/// Layout: day-grouped, flat-card sections (dot-date headers, #490 D-f);
/// rows: category glyph · actor + verb · trailing amount/audit chip.
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
      // #928: skip a malformed row instead of failing the whole page (the
      // catch below would discard every fetched row AND advance the cursor,
      // silently truncating the feed). Display-only rows: skip-and-report.
      final newLogs = decodeDocsSkippingMalformed(
        snap.docs,
        (d) => ActivityLog.fromFirestore(
          {...d.data()! as Map<String, dynamic>, 'id': d.id},
        ),
        context: 'ActivityFeed.page',
      );
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
    return eventAsync.when(
      loading: () => const _LoadingShimmer(),
      error: (_, _) => _ErrorView(
        onRetry: () => ref.invalidate(eventDetailProvider(eventRef)),
      ),
      data: (event) {
        if (event == null) return const _NotFoundView();
        return _buildActivityBody(context, event.participantNames);
      },
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
    final days = groupByDay(
      context,
      _activities,
      DateTime.now(),
      (log) => log.createdAt,
    );
    return ListView.builder(
      key: ActivityKeys.feedList,
      restorationId: 'activity_feed_scroll',
      controller: _scrollController,
      // #789: the panel clears the workspace's floating FAB.
      padding: const EdgeInsetsDirectional.fromSTEB(
        20,
        4,
        20,
        kEmbeddedEventPanelFabClearance,
      ),
      itemCount: days.length + (_hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == days.length) {
          // Next-page footer reuses the same skeleton primitive instead of a
          // bare spinner, so the screen has ONE loading treatment (#488).
          return SkeletonLoader.expenseList(count: 1);
        }
        final day = days[i];
        return Padding(
          key: ValueKey('activity-day-${day.label}'),
          padding: EdgeInsets.only(top: i == 0 ? context.spacing.space4 : 22),
          child: ActivityDaySection(
            label: day.label,
            dateSuffix: day.dateSuffix,
            // #866: flat + hairline, not raised — these rows are inert (their
            // content affordance is the inline ExpenseAuditDetail, not a tap
            // target); raised is the app's actionable-surface cue (#807).
            raised: false,
            children: [
              for (var j = 0; j < day.entries.length; j++)
                _activityRowFor(
                  context,
                  day.entries[j],
                  divider: j < day.entries.length - 1,
                  participantNames: participantNames,
                ),
            ],
          ),
        );
      },
    );
  }
}

// ──────────────────────────── Row adapter

/// Maps `category`/`eventType` onto the shared glyph vocabulary (#490 D-g).
/// GEAR/DOCS are dead Phase-39 categories and lose their bespoke icons on
/// purpose — they, and any unknown category, fall back to the generic glyph.
ActivityGlyph _glyphFor(ActivityLog log) => switch ((
  log.category,
  log.eventType,
)) {
  ('MONEY', 'CREATE') => ActivityGlyph.expenseAdded,
  ('MONEY', 'UPDATE') => ActivityGlyph.expenseEdited,
  ('MONEY', 'DELETE') => ActivityGlyph.expenseDeleted,
  _ => ActivityGlyph.generic,
};

ActivityRow _activityRowFor(
  BuildContext context,
  ActivityLog log, {
  required bool divider,
  required Map<String, String> participantNames,
}) {
  final diff = log.category == 'MONEY'
      ? ExpenseAuditDiff.fromMetadata(log.metadata)
      : const ExpenseAuditDiff();
  final showAuditChip = log.eventType == 'UPDATE' && diff.hasFieldChange;
  final amount = (!showAuditChip && diff.after != null)
      ? RAmount(value: diff.after!.amount, currency: diff.after!.currency, size: 14)
      : null;
  return ActivityRow(
    glyph: _glyphFor(log),
    actorName: log.actorName ?? context.l10n.activitySomeone,
    description: localizedEventActivityText(context.l10n, log),
    timestamp: log.createdAt,
    trailingAmount: amount,
    detail: showAuditChip
        ? ExpenseAuditDetail(
            diff: diff,
            eventType: log.eventType,
            participantNames: participantNames,
          )
        : null,
    muted: log.eventType == 'DELETE',
    maxLines: 3,
    divider: divider,
  );
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
      icon: Iconsax.warning_2,
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
