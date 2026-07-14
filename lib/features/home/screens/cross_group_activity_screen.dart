import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/day_grouping.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../activity/keys/activity_keys.dart';
import '../../activity/utils/activity_display.dart';
import '../../activity/utils/activity_nav.dart';
import '../../groups/providers/group_provider.dart';
import '../../../shared/widgets/activity_day_section.dart';
import '../../../shared/widgets/activity_filter_strip.dart';
import '../../../shared/widgets/activity_row.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/paper_backdrop.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_icon_button.dart';
import '../../../shared/widgets/scroll_under_header.dart';
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

  // #808 PR3: inline search over the loaded pages. `_searching` toggles the
  // field; `_query` (trimmed) narrows the visible rows and drives the honest
  // "search older activity" affordance.
  bool _searching = false;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocus;
  String _query = '';

  // #1063: the live unread feed may get ahead of the deliberately one-shot
  // pager. Reconcile that disagreement at most once per mounted screen; manual
  // pull-to-refresh remains the ongoing refresh mechanism (D-PR2-3).
  bool _didAttemptLiveEmptyRefresh = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _searchController = TextEditingController()..addListener(_onQueryChanged);
    _searchFocus = FocusNode();
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
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      ref.read(crossGroupActivityPagerProvider.notifier).loadMore();
    }
  }

  void _onQueryChanged() {
    final next = _searchController.text.trim();
    if (next != _query) setState(() => _query = next);
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _query = '';
      }
    });
    if (_searching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  bool _isInitialisedTrueEmpty(CrossGroupActivityPagerState pager) =>
      pager.initialised &&
      !pager.isLoadingMore &&
      pager.entries.isEmpty &&
      !pager.firstLoadFailed &&
      !pager.partialFailure;

  void _maybeReconcileLiveActivity(CrossGroupActivityPagerState pager) {
    if (_didAttemptLiveEmptyRefresh || !_isInitialisedTrueEmpty(pager)) {
      return;
    }

    final liveEntries = ref.watch(crossGroupActivityProvider).valueOrNull;
    if (liveEntries == null || liveEntries.isEmpty) return;

    _didAttemptLiveEmptyRefresh = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentPager = ref.read(crossGroupActivityPagerProvider);
      final currentLiveEntries = ref
          .read(crossGroupActivityProvider)
          .valueOrNull;
      if (_isInitialisedTrueEmpty(currentPager) &&
          currentLiveEntries != null &&
          currentLiveEntries.isNotEmpty) {
        ref.read(crossGroupActivityPagerProvider.notifier).refresh();
      }
    });
  }

  Widget _withRefresh(Widget child) => RefreshIndicator(
    onRefresh: () =>
        ref.read(crossGroupActivityPagerProvider.notifier).refresh(),
    child: child,
  );

  // #634: memoize the visible list. `entries` is append-only within a load, so
  // its length uniquely identifies its content; recompute only when the list
  // grows, the filter changes, the query changes, or the locale changes — not
  // on every rebuild. Query AND the type chip both apply (#808 PR3).
  List<CrossGroupActivityEntry>? _visibleCache;
  int _visibleCacheLen = -1;
  _Filter? _visibleCacheFilter;
  String _visibleCacheQuery = '';
  String? _visibleCacheLocale;

  List<CrossGroupActivityEntry> _visible(
    List<CrossGroupActivityEntry> entries,
    AppLocalizations l10n,
  ) {
    if (_visibleCache != null &&
        _visibleCacheLen == entries.length &&
        _visibleCacheFilter == _filter &&
        _visibleCacheQuery == _query &&
        _visibleCacheLocale == l10n.localeName) {
      return _visibleCache!;
    }
    final result = entries
        .where(
          (e) =>
              _matchesFilter(e.log.type, _filter) &&
              activityMatchesQuery(e, _query, l10n),
        )
        .toList();
    _visibleCache = result;
    _visibleCacheLen = entries.length;
    _visibleCacheFilter = _filter;
    _visibleCacheQuery = _query;
    _visibleCacheLocale = l10n.localeName;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final pager = ref.watch(crossGroupActivityPagerProvider);
    _maybeReconcileLiveActivity(pager);
    return Scaffold(
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: PaperBackdrop(
          // #1011: shared scroll-edge hairline under the fixed header cluster
          // (top bar + optional search + filter strip) once the feed scrolls.
          child: ScrollUnderHeader(
            header: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TopBar(
                  showBack: widget.showBack,
                  showSearch: pager.entries.isNotEmpty,
                  searching: _searching,
                  onToggleSearch: _toggleSearch,
                ),
                const OfflineBanner(),
                const SizedBox(height: 6),
                if (_searching) ...[
                  _SearchField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                  ),
                  SizedBox(height: context.spacing.space8),
                ],
                ActivityFilterStrip<_Filter>(
                  current: _filter,
                  onChange: (f) => setState(() => _filter = f),
                  options: [
                    ActivityFilterOption(
                      value: _Filter.all,
                      label: context.l10n.activityFilterAll,
                    ),
                    ActivityFilterOption(
                      value: _Filter.settlements,
                      label: context.l10n.activityFilterSettlements,
                    ),
                    ActivityFilterOption(
                      value: _Filter.events,
                      label: context.l10n.activityFilterEvents,
                    ),
                    ActivityFilterOption(
                      value: _Filter.members,
                      label: context.l10n.activityFilterMembers,
                    ),
                    ActivityFilterOption(
                      value: _Filter.expenses,
                      label: context.l10n.activityFilterExpenses,
                    ),
                  ],
                ),
                SizedBox(height: context.spacing.space8),
              ],
            ),
            child: _buildBody(context, pager),
          ),
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

    final querying = _query.isNotEmpty;
    final visible = _visible(pager.entries, context.l10n);
    if (visible.isEmpty) {
      // #808 PR3: a live query that matches none of the LOADED entries is its
      // own state — honest "no matches" with a "search older activity" action
      // while more pages remain. (True-empty and filter-empty are handled below
      // with the #807 add-expense CTA / plain filter copy.)
      if (querying && pager.entries.isNotEmpty) {
        final canLoadMore = pager.hasMore;
        return _withRefresh(
          EmptyStateView(
            icon: Iconsax.search_normal,
            title: context.l10n.activitySearchNoMatchesTitle,
            message: context.l10n.activitySearchNoMatchesMessage(_query),
            actionLabel: canLoadMore ? context.l10n.activitySearchOlder : null,
            onAction: canLoadMore
                ? () => ref
                      .read(crossGroupActivityPagerProvider.notifier)
                      .loadMore()
                : null,
            physics: const AlwaysScrollableScrollPhysics(),
          ),
        );
      }
      final isTrueEmpty = pager.entries.isEmpty;
      // #807: only offer the add-expense CTA on the true no-activity state and
      // only when the user has a group. Zero groups → NO CTA (never a duplicate
      // create-group affordance).
      final groups = ref.watch(userGroupsProvider).valueOrNull;
      final showCta = isTrueEmpty && groups != null && groups.isNotEmpty;
      return _withRefresh(
        EmptyStateView(
          icon: Iconsax.activity,
          title: isTrueEmpty
              ? context.l10n.activityNoActivityTitle
              : context.l10n.activityNoFilterTitle,
          message: isTrueEmpty
              ? context.l10n.activityCrossGroupEmptyMessage
              : context.l10n.activityNoFilterMessage,
          actionLabel: showCta ? context.l10n.ledgerAddExpense : null,
          onAction: showCta ? () => AddExpenseTargetSheet.show(context) : null,
          physics: const AlwaysScrollableScrollPhysics(),
        ),
      );
    }

    final days = groupByDay<CrossGroupActivityEntry>(
      context,
      visible,
      DateTime.now(),
      (e) => e.log.timestamp,
    );
    // While a query is active and more pages remain, the footer offers an
    // explicit "search older activity" pull (#808 PR3) — in addition to the
    // scroll-near-bottom auto-prefetch.
    final showSearchOlder =
        querying && pager.hasMore && !pager.isLoadingMore && !pager.partialFailure;
    final showFooter =
        pager.isLoadingMore || pager.partialFailure || showSearchOlder;
    return _withRefresh(
      ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        // Bottom inset clears the tab-shell add-expense FAB (#364).
        padding: EdgeInsetsDirectional.fromSTEB(
          context.spacing.space20,
          context.spacing.space4,
          context.spacing.space20,
          96,
        ),
        itemCount: days.length + (showFooter ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == days.length) {
            return _Footer(
              pager: pager,
              searching: querying,
              loadedCount: pager.entries.length,
            );
          }
          return Padding(
            padding: EdgeInsets.only(top: i == 0 ? 4 : 22),
            child: ActivityDaySection(
              label: days[i].label,
              dateSuffix: days[i].dateSuffix,
              raised: true,
              children: _buildRows(context, days[i].entries),
            ),
          );
        },
      ),
    );
  }
}

