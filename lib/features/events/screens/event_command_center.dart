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
import '../../../shared/widgets/directional_icon.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_icon_button.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../activity/screens/activity_feed_screen.dart';
import '../../groups/providers/group_balance_provider.dart';
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
///   1. Compact paper header — back · eyebrow (type · dates) + title ·
///      compact amount (only while collapsed) · search · settings.
///   2. Balance block — the current user's per-currency net (reuses the hub
///      state machine: empty / settled / youOwed / youOwe / mixed). Collapses
///      on scroll into the title row.
///   3. Recap banner — closed events show the Trip Receipt entry (#708, a
///      Recap-tab switch); open events with expenses show a labelled recap
///      entry (#811, replaced the tooltip-only header cup).
///   4. Segmented tab bar: Expenses · Settle up · Activity (· Recap when the
///      event is closed, #202).
///   5. Tab panels — the standalone screens in `embedded` mode, hosted in a
///      lazily-built keep-alive IndexedStack (state survives tab switches;
///      the #204 review sheet fires on first Settle-tab activation).
///   6. Floating `+ Add expense` pill over every tab (hidden when closed).
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
        error: (_, _) => _ErrorState(
          onRetry: () => ref.invalidate(
            eventDetailProvider((groupId: groupId, eventId: eventId)),
          ),
        ),
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
    final state = _resolveState(
      hasExpenses: expenses.isNotEmpty,
      lines: myLines,
    );

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
                onBack: () {
                  HapticService.lightClick();
                  // Nested route (#243): ancestors are materialized on any
                  // nav, so a bare pop always reaches the group.
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
              ),
              // Recap entry (#723 / #708 / #811). Closed: read-only banner whose
              // Trip Receipt entry switches to the Recap tab. Open + has
              // expenses: a labelled recap entry that pushes the recap route
              // (replaced the tooltip-only header cup — weak touch scent).
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
                )
              else if (expenses.isNotEmpty)
                _OpenRecapBanner(
                  onViewRecap: () {
                    HapticService.lightClick();
                    GoRouter.of(context).push(
                      '/group/${widget.groupId}/event/${widget.eventId}/recap',
                    );
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
          if (!event.isClosed)
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

enum _HubState { empty, settled, youOwed, youOwe, mixed }

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
    required this.onBack,
    required this.onSearch,
    required this.onSettings,
  });

  final Event event;
  final bool collapsed;
  final _HubState state;
  final List<({String currency, Decimal net})> lines;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dateRange = _formatDateRange(context, event.startDate, event.endDate);
    // #789: "Day N of M" for a live, multi-day trip — suppressed once closed.
    final day = event.isClosed
        ? null
        : liveTripDay(event.startDate, event.endDate, DateTime.now());
    final dayLabel = day == null
        ? null
        : context.l10n.eventDayOf(day.currentDay, day.totalDays);
    final eyebrow = [
      event.type.localizedShortLabel(context.l10n),
      ?dateRange,
      ?dayLabel,
    ].join(' · ');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 0),
          child: Row(
            children: [
              RIconButton(
                icon: Directionality.of(context) == TextDirection.rtl
                    ? Iconsax.arrow_right
                    : Iconsax.arrow_left,
                semanticLabel: context.l10n.commonBack,
                onTap: onBack,
              ),
              SizedBox(width: context.spacing.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption(
                        context,
                        fontSize: 9,
                        color: colors.primaryDark,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      event.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.displayOf(
                        context,
                        fontSize: 18,
                        color: colors.textPrimary,
                        height: 1.1,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (collapsed && lines.isNotEmpty)
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
                    child: _BalanceBlock(state: state, lines: lines),
                  ),
          ),
        ),
      ],
    );
  }

  static String? _formatDateRange(
    BuildContext context,
    DateTime? start,
    DateTime? end,
  ) {
    if (start == null && end == null) return null;
    if (start == null) return formatShortMonthDay(context, end!);
    if (end == null) return formatShortMonthDay(context, start);
    return formatDateRangeShort(context, start, end);
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
    final isUniform = state == _HubState.youOwed || state == _HubState.youOwe;

    return Column(
      key: EventKeys.balanceHeader,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Overline(label: context.l10n.eventYourBalance),
            if (isUniform)
              _Overline(
                label: isOwed
                    ? context.l10n.eventYouAreOwed
                    : context.l10n.eventYouOwe,
                color: isOwed ? colors.successText : colors.errorText,
              ),
          ],
        ),
        SizedBox(height: context.spacing.space4),
        if (state == _HubState.empty || state == _HubState.settled)
          Text(
            state == _HubState.settled
                ? context.l10n.eventAllSettled
                : context.l10n.eventNothingToSettleYet,
            style: AppTypography.displayOf(
              context,
              fontSize: 24,
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
              size: 30,
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
                    size: 22,
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
      margin: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 10),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.cardSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border, width: 0.5),
      ),
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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
            color: active ? colors.textPrimary : colors.textSecondary,
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

/// #811: open-event counterpart to [_ClosedBanner]. A slim labelled recap
/// entry that replaced the tooltip-only header cup (weak touch scent). Shown
/// only for OPEN events that have expenses; pushes the full recap route.
class _OpenRecapBanner extends StatelessWidget {
  const _OpenRecapBanner({required this.onViewRecap});

  final VoidCallback onViewRecap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: EventKeys.openRecapBanner,
      width: double.infinity,
      color: colors.textPrimary.withValues(alpha: 0.04),
      padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 10),
      child: Row(
        children: [
          Icon(Iconsax.cup, size: 14, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.recapOpenBannerLead,
              style: AppTypography.sans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            key: EventKeys.openRecapBannerViewRecap,
            onTap: onViewRecap,
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
      ),
    );
  }
}

// ──────────────────────────── Overline helper

class _Overline extends StatelessWidget {
  const _Overline({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text(
      label.toUpperCase(),
      style: AppTypography.sans(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: color ?? colors.textSecondary,
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
