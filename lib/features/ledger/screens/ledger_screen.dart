import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/utils/firestore_error_utils.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/no_access_view.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../events/embedded_panel_metrics.dart';
import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../events/utils/event_type_copy.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../../../core/constants/supported_currencies.dart';
import '../providers/expense_provider.dart';
import '../providers/ledger_perspective_provider.dart';
import '../providers/ledger_view_provider.dart';
import '../utils/ledger_categories.dart';
import '../utils/ledger_timeline.dart';
import '../widgets/ledger_category_strip.dart';
import '../widgets/ledger_day_card.dart';
import '../widgets/ledger_hero_block.dart';
import '../widgets/ledger_roster_strip.dart';

/// V5R ledger timeline — the Expenses panel of the tabbed event view (#758,
/// panel-only since #915: the full-chrome route died with PR-5 §4).
///
/// Layout top to bottom:
///   1. Mono trip-total caption ("TRIP TOTAL · OMR 142.350 · 6 expenses · 2 settled").
///   2. Horizontal roster strip — You anchor + per-person signed chips
///      (tap → settle-up preselect).
///   3. Category chip filter (cat-color dots, "All · N" first).
///   4. Day-grouped white cards with two-row italic day stamps. Distinct
///      settlement rows (dashed sage inset with sage-text overline).
///   5. Footer: mono "· END OF LEDGER ·".
///
/// The tabbed shell (`EventCommandCenter`) owns balance display, chrome,
/// offline banner, and the add/settle affordances.
class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  final String groupId;
  final String eventId;

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  int? _categoryFilter;

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
    // #261: the ledger renders this event's money — it needs the owning group's
    // currency before drawing any amount (never default 'OMR': a non-OMR group
    // would mis-scale precision). Gate on the group resolving, like
    // add_expense_screen / settle_up_screen.
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));

    return eventAsync.when(
      loading: () => const _LoadingState(),
      error: (error, stackTrace) {
        // #1237 / #358: a removed member's event listen is permission-denied
        // forever — retry just re-denies. Terminal no-access state; raw error
        // to Sentry, not the UI. (The hub shadows this panel; kept for
        // consistency + any future direct route.)
        if (isPermissionDenied(error)) {
          unawaited(Sentry.captureException(error, stackTrace: stackTrace));
          return const NoAccessView();
        }
        return _ErrorState(
          onRetry: () => ref.invalidate(eventDetailProvider(eventRef)),
        );
      },
      data: (event) {
        if (event == null) return const _NotFoundState();
        if (groupAsync.isLoading && !groupAsync.hasValue) {
          return const _LoadingState();
        }
        final group = groupAsync.valueOrNull;
        if (group == null) return const _NotFoundState();
        // #1030: members joins the gate — ledgerViewProvider folds it into
        // the #249 universe, so a members error renders wrong per-member
        // nets on the balances tab / roster strip. Bare hasError matches
        // this screen's local convention (stricter than #1005; changing the
        // money-stream legs is out of scope).
        final membersAsync = ref.watch(groupMembersProvider(widget.groupId));
        if (expensesAsync.hasError ||
            settlementsAsync.hasError ||
            membersAsync.hasError) {
          return _DataErrorState(
            onRetry: () {
              ref.invalidate(eventExpensesProvider(eventRef));
              ref.invalidate(eventSettlementsProvider(eventRef));
              ref.invalidate(groupMembersProvider(widget.groupId));
            },
          );
        }
        final expenses = expensesAsync.valueOrNull ?? <Expense>[];
        final settlements = settlementsAsync.valueOrNull ?? <Settlement>[];
        final currentUserId = ref.watch(currentUserIdProvider);
        return _Body(
          groupId: widget.groupId,
          eventId: widget.eventId,
          event: event,
          currency: group.currency,
          expenses: expenses,
          settlements: settlements,
          currentUserId: currentUserId,
          categoryFilter: _categoryFilter,
          onCategoryFilter: (cat) => setState(() => _categoryFilter = cat),
        );
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.groupId,
    required this.eventId,
    required this.event,
    required this.currency,
    required this.expenses,
    required this.settlements,
    required this.currentUserId,
    required this.categoryFilter,
    required this.onCategoryFilter,
  });

  final String groupId;
  final String eventId;
  final Event event;
  final String currency;
  final List<Expense> expenses;
  final List<Settlement> settlements;
  final String? currentUserId;
  final int? categoryFilter;
  final ValueChanged<int?> onCategoryFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Filter-INDEPENDENT work (balances, participant universe, name maps) is
    // memoized here (#106) so a category-chip tap re-runs only the cheap filter
    // pass below — not the BalanceCalculator Decimal pass or the resolveEventScoped
    // name maps. Keyed by EventRef; the provider watches the event/expenses/
    // settlements/members streams itself.
    final data = ref.watch(
      ledgerViewProvider((groupId: groupId, eventId: eventId)),
    );
    final participants = data.participants;
    final eventTotal = data.eventTotal;
    final expensePayerDisplayNames = data.expensePayerDisplayNames;
    // Restore the non-null records the consumers require: the provider defers
    // the two l10n fallbacks (null ⇒ unknown party) to keep itself BuildContext-
    // free. Cheap O(settlements) string pass — no resolveEventScoped here.
    final settlementDisplayNames =
        <String, ({String payerName, String recipientName})>{
          for (final entry in data.settlementDisplayNames.entries)
            entry.key: (
              payerName: entry.value.payerName ?? context.l10n.ledgerSomeone,
              recipientName:
                  entry.value.recipientName ?? context.l10n.ledgerSomeoneLower,
            ),
        };

    final currentPid = event.participantIds.contains(currentUserId)
        ? currentUserId
        : null;
    // #628: the filter-INDEPENDENT perspective (the "You" lines, the per-person
    // roster + sort, the per-currency people counts) is memoized in
    // ledgerPerspectiveProvider, keyed by (eventRef, currentPid). A category-
    // chip setState rebuilds this body but changes neither that key (currentPid
    // is stable across the tap) nor the watched ledgerViewProvider value, so the
    // O(C×M²) per-person `myNetByCurrency` pivots + sort are served from cache.
    final perspective = ref.watch(
      ledgerPerspectiveProvider((
        eventRef: (groupId: groupId, eventId: eventId),
        currentPid: currentPid,
      )),
    );
    final myDisplayName = perspective.myDisplayName;
    final myLines = perspective.myLines;
    // Restore the l10n display fallback the provider defers (null ⇒ unknown).
    final roster = <LedgerRosterPerson>[
      for (final e in perspective.roster)
        LedgerRosterPerson(
          participantId: e.participantId,
          displayName: e.displayName ?? context.l10n.ledgerMemberFallback,
          signedAmount: e.signedAmount,
          currency: e.currency,
        ),
    ];

    // #998: each roster chip carries that member's OWN net (their standing
    // vs the event), matching the hero's "You" convention — positive chip =
    // the group owes them, negative chip = they owe the group.
    final hasExpenses = expenses.isNotEmpty;
    final isSettled = hasExpenses && myLines.isEmpty;
    final rosterState = !hasExpenses
        ? LedgerRosterState.empty
        : isSettled
        ? LedgerRosterState.settled
        : LedgerRosterState.live;

    final filteredExpenses = categoryFilter == null
        ? expenses
        : expenses
              .where(
                (e) => ledgerCategoryBucket(e.categoryId) == categoryFilter,
              )
              .toList();
    final filteredSettlements = categoryFilter == null
        ? settlements
        : <Settlement>[];
    final timeline = <LedgerTimelineItem>[
      ...filteredExpenses.map(LedgerExpenseItem.new),
      ...filteredSettlements.map(LedgerSettlementItem.new),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final days = groupTimelineByDay(
      timeline,
      DateTime.now(),
      l10n: context.l10n,
    );

    return CustomScrollView(
      restorationId: 'ledger_scroll',
      slivers: [
        // #758: the tabbed shell owns the header, balance display, and
        // offline banner — only the timeline (caption, chips, day cards)
        // renders as the Expenses panel. PR-5 §4: the roster strip's
        // per-person settle-up preselect tap (below) is the only in-app
        // producer for `…/ledger/settle-up?memberId=` — the embedded Settle
        // tab panel takes no preselect.
        if (hasExpenses)
          SliverToBoxAdapter(
            child: LedgerTripCaption(
              label: eventTypeTotalLabel(
                event.type,
                context.l10n,
              ).toUpperCase(),
              totals: [
                for (final c in sortedGccFirst(eventTotal.keys))
                  (currency: c, total: eventTotal[c]!),
              ],
              expenseCount: expenses.length,
              settledCount: settlements.length,
            ),
          ),
        SliverToBoxAdapter(
          child: LedgerRosterStrip(
            state: rosterState,
            others: roster,
            currency: currency,
            currentUserDisplayName: myDisplayName ?? context.l10n.ledgerYou,
            currentUserId: currentPid,
            onPersonTap: (p) => GoRouter.of(context).push(
              '/group/$groupId/event/$eventId/ledger/'
              'settle-up?memberId=${Uri.encodeComponent(p.participantId)}',
            ),
          ),
        ),
        if (hasExpenses)
          SliverToBoxAdapter(
            child: LedgerCategoryStrip(
              expenses: expenses,
              totalCount: expenses.length,
              active: categoryFilter,
              onChange: onCategoryFilter,
            ),
          )
        else
          const SliverToBoxAdapter(child: LedgerCategoryStripEmpty()),
        // #807: settlements carry no category, so ANY active category filter
        // hides every settlement row — say so instead of vanishing them.
        if (categoryFilter != null && settlements.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: context.spacing.space20,
                end: context.spacing.space20,
                top: 4,
              ),
              child: Text(
                context.l10n.ledgerSettlementsHiddenByCategory,
                style: AppTypography.sans(
                  fontSize: 12,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 6)),
        if (timeline.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: context.spacing.space20,
              vertical: context.spacing.space16,
            ),
            sliver: SliverToBoxAdapter(
              child: hasExpenses
                  ? EmptyStateView(
                      icon: Iconsax.receipt_item,
                      title: context.l10n.ledgerNothingInCategoryTitle,
                      message: context.l10n.ledgerNothingInCategoryMessage,
                      actionLabel: context.l10n.ledgerClearFilters,
                      onAction: () => onCategoryFilter(null),
                    )
                  : _EmptyStateBody(currency: currency, eventType: event.type),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final day = days[index];
              return Padding(
                padding: EdgeInsets.only(top: index == 0 ? 4 : 14),
                child: LedgerDayCard(
                  dayLabel: day.label,
                  sub: null,
                  items: day.items,
                  currentParticipantId: currentPid,
                  participantCount: participants.length,
                  expensePayerDisplayNames: expensePayerDisplayNames,
                  settlementDisplayNames: settlementDisplayNames,
                  owedByExpenseId: data.owedByExpenseId,
                  onExpenseTap: (expense) => GoRouter.of(context).push(
                    '/group/$groupId/event/$eventId/ledger/'
                    'edit/${expense.id}',
                  ),
                ),
              );
            }, childCount: days.length),
          ),
        SliverToBoxAdapter(
          child: Padding(
            // #789: extend the trailing gutter so the last content clears the
            // workspace's floating FAB.
            padding: EdgeInsets.fromLTRB(
              0,
              context.spacing.space24,
              0,
              kEmbeddedEventPanelFabClearance,
            ),
            child: Center(
              child: Text(
                isSettled
                    ? '· ${context.l10n.ledgerEndOfLedger} · '
                          '${Decimal.zero.toStringAsFixed(AppFormatters.currencyConfig[currency]?.decimals ?? 3)} ·'
                    : '· ${context.l10n.ledgerEndOfLedger} ·',
                style: AppTypography.caption(
                  context,
                  fontSize: 9,
                  color: context.colors.textSecondary,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────── Empty-state body

class _EmptyStateBody extends StatelessWidget {
  const _EmptyStateBody({required this.currency, required this.eventType});

  final String currency;
  final EventType eventType;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 8),
      child: Column(
        children: [
          CustomPaint(
            size: const Size(120, 116),
            painter: _JournalPagePainter(colors: colors),
          ),
          SizedBox(height: context.spacing.space12),
          Text(
            context.l10n.ledgerEmptyStateTitle,
            textAlign: TextAlign.center,
            style: AppTypography.displayOf(
              context,
              fontSize: 22,
              color: colors.textPrimary,
              height: 1.2,
            ),
          ),
          SizedBox(height: context.spacing.space8),
          Text(
            eventTypeFirstExpenseBody(eventType, context.l10n, currency),
            textAlign: TextAlign.center,
            style: AppTypography.sans(
              fontSize: 13,
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sketched journal-page illustration for the empty state — rounded
/// rectangle outline, dashed ruled lines, and a saffron plus-circle in
/// the top-right corner. Lightweight Flutter mirror of the V5R SVG.
class _JournalPagePainter extends CustomPainter {
  _JournalPagePainter({required this.colors});
  final AppColorTokens colors;

  @override
  void paint(Canvas canvas, Size size) {
    final pagePaint = Paint()
      ..color = colors.cardSurface
      ..style = PaintingStyle.fill;
    final pageStroke = Paint()
      ..color = colors.textSecondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final ruleStroke = Paint()
      ..color = colors.rule2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final pageRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(18, 14, 84, 92),
      const Radius.circular(6),
    );
    canvas.drawRRect(pageRect, pagePaint);
    canvas.drawRRect(pageRect, pageStroke);

    final lines = <(double, double, double)>[
      (30, 36, 90),
      (30, 50, 90),
      (30, 64, 70),
      (30, 78, 84),
      (30, 92, 62),
    ];
    for (final (sx, y, ex) in lines) {
      _dashedHLine(canvas, sx, ex, y, ruleStroke, dash: 2, gap: 4);
    }

    final saffronTintPaint = Paint()..color = colors.saffronTint;
    final saffronStroke = Paint()
      ..color = colors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(const Offset(98, 14), 14, saffronTintPaint);
    canvas.drawCircle(const Offset(98, 14), 14, saffronStroke);
    final plusPaint = Paint()
      ..color = colors.primaryDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(92, 14), const Offset(104, 14), plusPaint);
    canvas.drawLine(const Offset(98, 8), const Offset(98, 20), plusPaint);
  }

  void _dashedHLine(
    Canvas canvas,
    double x0,
    double x1,
    double y,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    var x = x0;
    final step = dash + gap;
    while (x < x1) {
      final next = (x + dash).clamp(x0, x1);
      canvas.drawLine(Offset(x, y), Offset(next, y), paint);
      x += step;
    }
  }

  @override
  bool shouldRepaint(covariant _JournalPagePainter old) => old.colors != colors;
}

// ──────────────────────────── State views

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusBar = MediaQuery.of(context).padding.top;
    return Column(
      children: [
        SizedBox(
          height: 120 + statusBar,
          child: Container(color: colors.cardSoft),
        ),
        Expanded(child: SkeletonLoader.expenseList()),
      ],
    );
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
            title: context.l10n.ledgerCouldNotLoadEventTitle,
            message: context.l10n.ledgerConnectionRetryMessage,
            actionLabel: context.l10n.commonRetry,
            onAction: onRetry,
          ),
        ),
      ),
    );
  }
}

class _DataErrorState extends StatelessWidget {
  const _DataErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(context.spacing.space24),
          child: EmptyStateView(
            icon: Iconsax.warning_2,
            title: context.l10n.ledgerCouldNotLoadLedgerTitle,
            message: context.l10n.ledgerConnectionRetryMessage,
            actionLabel: context.l10n.ledgerReload,
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
            title: context.l10n.ledgerEventNotFoundTitle,
            message: context.l10n.ledgerEventNotFoundMessage,
            actionLabel: context.l10n.commonGoHome,
            onAction: () => GoRouter.of(context).go('/home'),
          ),
        ),
      ),
    );
  }
}