// ──────────────────────────── Footer (loading / partial-failure retry)

class _Footer extends ConsumerWidget {
  const _Footer({
    required this.pager,
    this.searching = false,
    this.loadedCount = 0,
  });
  final CrossGroupActivityPagerState pager;

  /// A query is active — offer an explicit "search older activity" pull.
  final bool searching;

  /// Count of loaded entries the query has already searched (footer copy).
  final int loadedCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (pager.isLoadingMore) {
      return SkeletonLoader.expenseList(count: 1);
    }
    if (pager.partialFailure) {
      // Partial failure (#244 OR-drop): survivors are shown above; offer a
      // retry for the groups whose fetch threw.
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
              onPressed: () => ref
                  .read(crossGroupActivityPagerProvider.notifier)
                  .retryFailed(),
              child: Text(context.l10n.activityReload),
            ),
          ],
        ),
      );
    }
    // #808 PR3: query active + more pages remain — surface how many loaded
    // entries were searched and a button to pull older pages through the pager.
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.space16),
      child: Column(
        children: [
          Text(
            context.l10n.activitySearchLoadedCount(loadedCount),
            textAlign: TextAlign.center,
            style: AppTypography.sans(
              fontSize: 13,
              color: context.colors.textSecondary,
            ),
          ),
          TextButton(
            key: ActivityKeys.searchOlderButton,
            onPressed: () =>
                ref.read(crossGroupActivityPagerProvider.notifier).loadMore(),
            child: Text(context.l10n.activitySearchOlder),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────── Top bar

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.showBack,
    required this.showSearch,
    required this.searching,
    required this.onToggleSearch,
  });

  final bool showBack;

  /// Whether the search toggle is offered (only once the feed has entries).
  final bool showSearch;

  /// Whether the inline search field is currently open (swaps the glyph).
  final bool searching;
  final VoidCallback onToggleSearch;

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
              icon: Iconsax.arrow_left,
              matchTextDirection: true,
              tooltip: context.l10n.commonBack,
              onTap: () => _back(context),
            )
          else
            // #1041: matches the ghost RIconButton's 44dp hit width so the
            // title column doesn't shift when showBack/showSearch toggle.
            const SizedBox(width: 44),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.historyTabTitle,
                  style: AppTypography.displayOf(
                    context,
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
          if (showSearch)
            RIconButton(
              key: ActivityKeys.searchToggle,
              variant: RIconButtonVariant.ghost,
              icon: searching ? Iconsax.close_circle : Iconsax.search_normal,
              tooltip: searching
                  ? context.l10n.activitySearchClose
                  : context.l10n.activitySearchTooltip,
              onTap: onToggleSearch,
            )
          else
            // #1041: matches the ghost RIconButton's 44dp hit width so the
            // title column doesn't shift when showBack/showSearch toggle.
            const SizedBox(width: 44),
        ],
      ),
    );
  }
}

