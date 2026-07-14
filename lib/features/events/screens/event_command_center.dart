import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/firestore_error_utils.dart';
import '../../../shared/widgets/directional_icon.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/no_access_view.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_icon_button.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../activity/screens/activity_feed_screen.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/models/settlement_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../ledger/providers/ledger_view_provider.dart';
import '../../ledger/screens/ledger_screen.dart';
import '../../ledger/screens/settle_up_screen.dart';
import '../../ledger/widgets/ledger_search_sheet.dart';
import '../keys/event_keys.dart';
import '../models/event_model.dart';
import '../providers/event_provider.dart';
import '../utils/event_display.dart';
import 'event_recap_screen.dart';

/// Tabbed event view (#758) — the event as one workspace.
///
/// Layout, top to bottom:
///   1. Compact paper header — back · title · compact amount (only while
///      collapsed) · search · settings.
///   2. Balance block + progress line — the current user's per-currency net
///      and open-event recap entry. Collapses on scroll into the title row.
///   3. Recap banner — closed events show the Trip Receipt entry (#708, a
///      Recap-tab switch).
///   4. Segmented tab bar: Expenses · Settle up · Activity (· Recap when the
///      event is closed, #202).
///   5. Tab panels — the standalone screens in `embedded` mode, hosted in a
///      lazily-built keep-alive IndexedStack (state survives tab switches;
///      the #204 review sheet fires on first Settle-tab activation).
///   6. Floating `+ Add expense` pill over the Expenses tab only (#1078;
///      hidden when closed).
///
/// The standalone routes (`…/ledger`, `…/ledger/settle-up`, `…/activity`,
/// `…/recap`) stay alive for deep links and render their full-chrome
/// versions; this screen embeds the same widgets as panels. Presentation
/// only — no route, money, or schema surface changes.
class EventCommandCenter extends ConsumerWidget {
  const EventCommandCenter({
    super.key,
    required this.groupId,
    required this.eventId,
    this.initialTab = EventTab.expenses,
  });

  final String groupId;
  final String eventId;

  /// PR-5 §4: seeds the hub's tab from the `?tab=` query param on cold
  /// landing (route-level redirects into `…/event/:eid?tab=…`). Query param
  /// only — nav data never travels via the router's opaque extra payload.
  final EventTab initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventAsync = ref.watch(
      eventDetailProvider((groupId: groupId, eventId: eventId)),
    );

    return Scaffold(
      key: EventKeys.screen,
      backgroundColor: context.colors.scaffoldBackground,
      body: eventAsync.when(
        loading: () => const _LoadingState(),
        error: (error, stackTrace) {
          // #1207 / #358: a removed member's event listen is permission-denied
          // forever — retrying just re-denies. Terminal no-access state with a
          // Home CTA; raw error goes to Sentry, not the UI.
          if (isPermissionDenied(error)) {
            unawaited(Sentry.captureException(error, stackTrace: stackTrace));
            return const NoAccessView();
          }
          return _ErrorState(
            onRetry: () => ref.invalidate(
              eventDetailProvider((groupId: groupId, eventId: eventId)),
            ),
          );
        },
        data: (event) {
          if (event == null) return const _NotFoundState();
          return _Content(
            event: event,
            groupId: groupId,
            eventId: eventId,
            initialTab: initialTab,
          );
        },
      ),
    );
  }
}

// ──────────────────────────── Tabs

/// Promoted from the file-private `_EventTab` (PR-5 §4) — zero external refs
/// before this change, so the rename is collision-free. Order matches the
/// [_LazyIndexedStack] panel order (`tab.index` indexes the panels).
enum EventTab {
  expenses,
  settleUp,
  activity,
  recap;

  /// Maps the hub's `?tab=` query param to a tab, EXPLICITLY:
  /// `expenses`/`activity`/`recap` map to themselves; `settleUp`, absent, or
  /// any unknown value falls back to Expenses — a cold `?tab=settleUp` must
  /// not fire the #204 settle-review sheet with no settle context.
  static EventTab fromQuery(String? value) {
    switch (value) {
      case 'expenses':
        return EventTab.expenses;
      case 'activity':
        return EventTab.activity;
      case 'recap':
        return EventTab.recap;
      default:
        return EventTab.expenses;
    }
  }
}

