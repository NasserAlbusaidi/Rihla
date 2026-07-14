import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/firestore_error_utils.dart';
import '../../../shared/widgets/no_access_view.dart';
import '../../../shared/widgets/offline_banner.dart';
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
import '../widgets/event_command_center/add_expense_fab.dart';
import '../widgets/event_command_center/closed_banner.dart';
import '../widgets/event_command_center/error_state.dart';
import '../widgets/event_command_center/event_header.dart';
import '../widgets/event_command_center/event_tab_bar.dart';
import '../widgets/event_command_center/hub_state.dart';
import '../widgets/event_command_center/lazy_indexed_stack.dart';
import '../widgets/event_command_center/loading_state.dart';
import '../widgets/event_command_center/not_found_state.dart';
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
        loading: () => const LoadingState(),
        error: (error, stackTrace) {
          // #1207 / #358: a removed member's event listen is permission-denied
          // forever — retrying just re-denies. Terminal no-access state with a
          // Home CTA; raw error goes to Sentry, not the UI.
          if (isPermissionDenied(error)) {
            unawaited(Sentry.captureException(error, stackTrace: stackTrace));
            return const NoAccessView();
          }
          return ErrorState(
            onRetry: () => ref.invalidate(
              eventDetailProvider((groupId: groupId, eventId: eventId)),
            ),
          );
        },
        data: (event) {
          if (event == null) return const NotFoundState();
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
/// [LazyIndexedStack] panel order (`tab.index` indexes the panels).
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
        ? HubState.unavailable
        : balancePending
        ? HubState.pending
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
              EventHeader(
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
                ClosedBanner(
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
              EventTabBar(
                active: tab,
                showRecap: showRecap,
                onSelect: _selectTab,
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: LazyIndexedStack(
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
              child: AddExpenseFab(
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

/// Settled ⇔ EVERY currency bucket nets exactly zero. Deliberate threshold
/// change (#382 PR-5, L13): this replaces `UserBalance.isSettled`'s 0.001
/// tolerance with the helpers' exact-zero predicate — the header's settled
/// gate TIGHTENS, so a sub-tolerance residual renders instead of silently
/// reading as settled (the calculator closes remainders, so one shouldn't
/// exist). Mixed signs across buckets have no honest single overline →
/// [HubState.mixed].
HubState _resolveState({
  required bool hasExpenses,
  required List<({String currency, Decimal net})> lines,
}) {
  if (!hasExpenses) return HubState.empty;
  if (lines.isEmpty) return HubState.settled;
  if (lines.every((l) => l.net > Decimal.zero)) return HubState.youOwed;
  if (lines.every((l) => l.net < Decimal.zero)) return HubState.youOwe;
  return HubState.mixed;
}
