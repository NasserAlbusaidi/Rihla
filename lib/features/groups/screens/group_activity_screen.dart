import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/day_grouping.dart';
import '../../../shared/widgets/activity_day_section.dart';
import '../../../shared/widgets/activity_filter_strip.dart';
import '../../../shared/widgets/activity_glyph.dart';
import '../../../shared/widgets/activity_row.dart';
import '../../../shared/widgets/caption_title_bar.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../activity/utils/activity_display.dart';
import '../../activity/utils/activity_nav.dart';
import '../keys/group_keys.dart';
import '../models/group_activity_log_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';

/// Full-screen paginated group activity timeline (saffron direction).
///
/// Wireframe ref: `Wireframes/Rihla/hifi/screens-group.jsx` → `Hi_GroupActivity()`.
/// Layout:
///   1. Journal top bar — back button, ACTIVITY caption, group name as the
///      serif display title (`CaptionTitleBar`, shared with the per-event feed)
///   2. Pill filter chips — All / Settlements / Events / Members
///   3. Day-grouped card-wrapped sections with category-icon-led rows
///      Day header: `TODAY · MAR 22` (mono caps, dot-separated date)
///      Settlement rows: sage-tinted arrow icon + signed share amount
///
/// Keeps cursor-based pagination (page size 50, prefetch within 200px
/// of bottom). Filter is applied client-side to fetched pages.
///
/// **Deviation from wireframe:** wireframe shows 3 view-mode chips
/// (Activity / By person / By category) instead of type filters. Type
/// filters kept for functional parity with the cross-group activity
/// screen and the prior implementation.
class GroupActivityScreen extends ConsumerStatefulWidget {
  const GroupActivityScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupActivityScreen> createState() =>
      _GroupActivityScreenState();
}

enum _Filter { all, settlements, events, members, expenses }

/// Test seam (#634): increments each time the filtered activity list is
/// actually recomputed (a cache miss). Re-tapping the already-active chip and
/// unrelated rebuilds (e.g. the group-name stream re-emitting) must NOT
/// increment this once the cache + equality guard are in place.
@visibleForTesting
int debugGroupActivityFilterComputes = 0;

class _GroupActivityScreenState extends ConsumerState<GroupActivityScreen> {
  final List<GroupActivityLog> _activities = [];
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _loadFailed = false;
  _Filter _filter = _Filter.all;
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
    if (pos.pixels >= pos.maxScrollExtent - 200 &&
        _hasMore &&
        !_isLoadingMore) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
      _loadFailed = false;
    });
    try {
      final service = ref.read(groupActivityServiceProvider);
      final snap = await service.fetchActivityPageRaw(
        widget.groupId,
        startAfter: _lastDocument,
        limit: 50,
      );
      final newActivities = snap.docs
          .map(
            (doc) =>
                GroupActivityLog.fromFirestore({...doc.data(), 'id': doc.id}),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _activities.addAll(newActivities);
        _lastDocument = snap.docs.isNotEmpty ? snap.docs.last : _lastDocument;
        _hasMore = snap.docs.length == 50;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _loadFailed = true;
      });
    }
  }

  // #634: memoize the filtered list. `_activities` is append-only (only
  // `addAll` in `_loadPage`), so its length uniquely identifies its content;
  // recompute only when the list grows or the filter changes — not on every
  // build (the group-name stream re-emitting, or re-tapping the active chip).
  List<GroupActivityLog>? _filteredCache;
  int _filteredCacheLen = -1;
  _Filter? _filteredCacheFilter;

  List<GroupActivityLog> get _filtered {
    if (_filteredCache != null &&
        _filteredCacheLen == _activities.length &&
        _filteredCacheFilter == _filter) {
      return _filteredCache!;
    }
    debugGroupActivityFilterComputes++;
    final result = _activities.where((a) => _matches(a.type, _filter)).toList();
    _filteredCache = result;
    _filteredCacheLen = _activities.length;
    _filteredCacheFilter = _filter;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final groupName =
        groupAsync.valueOrNull?.name ?? context.l10n.activityTitle;
    // #261: settlement amounts in this group's activity feed are in the group's
    // currency (no per-log currency field exists).
    final currency = groupAsync.valueOrNull?.currency ?? 'OMR';

    return Scaffold(
      key: GroupKeys.activityScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            CaptionTitleBar(
              caption: context.l10n.activityCaption,
              title: groupName,
              titleKey: GroupKeys.activityScreenTitle,
              backKey: GroupKeys.activityBackButton,
              onBack: () {
                if (GoRouter.of(context).canPop()) {
                  GoRouter.of(context).pop();
                } else {
                  GoRouter.of(context).go('/group/${widget.groupId}');
                }
              },
            ),
            ActivityFilterStrip<_Filter>(
              current: _filter,
              onChange: (f) => setState(() => _filter = f),
              options: [
                ActivityFilterOption(
                  value: _Filter.all,
                  label: context.l10n.activityFilterAll,
                  key: GroupKeys.activityFilterAll,
                ),
                ActivityFilterOption(
                  // P4: unify on the same key the cross-group screen uses —
                  // both l10n values are identical today.
                  value: _Filter.settlements,
                  label: context.l10n.activityFilterSettlements,
                  key: GroupKeys.activityFilterSettlements,
                ),
                ActivityFilterOption(
                  value: _Filter.events,
                  label: context.l10n.activityFilterEvents,
                  key: GroupKeys.activityFilterEvents,
                ),
                ActivityFilterOption(
                  value: _Filter.members,
                  label: context.l10n.activityFilterMembers,
                  key: GroupKeys.activityFilterMembers,
                ),
                ActivityFilterOption(
                  value: _Filter.expenses,
                  label: context.l10n.activityFilterExpenses,
                  key: GroupKeys.activityFilterExpenses,
                ),
              ],
            ),
            SizedBox(height: context.spacing.space8),
            Expanded(child: _buildBody(context, currency)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, String currency) {
    if (_isLoadingMore && _activities.isEmpty) {
      return SkeletonLoader.expenseList();
    }
    // A failed first load must surface a real, retryable error — never the
    // "No activity yet" empty state, which falsely reads as "this group is
    // empty" when the fetch actually failed (#488).
    if (_loadFailed && _activities.isEmpty) {
      return EmptyStateView(
        key: GroupKeys.activityErrorView,
        icon: Iconsax.warning_2,
        title: context.l10n.activityLoadFailedTitle,
        message: context.l10n.activityLoadFailedMessage,
        actionLabel: context.l10n.activityReload,
        onAction: _loadPage,
      );
    }
    if (_activities.isEmpty) {
      return EmptyStateView(
        icon: Iconsax.activity,
        title: context.l10n.activityNoActivityTitle,
        message: context.l10n.activityGroupEmptyMessage,
      );
    }
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return EmptyStateView(
        icon: Iconsax.search_normal,
        title: context.l10n.activityNoFilterTitle,
        message: context.l10n.activityNoFilterMessage,
      );
    }

    final days = groupByDay<GroupActivityLog>(
      context,
      filtered,
      DateTime.now(),
      (log) => log.timestamp,
    );

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsetsDirectional.fromSTEB(
        context.spacing.space20,
        context.spacing.space4,
        context.spacing.space20,
        context.spacing.space24,
      ),
      itemCount: days.length + (_hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == days.length) {
          // A failed *pagination* fetch shows a retry, not a perpetual
          // spinner indistinguishable from "reached the end" (#488).
          if (_loadFailed) {
            return Padding(
              padding: EdgeInsets.all(context.spacing.space16),
              child: Center(
                child: TextButton(
                  onPressed: _loadPage,
                  child: Text(context.l10n.activityReload),
                ),
              ),
            );
          }
          return SkeletonLoader.expenseList(count: 1);
        }
        return Padding(
          padding: EdgeInsets.only(top: i == 0 ? 4 : 22),
          child: ActivityDaySection(
            label: days[i].label,
            dateSuffix: days[i].dateSuffix,
            raised: true,
            children: _buildRows(
              context,
              days[i].entries,
              currency,
              widget.groupId,
            ),
          ),
        );
      },
    );
  }
}

