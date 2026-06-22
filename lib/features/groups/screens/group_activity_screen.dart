import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
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
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../activity/utils/activity_display.dart';
import '../keys/group_keys.dart';
import '../models/group_activity_log_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';

/// Full-screen paginated group activity timeline (saffron direction).
///
/// Wireframe ref: `Wireframes/Rihla/hifi/screens-group.jsx` → `Hi_GroupActivity()`.
/// Layout:
///   1. Top bar — back button + centered group name
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

enum _Filter { all, settlements, events, members }

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
    final result =
        _activities.where((a) => _matches(a.type, _filter)).toList();
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
            _TopBar(title: groupName, groupId: widget.groupId),
            _FilterStrip(
              current: _filter,
              onChange: (f) {
                // #634: re-tapping the already-active chip is a no-op.
                if (f == _filter) return;
                setState(() => _filter = f);
              },
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
        icon: Iconsax.activity,
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

    final days = _groupByDay(context, filtered, DateTime.now());

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsetsDirectional.fromSTEB(context.spacing.space20, context.spacing.space4, context.spacing.space20, context.spacing.space24),
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
          return Padding(
            padding: EdgeInsets.all(context.spacing.space16),
            child: Center(
              child: SizedBox(
                width: context.spacing.space16,
                height: context.spacing.space16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.primary,
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: EdgeInsets.only(top: i == 0 ? 4 : 22),
          child: _DaySection(
            label: days[i].label,
            dateSuffix: days[i].dateSuffix,
            entries: days[i].entries,
            currency: currency,
          ),
        );
      },
    );
  }
}