// ──────────────────────────── Content

class _Content extends ConsumerStatefulWidget {
  const _Content({
    required this.event,
    required this.groupId,
    required this.eventId,
    required this.initialTab,
  });

  final Event event;
  final String groupId;
  final String eventId;
  final EventTab initialTab;

  @override
  ConsumerState<_Content> createState() => _ContentState();
}

class _ContentState extends ConsumerState<_Content> {
  late EventTab _tab;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    // All producers `push` the hub URL (imperative pageKey) — no
    // `didUpdateWidget` path is needed; a warm in-app push with a different
    // `?tab=` stacks a second hub instance instead (known + accepted).
    _tab = widget.initialTab;
  }

  void _selectTab(EventTab tab) {
    if (tab == _tab) return;
    HapticService.lightClick();
    setState(() {
      _tab = tab;
      // Mockup contract: a tab switch re-expands the balance header.
      _collapsed = false;
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final collapsed = n.metrics.pixels > 24;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final currentUid = ref.watch(currentUserIdProvider);
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
    // #631: the header shares the ledger's memoized balance pass — no second
    // BalanceCalculator run.
    final view = ref.watch(ledgerViewProvider(eventRef));

    final expenses = expensesAsync.valueOrNull ?? const <Expense>[];
    // #382 PR-5: one line per currency bucket — currencies never net against
    // each other, so the header renders per-currency lines and "settled"
    // means settled in all of them.
    final myLines = nonZeroNetsGccFirst(
      myNetByCurrency(view.balances, currentUid),
    );
    // #1028: a hard-errored source stream means view.balances was computed
    // WITHOUT that stream's folds — wrong nets, not just false-settled. Gate
    // the streams with the #1005 hard-error pattern (hasError && !hasValue:
    // a stale-but-valid value keeps rendering; the ledger panel below owns
    // the loud Reload affordance). Same !hasValue vocabulary for the
    // first-value window, which otherwise renders a false "Nothing to
    // settle yet". #1030: members joins both gates — ledgerViewProvider
    // folds it too, and a members-less #249 universe is WRONG nets, not
    // fewer nets.
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));
    final balanceUnavailable =
        (expensesAsync.hasError && !expensesAsync.hasValue) ||
        (settlementsAsync.hasError && !settlementsAsync.hasValue) ||
        (membersAsync.hasError && !membersAsync.hasValue);
    final balancePending =
        !balanceUnavailable &&
        ((expensesAsync.isLoading && !expensesAsync.hasValue) ||
            (settlementsAsync.isLoading && !settlementsAsync.hasValue) ||
            (membersAsync.isLoading && !membersAsync.hasValue));
    final state = balanceUnavailable
        ? _HubState.unavailable
        : balancePending
        ? _HubState.pending
        : _resolveState(hasExpenses: expenses.isNotEmpty, lines: myLines);

    final showRecap = event.isClosed;
    // The Recap tab exists only while closed; if the event reopens under a
    // recap-active screen, fall back to Expenses.
    final tab = (!showRecap && _tab == EventTab.recap)
        ? EventTab.expenses
        : _tab;

    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              _EventHeader(
                event: event,
                collapsed: _collapsed,
                state: state,
                lines: myLines,
                hasExpenses: expenses.isNotEmpty,
                onBack: () {
                  HapticService.lightClick();
                  // Nested route (#243/#996): a bare pop reaches the group
                  // because every entry either navigates from it, `go`es the
                  // full location (materializing the ancestor), or — for the
                  // §2 smart-forward — imperatively pushes /group/:gid first.
                  // Imperative push alone does NOT materialize ancestors.
                  if (GoRouter.of(context).canPop()) {
                    GoRouter.of(context).pop();
                  }
                },
                onSearch: () => _openSearch(
                  context,
                  view,
                  expenses,
                  settlementsAsync.valueOrNull ?? const <Settlement>[],
                ),
                onSettings: () {
                  HapticService.lightClick();
                  GoRouter.of(context).push(
                    '/group/${widget.groupId}/event/${widget.eventId}/settings',
                  );
                },
                onViewRecap: () {
                  HapticService.lightClick();
                  GoRouter.of(context).push(
                    '/group/${widget.groupId}/event/${widget.eventId}/recap',
                  );
                },
              ),
              // Recap entry (#723 / #708). Closed: read-only banner whose
              // Trip Receipt entry switches to the Recap tab.
              if (event.isClosed)
                _ClosedBanner(
                  closedByName: event.closedBy == null
                      ? null
                      : (view.rosterDisplayNames[event.closedBy] ??
                            event.participantNames[event.closedBy]),
                  onViewReceipt: expenses.isEmpty
                      ? null
                      : () {
                          HapticService.lightClick();
                          _selectTab(EventTab.recap);
                        },
                ),
              const OfflineBanner(),
              _EventTabBar(
                active: tab,
                showRecap: showRecap,
                onSelect: _selectTab,
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: _LazyIndexedStack(
                    index: tab.index,
                    children: [
                      LedgerScreen(
                        groupId: widget.groupId,
                        eventId: widget.eventId,
                      ),
                      SettleUpScreen(
                        groupId: widget.groupId,
                        eventId: widget.eventId,
                        embedded: true,
                      ),
                      ActivityFeedScreen(
                        groupId: widget.groupId,
                        eventId: widget.eventId,
                      ),
                      if (showRecap)
                        EventRecapScreen(
                          groupId: widget.groupId,
                          eventId: widget.eventId,
                          embedded: true,
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // #723: spending is frozen on a closed event — no add affordance.
          // #1078: the pill overlays only its own panel — on Settle up /
          // Activity / Recap it was a mis-tap trap sitting on money controls
          // (Mark-received) at the rest scroll position.
          if (!event.isClosed && tab == EventTab.expenses)
            PositionedDirectional(
              end: 16,
              bottom: 16,
              child: _AddExpenseFab(
                onTap: () {
                  HapticService.lightClick();
                  GoRouter.of(context).push(
                    '/group/${widget.groupId}/event/${widget.eventId}/ledger/add',
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _openSearch(
    BuildContext context,
    LedgerView view,
    List<Expense> expenses,
    List<Settlement> settlements,
  ) {
    HapticService.lightClick();
    // Restore the l10n fallbacks the provider defers (same pass as the
    // standalone ledger body).
    final settlementDisplayNames =
        <String, ({String payerName, String recipientName})>{
          for (final entry in view.settlementDisplayNames.entries)
            entry.key: (
              payerName: entry.value.payerName ?? context.l10n.ledgerSomeone,
              recipientName:
                  entry.value.recipientName ?? context.l10n.ledgerSomeoneLower,
            ),
        };
    showLedgerSearchSheet(
      context,
      expenses: expenses,
      settlements: settlements,
      expensePayerDisplayNames: view.expensePayerDisplayNames,
      settlementDisplayNames: settlementDisplayNames,
      groupId: widget.groupId,
      eventId: widget.eventId,
    );
  }
}

// ──────────────────────────── State machine

enum _HubState { empty, settled, youOwed, youOwe, mixed, pending, unavailable }

/// Settled ⇔ EVERY currency bucket nets exactly zero. Deliberate threshold
/// change (#382 PR-5, L13): this replaces `UserBalance.isSettled`'s 0.001
/// tolerance with the helpers' exact-zero predicate — the header's settled
/// gate TIGHTENS, so a sub-tolerance residual renders instead of silently
/// reading as settled (the calculator closes remainders, so one shouldn't
/// exist). Mixed signs across buckets have no honest single overline →
/// [_HubState.mixed].
_HubState _resolveState({
  required bool hasExpenses,
  required List<({String currency, Decimal net})> lines,
}) {
  if (!hasExpenses) return _HubState.empty;
  if (lines.isEmpty) return _HubState.settled;
  if (lines.every((l) => l.net > Decimal.zero)) return _HubState.youOwed;
  if (lines.every((l) => l.net < Decimal.zero)) return _HubState.youOwe;
  return _HubState.mixed;
}

// ──────────────────────────── Header

class _EventHeader extends StatelessWidget {
  const _EventHeader({
    required this.event,
    required this.collapsed,
    required this.state,
    required this.lines,
    required this.hasExpenses,
    required this.onBack,
    required this.onSearch,
    required this.onSettings,
    required this.onViewRecap,
  });

  final Event event;
  final bool collapsed;
  final _HubState state;
  final List<({String currency, Decimal net})> lines;
  final bool hasExpenses;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final VoidCallback onViewRecap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // #789: "Day N of M" for a live, multi-day trip — suppressed once closed.
    final day = event.isClosed
        ? null
        : liveTripDay(event.startDate, event.endDate, DateTime.now());
    final dayLabel = day == null
        ? null
        : context.l10n.eventDayOf(day.currentDay, day.totalDays);
    final showRecapLink = !event.isClosed && hasExpenses;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 0),
          child: Row(
            children: [
              RIconButton(
                icon: Iconsax.arrow_left,
                matchTextDirection: true,
                semanticLabel: context.l10n.commonBack,
                onTap: onBack,
              ),
              SizedBox(width: context.spacing.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.displayOf(
                        context,
                        fontSize: 20,
                        color: colors.textPrimary,
                        height: 1.1,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              // #1028: under unavailable/pending the lines may be non-empty
              // WRONG nets (ledgerViewProvider folds an errored stream to
              // []) — never render them compactly either.
              if (collapsed &&
                  lines.isNotEmpty &&
                  state != _HubState.unavailable &&
                  state != _HubState.pending)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6, end: 2),
                  child: _CompactAmounts(lines: lines),
                ),
              RIconButton(
                key: EventKeys.searchButton,
                icon: Iconsax.search_normal,
                tooltip: context.l10n.ledgerSearchExpensesTooltip,
                onTap: onSearch,
              ),
              RIconButton(
                key: EventKeys.settingsButton,
                icon: Iconsax.setting_2,
                semanticLabel: context.l10n.ledgerEventSettingsTooltip,
                onTap: onSettings,
              ),
            ],
          ),
        ),
        // The balance block collapses on scroll, handing the list its space
        // back; the compact amount above stands in while collapsed.
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: AlignmentDirectional.topCenter,
            child: collapsed
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      20,
                      10,
                      20,
                      4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _BalanceBlock(state: state, lines: lines),
                        const SizedBox(height: 6),
                        _TripProgressLine(
                          dayLabel: dayLabel,
                          showRecap: showRecapLink,
                          onViewRecap: onViewRecap,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Small per-currency amounts shown beside the title while collapsed.
class _CompactAmounts extends StatelessWidget {
  const _CompactAmounts({required this.lines});

  final List<({String currency, Decimal net})> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: EventKeys.headerCompactAmount,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in lines)
          RAmount(
            value: line.net,
            currency: line.currency,
            size: 12,
            weight: FontWeight.w700,
            sign: true,
            tone: line.net > Decimal.zero ? AmountTone.sage : AmountTone.rust,
          ),
      ],
    );
  }
}

/// The expanded per-currency balance display — reuses the hub's copy and
/// state machine (empty / settled / uniform-owed / uniform-owe / mixed).
class _BalanceBlock extends StatelessWidget {
  const _BalanceBlock({required this.state, required this.lines});

  final _HubState state;
  final List<({String currency, Decimal net})> lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isOwed = state == _HubState.youOwed;
    final label = switch (state) {
      _HubState.youOwed => context.l10n.eventYouAreOwed,
      _HubState.youOwe => context.l10n.eventYouOwe,
      _HubState.mixed => context.l10n.eventYourBalance,
      _ => null,
    };

    return Column(
      key: EventKeys.balanceHeader,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text(
            label,
            style: AppTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          SizedBox(height: context.spacing.space4),
        ],
        // #1028: unavailable/pending render FIRST — with empty lines they
        // would otherwise fall through to the lines else-branch (empty
        // column), and with wrong non-empty lines they must never render.
        if (state == _HubState.unavailable)
          Row(
            key: EventKeys.balanceHeaderUnavailable,
            children: [
              Icon(Iconsax.warning_2, size: 16, color: colors.warning),
              SizedBox(width: context.spacing.space8),
              Text(
                context.l10n.homeBalanceUnavailable,
                style: AppTypography.displayOf(
                  context,
                  fontSize: 20,
                  color: colors.textSecondary,
                  height: 1.05,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          )
        else if (state == _HubState.pending)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: KeyedSubtree(
              key: EventKeys.balanceHeaderPending,
              child: SkeletonLoader.trailingBalance(),
            ),
          )
        else if (state == _HubState.empty || state == _HubState.settled)
          Text(
            state == _HubState.settled
                ? context.l10n.eventAllSettled
                : context.l10n.eventNothingToSettleYet,
            style: AppTypography.displayOf(
              context,
              fontSize: 26,
              color: state == _HubState.settled
                  ? colors.successText
                  : colors.textSecondary,
              height: 1.05,
              letterSpacing: -0.3,
            ),
          )
        else if (lines.length == 1)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: RAmount(
              value: lines.first.net.abs(),
              currency: lines.first.currency,
              size: 34,
              weight: FontWeight.w800,
              sign: true,
              tone: isOwed ? AmountTone.sage : AmountTone.rust,
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines.length; i++)
                Padding(
                  padding: EdgeInsetsDirectional.only(top: i == 0 ? 0 : 2),
                  child: RAmount(
                    value: lines[i].net,
                    currency: lines[i].currency,
                    size: 26,
                    weight: FontWeight.w800,
                    sign: true,
                    tone: lines[i].net > Decimal.zero
                        ? AmountTone.sage
                        : AmountTone.rust,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// #811: open-event progress line that keeps the recap labelled and tappable.
/// The outer key can also mark a day-only line; the InkWell key is the recap
/// affordance proof.
class _TripProgressLine extends StatelessWidget {
  const _TripProgressLine({
    required this.dayLabel,
    required this.showRecap,
    required this.onViewRecap,
  });

  final String? dayLabel;
  final bool showRecap;
  final VoidCallback onViewRecap;

  @override
  Widget build(BuildContext context) {
    if (dayLabel == null && !showRecap) return const SizedBox.shrink();

    final colors = context.colors;
    final text = [
      ?dayLabel,
      if (showRecap) context.l10n.eventViewReceipt,
    ].join(' · ');
    final row = Row(
      children: [
        if (showRecap) ...[
          Icon(Iconsax.cup, size: 14, color: colors.textSecondary),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
        if (showRecap) ...[
          const SizedBox(width: 4),
          DirectionalIcon(Iconsax.arrow_right, size: 14, color: colors.primary),
        ],
      ],
    );

    if (!showRecap) {
      return Align(
        key: EventKeys.openRecapBanner,
        alignment: AlignmentDirectional.centerStart,
        child: row,
      );
    }

    return Align(
      key: EventKeys.openRecapBanner,
      alignment: AlignmentDirectional.centerStart,
      child: InkWell(
        key: EventKeys.openRecapBannerViewRecap,
        onTap: onViewRecap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(alignment: AlignmentDirectional.centerStart, child: row),
        ),
      ),
    );
  }
}

// ──────────────────────────── Tab bar

class _EventTabBar extends StatelessWidget {
  const _EventTabBar({
    required this.active,
    required this.showRecap,
    required this.onSelect,
  });

  final EventTab active;
  final bool showRecap;
  final ValueChanged<EventTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tabs = <({EventTab tab, Key key, String label})>[
      (
        tab: EventTab.expenses,
        key: EventKeys.tabExpenses,
        label: context.l10n.eventTabExpenses,
      ),
      (
        tab: EventTab.settleUp,
        key: EventKeys.tabSettleUp,
        label: context.l10n.eventTabSettleUp,
      ),
      (
        tab: EventTab.activity,
        key: EventKeys.tabActivity,
        label: context.l10n.eventTabActivity,
      ),
      if (showRecap)
        (
          tab: EventTab.recap,
          key: EventKeys.tabRecap,
          label: context.l10n.eventTabRecap,
        ),
    ];

    return Container(
      key: EventKeys.tabBar,
      height: 44,
      margin: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 10),
      // #1067 §4: the Stack separates the 44dp hit layer from the compact
      // painted track. The old 3dp inset remains visual, not a hit constraint.
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            top: 3,
            bottom: 3,
            child: DecoratedBox(
              key: const Key('event_tab_bar_track'),
              decoration: BoxDecoration(
                color: colors.cardSoft,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colors.border, width: 0.5),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Row(
              children: [
                for (final t in tabs)
                  Expanded(
                    child: _TabButton(
                      key: t.key,
                      label: t.label,
                      active: t.tab == active,
                      onTap: () => onSelect(t.tab),
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

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // #1067 §4: the opaque hit box reaches 44dp while the full-width
        // painted pill stays at its deliberately compact intrinsic height.
        child: SizedBox(
          height: 44,
          child: Center(
            child: SizedBox(
              width: double.infinity,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? colors.cardSurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: active ? context.shadows.raised : null,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────── Lazy keep-alive stack

/// IndexedStack that builds each child on FIRST activation and keeps it alive
/// afterwards — panel state (activity pagination, ledger filter, the #204
/// once-per-entry review sheet guard) survives tab switches, while inactive
/// never-visited panels cost nothing.
class _LazyIndexedStack extends StatefulWidget {
  const _LazyIndexedStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<_LazyIndexedStack> {
  final Set<int> _built = {};

  @override
  Widget build(BuildContext context) {
    _built.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          if (_built.contains(i))
            widget.children[i]
          else
            const SizedBox.shrink(),
      ],
    );
  }
}

// ──────────────────────────── Add-expense FAB

class _AddExpenseFab extends StatelessWidget {
  const _AddExpenseFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: EventKeys.addExpenseFab,
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [colors.primary, colors.primaryDark],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: context.shadows.floating,
          ),
          padding: const EdgeInsetsDirectional.fromSTEB(16, 13, 18, 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Iconsax.add, size: 18, color: colors.textOnPrimary),
              const SizedBox(width: 6),
              Text(
                context.l10n.eventAddExpense,
                style: AppTypography.sans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
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

// ──────────────────────────── Closed banner (#723 / #708)

class _ClosedBanner extends StatelessWidget {
  const _ClosedBanner({this.closedByName, this.onViewReceipt});

  final String? closedByName;

  /// #708 close-wiring: opens the shareable Trip Receipt — now a switch to
  /// the Recap tab. Null hides the affordance when there is nothing to
  /// export.
  final VoidCallback? onViewReceipt;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = closedByName;
    final text = (name != null && name.isNotEmpty)
        ? context.l10n.eventClosedBannerBy(name)
        : context.l10n.eventClosedBanner;
    return Container(
      key: EventKeys.closedBanner,
      width: double.infinity,
      color: colors.textPrimary.withValues(alpha: 0.04),
      padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 10),
      child: Row(
        children: [
          Icon(Iconsax.lock, size: 14, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTypography.sans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
          if (onViewReceipt != null) ...[
            const SizedBox(width: 8),
            InkWell(
              key: EventKeys.closedBannerViewReceipt,
              onTap: onViewReceipt,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 4, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.eventViewReceipt,
                      style: AppTypography.sans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 3),
                    DirectionalIcon(
                      Iconsax.arrow_right,
                      size: 13,
                      color: colors.textPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────── States

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return SafeArea(child: SkeletonLoader.generic(count: 3));
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
          padding: EdgeInsets.all(context.spacing.space24),
          child: EmptyStateView(
            icon: Iconsax.warning_2,
            title: context.l10n.eventLoadFailedTitle,
            message: context.l10n.activityLoadFailedMessage,
            actionLabel: context.l10n.commonRetry,
            onAction: onRetry,
          ),
        ),
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  const _NotFoundState();
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(context.spacing.space24),
          child: EmptyStateView(
            icon: Iconsax.box_remove,
            title: context.l10n.eventNotFound,
            message: context.l10n.eventMissingMessage,
            actionLabel: context.l10n.commonGoHome,
            onAction: () => GoRouter.of(context).go('/home'),
          ),
        ),
      ),
    );
  }
}