// ──────────────────────────── Inline search field

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

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
      child: Container(
        decoration: BoxDecoration(
          color: colors.inputFill,
          borderRadius: BorderRadius.circular(context.spacing.radiusInput),
        ),
        padding: EdgeInsets.symmetric(horizontal: context.spacing.space12),
        child: Row(
          children: [
            Icon(
              Iconsax.search_normal,
              size: 18,
              color: colors.textSecondary,
            ),
            SizedBox(width: context.spacing.space8),
            Expanded(
              child: TextField(
                key: ActivityKeys.searchField,
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: context.l10n.activitySearchHint,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                style: AppTypography.sans(
                  fontSize: 15,
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: controller.clear,
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  Iconsax.close_circle,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────── Rows

/// Builds one day's rows onto the shared [ActivityRow] — group context as the
/// bordered tag chip (D-b); `showCurrency` stays always-on here (unchanged
/// from today), unlike the group timeline's foreign-currency-only label.
List<Widget> _buildRows(
  BuildContext context,
  List<CrossGroupActivityEntry> entries,
) {
  return [
    for (var i = 0; i < entries.length; i++)
      _buildRow(context, entries[i], i < entries.length - 1),
  ];
}

Widget _buildRow(
  BuildContext context,
  CrossGroupActivityEntry entry,
  bool divider,
) {
  final log = entry.log;
  // #808 PR2: single chokepoint — legacy settlement `amount` OR the server
  // fan-in `amountFils`+`currency` shape (fils never through decimal-units).
  final amount = activityAmount(log, entry.currency);

  return ActivityRow(
    glyph: glyphForGroupActivityType(log.type),
    actorName: log.actorName,
    description: localizedGroupActivityText(context.l10n, log),
    timestamp: log.timestamp,
    groupName: entry.groupName,
    trailingAmount: amount == null
        ? null
        : RAmount(
            // #382 PR-4: stamped settlement currency wins; legacy rows fall
            // back to the entry's group currency. #808 PR2: expense entries
            // carry their own per-doc currency.
            value: amount.value,
            currency: amount.currency,
            size: 14,
          ),
    divider: divider,
    onTap: () => GoRouter.of(context)
        .push(activityRowTarget(groupId: entry.groupId, log: entry.log)),
  );
}

// ──────────────────────────── Helpers

bool _matchesFilter(String type, _Filter f) {
  return switch (f) {
    _Filter.all => true,
    _Filter.settlements =>
      type == 'group_settlement' || type == 'event_settlement',
    _Filter.events => type == 'event_created' || type == 'event_deleted',
    _Filter.members =>
      type == 'member_joined' ||
      type == 'member_left' ||
      type == 'member_resplit',
    _Filter.expenses => type.startsWith('expense_'),
  };
}
