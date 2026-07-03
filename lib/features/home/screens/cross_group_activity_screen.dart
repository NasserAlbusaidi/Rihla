import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/localized_dates.dart';
import '../../activity/utils/activity_display.dart';
import '../../groups/providers/group_provider.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_icon_button.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../providers/activity_unread_provider.dart';
import '../providers/cross_group_activity_pager.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/add_expense_target_sheet.dart';

/// Full-screen cross-group activity feed (saffron travel-journal direction).
///
/// Wireframe ref: `Wireframes/Rihla/hifi/screens-shell.jsx` → `Hi_Activity()`.
/// Layout, top to bottom:
///   1. Large top bar — italic display "Activity" + ink-3 subtitle
///   2. Filter chips strip (All / Settlements / Events / Members)
///   3. Day-grouped sections, each wrapped in a card-surface card
///   4. Rows: category icon + actor/verb/description title + group context
///
/// Filter set differs from the wireframe because our activity log records
/// group-life events (settlement, event creation, member changes) rather
/// than per-expense entries. Chip labels are remapped to our type vocabulary.
class CrossGroupActivityScreen extends ConsumerStatefulWidget {
  const CrossGroupActivityScreen({super.key, this.showBack = false});

  /// Whether to render the back affordance. `false` (default) when the screen
  /// is the Activity bottom-nav tab (`BottomNavShell`); the `/activity` route
  /// builds it with `true`. Mirrors `ProfileScreen.showBack`. (#666)
  final bool showBack;

  @override
  ConsumerState<CrossGroupActivityScreen> createState() =>
      _CrossGroupActivityScreenState();
}

enum _Filter { all, settlements, events, members, expenses }

class _CrossGroupActivityScreenState
    extends ConsumerState<CrossGroupActivityScreen> {
  _Filter _filter = _Filter.all;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    // #808 PR2: reaching the tab (routed /activity or the first tab build)
    // marks the feed seen → clears the unread dot. Post-frame so we never
    // mutate a provider during the first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(activitySeenProvider.notifier).markSeenNow();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      ref.read(crossGroupActivityPagerProvider.notifier).loadMore();
    }
  }

  // #634: memoize the filtered list. `entries` is append-only within a load,
  // so its length uniquely identifies its content; recompute only when the list
  // grows or the filter changes — not on every rebuild.
  List<CrossGroupActivityEntry>? _filteredCache;
  int _filteredCacheLen = -1;
  _Filter? _filteredCacheFilter;

  List<CrossGroupActivityEntry> _filtered(
    List<CrossGroupActivityEntry> entries,
  ) {
    if (_filteredCache != null &&
        _filteredCacheLen == entries.length &&
        _filteredCacheFilter == _filter) {
      return _filteredCache!;
    }
    final result = entries
        .where((e) => _matchesFilter(e.log.type, _filter))
        .toList();
    _filteredCache = result;
    _filteredCacheLen = entries.length;
    _filteredCacheFilter = _filter;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final pager = ref.watch(crossGroupActivityPagerProvider);
    return Scaffold(
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(showBack: widget.showBack),
            const SizedBox(height: 6),
            _FilterStrip(
              current: _filter,
              onChange: (f) => setState(() => _filter = f),
            ),
            SizedBox(height: context.spacing.space8),
            Expanded(child: _buildBody(context, pager)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    CrossGroupActivityPagerState pager,
  ) {
    // #488: a layout-matched skeleton, not a blank screen, on the first load.
    if (!pager.initialised && pager.entries.isEmpty) {
      return SkeletonLoader.expenseList();
    }
    // A failed first load (or a partial failure with zero survivors) surfaces a
    // real, retryable error — never the misleading "No activity yet".
    if (pager.entries.isEmpty &&
        (pager.firstLoadFailed || pager.partialFailure)) {
      return EmptyStateView(
        icon: Iconsax.warning_2,
        title: context.l10n.activityLoadFailedTitle,
        message: context.l10n.activityLoadFailedMessage,
        onAction: () =>
            ref.read(crossGroupActivityPagerProvider.notifier).refresh(),
        actionLabel: context.l10n.commonRetry,
      );
    }

    final filtered = _filtered(pager.entries);
    if (filtered.isEmpty) {
      final isTrueEmpty = pager.entries.isEmpty;
      // #807: only offer the add-expense CTA on the true no-activity state and
      // only when the user has a group. Zero groups → NO CTA (never a duplicate
      // create-group affordance).
      final groups = ref.watch(userGroupsProvider).valueOrNull;
      final showCta = isTrueEmpty && groups != null && groups.isNotEmpty;
      return EmptyStateView(
        icon: Iconsax.activity,
        title: isTrueEmpty
            ? context.l10n.activityNoActivityTitle
            : context.l10n.activityNoFilterTitle,
        message: isTrueEmpty
            ? context.l10n.activityCrossGroupEmptyMessage
            : context.l10n.activityNoFilterMessage,
        actionLabel: showCta ? context.l10n.ledgerAddExpense : null,
        onAction: showCta ? () => AddExpenseTargetSheet.show(context) : null,
      );
    }

    final days = _groupByDay(context, filtered, DateTime.now());
    final showFooter = pager.isLoadingMore || pager.partialFailure;
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(crossGroupActivityPagerProvider.notifier).refresh(),
      child: ListView.builder(
        controller: _scrollController,
        // Bottom inset clears the tab-shell add-expense FAB (#364).
        padding: EdgeInsetsDirectional.fromSTEB(
          context.spacing.space20,
          context.spacing.space4,
          context.spacing.space20,
          96,
        ),
        itemCount: days.length + (showFooter ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == days.length) return _Footer(pager: pager);
          return Padding(
            padding: EdgeInsets.only(top: i == 0 ? 4 : 22),
            child: _DaySection(label: days[i].label, entries: days[i].entries),
          );
        },
      ),
    );
  }
}