// ──────────────────────────── Top bar

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.groupId});
  final String title;
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(context.spacing.space12, context.spacing.space4, context.spacing.space20, context.spacing.space8),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                key: GroupKeys.activityBackButton,
                tooltip: context.l10n.commonBack,
                icon: Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Iconsax.arrow_right_2
                      : Iconsax.arrow_left_2,
                  size: 20,
                ),
                color: colors.textPrimary,
                onPressed: () {
                  HapticService.lightClick();
                  if (GoRouter.of(context).canPop()) {
                    GoRouter.of(context).pop();
                  } else {
                    GoRouter.of(context).go('/group/$groupId');
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 52),
              child: Text(
                title,
                key: GroupKeys.activityScreenTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────── Filter chips

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.current, required this.onChange});
  final _Filter current;
  final ValueChanged<_Filter> onChange;

  @override
  Widget build(BuildContext context) {
    final options = [
      (
        _Filter.all,
        context.l10n.activityFilterActivity,
        GroupKeys.activityFilterAll,
      ),
      (
        _Filter.settlements,
        context.l10n.activityFilterSettles,
        GroupKeys.activityFilterSettlements,
      ),
      (
        _Filter.events,
        context.l10n.activityFilterEvents,
        GroupKeys.activityFilterEvents,
      ),
      (
        _Filter.members,
        context.l10n.activityFilterMembers,
        GroupKeys.activityFilterMembers,
      ),
    ];
    return SizedBox(
      height: context.spacing.space32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
        children: [
          for (final opt in options) ...[
            _Chip(
              chipKey: opt.$3,
              label: opt.$2,
              active: current == opt.$1,
              onTap: () {
                HapticService.selection();
                onChange(opt.$1);
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.chipKey,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final Key chipKey;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      key: chipKey,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? colors.textPrimary : colors.cardSoft,
          borderRadius: BorderRadius.circular(context.spacing.radiusPill),
          border: Border.all(
            color: active ? colors.textPrimary : colors.rule,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.sans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? colors.scaffoldBackground : colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────── Day section + row

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.label,
    required this.dateSuffix,
    required this.entries,
    required this.currency,
  });
  final String label;
  final String? dateSuffix;
  final List<GroupActivityLog> entries;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelStyle = AppTypography.mono(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: colors.textSecondary,
      letterSpacing: 2,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(), style: labelStyle),
            if (dateSuffix != null)
              Text(' · ${dateSuffix!.toUpperCase()}', style: labelStyle),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 0.5, color: colors.rule2)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
            boxShadow: context.shadows.raised,
          ),
          padding: EdgeInsets.symmetric(horizontal: context.spacing.space16),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++)
                _ActivityRow(
                  log: entries[i],
                  divider: i < entries.length - 1,
                  currency: currency,
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
    required this.currency,
  });
  final GroupActivityLog log;
  final bool divider;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amountRaw = log.metadata['amount'];
    final amount = _coerceAmount(amountRaw);
    // #382 PR-4: settlements stamped with a bucket currency render in it;
    // legacy rows fall back to the group currency threaded in by the screen.
    final rowCurrency = activityAmountCurrency(log, currency);
    final isSettlement = log.type == 'group_settlement';
    final description = localizedGroupActivityText(context.l10n, log);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
      child: Column(
        children: [
          Row(
            // Top-align so the category icon pins to the first line when a
            // long actor + verb phrase wraps to two lines (#159).
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CategoryIcon(type: log.type),
              SizedBox(width: context.spacing.space12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: log.actorName,
                        style: AppTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: description,
                        style: AppTypography.sans(
                          fontSize: 14,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: context.spacing.space12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (amount != null) ...[
                    RAmount(
                      value: amount,
                      currency: rowCurrency,
                      size: 14,
                      // Label only foreign amounts; the group's own currency
                      // stays bare (the expense_audit_detail !sameCurrency
                      // idiom).
                      showCurrency: rowCurrency != currency,
                    ),
                    const SizedBox(height: 2),
                  ],
                  if (isSettlement && amount != null)
                    RAmount(
                      value: amount,
                      currency: rowCurrency,
                      size: 11,
                      sign: true,
                      tone: AmountTone.sage,
                      showCurrency: false,
                    )
                  else
                    Text(
                      formatRelativeShort(context, log.timestamp),
                      style: AppTypography.mono(
                        fontSize: 10,
                        color: colors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                ],
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

  /// Settlement amounts may arrive as a stringified Decimal (see
  /// `GroupSettleUpScreen.logGroupEvent` metadata) or as a num. Coerce to a
  /// `Decimal` WITHOUT forcing OMR's 3dp (#261) — [RAmount] applies the group's
  /// own currency precision.
  Decimal? _coerceAmount(Object? raw) {
    if (raw == null) return null;
    if (raw is num) {
      return Decimal.parse(raw.toString());
    }
    if (raw is String) {
      return Decimal.tryParse(raw);
    }
    return null;
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sageSoft = Color.alphaBlend(
      colors.success.withValues(alpha: 0.18),
      colors.cardSurface,
    );
    final (bg, fg, icon, hasBorder) = switch (type) {
      'group_settlement' => (
        sageSoft,
        colors.success,
        // Money/wallet glyph (matches the settle-up total chip, #157) — not a
        // bare chevron, which read as navigation amid the other category
        // glyphs (#160).
        Iconsax.wallet_3,
        false,
      ),
      'event_created' => (
        colors.saffronSoft,
        colors.primaryDark,
        Iconsax.calendar_1,
        true,
      ),
      'event_deleted' => (
        colors.cardSoft,
        colors.textSecondary,
        Iconsax.calendar_remove,
        true,
      ),
      'member_joined' => (colors.cardSoft, colors.cat2, Iconsax.user_add, true),
      'member_left' => (
        colors.cardSoft,
        colors.textSecondary,
        Iconsax.user_minus,
        true,
      ),
      _ => (colors.cardSoft, colors.textSecondary, Iconsax.activity, true),
    };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: hasBorder ? Border.all(color: colors.rule, width: 0.5) : null,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: fg),
    );
  }
}

// ──────────────────────────── Helpers

bool _matches(String type, _Filter f) {
  return switch (f) {
    _Filter.all => true,
    _Filter.settlements => type == 'group_settlement',
    _Filter.events => type == 'event_created' || type == 'event_deleted',
    _Filter.members => type == 'member_joined' || type == 'member_left',
  };
}

class _DayGroup {
  const _DayGroup({
    required this.label,
    required this.dateSuffix,
    required this.entries,
  });
  final String label;
  final String? dateSuffix;
  final List<GroupActivityLog> entries;
}

List<_DayGroup> _groupByDay(
  BuildContext context,
  List<GroupActivityLog> logs,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  // #634: hoist the constant l10n strings and the DateFormat out of the
  // per-log loop — constructing a DateFormat parses the ICU skeleton each call.
  final todayLabel = context.l10n.timelineToday;
  final yesterdayLabel = context.l10n.timelineYesterday;
  final monthDayFmt = shortMonthDayFormatter(context);
  final buckets = <String, _DayBucket>{};
  final order = <String>[];
  for (final log in logs) {
    final ts = log.timestamp;
    final day = DateTime(ts.year, ts.month, ts.day);
    final diff = today.difference(day).inDays;
    final dateText = monthDayFmt.format(ts);
    final (label, suffix) = switch (diff) {
      0 => (todayLabel, dateText),
      1 => (yesterdayLabel, dateText),
      _ => (dateText, null),
    };
    final bucket = buckets.putIfAbsent(label, () {
      order.add(label);
      return _DayBucket(suffix: suffix, entries: []);
    });
    bucket.entries.add(log);
  }
  return [
    for (final label in order)
      _DayGroup(
        label: label,
        dateSuffix: buckets[label]!.suffix,
        entries: buckets[label]!.entries,
      ),
  ];
}

class _DayBucket {
  _DayBucket({required this.suffix, required this.entries});
  final String? suffix;
  final List<GroupActivityLog> entries;
}