/// Verbatim from the old `_CategoryIcon` type switch — mapped onto the
/// shared [ActivityGlyph] vocabulary. Will be lifted into
/// `activity_display.dart` as `glyphForGroupActivityType` in PR 4 so the
/// cross-group feed shares one copy.
ActivityGlyph _glyphForType(String type) => switch (type) {
  'group_settlement' => ActivityGlyph.settlement,
  'event_created' => ActivityGlyph.eventCreated,
  'event_deleted' => ActivityGlyph.eventDeleted,
  'member_joined' => ActivityGlyph.memberJoined,
  'member_left' => ActivityGlyph.memberLeft,
  'expense_added' => ActivityGlyph.expenseAdded,
  'expense_edited' => ActivityGlyph.expenseEdited,
  'expense_deleted' => ActivityGlyph.expenseDeleted,
  _ => ActivityGlyph.generic,
};

List<Widget> _buildRows(
  BuildContext context,
  List<GroupActivityLog> entries,
  String currency,
  String groupId,
) {
  return [
    for (var i = 0; i < entries.length; i++)
      _buildRow(context, entries[i], i < entries.length - 1, currency, groupId),
  ];
}

Widget _buildRow(
  BuildContext context,
  GroupActivityLog log,
  bool divider,
  String currency,
  String groupId,
) {
  // #808 PR2: single chokepoint — handles both the legacy settlement `amount`
  // and the server-fan-in `amountFils`+`currency` shape (fils never rendered
  // through the decimal-units path). #382 PR-4: a stamped bucket currency
  // wins; legacy rows fall back to the group currency threaded in.
  final amt = activityAmount(log, currency);
  final description = localizedGroupActivityText(context.l10n, log);
  // #852: per-type deep-link shared with the History tab (activity_nav.dart;
  // total, so safe to resolve during build). A target resolving to this
  // screen's own group root (member_*, event_deleted, unknown types, or a
  // guard-degraded eventId) stays inert — pushing a duplicate of the parent
  // screen is the false affordance this issue removes.
  final target = activityRowTarget(groupId: groupId, log: log);
  final selfTarget = target == '/group/$groupId';

  return ActivityRow(
    glyph: _glyphForType(log.type),
    actorName: log.actorName,
    description: description,
    timestamp: log.timestamp,
    trailingAmount: amt == null
        ? null
        : RAmount(
            value: amt.value,
            currency: amt.currency,
            size: 14,
            // Label only foreign amounts; the group's own currency stays bare
            // (the expense_audit_detail !sameCurrency idiom).
            showCurrency: amt.currency != currency,
          ),
    divider: divider,
    onTap: selfTarget ? null : () => GoRouter.of(context).push(target),
  );
}

// ──────────────────────────── Helpers

bool _matches(String type, _Filter f) {
  return switch (f) {
    _Filter.all => true,
    _Filter.settlements => type == 'group_settlement',
    _Filter.events => type == 'event_created' || type == 'event_deleted',
    _Filter.members => type == 'member_joined' || type == 'member_left',
    _Filter.expenses => type.startsWith('expense_'),
  };
}