// ──────────────────────────── Footer (loading / partial-failure retry)

class _Footer extends ConsumerWidget {
  const _Footer({required this.pager});
  final CrossGroupActivityPagerState pager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (pager.isLoadingMore) {
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
    // Partial failure (#244 OR-drop): survivors are shown above; offer a retry
    // for the groups whose fetch threw.
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.space16),
      child: Column(
        children: [
          Text(
            context.l10n.activityPartialFailure,
            textAlign: TextAlign.center,
            style: AppTypography.sans(
              fontSize: 13,
              color: context.colors.textSecondary,
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(crossGroupActivityPagerProvider.notifier).retryFailed(),
            child: Text(context.l10n.activityReload),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────── Top bar

class _TopBar extends StatelessWidget {
  const _TopBar({required this.showBack});

  final bool showBack;

  // #666: top-level route entry. When /activity is the sole stack page
  // (canPop()==false), pop has nothing to return to — fall back to /home so
  // the user is never stranded. Mirrors ProfileScreen._back.
  void _back(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(AppRoutes.home);
      }
      return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        context.spacing.space20,
        context.spacing.space8,
        context.spacing.space20,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBack)
            RIconButton(
              variant: RIconButtonVariant.ghost,
              icon: Directionality.of(context) == TextDirection.rtl
                  ? Iconsax.arrow_right
                  : Iconsax.arrow_left,
              tooltip: context.l10n.commonBack,
              onTap: () => _back(context),
            )
          else
            const SizedBox(width: 40),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.activityTitle,
                  style: AppTypography.display(
                    fontSize: 28,
                    color: colors.textPrimary,
                    letterSpacing: -0.5,
                    height: 1.0,
                  ),
                ),
                SizedBox(height: context.spacing.space4),
                Text(
                  context.l10n.activitySubtitle,
                  style: AppTypography.sans(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 40),
        ],
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
    final labels = {
      _Filter.all: context.l10n.activityFilterAll,
      _Filter.settlements: context.l10n.activityFilterSettlements,
      _Filter.events: context.l10n.activityFilterEvents,
      _Filter.members: context.l10n.activityFilterMembers,
      _Filter.expenses: context.l10n.activityFilterExpenses,
    };
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
        children: [
          for (final entry in labels.entries) ...[
            _Chip(
              label: entry.value,
              active: current == entry.key,
              onTap: () => onChange(entry.key),
            ),
            SizedBox(width: context.spacing.space8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
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

// ──────────────────────────── Day section

class _DaySection extends StatelessWidget {
  const _DaySection({required this.label, required this.entries});
  final String label;
  final List<CrossGroupActivityEntry> entries;

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
                  entry: entries[i],
                  divider: i < entries.length - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────── Row

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry, required this.divider});
  final CrossGroupActivityEntry entry;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final log = entry.log;
    final description = localizedGroupActivityText(context.l10n, log);
    // #808 PR2: single chokepoint — legacy settlement `amount` OR the server
    // fan-in `amountFils`+`currency` shape (fils never through decimal-units).
    final amount = activityAmount(log, entry.currency);

    return InkWell(
      onTap: () => GoRouter.of(context).push('/group/${entry.groupId}'),
      child: Padding(
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
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
                      const SizedBox(height: 3),
                      Text(
                        entry.groupName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: context.spacing.space12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (amount != null)
                      RAmount(
                        value: amount.value,
                        // #382 PR-4: stamped settlement currency wins; legacy
                        // rows fall back to the entry's group currency. #808
                        // PR2: expense entries carry their own per-doc currency.
                        currency: amount.currency,
                        size: 14,
                      )
                    else
                      const SizedBox.shrink(),
                    SizedBox(height: amount != null ? 3 : 0),
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
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (bg, fg, icon) = switch (type) {
      'group_settlement' => (
        colors.cardSoft,
        colors.success,
        // Money/wallet glyph, not a navigation chevron (#160) — matches the
        // group activity feed and the settle-up total chip.
        Iconsax.wallet_3,
      ),
      'event_created' => (
        colors.saffronSoft,
        colors.primaryDark,
        Iconsax.calendar_1,
      ),
      'event_deleted' => (
        colors.cardSoft,
        colors.textSecondary,
        Iconsax.calendar_remove,
      ),
      'member_joined' => (colors.cardSoft, colors.cat2, Iconsax.user_add),
      'member_left' => (
        colors.cardSoft,
        colors.textSecondary,
        Iconsax.user_minus,
      ),
      // #808 PR2: expense fan-in entries (receipt family — a money glyph, not a
      // navigation chevron; parallels the settlement wallet glyph, #160).
      'expense_added' => (
        colors.saffronSoft,
        colors.primaryDark,
        Iconsax.receipt_add,
      ),
      'expense_edited' => (
        colors.cardSoft,
        colors.textSecondary,
        Iconsax.receipt_edit,
      ),
      'expense_deleted' => (
        colors.cardSoft,
        colors.textSecondary,
        Iconsax.receipt_minus,
      ),
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

bool _matchesFilter(String type, _Filter f) {
  return switch (f) {
    _Filter.all => true,
    _Filter.settlements => type == 'group_settlement',
    _Filter.events => type == 'event_created' || type == 'event_deleted',
    _Filter.members => type == 'member_joined' || type == 'member_left',
    _Filter.expenses => type.startsWith('expense_'),
  };
}

class _DayGroup {
  const _DayGroup({required this.label, required this.entries});
  final String label;
  final List<CrossGroupActivityEntry> entries;
}

List<_DayGroup> _groupByDay(
  BuildContext context,
  List<CrossGroupActivityEntry> entries,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final groups = <String, List<CrossGroupActivityEntry>>{};
  final order = <String>[];

  for (final e in entries) {
    final ts = e.log.timestamp;
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
    groups[label]!.add(e);
  }
  return [
    for (final label in order) _DayGroup(label: label, entries: groups[label]!),
  ];
}
